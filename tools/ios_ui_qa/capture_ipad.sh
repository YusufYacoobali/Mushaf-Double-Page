#!/usr/bin/env bash
# One fresh device, bounded operations, independent layout/navigation/zoom cases.
set -Eeuo pipefail
DEVICE="$IPAD_DEVICE"
VERSION="$IPAD_VERSION"
CASE="${IPAD_CASE:-layout}"
OUTPUT="screenshots-native/$DEVICE-$VERSION"
APP="${IPAD_APP:-ci-app/Runner.app}"
mkdir -p "$OUTPUT"
cp .ci/ipad-template.json "$OUTPUT/template.json"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
BOOT_READY=0
op() { local stage="$1" seconds="$2"; shift 2; python3 .github/scripts/ci_run.py --operation "$stage" --timeout "$seconds" --output "$OUTPUT/operations" -- "$@"; }
cleanup() {
  local status=$?
  if [[ -n "$UDID" ]]; then
    if [[ "$BOOT_READY" == 1 ]]; then
      op screenshot 45 xcrun simctl io "$UDID" screenshot "$OUTPUT/final-frame.png" || true
    fi
    op shutdown 45 xcrun simctl shutdown "$UDID" || true
    op delete 45 xcrun simctl delete "$UDID" || true
  fi
  return "$status"
}
trap cleanup EXIT
RUNTIME=$(python3 -c 'import json;print(json.load(open(".ci/ipad-template.json"))["runtime"])')
TYPE=$(python3 -c 'import json;print(json.load(open(".ci/ipad-template.json"))["device"]["deviceTypeIdentifier"])')
# Fresh simulator devices cannot repair a wedged host-wide CoreSimulator service.
# On a throwaway GitHub runner, verify display readiness, install AND app launch
# before declaring startup successful. One failed start triggers a service restart.
CACHE="${READER_ASSET_CACHE:-$PWD/.ci/quran-pages}"
bash .github/scripts/simulator_host_health.sh preflight "$OUTPUT/host-preflight" || true
STARTUP_READY=0
for attempt in 1 2; do
  BOOT_READY=0
  DATA=""
  echo "Starting $DEVICE $VERSION attempt $attempt/2"
  if ! python3 .github/scripts/ci_run.py --operation create --timeout 75 --output "$OUTPUT/operations" --value-file "$OUTPUT/udid.txt" -- xcrun simctl create "reader-$GITHUB_RUN_ID-$DEVICE-$VERSION-$attempt" "$TYPE" "$RUNTIME"; then
    if [[ "$attempt" == 1 ]]; then bash .github/scripts/simulator_host_health.sh recover "$OUTPUT/host-recovery" || true; fi
    continue
  fi
  UDID=$(tail -n 1 "$OUTPUT/udid.txt")
  if op boot 75 xcrun simctl boot "$UDID"; then
    # macOS 15 has the classic Simulator.app. Opening its real display helps
    # initialize render services before trying screenshots and XCTest.
    if [[ -d "${DEVELOPER_DIR:-}/Applications/Simulator.app" ]]; then
      op simulator-ui 35 open -a "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$UDID" || true
    else
      op simulator-ui 35 open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
    fi
    if ! op bootstatus 225 xcrun simctl bootstatus "$UDID" -b; then
      echo "::warning::iPad bootstatus stalled; checking physical display"
    fi
    if op display-ready 65 xcrun simctl io "$UDID" screenshot "$OUTPUT/boot-$attempt.png"; then
      BOOT_READY=1
    fi
  fi
  if [[ "$BOOT_READY" == 1 ]] && op install 150 xcrun simctl install "$UDID" "$APP" &&
      python3 .github/scripts/ci_run.py --operation container --timeout 120 --output "$OUTPUT/operations" --value-file "$OUTPUT/container.txt" -- xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data; then
    DATA=$(tail -n 1 "$OUTPUT/container.txt")
    PREFS="$DATA/Library/Preferences/$BUNDLE_ID.plist"
    if op seed 35 bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID" "$DATA" &&
       op asset-cache 90 python3 .github/scripts/reader_asset_cache.py import --data "$DATA" --prefs "$PREFS" --cache "$CACHE"; then
      # First launch sometimes hangs while SpringBoard finishes first-boot work.
      # A second launch can return a PID if the first call actually started it.
      if op launch 105 xcrun simctl launch "$UDID" "$BUNDLE_ID" ||
         { sleep 8; op launch-retry 105 xcrun simctl launch "$UDID" "$BUNDLE_ID"; }; then
        STARTUP_READY=1
        break
      fi
    fi
  fi
  echo "::warning::iPad $DEVICE $VERSION startup attempt $attempt failed"
  if [[ "$BOOT_READY" == 1 ]]; then op failed-frame 35 xcrun simctl io "$UDID" screenshot "$OUTPUT/failed-$attempt.png" || true; fi
  op shutdown 45 xcrun simctl shutdown "$UDID" || true
  op delete 45 xcrun simctl delete "$UDID" || true
  UDID=""
  if [[ "$attempt" == 1 ]]; then
    bash .github/scripts/simulator_host_health.sh recover "$OUTPUT/host-recovery" || true
  fi
done
if [[ "$STARTUP_READY" != 1 ]]; then
  bash .github/scripts/simulator_host_health.sh diagnose "$OUTPUT/host-final" || true
  echo "::error::iPad CoreSimulator/app startup failed twice; reader UI tests not executed"
  exit 1
fi
# Genuine Quran assets and screenshots, not the simulator boot flag, are the
# proof of a successful application start.
op download 540 python3 .github/scripts/reader_asset_cache.py wait --data "$DATA"
result=0
phase() {
  local name="$1" method="$2"
  local status=0
  op "$name" 210 xcodebuild test-without-building -project tools/ios_ui_qa/ReaderUIHarness.xcodeproj -scheme ReaderVisualTests -derivedDataPath ui-build -destination "id=$UDID" -parallel-testing-enabled NO "-only-testing:ReaderVisualTests/ReaderVisualTests/$method" CODE_SIGNING_ALLOWED=NO || status=$?
  if [[ "$status" != 0 ]]; then result=1; fi
  python3 - "$OUTPUT/cases.json" "$name" "$status" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);cases=json.loads(p.read_text()) if p.exists() else {};cases[sys.argv[2]]={'passed':sys.argv[3]=='0'};p.write_text(json.dumps(cases,indent=2)+'\n')
PY
  TEST_DATA=$(python3 - "$UDID" <<'PY2'
import subprocess,sys
p=subprocess.run(['xcrun','simctl','get_app_container',sys.argv[1],'org.mushaf.visualqa.tests.xctrunner','data'],text=True,capture_output=True,timeout=30)
print(p.stdout.strip() if p.returncode==0 else '')
PY2
)
  if [[ -n "$TEST_DATA" ]]; then
    python3 - "$TEST_DATA/Documents/reader-qa" "$OUTPUT" "$DEVICE" <<'PY'
from pathlib import Path
import shutil,sys
source,destination,device=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
for f in source.glob('*'):
 name=f.name
 if name.startswith('portrait.png'):name=name.replace('portrait.png','portrait-after-18s.png',1)
 shutil.copy2(f,destination/f'ipad-{device}-{name}')
PY
  fi
}
if [[ "$CASE" == layout || "$CASE" == all ]]; then phase rotation testLayout; fi
if [[ "$CASE" == navigation || "$CASE" == all ]]; then phase navigation testNavigation; fi
if [[ "$CASE" == zoom || "$CASE" == all ]]; then phase zoom testZoom; fi
op asset-cache 90 python3 .github/scripts/reader_asset_cache.py export --data "$DATA" --prefs "$PREFS" --cache "$CACHE" || true
if [[ -f "$DATA/Documents/reader-geometry.json" ]]; then cp "$DATA/Documents/reader-geometry.json" "$OUTPUT/rendered-geometry.json"; fi
exit "$result"
