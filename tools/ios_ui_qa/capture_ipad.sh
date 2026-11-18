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
op() { local stage="$1" seconds="$2"; shift 2; python3 .github/scripts/ci_run.py --operation "$stage" --timeout "$seconds" --output "$OUTPUT/operations" -- "$@"; }
cleanup() {
  local status=$?
  if [[ -n "$UDID" ]]; then
    op screenshot 30 xcrun simctl io "$UDID" screenshot "$OUTPUT/final-frame.png" || true
    op shutdown 30 xcrun simctl shutdown "$UDID" || true
    op delete 30 xcrun simctl delete "$UDID" || true
  fi
  return "$status"
}
trap cleanup EXIT
RUNTIME=$(python3 -c 'import json;print(json.load(open(".ci/ipad-template.json"))["runtime"])')
TYPE=$(python3 -c 'import json;print(json.load(open(".ci/ipad-template.json"))["device"]["deviceTypeIdentifier"])')
python3 .github/scripts/ci_run.py --operation create --timeout 30 --output "$OUTPUT/operations" --value-file "$OUTPUT/udid.txt" -- xcrun simctl create "reader-$GITHUB_RUN_ID-$DEVICE-$VERSION" "$TYPE" "$RUNTIME"
UDID=$(tail -n 1 "$OUTPUT/udid.txt")
op boot 30 xcrun simctl boot "$UDID"
op boot 150 xcrun simctl bootstatus "$UDID" -b
op install 90 xcrun simctl install "$UDID" "$APP"
op seed 30 bash .github/scripts/seed_simulator_reading_page.sh "$UDID" "$BUNDLE_ID"
python3 .github/scripts/ci_run.py --operation container --timeout 30 --output "$OUTPUT/operations" --value-file "$OUTPUT/container.txt" -- xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data
DATA=$(tail -n 1 "$OUTPUT/container.txt")
PREFS="$DATA/Library/Preferences/$BUNDLE_ID.plist"
CACHE="${READER_ASSET_CACHE:-$PWD/.ci/quran-pages}"
op asset-cache 90 python3 .github/scripts/reader_asset_cache.py import --data "$DATA" --prefs "$PREFS" --cache "$CACHE"
op launch 40 xcrun simctl launch "$UDID" "$BUNDLE_ID"
op download 420 python3 .github/scripts/reader_asset_cache.py wait --data "$DATA"
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
