#!/usr/bin/env bash
# Version 1.2.0 *See README.md for requirements*

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# Path to ffmpeg
FFMPEG="/usr/bin"
# Timeout if a tmp file never vanishes
TIMEOUT=14400
# -----------------------------------------------------------------------------------------------
IFS=$'\n'

# Check if a directory is passed as an argument
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "Please call the script with a trailing directory to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "$WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Process various video formats
find "$WORKINGDIRECTORY" -type f \( -iname "*.avc" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.MOV" -o -iname "*.wmv" -o -iname "*.asf" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.3gp" \) -print0 | while IFS= read -r -d '' file
do
  # Extract base name without extension to compare
  base_name="${file%.*}"
  # Construct the temporary file and original file paths
  temp_file="${base_name}.tmp.${file##*.}"  # e.g., file.tmp.mkv
  original_file="${base_name}.${file##*.}"  # e.g., file.mkv or file.mp4
  
  # Pause and check every 5 minutes if a temp file exists, another process is working already
  if [[ -f "$temp_file" ]]; then
    echo "Temporary file $temp_file exists. Pausing until it is removed or timeout occurs."
    elapsed_time=0
    while [[ -f "$temp_file" && $elapsed_time -lt $TIMEOUT ]]; do
      sleep 300
      ((elapsed_time+=300))
    done
    
    # Check if we exited due to timeout
    if [[ -f "$temp_file" ]]; then
      echo "Timeout reached. Temporary file $temp_file still exists after 10 minutes. Exiting script."
      exit 1  # Exit with an error status
    else
      echo "Temporary file $temp_file removed. Resuming processing."
    fi
  fi

  echo "Processing $file"
  
  # Check if the file already has HEVC video codec
  codec=$("$FFMPEG/ffprobe" -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
  
  # Only convert if the video is not already HEVC
  if [[ "$codec" != "hevc" ]]; then
    # Get all stream info (codec_name, channels for audio, and resolution for video)
    file_info=$("$FFMPEG/ffprobe" -v error -select_streams a:v:s -show_entries stream=codec_name,channels,width,height -of default=nokey=1:noprint_wrappers=1 "$file")
    
    # Start constructing the map_str for video and subtitle streams
    map_str=()
    map_str+=("-map" "0:v")  # Always map video streams

    # Check if there are subtitle streams and map them if they exist
    subtitle_streams=$("$FFMPEG/ffprobe" -v error -select_streams s -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$file")
    if [ -n "$subtitle_streams" ]; then
      map_str+=("-map" "0:s")  # Add subtitle streams only if they exist
    fi

    # Loop through each audio stream and add it to map_str
    track_num=0
    while read -r line; do
      acodec=$(echo "$line" | cut -d' ' -f1)
      achannels=$(echo "$line" | cut -d' ' -f2)
      
      # Add the current audio track to the map, ensuring it exists
      map_str+=("-map" "0:a:$track_num?")  # Add '?' to ignore missing streams

      # Increment track number for the next loop
      ((track_num++))

    done <<< "$file_info"

    # Prepare the new file name for output with a temporary name but always with .mkv extension
    temp_newfile="${base_name}.tmp.mkv"

    echo "Converting video stream of $file to HEVC (H.265)..."

    # Perform the conversion with ffmpeg (video to HEVC, audio and subtitle streams remain unchanged)
    "$FFMPEG/ffmpeg" -nostdin -i "$file" "${map_str[@]}" -vcodec libx265 -acodec copy -scodec copy -preset fast -crf 28 "$temp_newfile"

    # Check if ffmpeg command succeeded
    if [ $? -eq 0 ]; then
      echo "Conversion successful, replacing the original file with the new one."
      rm "$file"
      mv "$temp_newfile" "${base_name}.mkv"

    else
      echo "Conversion failed for $file. Original file remains unchanged."
      # Remove the temporary file if conversion failed
      rm "$temp_newfile"
    fi
  else
    echo "File $file already has HEVC video, skipping conversion."
  fi
done

unset IFS
