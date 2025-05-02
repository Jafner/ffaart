#!/bin/bash

# Assert that video bitrate is within a percentage range of expected
assert_bitrate() {
  expected="$(numfmt --from=si "$1")"
  file="$2"
  tolerance_percent="${3:-5}" # default 5% tolerance

  actual=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file")
  lower_bound=$((expected * (100 - tolerance_percent) / 100))
  upper_bound=$((expected * (100 + tolerance_percent) / 100))

  if (( actual >= lower_bound && actual <= upper_bound )); then
    echo "PASS: Bitrate $(numfmt --to=si --suffix=bps "$actual") is within ${tolerance_percent}% of expected $(numfmt --to=si --suffix=bps "$expected")"
    return 0
  else
    echo "FAIL: Bitrate $(numfmt --to=si --suffix=bps "$actual") is not within ${tolerance_percent}% of expected $(numfmt --to=si --suffix=bps "$expected")"
    return 1
  fi
}

# Assert video resolution matches expected
assert_resolution() {
  file="$2"
  expected="$1"
  expected_x="${expected%x*}"
  expected_y="${expected#*x}"

  actual=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file")
  actual_x=${actual%x*}
  actual_y=${actual#*x}

  if [[ "$actual_x" == "$expected_x" && "$actual_y" == "$expected_y" ]]; then
    echo "PASS: Resolution ${actual_x}x${actual_y} matches expected ${expected_x}x${expected_y}"
    return 0
  else
    echo "FAIL: Resolution ${actual_x}x${actual_y} does not match expected ${expected_x}x${expected_y}"
    return 1
  fi
}

# Assert video framerate matches expected (with small floating point tolerance)
assert_framerate() {
  file="$1"
  expected="$2"
  actual=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$file")

  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: Framerate $actual matches expected $expected"
    return 0
  else
    echo "FAIL: Framerate $actual does not match expected $expected"
    return 1
  fi
}

# Assert video codec matches expected
assert_codec() {
  file="$1"
  expected="av1"
  actual=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")

  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: Codec $actual matches expected $expected"
    return 0
  else
    echo "FAIL: Codec $actual does not match expected $expected"
    return 1
  fi
}

case "$1" in
  bitrate) shift; assert_bitrate "$@" ;;
  resolution) shift; assert_resolution "$@" ;;
  framerate) shift; assert_framerate "$@" ;;
  codec) shift; assert_codec "$@" ;;
  usage) echo "Usage: $0 <bitrate|resolution|framerate|codec> <options>" ;;
  *) echo "Unrecognized argument $1"; exit 1;;
esac

# Simple usage:
# ./test.sh bitrate 4M <file>
# ./test.sh resolution 1920x1080 <file>
# ./test.sh framerate 30 <file>
# ./test.sh codec av1 <file>
