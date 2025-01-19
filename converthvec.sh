#!/usr/bin/env bash
# Version 1.1.2 *See README.md for requirements*

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# Path to ffmpeg
FFMPEG="/usr/bin"
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
find "$WORKINGDIRECTORY" -type f \( -iname "*.webm" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.MOV" -o -iname "*.wmv" -o -iname "*.asf" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.flv" -o -iname "*.3gp" \) -print0 | while IFS= read -r -d '' file
do
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

    # Prepare the new file name for output
    newfile="${file%.*}.mkv"

    echo "Converting video stream of $file to HEVC (H.265)..."

    # Perform the conversion with ffmpeg (video to HEVC, audio and subtitle streams remain unchanged)
    "$FFMPEG/ffmpeg" -i "$file" "${map_str[@]}" -vcodec libx265 -acodec copy -scodec copy -preset fast -crf 28 "$newfile"

    # Check if ffmpeg command succeeded
    if [ $? -eq 0 ]; then
      echo "Conversion successful, removing original file and replacing with new one."

      # Remove the original file
      rm "$file"

      # Rename the new file to replace the original
      mv "$newfile" "$file"
    else
      echo "Conversion failed for $file. Original file remains unchanged."
    fi
  else
    echo "File $file already has HEVC video, skipping conversion."
  fi
done

unset IFS
