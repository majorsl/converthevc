# converthevc
 A script that will convert a variety of video formats to HVEC MKV files. Call the script with a trailing directory path and it will process the items in that location.

*Process*

When processing files, the changes are written to a temp file. Upon success, the original file is removed and replaced with the updated .mkv version.

The script will pause if another instances of itself is running. If the script pauses, the script is probably running from another call. It will ait until that completes before processing files. This is for automations where the script may be called multiple times from another script or binary and will keep the processor from getting overwhlmed with conversions.

*Current list of formats it will look into and convert*

3gp asf avc avi flv mkv m4v mov mp4 mpg mpeg webm wmv

When complete it will give a summary of its work.

📋 Totals:
 - ✅ Converted successfully: 8
 - 🔁 Skipped (already HEVC): 136
 - ❌ Failed conversions: 0
 - 📈 Increased file size: 0
 - 💾 Total space saved: 1.45 GB

*Requires ffmpeg.
