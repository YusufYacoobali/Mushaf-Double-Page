#!/usr/bin/env bash
# Capture real Flutter reader screenshots at min/max zoom. Xcode 27's AXe
# accessibility service times out in CI even though the app is running.
# Avoid AXe: seed app zoom while Runner is stopped, then require fresh rendered
# geometry at that zoom and cross-check the genuine screenshot before passing.
set -Eeuo pipefail
if [[ "$#" != 3 ]]; then echo "Usage: $0 <state> <min-percent> <max-percent>" >&2; exit 2; fi
LABEL="$1"
MIN="$2"
MAX="$3"
UDID="$DUOCTL_UDID"
APP="ci-app/Runner.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
PREFS="$DATA/Library/Preferences/$BUNDLE_ID.plist"
mkdir -p screenshots

capture_at() {
  local percent="$1"
  local tag="$2"
  local name="screenshots/$LABEL-$tag-$percent"
  echo "$LABEL: configuring actual app zoom $percent%"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 2
  python3 - "$PREFS" "$LABEL" "$percent" "$name-preference.txt" <<'PY'
import math
import os
import plistlib
import sys

path, posture, percent_str, evidence_path = sys.argv[1:]
percent = int(percent_str)
key = ("flutter.quran_single_page_scale"
       if posture in ("duo-folded", "duo-unfolded-portrait") else "flutter.quran_landscape_page_scale")
data = {}
if os.path.exists(path):
    with open(path, "rb") as f:
        data = plistlib.load(f)
data.update({
    key: percent / 100,
    "flutter.CurrentPage1": 4,
    "flutter.reader_controls_arrow_only": False,
    "flutter.review_prompt_rate_chosen": True,
})
with open(path, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
with open(path, "rb") as f:
    actual = plistlib.load(f)[key]
assert math.isclose(actual, percent / 100, abs_tol=1e-6)
with open(evidence_path, "w") as f:
    f.write(f"Real app SharedPreferences {key}={actual}; reader page=4\n")
print(f"Verified on disk {key} = {actual}")
PY
  # Editing the plist file alone is NOT sufficient: iOS cfprefsd caches the
  # UserDefaults domain across Runner restarts. Update the live preference
  # service through simctl spawn (the same NSUserDefaults the Flutter plugin
  # reads), then verify that daemon's value before relaunching the app.
  local key value live mode launched_after
  if [[ "$LABEL" == "duo-folded" || "$LABEL" == "duo-unfolded-portrait" ]]; then
    key="flutter.quran_single_page_scale"
  else
    key="flutter.quran_landscape_page_scale"
  fi
  value="$(python3 -c 'import sys;print(int(sys.argv[1])/100)' "$percent")"
  if xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "$key" -float "$value"; then
    live="$(xcrun simctl spawn "$UDID" defaults read "$BUNDLE_ID" "$key")"
    echo "iOS NSUserDefaults daemon $key: $live" | tee -a "$name-preference.txt"
    python3 - "$live" "$value" <<'PY'
import math,sys
assert math.isclose(float(sys.argv[1]),float(sys.argv[2]),abs_tol=0.0001),sys.argv
PY
  else
    # Simulator versions without a working defaults tool must discard cached
    # preferences before the next Runner launch.
    echo "::warning::defaults write unavailable; invalidating cfprefsd cache"
    xcrun simctl spawn "$UDID" killall cfprefsd >/dev/null 2>&1 || true
  fi
  # Guest defaults can address a different user domain from the sandboxed app.
  # Always discard cached preferences and reapply the container values after
  # pending daemon writes stop. Rendered geometry below remains the proof.
  xcrun simctl spawn "$UDID" killall cfprefsd >/dev/null 2>&1 || true
  sleep 1
  python3 - "$PREFS" "$key" "$value" <<'PY'
import plistlib, sys
path, key, value = sys.argv[1:]
with open(path, 'rb') as f:
    data = plistlib.load(f)
data.update({key: float(value), 'flutter.CurrentPage1': 4,
             'flutter.reader_controls_arrow_only': False,
             'flutter.review_prompt_rate_chosen': True})
with open(path, 'wb') as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
PY
  rm -f "$DATA/Documents/reader-geometry.json"
  launched_after="$(python3 -c 'import time; print(time.time())')"
  for n in 1 2 3; do
    if xcrun simctl launch "$UDID" "$BUNDLE_ID"; then break; fi
    sleep 5
  done
  sleep 5
  duoctl state > "$name-state.json"
  # Retain the actual screen even when posture/geometry validation fails.
  duoctl screenshot "$name.png"
  python3 - "$name-state.json" "$LABEL" <<'PY'
import json
import sys
state = json.load(open(sys.argv[1]))
label = sys.argv[2]
active = state.get("activeScreen")
angle = float(state.get("hingeAngle", -1))
if label == "duo-folded":
    assert active == "cover" and angle <= 15, state
else:
    assert active != "cover", state
    if label == "duo-half-open-book":
        assert 60 <= angle <= 120, state
        assert state.get("orientation") == "landscape", state
    else:
        assert angle >= 160, state
    if label == "duo-unfolded-portrait":
        assert state.get("orientation") == "portrait", state
print(f"Validated display: {active}, hinge={angle}, orientation={state.get('orientation')}")
PY
  case "$LABEL" in
    duo-folded|duo-unfolded-portrait) mode=single ;;
    duo-unfolded-wide) mode=spread ;;
    duo-half-open-book) mode=dualScreenBook ;;
    *) echo "::error::Unknown posture $LABEL"; return 1 ;;
  esac
  # This bounded wait observes the app; it never substitutes the requested
  # percentage for the rendered percentage. Keep the last snapshot on failure.
  if ! python3 - "$DATA/Documents/reader-geometry.json" "$name.layout.json" "$percent" "$mode" "$launched_after" > "$name-geometry.txt" 2>&1 <<'PY'
import json, sys, time
from pathlib import Path
sys.path.insert(0, '.github/scripts')
from verify_fitted_capture import assert_capture_state
source, destination, percent, mode, after = sys.argv[1:]
deadline = time.monotonic() + 30
last_error = 'No rendered geometry was written'
while time.monotonic() < deadline:
    try:
        data = json.loads(Path(source).read_text())
        Path(destination).write_text(json.dumps(data, indent=2) + '\n')
        assert_capture_state(data, int(percent), mode, float(after))
        print(f"Fresh rendered {mode} geometry at {data['zoom'] * 100:g}%")
        break
    except (OSError, ValueError, KeyError, TypeError, AssertionError) as error:
        last_error = str(error)
        time.sleep(.5)
else:
    raise RuntimeError(f'Rendered geometry did not match within 30s: {last_error}')
PY
  then
    cat "$name-geometry.txt"
    duoctl screenshot "$name.png" || true
    return 1
  fi
  cat "$name-geometry.txt"
  duoctl screenshot "$name.png"
  [[ -s "$name.png" ]] || { echo "::error::No screenshot created: $name.png"; return 1; }
  sips -g pixelWidth -g pixelHeight "$name.png"
  python3 .github/scripts/verify_fitted_capture.py "$name.png" "$name.layout.json" --zoom "$percent" --mode "$mode" --after "$launched_after" | tee "$name-verification.txt"
  echo "PASS: real $LABEL reader at $percent% ($name.png)" | tee -a "screenshots/$LABEL-result.txt"
}
echo "Running $LABEL at min=$MIN and max=$MAX"
capture_at "$MIN" min
capture_at "$MAX" max

# A bug in the previous CI runner reported both endpoints as a PASS while
# the captured PNGs were literally byte-identical (the original default zoom
# was still on screen). Reject this false-positive explicitly.
if cmp -s "screenshots/$LABEL-min-$MIN.png" "screenshots/$LABEL-max-$MAX.png"; then
  echo "::error::$LABEL: min and max screenshots are identical, so zoom was NOT verified"
  exit 1
fi
echo "PASS: $LABEL min $MIN% and max $MAX% generated distinct genuine screenshots"
