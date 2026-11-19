#!/usr/bin/env bash
# Build only the small, separate XCTest host used to rotate an installed reader.
# This never rebuilds or modifies Runner.app and runs before simulator startup.
set -Eeuo pipefail
APP="${IPAD_APP:-ci-app/Runner.app}"
test -d "$APP"
command -v xcodegen >/dev/null
python3 - "$APP/Info.plist" <<'PY'
import json
from pathlib import Path
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    identifier = plistlib.load(stream)["CFBundleIdentifier"]
assert isinstance(identifier, str) and identifier
Path("tools/ios_ui_qa/ReaderAppIdentity.swift").write_text(
    "enum ReaderAppIdentity { static let bundleID = " + json.dumps(identifier) + " }\n"
)
PY
xcodegen generate --spec tools/ios_ui_qa/project.yml
python3 .github/scripts/ci_run.py --operation rotation-harness-build --timeout 360 \
  --output screenshots-ipad/setup -- \
  xcodebuild build-for-testing -project tools/ios_ui_qa/ReaderUIHarness.xcodeproj \
  -scheme ReaderVisualTests -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ui-build \
  CODE_SIGNING_ALLOWED=NO
