#!/bin/bash

# ffaart: Fidelity-First Automagical AV1 Reencoding to Target
#   An intelligent video transcoding utility which prioritizes perceptual quality
#   while leveraging AV1 to reduce file sizes with minimal manual input.
#
# Usage: ffaart [--bitrate B] [--resolution X Y] [--framerate R] file

main() { # Takes a file path, creates a new file.
  INPUT_FILE_PATH="$1"
  INPUT_FILE_SIZE="$(stat -c %s "$INPUT_FILE_PATH")"

  # We remux to mp4 if the input file is not already an mp4.
  # Some metadata are not available in other formats.
  EXT=$(echo "${INPUT_FILE_PATH##*.}" | tr '[:upper:]' '[:lower:]')
  if [[ "$EXT" != "mp4" ]]; then
    ffmpeg -hide_banner -nostdin -loglevel error -i "$INPUT_FILE_PATH" -c copy "${INPUT_FILE_PATH%.*}.mp4"
    INPUT_FILE_PATH="${INPUT_FILE_PATH%.*}.mp4"
  fi

  # Set target file path
  # If TARGET_FILE_PATH is not set, default to the input file with .mp4 extension
  # If TARGET_FILE_PATH collides with the input file, temporarily use .av1.mp4 extension
  TARGET_FILE_PATH=${TARGET_FILE_PATH:-"${INPUT_FILE_PATH%.*}.mp4"}
  if [[ "$TARGET_FILE_PATH" == "$INPUT_FILE_PATH" ]]; then
    TARGET_FILE_PATH="${INPUT_FILE_PATH%.*}.av1.mp4"
  fi

  # Detect hwaccel capabilities
  # TODO: Support acceleration with non-vaapi, non-AMD hardware.
  if ffmpeg -hide_banner -hwaccels | grep -q vaapi && [ -e "/dev/dri/renderD128" ]; then
    HWACCEL_MODE="vaapi"
  else
    HWACCEL_MODE="cpu"
    echo "Warning: Hardware acceleration not available. This will take a while."
  fi

  # Set target resolution
  SOURCE_RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_FILE_PATH")
  TARGET_RESOLUTION_X=${TARGET_RESOLUTION_X:-${SOURCE_RESOLUTION%x*}}
  TARGET_RESOLUTION_Y=${TARGET_RESOLUTION_Y:-${SOURCE_RESOLUTION##*x}}

  # Set target framerate
  SOURCE_FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE_PATH")
  TARGET_FRAMERATE="${TARGET_FRAMERATE:-$SOURCE_FRAMERATE}" # This is a fractional value like 30000/1001 or 60/1

  # Set target bitrate
  SOURCE_VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE_PATH")
  SOURCE_BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE_PATH")

  case $SOURCE_VCODEC in
    "av1") TARGET_BITRATE=${TARGET_BITRATE:-$SOURCE_BITRATE} ;;
    "h264") TARGET_BITRATE=${TARGET_BITRATE:-$((SOURCE_BITRATE * 60 / 100))} ;;
    "hevc") TARGET_BITRATE=${TARGET_BITRATE:-$((SOURCE_BITRATE * 80 / 100))} ;;
  esac

  # Build the ffmpeg command
  if [[ "$HWACCEL_MODE" == "vaapi" ]]; then
    FFMPEG_CMD="ffmpeg \
      -hide_banner \
      -nostdin \
      -loglevel error \
      -vaapi_device /dev/dri/renderD128 \
      -i \"$INPUT_FILE_PATH\" \
      -y \
      -filter:v \"scale=$TARGET_RESOLUTION_X:$TARGET_RESOLUTION_Y,format=nv12,hwupload\" \
      -codec:v av1_vaapi \
      -r \"$TARGET_FRAMERATE\" \
      -b:v \"$TARGET_BITRATE\" \
      \"$TARGET_FILE_PATH\""
  elif [[ "$HWACCEL_MODE" == "cpu" ]]; then
    FFMPEG_CMD="ffmpeg \
      -hide_banner \
      -nostdin \
      -loglevel error \
      -i \"$INPUT_FILE_PATH\" \
      -y \
      -filter:v \"scale=$TARGET_RESOLUTION_X:$TARGET_RESOLUTION_Y,format=nv12\" \
      -codec:v libsvtav1 \
      -r \"$TARGET_FRAMERATE\" \
      -b:v \"$TARGET_BITRATE\" \
      \"$TARGET_FILE_PATH\""
  else
    echo "Unknown HWACCEL_MODE $HWACCEL_MODE"; exit 1
  fi

  # Dry run if flagged
  DRY_RUN=${DRY_RUN:-false}
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "RESOLUTION: $SOURCE_RESOLUTION -> ${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y}"
    echo "FRAMERATE: $SOURCE_FRAMERATE -> $TARGET_FRAMERATE"
    echo "BITRATE: $(numfmt --to=si --suffix=bps --format="%.1f" "$SOURCE_BITRATE") ($SOURCE_VCODEC) -> $(numfmt --to=si --suffix=bps --format="%.1f" "$TARGET_BITRATE")"
    TARGET_FILE_SIZE_ESTIMATE="$(( $(stat -c %s "$INPUT_FILE_PATH") * TARGET_BITRATE / SOURCE_BITRATE ))"
    echo "FILESIZE: \
      $(numfmt --to=iec --suffix=B --format="%.1f" "$(stat -c %s "$INPUT_FILE_PATH")") -> \
      $(numfmt --to=iec --suffix=B --format="%.1f" "$TARGET_FILE_SIZE_ESTIMATE") (estimate)"
    echo "FFMPEG_CMD: $(echo "$FFMPEG_CMD" | tr -s ' ')"
    exit 0
  fi

  # Prevent unnecessary runs.
  if [[ "$TARGET_FILE_PATH" == "${INPUT_FILE_PATH%.*}.av1.mp4" ]]; then
    if [[
      "${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y}" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "${INPUT_FILE_PATH%.*}.mp4")" &&
      "$TARGET_FRAMERATE" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "${INPUT_FILE_PATH%.*}.mp4")" &&
      "av1" == "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${INPUT_FILE_PATH%.*}.mp4")"
    ]]; then
      echo "Target file \"$TARGET_FILE_PATH\" already matches resolution, framerate, and video codec. If you just want to reduce the bitrate, use this:"
      echo "ffmpeg -hide_banner -nostdin -loglevel error -vaapi_device /dev/dri/renderD128 -i \"$INPUT_FILE_PATH\" -y -filter:v \"format=nv12,hwupload\" -codec:v av1_vaapi -b:v \"$TARGET_BITRATE\" \"$TARGET_FILE_PATH\""
      exit 1
    fi
  fi


  # Process the file
  time_ffmpeg_pre="$(date +%s)"
  bash -c "$FFMPEG_CMD"
  if [[ "$TARGET_FILE_PATH" == "${INPUT_FILE_PATH%.*}.av1.mp4" ]]; then
    TARGET_FILE_PATH="${INPUT_FILE_PATH%.*}.mp4"
    mv "${INPUT_FILE_PATH%.*}.av1.mp4" "$TARGET_FILE_PATH"
  fi
  time_ffmpeg_post="$(date +%s)"

  PROCESS_DURATION="$(date -ud "@$((time_ffmpeg_post - time_ffmpeg_pre))" +'%H:%M:%S')"
  SIZE_REDUCTION="$(numfmt --to=iec --format="%.2f" $(( "$INPUT_FILE_SIZE" - "$(stat -c %s "$TARGET_FILE_PATH")" )))"

  # Log
  if [[ ! -f ffaart.log ]]; then
    echo "epoch,\
    input_file_path,\
    target_file_path,\
    source_resolution,\
    source_framerate,\
    source_bitrate,\
    target_resolution,\
    target_framerate,\
    target_bitrate,\
    process_duration,\
    size_reduction" | xargs > ffaart.log
  fi
  {
    echo -n "$(date +%s),"
    echo -n "$INPUT_FILE_PATH,"
    echo -n "$TARGET_FILE_PATH,"
    echo -n "$SOURCE_RESOLUTION,"
    echo -n "$SOURCE_FRAMERATE,"
    echo -n "$SOURCE_BITRATE,"
    echo -n "${TARGET_RESOLUTION_X}x${TARGET_RESOLUTION_Y},"
    echo -n "$TARGET_FRAMERATE,"
    echo -n "$TARGET_BITRATE,"
    echo -n "$PROCESS_DURATION,"
    echo -n "$SIZE_REDUCTION"
    echo ""
  } >> ffaart.log
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --bitrate)
      TARGET_BITRATE="$2"
      shift; shift;;
    --dry-run)
      DRY_RUN=true
      shift;;
    --output)
      TARGET_FILE_PATH="$2"
      shift; shift;;
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

main "$INPUT_FILE_PATH"
