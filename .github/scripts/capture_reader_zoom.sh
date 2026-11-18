#!/usr/bin/env bash
# Capture EVERY toolbar zoom step from the running reader. Set UserDefaults in
# its daemon, then verify the rendered mode and zoom in the app's debug output.
# v5 comparison builds predate that debug geometry marker.
set -Eeuo pipefail
LABEL="$1" MIN="$2" MAX="$3" KEY="flutter.$4" MODE="$5"
UDID="$SIMULATOR_UDID"
OUT="${SCREENSHOTS_DIR:-screenshots}"
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
mkdir -p "$OUT"
for percent in $(seq "$MIN" 5 "$MAX"); do
  name="$OUT/$LABEL-$percent"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  value="$(python3 -c 'import sys;print(int(sys.argv[1])/100)' "$percent")"
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "$KEY" -float "$value"
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" flutter.CurrentPage1 -int 4
  live="$(xcrun simctl spawn "$UDID" defaults read "$BUNDLE_ID" "$KEY")"
  python3 - "$live" "$value" > "$name-preference.txt" <<'PY'
import math, sys
assert math.isclose(float(sys.argv[1]), float(sys.argv[2]), abs_tol=.0001), sys.argv
print(f"Verified live NSUserDefaults zoom={sys.argv[1]}; page=4")
PY
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" > "$name-app.log" 2>&1 &
  launch_pid=$!
  sleep 11
  if [[ "${CAPTURE_DEVICE:-ipad}" == duo ]]; then
    duoctl state > "$name-state.json"
    python3 .github/scripts/verify_duo_state.py "$name-state.json" "$LABEL"
    duoctl screenshot "$name.png"
  else
    xcrun simctl io "$UDID" screenshot "$name.png"
  fi
  [[ -s "$name.png" ]] || { echo "::error::Screenshot missing: $name.png"; exit 1; }
  if [[ "${VERIFY_READER_LOG:-1}" == 1 ]]; then
    python3 .github/scripts/verify_reader_render.py "$name-app.log" "$MODE" "$percent" "$name-render.json"
  fi
  echo "Captured actual $LABEL $percent%"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  wait "$launch_pid" || true
done
# Reject frozen screens at every adjacent zoom step, not only the endpoints.
python3 - "$OUT" "$LABEL" "$MIN" "$MAX" <<'PY'
import hashlib, pathlib, sys
root, label, low, high = sys.argv[1:]
previous = None
for percent in range(int(low), int(high)+1, 5):
    path = pathlib.Path(root) / f"{label}-{percent}.png"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest != previous, f"Frozen zoom capture at {percent}%: {path}"
    previous = digest
print(f"PASS: every {label} zoom generated a distinct screenshot")
PY
