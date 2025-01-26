# converthvec
 A script that will convert a variety of video formats to HVEC MKV files. Call the script with a trailing directory path and it will process the items in that location.

*Process*
When processing files, the changes are written to a temp file. Upon success, the original file is removed and replaced with the updated .mkv version.

*Current list of formats it will look into and convert*
3gp asf avc avi flv mkv m4v mov mp4 mpg mpeg webm wmv

*Requires ffmpeg.