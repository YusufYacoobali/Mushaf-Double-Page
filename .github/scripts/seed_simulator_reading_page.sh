#!/usr/bin/env bash
# Seed only the throwaway iOS simulator container; never alter app production
# code or the actual Quran images. Select the first text page rather than cover.
set -euo pipefail
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then echo "Usage: $0 <simulator-udid> <bundle-id> [data-dir]" >&2; exit 2; fi
UDID="$1"; BUNDLE="$2"
# When the caller resolved the app container, avoid another slow simctl query.
DATA="${3:-}"
if [[ -z "$DATA" ]]; then DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"; fi
[[ -d "$DATA" ]] || { echo "App data folder missing: $DATA" >&2; exit 1; }
PREFS="$DATA/Library/Preferences/$BUNDLE.plist"
mkdir -p "$(dirname "$PREFS")"
python3 - "$PREFS" <<'PY'
import os
import plistlib
import sys
path=sys.argv[1]
data={}
if os.path.exists(path):
    try:
        with open(path,"rb") as f: data=plistlib.load(f)
    except Exception: data={}
data.update({
    "flutter.CurrentPage1": 4,
    "flutter.quran_single_page_scale": 0.8,
    "flutter.quran_landscape_page_scale": 0.7,
    "flutter.reader_controls_arrow_only": False,
    "flutter.review_prompt_rate_chosen": True,
})
with open(path,"wb") as f: plistlib.dump(data,f,fmt=plistlib.FMT_BINARY)
print("CI simulator starting page=4, single zoom=80%, spread zoom=70%")
PY
