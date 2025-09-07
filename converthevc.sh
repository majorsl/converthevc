#!/usr/bin/env bash
# Version 1.5.2 - Added AV1 skip option

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
FFMPEG="/usr/bin"
LOCKFILE="/tmp/convert_video.lock"
# -----------------------------------------------------------------------------------------------

IFS=$'\n'
declare -a summary_lines

# Acquire a lock with a 6-hour timeout
exec 200>"$LOCKFILE"
echo "🔒 Waiting for lock on $LOCKFILE ..."
flock -w 21600 200 || {
  echo "⏱ Timeout waiting for lock (6 hours). Another instance may be stuck. Exiting."
  exit 1
}
echo "✅ Lock acquired"

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
while IFS= read -r -d '' file; do
  # Skip .tmp.* files from interrupted conversions
  if [[ "$file" == *.tmp.* ]]; then
    echo "Skipping temporary file: $file"
    continue
  fi

  base_name="${file%.*}"
  temp_file="${base_name}.tmp.${file##*.}"
  original_file="${base_name}.${file##*.}"

  echo -e "⏳ Processing:\033[0m $file"

  codec=$("$FFMPEG/ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$file" | tr -d ' \t\r\n')

  echo "   Detected codec: '$codec'"

  if [[ "$codec" == "hevc" ]]; then
    echo "   Skipping: already HEVC"
    summary_lines+=("🔁 $(basename "$file"): already HEVC, skipped")

  elif [[ "$codec" == "av1" ]]; then
    echo "   Skipping: already AV1"
    summary_lines+=("🔁 $(basename "$file"): already AV1, skipped")

  else
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
    echo "   Checking for hardware acceleration..."
    use_nvenc=false
    use_vaapi=false

    if command -v nvidia-smi >/dev/null && "$FFMPEG/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q hevc_nvenc; then
      echo "   ✅ NVENC is available. Using NVIDIA hardware acceleration."
      use_nvenc=true
    elif "$FFMPEG/ffmpeg" -hwaccels 2>/dev/null | grep -q vaapi && \
         test -e /dev/dri/renderD128 && \
         "$FFMPEG/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q hevc_vaapi; then
      echo "   ✅ VAAPI is available. Using Intel hardware acceleration."
      use_vaapi=true
    else
      echo "   ⚠️ No supported hardware acceleration available. Falling back to software encoding."
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
      original_size=$(stat -c%s "$file")
      new_size=$(stat -c%s "$temp_newfile")
      savings=$((original_size - new_size))

      rm "$file"
      mv "$temp_newfile" "${base_name}.mkv"

      if [ $savings -ge 0 ]; then
        percent_savings=$((100 * savings / original_size))
        summary_lines+=("✅ $(basename "$file"): saved $((savings / 1024 / 1024)) MB (${percent_savings}% smaller)")
      else
        increase=$((new_size - original_size))
        percent_increase=$((100 * increase / original_size))
        summary_lines+=("📈 $(basename "$file"): grew by $((increase / 1024 / 1024)) MB (${percent_increase}% bigger)")
      fi
    else
      rm -f "$temp_newfile"
      summary_lines+=("❌ $(basename "$file"): conversion failed")
    fi
  fi

done < <(find "$WORKINGDIRECTORY" -type f \( -iname "*.avc" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.MOV" -o -iname "*.wmv" -o -iname "*.asf" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.3gp" \) -print0)

# Summary output
echo -e "\n\033[1m📊 Conversion Summary:\033[0m"
for line in "${summary_lines[@]}"; do
  echo " - $line"
done

# Count summary categories and size changes
count_converted=0
count_skipped=0
count_failed=0
count_grew=0
total_saved=0
total_increased=0

for line in "${summary_lines[@]}"; do
  case "$line" in
    ✅*)
      ((count_converted++))
      [[ "$line" =~ saved[[:space:]]([0-9]+) ]] && ((total_saved += BASH_REMATCH[1]))
      ;;
    📈*)
      ((count_converted++))
      ((count_grew++))
      [[ "$line" =~ grew[[:space:]]by[[:space:]]([0-9]+) ]] && ((total_increased += BASH_REMATCH[1]))
      ;;
    🔁*) ((count_skipped++)) ;;
    ❌*) ((count_failed++)) ;;
  esac
done

# Final Summary
echo -e "\n\033[1m📋 Totals:\033[0m"
echo " - ✅ Converted successfully: $count_converted"
echo " - 🔁 Skipped (already HEVC/AV1): $count_skipped"
echo " - ❌ Failed conversions: $count_failed"
echo " - 📈 Increased file size: $count_grew"
if [ $total_saved -gt 0 ]; then
  saved_human=$(numfmt --to=iec "$((total_saved * 1024 * 1024))")
  echo " - 💾 Total space saved: $saved_human"
fi
if [ $total_increased -gt 0 ]; then
  increased_human=$(numfmt --to=iec "$((total_increased * 1024 * 1024))")
  echo " - ℹ️ Total size increase: $increased_human"
fi

echo " "
unset IFS
