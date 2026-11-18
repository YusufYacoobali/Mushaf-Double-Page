#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p screenshots-ipad
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    xcrun simctl list devices -j > screenshots-ipad/devices-on-error.json 2>&1 || true
    xcrun simctl io "$UDID" screenshot screenshots-ipad/screenshot-on-error.png || true
  fi
  if [[ -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
FAMILY="${IPAD_FAMILY:-mini}"
xcrun simctl list devicetypes -j > screenshots-ipad/device-types.json
TYPE="$(python3 - screenshots-ipad/device-types.json "$FAMILY" <<'PY'
import json, re, sys
patterns = {'mini': r'^iPad mini', 'ipad': r'^iPad \(',
            'air11': r'^iPad Air 11', 'air13': r'^iPad Air 13',
            'pro11': r'^iPad Pro 11', 'pro13': r'^iPad Pro 13'}
devices = [d for d in json.load(open(sys.argv[1]))['devicetypes']
           if re.search(patterns[sys.argv[2]], d['name'])]
assert devices, f'No simulator device for {sys.argv[2]}'
print(devices[-1]['identifier'])
PY
)"
UDID="$(xcrun simctl create "quran-ci-ipad-$FAMILY-$GITHUB_RUN_ID" "$TYPE" com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
echo "Fresh iPad $FAMILY ($TYPE): $UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
sleep 5
for n in 1 2 3 4; do
  if xcrun simctl launch "$UDID" "$BUNDLE_ID"; then break; fi
  sleep 7
done
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
ready=0
for n in $(seq 1 45); do
  count=0
  if [[ -d "$DATA/Documents/indopak_tajweed" ]]; then
    count=$(find "$DATA/Documents/indopak_tajweed" -type f -name '*.webp' | wc -l | tr -d ' ')
  fi
  echo "iPad Quran images: $count/851"
  if [[ "$count" -ge 851 ]]; then ready=1; break; fi
  sleep 7
done
[[ "$ready" -eq 1 ]] || { echo "::error::iPad did not load real Quran pages"; exit 1; }
export SIMULATOR_UDID="$UDID" CAPTURE_DEVICE=ipad SCREENSHOTS_DIR=screenshots-ipad
failures=0
for orientation in portrait landscape; do
  if python3 .github/scripts/simulator_orientation.py "$UDID" "$orientation" > "screenshots-ipad/$FAMILY-$orientation-state.json"; then
    if [[ "$orientation" == portrait ]]; then
      minimum=70; key=quran_single_page_scale; mode=single
    else
      minimum=60; key=quran_landscape_page_scale; mode=spread
    fi
    if ! bash .github/scripts/capture_reader_zoom.sh "ipad-$FAMILY-$orientation" "$minimum" 100 "$key" "$mode"; then
      failures=$((failures+1))
    fi
  else
    failures=$((failures+1))
  fi
done
echo "iPad $FAMILY failed cases: $failures" | tee screenshots-ipad/status.txt
[[ "$failures" -eq 0 ]]
