#!/usr/bin/env bash
set -Eeuo pipefail
# macOS does not provide GNU timeout; use Perl alarm around potentially hung simctl calls.
timeout() { perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\\n"' "$@"; }
mkdir -p screenshots-ipad
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
UDID=""
cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    timeout 20 xcrun simctl list devices -j > screenshots-ipad/devices-on-error.json 2>&1 || true
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
bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
sleep 2
launched=0
for n in 1 2 3; do
  if timeout 90 xcrun simctl launch "$UDID" "$BUNDLE_ID"; then launched=1; break; fi
  sleep 4
done
$([[ "$launched" -eq 1 ]] || { echo "::error::iPad app launch failed"; exit 1; })
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
  sleep 5
done
[[ "$ready" -eq 1 ]] || { echo "::error::iPad did not load real Quran pages"; exit 1; }
echo "::endgroup::"
sleep 2
timeout 60 xcrun simctl io "$UDID" screenshot screenshots-ipad/ipad-mini-portrait.png
# The initial intercession tip overlays Quran text. Capture a later state too
# without altering application code, so reviewers can distinguish an
# auto-dismissing overlay from a persistent layout issue.
sleep 18
timeout 60 xcrun simctl io "$UDID" screenshot screenshots-ipad/ipad-mini-portrait-after-18s.png
echo "iPad mini portrait: Quran images loaded, app screenshot captured" | tee screenshots-ipad/status.txt
