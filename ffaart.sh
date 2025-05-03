#!/bin/bash

# ffaart: Fidelity-First Automagical AV1 Reencoding to Target
#   An intelligent video transcoding utility which prioritizes perceptual quality
#   while leveraging AV1 to reduce file sizes with minimal manual input.
#
# Usage: ffaart [--bitrate B] [--resolution X Y] [--framerate R] file

__log() {
  log_level="$1"
  log_message="$2"
  log_input_file="$INPUT_FILE_PATH"
  #shellcheck disable=SC2016
  echo '{}' |\
    jq \
      --monochrome-output \
      --compact-output \
      --raw-output \
      --arg timestamp "$(date +%s)" \
      --arg log_level "$log_level" \
      --arg log_message "$log_message" \
      --arg input_file "$log_input_file" \
      '.timestamp=$timestamp|.log_level=$log_level|.message=$log_message|.input_file=$input_file'
}

main() { # Takes a file path, creates a new file.
  INPUT_FILE_PATH="$1"
  INTERMEDIATE_FILE_PATH="/tmp/tmp.mp4"
  TARGET_FILE_PATH="${INPUT_FILE_PATH%.*}.mp4"

  # Create our intermediate file, remuxing if necessary
  # Some metadata are not available in other formats.
  EXT=$(echo "${INPUT_FILE_PATH##*.}" | tr '[:upper:]' '[:lower:]')
  if [[ "$EXT" != "mp4" ]]; then
    ffmpeg -hide_banner -nostdin -loglevel error -i "$INPUT_FILE_PATH" -c copy "$INTERMEDIATE_FILE_PATH"
  else
    cp "$INPUT_FILE_PATH" "$INTERMEDIATE_FILE_PATH"
  fi

  # Detect hwaccel capabilities
  # TODO: Support acceleration with non-vaapi, non-AMD hardware.
  if ! ffmpeg -hide_banner -hwaccels | grep -q vaapi && [ -e "/dev/dri/renderD128" ]; then
    __log "ERROR" "Required hardware acceleration not found: vaapi, /dev/dri/renderD128"
    exit 1
  fi

  # Set target resolution
  SOURCE_RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INTERMEDIATE_FILE_PATH")
  TARGET_RESOLUTION_X=${TARGET_RESOLUTION_X:-${SOURCE_RESOLUTION%x*}}
  TARGET_RESOLUTION_Y=${TARGET_RESOLUTION_Y:-${SOURCE_RESOLUTION##*x}}

  # Set target framerate
  SOURCE_FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INTERMEDIATE_FILE_PATH")
  TARGET_FRAMERATE="${TARGET_FRAMERATE:-$SOURCE_FRAMERATE}" # This is a fractional value like 30000/1001 or 60/1

  # Set target bitrate
  SOURCE_VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INTERMEDIATE_FILE_PATH")
  SOURCE_BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$INTERMEDIATE_FILE_PATH")

  case $SOURCE_VCODEC in
    "av1") TARGET_BITRATE=${TARGET_BITRATE:-$SOURCE_BITRATE} ;;
    "h264") TARGET_BITRATE=${TARGET_BITRATE:-$((SOURCE_BITRATE * 60 / 100))} ;;
    "hevc") TARGET_BITRATE=${TARGET_BITRATE:-$((SOURCE_BITRATE * 80 / 100))} ;;
  esac

  # Build the ffmpeg command
  FFMPEG_CMD="ffmpeg \
    -hide_banner \
    -nostdin \
    -loglevel error \
    -vaapi_device /dev/dri/renderD128 \
    -i \"$INTERMEDIATE_FILE_PATH\" \
    -y \
    -filter:v \"scale=$TARGET_RESOLUTION_X:$TARGET_RESOLUTION_Y,format=nv12,hwupload\" \
    -codec:v av1_vaapi \
    -r \"$TARGET_FRAMERATE\" \
    -b:v \"$TARGET_BITRATE\" \
    \"$TARGET_FILE_PATH\""

  if [[ -f "$TARGET_FILE_PATH" ]]; then
    if [[
      "${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y}" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$TARGET_FILE_PATH")" &&
      "$TARGET_FRAMERATE" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE_PATH")" &&
      "av1" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE_PATH")"
    ]]; then
      __log "WARN" "Skipping. Target already matches resolution, framerate, and video codec"
      exit 1
    fi
  fi

  # Dry run if flagged
  DRY_RUN=${DRY_RUN:-false}
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -n "$FFMPEG_CMD" | tr -s ' '
    echo " && mv \"$INTERMEDIATE_FILE_PATH\" \"$TARGET_FILE_PATH\""
    exit 0
    # Note: Dry runs do not write to ffaart.log
  fi

  # Error out before clobbering backup of original file.
  if [[
    "$INPUT_FILE_PATH" == *".original.${INPUT_FILE_PATH##*.}" ||
    -f "${INPUT_FILE_PATH%.*}.original.${INPUT_FILE_PATH##*.}"
  ]]; then
    __log "ERROR" "Backing up original file would clobber \"${INPUT_FILE_PATH%.*}.original.${INPUT_FILE_PATH##*.}\""; exit 1
  fi
  mv "$INPUT_FILE_PATH" "${INPUT_FILE_PATH%.*}.original.${INPUT_FILE_PATH##*.}"

  # Run the ffmpeg command
  bash -c "$FFMPEG_CMD" 2>/dev/null || (__log "ERROR" "ffmpeg failed to process file"; exit 1)

  # Unless we want to keep the original file, delete it
  if [[ "${KEEP_ORIGINAL:-false}" == "false" ]]; then
    rm "${INPUT_FILE_PATH%.*}.original.${INPUT_FILE_PATH##*.}"
  fi

  # Clean up the intermediate file
  rm "$INTERMEDIATE_FILE_PATH"

  # Log success
  result="$(\
    echo '{}' |\
    jq --monochrome-output --compact-output --raw-output \
      --arg result_file_path "$TARGET_FILE_PATH" \
      --arg result_resolution "${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y}" \
      --arg result_framerate "$TARGET_FRAMERATE" \
      --arg result_bitrate "$TARGET_BITRATE" \
    '.result_file_path=$result_file_path|.result_resolution=$result_resolution|.result_framerate=$result_framerate|.result_bitrate=$result_bitrate'
  )"
  __log "INFO" "$result"
  exit 0
}

isvalid() {
  if [[ ! -f "$1" ]]; then return 1; fi # Input is a file.
  if ! file -b --mime-type "$1" | grep -q '^video/'; then return 1; fi # Input is a video.

  # Input contains video stream encoded with supported codec.
  FFPROBE_VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)
  if [[ -z "$FFPROBE_VCODEC" ]]; then return 1; fi
  case "$FFPROBE_VCODEC" in
    h264|hevc|av1) ;;
    *) return 1;;
  esac

  return 0
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --bitrate)
      TARGET_BITRATE="$2"
      shift; shift;;
    --dry-run)
      DRY_RUN=true
      shift;;
    --keep-original)
      KEEP_ORIGINAL=true
      shift;;
    --resolution)
      TARGET_RESOLUTION_X="$2"
      TARGET_RESOLUTION_Y="$3"
      shift; shift; shift;;
    --framerate)
      TARGET_FRAMERATE="$2"
      shift; shift;;
    *)
      if [[ -f "$1" ]]; then
        if [[ "$#" -gt 1 ]]; then echo "Too many arguments."; exit 1
        else
          INPUT_FILE_PATH="$(realpath "$1")"
          shift
        fi
      else
        echo "Unrecognized argument $1"
        exit 1
      fi;;
  esac
done

if [[ -z "$INPUT_FILE_PATH" ]]; then echo "No input file path found."; exit 1; fi

if isvalid "$INPUT_FILE_PATH"; then
  #shellcheck disable=SC2317,SC2016
  main "$INPUT_FILE_PATH" || __log "ERROR" "$(\
    echo "{}" |\
    jq --monochrome-output --compact-output --raw-output \
      --arg debug "INPUT_FILE_PATH=$INPUT_FILE_PATH
      SOURCE_VCODEC=$SOURCE_VCODEC
      SOURCE_RESOLUTION=$SOURCE_RESOLUTION
      SOURCE_FRAMERATE=$SOURCE_FRAMERATE
      SOURCE_BITRATE=$SOURCE_BITRATE
      TARGET_RESOLUTION=${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y}
      TARGET_FRAMERATE=$TARGET_FRAMERATE
      TARGET_BITRATE=$TARGET_BITRATE"
      '.text="Unknown error while processing file."|.debug=$debug'
  )"
else
  __log "WARN" "Invalid input"
  exit 1
fi
