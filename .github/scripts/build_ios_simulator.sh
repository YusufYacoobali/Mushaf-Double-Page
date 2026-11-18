#!/usr/bin/env bash
set -Eeuo pipefail
# The same build configuration is used for the reader and the v5 reference.
# These edits affect the isolated CI checkout, never the repository revision.
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' ios/Runner.xcodeproj/project.pbxproj
python3 - <<'PY'
from pathlib import Path
p = Path('ios/Podfile')
s = p.read_text()
marker = '    flutter_additional_ios_build_settings(target)\n'
assert marker in s
s = s.replace(marker, marker + "    target.build_configurations.each do |config|\n      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'\n    end\n")
p.write_text(s)
PY
FLUTTER_XCODE_ARCHS=arm64 flutter build ios --simulator --debug --no-pub --dart-define=READER_LAYOUT_QA=true
test -x build/ios/iphonesimulator/Runner.app/Runner
lipo -archs build/ios/iphonesimulator/Runner.app/Runner | grep -qw arm64
mkdir -p .ci/simulator-build
tar -czf .ci/simulator-build/ios-simulator-runner.tgz -C build/ios/iphonesimulator Runner.app
