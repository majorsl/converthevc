#!/usr/bin/env bash
# Version 1.4.0 - Adds NVIDIA NVENC detection alongside VAAPI, uses libx265 as fallback

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# Path to ffmpeg binaries (without trailing slash)
FFMPEG="/usr/bin"
# Lockfile location (ensures only one instance of this script runs at a time)
LOCKFILE="/tmp/convert_video.lock"
# -----------------------------------------------------------------------------------------------

IFS=$'\n'

# Acquire a lock to prevent concurrent script runs
exec 200>"$LOCKFILE"
flock 200

# Check if a directory is passed as an argument
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "Please call the script with a directory to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "$WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Process video files
find "$WORKINGDIRECTORY" -type f \( -iname "*.avc" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.MOV" -o -iname "*.wmv" -o -iname "*.asf" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.3gp" \) -print0 | while IFS= read -r -d '' file
do
  # Skip .tmp.* files from interrupted conversions
  if [[ "$file" == *.tmp.* ]]; then
    echo "Skipping temporary file: $file"
    continue
  fi

  base_name="${file%.*}"
  temp_file="${base_name}.tmp.${file##*.}"
  original_file="${base_name}.${file##*.}"

  echo "Processing $file"

  codec=$("$FFMPEG/ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
  echo "Detected codec: '$codec'"

  if [[ "$codec" != "hevc" ]]; then
    file_info=$("$FFMPEG/ffprobe" -v error -select_streams a:v:s -show_entries stream=codec_name,channels,width,height -of default=nokey=1:noprint_wrappers=1 "$file")

    map_str=()
    map_str+=("-map" "0:v")

    subtitle_streams=$("$FFMPEG/ffprobe" -v error -select_streams s -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$file")
    if [ -n "$subtitle_streams" ]; then
      map_str+=("-map" "0:s")
    fi

    track_num=0
    while read -r line; do
      map_str+=("-map" "0:a:$track_num?")
      ((track_num++))
    done <<< "$file_info"

    temp_newfile="${base_name}.tmp.mkv"

    # Detect hardware acceleration
    echo "Checking for hardware acceleration..."
    use_nvenc=false
    use_vaapi=false

    if command -v nvidia-smi >/dev/null && "$FFMPEG/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q hevc_nvenc; then
      echo "NVENC is available. Using NVIDIA hardware acceleration for $file"
      use_nvenc=true
    elif "$FFMPEG/ffmpeg" -hwaccels 2>/dev/null | grep -q vaapi && \
         test -e /dev/dri/renderD128 && \
         "$FFMPEG/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q hevc_vaapi; then
      echo "VAAPI is available. Using Intel hardware acceleration for $file"
      use_vaapi=true
    else
      echo "No supported hardware acceleration available. Falling back to software encoding."
    fi

    # Run appropriate encoding
if $use_nvenc; then
  "$FFMPEG/ffmpeg" -nostdin -i "$file" "${map_str[@]}" \
    -vcodec hevc_nvenc -rc:v vbr -cq:v 28 -qmin:v 28 -qmax:v 28 -b:v 0 -preset p4 \
    -acodec copy -scodec copy "$temp_newfile"

    elif $use_vaapi; then
      "$FFMPEG/ffmpeg" -nostdin -vaapi_device /dev/dri/renderD128 -hwaccel vaapi \
        -i "$file" "${map_str[@]}" \
        -vf 'format=nv12,hwupload' \
        -vcodec hevc_vaapi -qp 25 -acodec copy -scodec copy "$temp_newfile"

    else
      "$FFMPEG/ffmpeg" -nostdin -i "$file" "${map_str[@]}" \
        -vcodec libx265 -acodec copy -scodec copy -preset fast -crf 25 "$temp_newfile"
    fi

    # Handle result
    if [ $? -eq 0 ]; then
      echo "Conversion successful. Replacing original."
      rm "$file"
      mv "$temp_newfile" "${base_name}.mkv"
    else
      echo "Conversion failed for $file. Original file remains."
      rm -f "$temp_newfile"
    fi

  else
    echo "File $file already has HEVC video, skipping conversion."
  fi
done

unset IFS
