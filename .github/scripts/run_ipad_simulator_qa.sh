#!/usr/bin/env bash
set -Eeuo pipefail
DEVICE="${IPAD_DEVICE:-mini}"
VERSION="${IPAD_VERSION:-v6}"
OUTPUT="screenshots-ipad/$DEVICE-$VERSION"
mkdir -p "$OUTPUT"
APP="${IPAD_APP:-ci-app/Runner.app}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    xcrun simctl list devices -j > "$OUTPUT/devices-on-error.json" 2>&1 || true
    xcrun simctl io "$UDID" screenshot "$OUTPUT/screenshot-on-error.png" || true
  fi
  if [[ -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
case "$DEVICE" in
  mini) DEVICE_TYPE='iPad mini (A17 Pro)' ;;
  pro11) DEVICE_TYPE='com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB' ;;
  pro13) DEVICE_TYPE='com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB' ;;
  *) echo "Unknown iPad: $DEVICE" >&2; exit 2 ;;
esac
UDID="$(xcrun simctl create "quran-ci-ipad-$GITHUB_RUN_ID-$DEVICE-$VERSION" "$DEVICE_TYPE" com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
echo "Fresh $DEVICE_TYPE ($VERSION): $UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
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
sleep 3
xcrun simctl io "$UDID" screenshot "$OUTPUT/ipad-$DEVICE-portrait.png"
# The initial intercession tip overlays Quran text. Capture a later state too
# without altering application code, so reviewers can distinguish an
# auto-dismissing overlay from a persistent layout issue.
sleep 18
python3 .github/scripts/simulator_reader_input.py capture "$UDID" "$OUTPUT/ipad-$DEVICE-portrait-after-18s.png"

# Use the Simulator's real rotation action, with no injected application code.
# Confirm the rendered PNG is landscape before accepting the capture.
python3 .github/scripts/simulator_reader_input.py landscape "$UDID" 2>&1 | tee "$OUTPUT/rotation.txt"
sleep 3
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
sleep 2
bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 5
python3 .github/scripts/simulator_reader_input.py capture "$UDID" "$OUTPUT/ipad-$DEVICE-landscape.png" --require-zoom
python3 - "$OUTPUT/ipad-$DEVICE-landscape.png" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    header = f.read(24)
width, height = struct.unpack('>II', header[16:24])
assert width > height, f'Landscape did not render: {width}x{height}'
print(f'Actual landscape PNG: {width}x{height}')
PY
echo "$DEVICE $VERSION: real portrait and landscape captured" | tee "$OUTPUT/status.txt"
