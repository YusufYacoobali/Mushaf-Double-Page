#!/usr/bin/env bash
# A genuine simulator screen recording, plus stills that verify the pair moved
# from 4/5 to 6/7. Video failures are reported separately from mandatory stills.
set -Eeuo pipefail
UDID="$DUOCTL_UDID"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' ci-app/Runner.app/Info.plist)
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
bash .github/scripts/capture_duo_zoom.sh duo-half-open-book 80 80
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
rm -f "$DATA/Documents/reader-qa.json"
SIMCTL_CHILD_MUSHAF_QA_TEST=1 SIMCTL_CHILD_MUSHAF_QA_ZOOM=0.8 \
  xcrun simctl launch "$UDID" "$BUNDLE_ID" > screenshots/book-navigation-app.log 2>&1
record_pid=""
cleanup_recording() {
  if [[ -n "$record_pid" ]]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" || true
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup_recording EXIT
sleep 12
duoctl state > screenshots/book-navigation-state.json
display="$(python3 -c 'import json;print(json.load(open("screenshots/book-navigation-state.json"))["displayId"])')"
cp "$DATA/Documents/reader-qa.json" screenshots/book-navigation-before-live.json
python3 .github/scripts/verify_reader_render.py screenshots/book-navigation-before-live.json dualScreenBook 80 screenshots/book-navigation-before.json
duoctl screenshot screenshots/book-navigation-before.png
xcrun simctl io "$UDID" recordVideo --display="$display" --codec=h264 screenshots/book-navigation.mp4 > screenshots/book-recording.log 2>&1 &
record_pid=$!
sleep 2
duoctl swipe 150 300 800 300 --duration 0.6
sleep 3
duoctl screenshot screenshots/book-navigation-after.png
cp "$DATA/Documents/reader-qa.json" screenshots/book-navigation-after-live.json
python3 .github/scripts/verify_reader_render.py screenshots/book-navigation-after-live.json dualScreenBook 80 screenshots/book-navigation-after.json 6
cleanup_recording
trap - EXIT
if [[ -s screenshots/book-navigation.mp4 ]]; then
  echo 'Created actual book-mode simulator screen recording' > screenshots/video-status.txt
else
  echo 'Video unsupported; see book-recording.log. Navigation stills verified.' > screenshots/video-status.txt
fi
