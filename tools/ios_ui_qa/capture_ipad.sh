#!/usr/bin/env bash
# Keep the proven clean-device/download setup; use XCTest for conventional iPads.
set -Eeuo pipefail
DEVICE="$IPAD_DEVICE"
VERSION="$IPAD_VERSION"
OUTPUT="screenshots-native/$DEVICE-$VERSION"
mkdir -p "$OUTPUT"
APP="${IPAD_APP:-ci-app/Runner.app}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
cleanup() {
  local status=$?
  if [[ -n "$UDID" ]]; then
    xcrun simctl io "$UDID" screenshot "$OUTPUT/final-frame.png" || true
    xcrun simctl shutdown "$UDID" || true
    xcrun simctl delete "$UDID" || true
  fi
  return "$status"
}
trap cleanup EXIT
xcrun simctl list devices available -j > "$OUTPUT/devices.json"
python3 - "$OUTPUT/devices.json" "$DEVICE" "$OUTPUT/template.json" <<'PY'
import json, re, sys
source, device, destination = sys.argv[1:]
needle = {'mini': 'iPad mini', 'pro11': 'iPad Pro 11-inch', 'pro13': 'iPad Pro 13-inch'}[device]
options = [(tuple(map(int, re.findall(r'\d+', runtime))), runtime, item)
           for runtime, devices in json.load(open(source))['devices'].items() if '.iOS-' in runtime
           for item in devices if item.get('isAvailable') and needle in item['name']]
assert options, f'No available simulator matching {needle}'
_, runtime, template = max(options, key=lambda item: item[0])
json.dump({'runtime': runtime, 'device': template}, open(destination, 'w'), indent=2)
print(f"Using {template['name']} on {runtime}")
PY
RUNTIME=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["runtime"])' "$OUTPUT/template.json")
TYPE=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["device"];print(d.get("deviceTypeIdentifier", d["name"]))' "$OUTPUT/template.json")
UDID=$(xcrun simctl create "reader-ui-$GITHUB_RUN_ID-$DEVICE-$VERSION" "$TYPE" "$RUNTIME")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
sleep 5
xcrun simctl launch "$UDID" "$BUNDLE_ID"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
ready=0
for n in $(seq 1 60); do
  count=0
  if [[ -d "$DATA/Documents/indopak_tajweed" ]]; then
    count=$(find "$DATA/Documents/indopak_tajweed" -type f -name '*.webp' | wc -l | tr -d ' ')
  fi
  echo "$DEVICE $VERSION: Quran images $count/851"
  if [[ "$count" -ge 851 ]]; then ready=1; break; fi
  sleep 7
done
[[ "$ready" == 1 ]] || { echo 'Reader did not load its real Quran pages' >&2; exit 1; }

result=0
xcodebuild test-without-building -project tools/ios_ui_qa/ReaderUIHarness.xcodeproj \
  -scheme ReaderVisualTests -derivedDataPath ui-build -destination "id=$UDID" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO > "$OUTPUT/xctest.log" 2>&1 || result=$?
TEST_DATA=$(xcrun simctl get_app_container "$UDID" org.mushaf.visualqa.tests.xctrunner data 2>/dev/null || true)
if [[ -n "$TEST_DATA" ]]; then
  cp "$TEST_DATA/Documents/reader-qa/portrait.png" "$OUTPUT/ipad-$DEVICE-portrait-after-18s.png" || true
  cp "$TEST_DATA/Documents/reader-qa/landscape.png" "$OUTPUT/ipad-$DEVICE-landscape.png" || true
  for frame in portrait-70 portrait-100 landscape-60 landscape-100; do
    cp "$TEST_DATA/Documents/reader-qa/$frame.png" "$OUTPUT/ipad-$DEVICE-$frame.png" || true
  done
fi
python3 - "$OUTPUT" "$DEVICE" <<'PY'
from pathlib import Path
from PIL import Image, ImageOps
import sys
root, device = Path(sys.argv[1]), sys.argv[2]
for mode in ['portrait-after-18s', 'landscape']:
    path = root / f'ipad-{device}-{mode}.png'
    # XCTest stores landscape pixels in sensor orientation with EXIF rotation.
    # Validate the displayed image, keeping the original screenshot untouched.
    width, height = ImageOps.exif_transpose(Image.open(path)).size
    assert (width > height) == (mode == 'landscape'), (mode, width, height)
    print(f'Actual {mode} PNG: {width}x{height}')
PY
exit "$result"
