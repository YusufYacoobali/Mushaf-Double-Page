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
# Keep the successfully booted v5 simulator alive for the v6 comparison.
# Reusing the same guest avoids a second costly CoreSimulator cold-start.
KEEP_DEVICE="${IPAD_KEEP_DEVICE:-0}"
REUSE_UDID="${IPAD_REUSE_UDID:-}"
op() { local stage="$1" seconds="$2"; shift 2; python3 .github/scripts/ci_run.py --operation "$stage" --timeout "$seconds" --output "$OUTPUT/operations" -- "$@"; }
cleanup() {
  local status=$?
  if [[ -n "$UDID" ]]; then
    if [[ "$status" == 0 && "$KEEP_DEVICE" == 1 ]]; then
      mkdir -p .ci
      printf '%s\n' "$UDID" > ".ci/ipad-$DEVICE-reuse-udid.txt"
      echo "Preserved booted v5 iPad $UDID for v6 on the same runner"
      return 0
    fi
    # Diagnostics are already in operations/ and XCTest attachments.
    # A second screenshot at shutdown often hangs the same display service.
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
  if [[ "$attempt" == 1 && -n "$REUSE_UDID" ]]; then
    UDID="$REUSE_UDID"
    echo "Reusing already-booted v5 simulator $UDID; skipping create, boot and GUI"
    if op reuse-ready 55 xcrun simctl spawn "$UDID" /usr/bin/true; then
      BOOT_READY=1
      # Same app bundle ID: uninstall v5 so v6 has clean, isolated preferences.
      op terminate-v5 25 xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
      op uninstall-v5 45 xcrun simctl uninstall "$UDID" "$BUNDLE_ID" || true
    fi
  else
    if ! python3 .github/scripts/ci_run.py --operation create --timeout 75 --output "$OUTPUT/operations" --value-file "$OUTPUT/udid.txt" -- xcrun simctl create "reader-$GITHUB_RUN_ID-$DEVICE-$VERSION-$attempt" "$TYPE" "$RUNTIME"; then
      if [[ "$attempt" == 1 ]]; then bash .github/scripts/simulator_host_health.sh recover "$OUTPUT/host-recovery" || true; fi
      continue
    fi
    UDID=$(tail -n 1 "$OUTPUT/udid.txt")
    if op boot 75 xcrun simctl boot "$UDID"; then
      # Opening Simulator.app is optional: CoreSimulator and XCTest can render
      # headlessly, and a blocked GUI must not prevent the actual app launch.
      if [[ -d "${DEVELOPER_DIR:-}/Applications/Simulator.app" ]]; then
        op simulator-ui 35 open -a "$DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$UDID" || true
      fi
      if op bootstatus 225 xcrun simctl bootstatus "$UDID" -b; then
        BOOT_READY=1
      fi
    fi
  fi
  # The old harness took a pre-app screenshot here and discarded otherwise
  # healthy devices when CoreSimulator's display daemon was slow. Install and
  # launch first; XCTest will provide the required genuine reader screenshots.
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
  # Don't call an already wedged screenshot service again as a failure probe.
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
