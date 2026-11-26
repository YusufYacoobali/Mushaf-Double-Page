#!/usr/bin/env bash
# Seed only the throwaway iOS simulator container; never alter app production
# code or the actual Quran images. Existing workflows keep their original
# defaults; the proven capture workflow supplies its requested page and zooms.
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
page=int(os.environ.get("READER_QA_PAGE", "4"))
single_zoom=int(os.environ.get("READER_QA_SINGLE_ZOOM", "80"))
spread_zoom=int(os.environ.get("READER_QA_SPREAD_ZOOM", "70"))
assert 1 <= page <= 851, "Invalid Quran page"
assert 70 <= single_zoom <= 100 and 60 <= spread_zoom <= 100, "Invalid reader zoom"
data={}
if os.path.exists(path):
    try:
        with open(path,"rb") as f: data=plistlib.load(f)
    except Exception: data={}
data.update({
    "flutter.CurrentPage1": page,
    "flutter.quran_single_page_scale": single_zoom / 100,
    "flutter.quran_landscape_page_scale": spread_zoom / 100,
    "flutter.reader_controls_arrow_only": False,
    "flutter.review_prompt_rate_chosen": True,
})
with open(path,"wb") as f: plistlib.dump(data,f,fmt=plistlib.FMT_BINARY)
print(f"CI simulator starting page={page}, single zoom={single_zoom}%, spread zoom={spread_zoom}%")
PY
