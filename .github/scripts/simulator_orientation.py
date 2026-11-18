#!/usr/bin/env python3
"""Request iPad scene orientation in the QA build; verify actual PNG geometry.

External simulator orientation commands silently did nothing on these iPads.
The disposable build requests UIWindowScene geometry through public UIKit APIs.
"""
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import time

udid, desired = sys.argv[1:]
with open('ci-app/Runner.app/Info.plist', 'rb') as f:
    bundle = plistlib.load(f)['CFBundleIdentifier']
subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], capture_output=True)
environment = os.environ | {'SIMCTL_CHILD_MUSHAF_QA_TEST': '1',
    'SIMCTL_CHILD_MUSHAF_QA_ZOOM': '0.8',
    'SIMCTL_CHILD_MUSHAF_QA_ORIENTATION': desired}
subprocess.run(['xcrun', 'simctl', 'launch', udid, bundle], env=environment, check=True,
               stdout=sys.stderr)
attempts = []
data = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle, 'data'], text=True).strip()
native_state = Path(data) / 'Documents/reader-qa-native.json'
native = None
passed = False
with tempfile.TemporaryDirectory() as directory:
    screenshot = Path(directory) / 'orientation.png'
    for attempt in range(10):
        time.sleep(3)
        subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot)],
                       check=True, capture_output=True)
        data = screenshot.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Not a real PNG'
        width, height = struct.unpack('>II', data[16:24])
        if native_state.exists():
            try: native = json.loads(native_state.read_text())
            except ValueError: pass
        attempts.append({'width': width, 'height': height, 'native': native})
        if (width > height) == (desired == 'landscape'):
            passed = True
            break
print(json.dumps({'orientation': desired, 'passed': passed, 'attempts': attempts}, indent=2))
if not passed:
    raise RuntimeError(f'iPad did not render {desired}; native state: {native}')
