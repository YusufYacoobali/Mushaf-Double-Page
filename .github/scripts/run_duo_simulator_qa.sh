#!/usr/bin/env bash
# A single fresh simulator. Fail the requested case, not an unrelated matrix.
set -Eeuo pipefail
mkdir -p screenshots/operations
APP=ci-app/Runner.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
STARTUP_READY=0
op() { local stage="$1" seconds="$2"; shift 2; python3 .github/scripts/ci_run.py --operation "$stage" --timeout "$seconds" --output screenshots/operations -- "$@"; }
cleanup() {
 local status=$?
 if [[ -n "${DATA:-}" && ! -f "${CACHE:-/nonexistent}/pages.json" ]]; then
  op asset-cache 90 python3 .github/scripts/reader_asset_cache.py export --data "$DATA" --prefs "$DATA/Library/Preferences/$BUNDLE_ID.plist" --cache "$CACHE" || true
 fi
 if [[ -n "$UDID" ]]; then
  # Do not waste time trying to capture an unresponsive simulator display.
  if [[ "$STARTUP_READY" == 1 ]]; then op screenshot 45 duoctl screenshot screenshots/final-frame.png || true; fi
  if [[ "$status" -ne 0 ]]; then bash .github/scripts/simulator_host_health.sh diagnose screenshots/host-health || true; fi
  op shutdown 45 xcrun simctl shutdown "$UDID" || true
  op delete 45 xcrun simctl delete "$UDID" || true
 fi
 return "$status"
}
trap cleanup EXIT
# On hosted Xcode 27 the device may be Booted while display services hang.
# Require responsive physical display evidence, not merely a state flag.
# Recover at most once with a NEW isolated Duo instead of restarting all QA.
CACHE="${READER_ASSET_CACHE:-$PWD/.ci/quran-pages}"
# Prime the host simulator services and record its actual runtime mount state.
bash .github/scripts/simulator_host_health.sh preflight screenshots/host-preflight || true
for attempt in 1 2; do
  echo "Starting Duo simulator attempt $attempt/2"
  DATA=""
  if ! python3 .github/scripts/ci_run.py --operation create --timeout 75 --output screenshots/operations --value-file screenshots/udid.txt -- xcrun simctl create "reader-$GITHUB_RUN_ID-$attempt" 'iPhone Duo' com.apple.CoreSimulator.SimRuntime.iOS-27-1; then
    continue
  fi
  UDID=$(tail -n 1 screenshots/udid.txt)
  export DUOCTL_UDID="$UDID"
  booted=0
  if op boot 90 xcrun simctl boot "$UDID"; then
    # Xcode 27 uses Device Hub, not the old Simulator.app. Attach its real
    # display panel; a merely Booted CoreSimulator state is not sufficient.
    op device-hub 35 open -b com.apple.dt.Devices "devices://manage/select?id=$UDID" || true
    if ! op bootstatus 230 xcrun simctl bootstatus "$UDID" -b; then
      echo "::warning::Duo bootstatus stalled; testing actual display readiness"
    fi
    if op display-ready 60 duoctl state &&
       op display-capture 60 duoctl screenshot "screenshots/duo-startup-$attempt.png"; then
      booted=1
    fi
  fi
  if [[ "$booted" == 1 ]]; then
    if op install 150 xcrun simctl install "$UDID" "$APP" &&
       python3 .github/scripts/ci_run.py --operation container --timeout 120 --output screenshots/operations --value-file screenshots/container.txt -- xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data; then
      DATA=$(tail -n 1 screenshots/container.txt)
      if op seed 35 bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID" "$DATA" &&
         op asset-cache 120 python3 .github/scripts/reader_asset_cache.py import --data "$DATA" --prefs "$DATA/Library/Preferences/$BUNDLE_ID.plist" --cache "$CACHE" &&
         op launch 90 xcrun simctl launch "$UDID" "$BUNDLE_ID"; then
        STARTUP_READY=1
        break
      fi
    fi
  fi
  echo "::warning::Duo startup attempt $attempt failed; discarding simulator"
  op shutdown 60 xcrun simctl shutdown "$UDID" || true
  op delete 60 xcrun simctl delete "$UDID" || true
  UDID=""
  if [[ "$attempt" == 1 ]]; then
    # Discarding the simulated device alone left the *same* blocked host
    # service in both previous attempts. Recover that service exactly once.
    bash .github/scripts/simulator_host_health.sh recover screenshots/host-recovery || true
  fi
done
if [[ "$STARTUP_READY" != 1 ]]; then
  echo "::error::Both isolated Duo startup attempts failed; see stage diagnostics"
  exit 1
fi
op download 540 python3 .github/scripts/reader_asset_cache.py wait --data "$DATA"
CASE="${READER_TEST_CASE:-layout}"
TARGET="${DUO_TARGET:-duo-smoke}"
PROFILE="${READER_CAPTURE_PROFILE:-smoke}"
MODES="folded portrait landscape book"
if [[ "$TARGET" != duo-smoke ]]; then MODES="${TARGET#duo-}"; fi
for mode in $MODES; do
 export READER_CASE="$mode"
 case "$mode" in
  folded) op posture 45 duoctl close; LABEL=duo-folded; MIN=70; EXPECT=single ;;
  portrait) op posture 45 duoctl open; op rotation 45 duoctl rotate portrait; LABEL=duo-unfolded-portrait; MIN=70; EXPECT=single ;;
  landscape) op posture 45 duoctl open; op rotation 45 duoctl rotate landscape; LABEL=duo-unfolded-wide; MIN=60; EXPECT=spread ;;
  book) op posture 45 duoctl half; op rotation 45 duoctl rotate landscape; LABEL=duo-half-open-book; MIN=60; EXPECT=dualScreenBook ;;
  *) echo "Unknown Duo target $TARGET" >&2; exit 2 ;;
 esac
 sleep 1
 if [[ "$CASE" == navigation || "$CASE" == zoom ]]; then
  op launch 90 python3 .github/scripts/simulator_reader_input.py capture "$UDID" "screenshots/$LABEL-launch.png" --layout-metadata "$DATA/Documents/reader-geometry.json" --expected-mode "$EXPECT"
 fi
 if [[ "$CASE" == layout || "$CASE" == all ]]; then
  if [[ "$PROFILE" == endpoints ]]; then
   bash .github/scripts/capture_duo_zoom.sh "$LABEL" "$MIN" 100
  else
   bash .github/scripts/capture_duo_zoom.sh "$LABEL" 100 100
  fi
  if [[ "$mode" == book ]]; then
   op gesture 50 python3 .github/scripts/record_book_swipe.py
   op screenshot 90 python3 .github/scripts/simulator_reader_input.py capture "$UDID" screenshots/duo-half-open-book-after-swipe.png --zoom 100 --layout-metadata "$DATA/Documents/reader-geometry.json" --expected-mode dualScreenBook
   op gesture 15 python3 - "$DATA/Documents/reader-geometry.json" "$DATA/Library/Preferences/$BUNDLE_ID.plist" <<'PY'
import json,plistlib,sys,time
rendered=json.load(open(sys.argv[1]));assert rendered['focusedPage']==6,rendered
page=None
for _ in range(10):
 page=plistlib.load(open(sys.argv[2],'rb')).get('flutter.CurrentPage1')
 if page==6:break
 time.sleep(.3)
result={'expectedFocusedPage':6,'observedFocusedPage':page};json.dump(result,open('screenshots/duo-book-swipe-result.json','w'));assert page==6,result
PY
  fi
 fi
 if [[ "$CASE" == navigation || "$CASE" == all ]]; then
  op navigation 100 python3 .github/scripts/duo_controls.py navigation "$UDID" "$DATA/Documents/reader-geometry.json" "screenshots/$LABEL-navigation"
 fi
 if [[ "$CASE" == zoom || "$CASE" == all ]]; then
  op zoom 240 python3 .github/scripts/duo_controls.py zoom "$UDID" "$DATA/Documents/reader-geometry.json" "screenshots/$LABEL-zoom"
 fi
 echo "PASS $LABEL $CASE" | tee -a screenshots/case-results.txt
done
op asset-cache 90 python3 .github/scripts/reader_asset_cache.py export --data "$DATA" --prefs "$DATA/Library/Preferences/$BUNDLE_ID.plist" --cache "$CACHE" || true
