#!/usr/bin/env bash
set -Eeuo pipefail
# macOS does not provide GNU timeout; use Perl alarm around potentially hung simctl calls.
timeout() { perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\\n"' "$@"; }
mkdir -p screenshots-ipad
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
QA_PAGE="${READER_QA_PAGE:-6}"
# Configure only the disposable simulator; production defaults remain intact.
export READER_QA_PAGE="$QA_PAGE" READER_QA_SINGLE_ZOOM=100 READER_QA_SPREAD_ZOOM=100
UDID=""
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    timeout 20 xcrun simctl list devices -j > screenshots-ipad/devices-on-error.json 2>&1 || true
    if [[ -n "$UDID" ]]; then
      timeout 50 xcrun simctl spawn "$UDID" log show --last 6m --style compact --predicate 'process == "Runner" OR (process == "runningboardd" AND eventMessage CONTAINS "Runner")' > screenshots-ipad/runner-app-log.txt 2>&1 || true
    fi
    [[ -n "$UDID" ]] && timeout 20 xcrun simctl io "$UDID" screenshot screenshots-ipad/screenshot-on-error.png || true
  fi
  if [[ -n "$UDID" ]]; then
    timeout 20 xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    timeout 20 xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
echo "::group::Create and boot iPad mini"
UDID="$(timeout 90 xcrun simctl create "quran-ci-ipad-$GITHUB_RUN_ID" 'iPad mini (A17 Pro)' com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
echo "Fresh iPad mini: $UDID"
timeout 90 xcrun simctl boot "$UDID"
timeout 600 xcrun simctl bootstatus "$UDID" -b
echo "::endgroup::"
echo "::group::Install and launch Quran"
timeout 240 xcrun simctl install "$UDID" "$APP"
# Clear any cached UserDefaults before writing the disposable app container.
# Rendered geometry below must still confirm the requested page and both zooms.
timeout 30 xcrun simctl spawn "$UDID" killall cfprefsd >/dev/null 2>&1 || true
sleep 1
bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
sleep 2
launched_after="$(python3 -c 'import time; print(time.time())')"
launched=0
for n in 1 2 3; do
  if timeout 90 xcrun simctl launch "$UDID" "$BUNDLE_ID"; then launched=1; break; fi
  sleep 4
done
[[ "$launched" -eq 1 ]] || { echo "::error::iPad app launch failed"; exit 1; }
echo "::endgroup::"
echo "::group::Wait for real Quran pages"
DATA="$(timeout 90 xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
ready=0
for n in $(seq 1 45); do
  count=0
  if [[ -d "$DATA/Documents/indopak_tajweed" ]]; then
    count=$(find "$DATA/Documents/indopak_tajweed" -type f -name '*.webp' | wc -l | tr -d ' ')
  fi
  echo "iPad Quran images: $count/851"
  if [[ "$count" -ge 851 ]]; then ready=1; break; fi
  if [[ "$n" == 4 || "$n" == 14 ]]; then
    # simctl launch returns a PID before Flutter's first frame. Reopen the
    # same container if the process exited during first boot.
    if running="$(timeout 25 xcrun simctl spawn "$UDID" launchctl list)" &&
       ! awk -v id="$BUNDLE_ID" '$1 ~ /^[0-9]+$/ && index($3, id) { found=1 } END {exit !found}' <<< "$running"; then
      echo "::warning::Reader process exited on cold iPad boot; relaunching"
      timeout 90 xcrun simctl launch "$UDID" "$BUNDLE_ID"
    fi
  fi
  sleep 5
done
[[ "$ready" -eq 1 ]] || { echo "::error::iPad did not load real Quran pages"; exit 1; }
echo "::endgroup::"
sleep 18
# The first-launch notification prompt can cover portrait while geometry still
# passes. Clear only the known app prompt and require a clear screen before PNG.
echo "::group::Prepare unobstructed iPad mini portrait"
python3 .github/scripts/ci_run.py --operation ipad-portrait-preparation --timeout 360 \
  --output screenshots-ipad/portrait-preparation -- \
  xcodebuild test-without-building -project tools/ios_ui_qa/ReaderUIHarness.xcodeproj \
  -scheme ReaderVisualTests -derivedDataPath ui-build \
  -destination "platform=iOS Simulator,id=$UDID" -parallel-testing-enabled NO \
  -only-testing:ReaderVisualTests/ReaderVisualTests/testPreparePortrait \
  -resultBundlePath screenshots-ipad/portrait-preparation.xcresult CODE_SIGNING_ALLOWED=NO
echo "::endgroup::"
python3 .github/scripts/capture_reader_endpoint.py "$DATA/Documents/reader-geometry.json" \
  screenshots-ipad/ipad-mini-portrait.png ipad-mini 100 "$launched_after" --udid "$UDID" --page "$QA_PAGE"
# Rotate the actual running simulator. Both zoom preferences were seeded at
# 100%, so rotation keeps the requested page without restarting the app.
echo "::group::Rotate iPad mini to landscape"
rotated_after="$(python3 -c 'import time; print(time.time())')"
python3 .github/scripts/ci_run.py --operation ipad-landscape-rotation --timeout 360 \
  --output screenshots-ipad/rotation -- \
  xcodebuild test-without-building -project tools/ios_ui_qa/ReaderUIHarness.xcodeproj \
  -scheme ReaderVisualTests -derivedDataPath ui-build \
  -destination "platform=iOS Simulator,id=$UDID" -parallel-testing-enabled NO \
  -only-testing:ReaderVisualTests/ReaderVisualTests/testRotateLandscape \
  -resultBundlePath screenshots-ipad/rotation.xcresult CODE_SIGNING_ALLOWED=NO
echo "::endgroup::"
python3 .github/scripts/capture_reader_endpoint.py "$DATA/Documents/reader-geometry.json" \
  screenshots-ipad/ipad-mini-landscape.png ipad-mini-landscape 100 "$rotated_after" --udid "$UDID" --page "$QA_PAGE"
echo "iPad mini: verified portrait and landscape at 100%, reader page=$QA_PAGE" | tee screenshots-ipad/status.txt
