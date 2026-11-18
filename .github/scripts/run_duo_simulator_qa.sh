#!/usr/bin/env bash
# Fresh, dedicated simulator on a clean GitHub Actions runner. Building the
# Flutter app on the same runner previously exhausted the iPhone Duo simulator.
set -Eeuo pipefail
mkdir -p screenshots
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
attempt=0

diagnose() {
  echo "Collecting Duo simulator diagnostics"
  xcrun simctl list devices -j > screenshots/all-simulator-devices.json 2>&1 || true
  xcrun simctl list runtimes -j > screenshots/available-runtimes.json 2>&1 || true
  (sysctl hw.memsize; vm_stat; df -h .) > screenshots/runner-resources.txt 2>&1 || true
  if [[ -n "$UDID" ]]; then
    xcrun simctl listapps "$UDID" > screenshots/installed-apps.txt 2>&1 || true
    xcrun simctl spawn "$UDID" log show --last 4m --style compact --predicate 'process == "Runner"' > screenshots/runner-app-log.txt 2>&1 || true
    duoctl state > screenshots/last-duo-state.json 2>&1 || true
    duoctl screenshot screenshots/last-duo-screen.png || true
  fi
}
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then diagnose; fi
  if [[ -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

device_state() {
  xcrun simctl list devices -j | jq -r --arg id "$UDID" '[.devices[][] | select(.udid == $id) | .state][0] // "Missing"'
}
new_device() {
  if [[ -n "$UDID" ]]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
  local name="quran-ci-duo-$GITHUB_RUN_ID-$attempt"
  # Apple iOS 27.1 is the Duo-specific runtime; use a brand-new device, not
  # the hosted image's default C898... device, which repeatedly shut down.
  if ! UDID="$(xcrun simctl create "$name" 'iPhone Duo' com.apple.CoreSimulator.SimRuntime.iOS-27-1)"; then
    echo "Explicit iOS 27.1 runtime unavailable; trying latest compatible runtime"
    UDID="$(xcrun simctl create "$name" 'iPhone Duo')" || return 1
  fi
  echo "Created fresh Duo simulator $UDID"
  export DUOCTL_UDID="$UDID"
  xcrun simctl boot "$UDID" || return 1
  xcrun simctl bootstatus "$UDID" -b || return 1
  [[ "$(device_state)" == "Booted" ]] || return 1
}
start_app() {
  echo "Installing on freshly booted Duo $UDID"
  xcrun simctl install "$UDID" "$APP" || return 1
  bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID" || return 1
  sleep 5
  local n
  for n in 1 2 3 4; do
    echo "App launch attempt $n; simulator state=$(device_state)"
    [[ "$(device_state)" == "Booted" ]] || return 1
    if xcrun simctl launch "$UDID" "$BUNDLE_ID"; then return 0; fi
    sleep 8
  done
  return 1
}
wait_for_real_quran_pages() {
  local data count n
  data="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)" || return 1
  for n in $(seq 1 42); do
    if [[ "$(device_state)" != "Booted" ]]; then
      echo "Duo simulator shut down during the Quran download"
      return 1
    fi
    count=0
    if [[ -d "$data/Documents/indopak_tajweed" ]]; then
      count=$(find "$data/Documents/indopak_tajweed" -type f -name '*.webp' | wc -l | tr -d ' ')
    fi
    echo "Duo Quran images $count / 851 ($n/42)"
    if [[ "$count" -ge 851 ]]; then
      echo "PASS: 851 real Quran images installed" | tee screenshots/page-download.txt
      return 0
    fi
    sleep 7
  done
  echo "::error::Actual Quran pages failed to load, not a visual test pass"
  return 1
}
ready=0
for attempt in 1 2; do
  echo "Starting isolated Duo attempt $attempt/2"
  if new_device && start_app && wait_for_real_quran_pages; then
    ready=1
    break
  fi
  echo "Attempt $attempt failed; creating a NEW simulator instead of endlessly rebooting a broken instance"
done
if [[ "$ready" != 1 ]]; then
  echo "::error::Unable to keep a brand-new iPhone Duo simulator running on the hosted runner"
  exit 1
fi
export DUOCTL_UDID="$UDID"
# A clean iOS 27 Duo displays a first-run notification permission alert on
# top of the actual Quran reader (seen in artifact 14371470393). Dismiss
# the system alert using a real active-display touch before any captures.
# The "Don't Allow" button is centred at (120, 385) logical points on the
# 466 x 678 cover display; this changes ONLY the disposable simulator.
duoctl screenshot screenshots/duo-first-launch-permission.png || true
echo "Dismissing first-run iOS notification permission alert"
duoctl tap 120 385
sleep 3
duoctl screenshot screenshots/duo-after-permission.png || true
# AXe's describe-ui times out on GitHub's iOS 27 Duo simulator even
# when the app and its 851 real pages are loaded. Never gate screenshots on
# that unrelated accessibility service.
sleep 2
duoctl state > screenshots/duo-initial-state.json
echo "App launched; 851 Quran images exist. Capturing actual reader renders."

failures=0
run_case() {
  local label="$1" minimum="$2" maximum="$3"
  echo "Capturing $label ($minimum% / $maximum%)"
  if ! bash .github/scripts/capture_duo_zoom.sh "$label" "$minimum" "$maximum"; then
    failures=$((failures+1))
    echo "::error::$label failed; continuing other postures"
  fi
}
if duoctl close; then
  sleep 2
  duoctl screenshot screenshots/duo-folded-base.png || true
  run_case duo-folded 70 100
else
  echo "::error::Unable to fold the Duo"
  failures=$((failures+1))
fi
if duoctl open; then
  sleep 2
  duoctl rotate landscape
  duoctl screenshot screenshots/duo-open-base.png || true
  run_case duo-unfolded-wide 60 100
  if duoctl rotate portrait; then
    sleep 2
    duoctl screenshot screenshots/duo-open-portrait-base.png || true
    run_case duo-unfolded-portrait 70 100
  else
    echo "::error::Unable to rotate unfolded Duo to portrait"
    failures=$((failures+1))
  fi
else
  echo "::error::Unable to unfold the Duo"
  failures=$((failures+1))
fi
# Priority 1 adds one posture to the proven v5 capture sequence.
if duoctl half && duoctl rotate landscape; then
  sleep 2
  duoctl screenshot screenshots/duo-half-open-book-base.png || true
  run_case duo-half-open-book 60 100
  # Optional native recording of the verified 100% book and real forward swipe.
  # Recording support varies between simulator images; PNG verification remains
  # mandatory even when video capture is unavailable.
  video_pid=""
  if display_id=$(python3 - "$UDID" <<'PY'
import runpy, shutil, sys
from pathlib import Path
native = runpy.run_path(str(Path(shutil.which('duoctl')).resolve()), run_name='reader_video')
active = [d for d in native['displays'](sys.argv[1]) if d.get('active')]
assert len(active) == 1, active
print(active[0]['displayId'])
PY
  ); then
    xcrun simctl io "$UDID" recordVideo --display="$display_id" --codec=h264 screenshots/duo-half-open-book.mov > screenshots/duo-video.log 2>&1 &
    video_pid=$!
    sleep 2
  fi
  # A real horizontal swipe should move the RTL book from 4/5 to 6/7.
  duoctl swipe 540 300 900 300 --duration 0.3
  sleep 2
  duoctl screenshot screenshots/duo-half-open-book-after-swipe.png
  if [[ -n "$video_pid" ]]; then
    kill -INT "$video_pid" 2>/dev/null || true
    wait "$video_pid" || true
  fi
else
  echo "::error::Unable to enter half-open book posture"
  failures=$((failures+1))
fi
echo "Duo failed cases: $failures" | tee screenshots/qa-result.txt
[[ "$failures" -eq 0 ]]
