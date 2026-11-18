#!/usr/bin/env python3
"""Select the real iPad simulator; retry slow CoreSimulator enumeration."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True, choices=['mini', 'pro11', 'pro13'])
parser.add_argument('--reference', required=True)
args = parser.parse_args()
needle = {'mini': 'iPad mini', 'pro11': 'iPad Pro 11-inch',
          'pro13': 'iPad Pro 13-inch'}[args.device]
last_error = None
for attempt in range(1, 4):
    try:
        output = subprocess.check_output(
            ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
            stderr=subprocess.STDOUT, timeout=100)
        available = json.loads(output)
        options = [
            (tuple(map(int, re.findall(r'\d+', runtime))), runtime, device)
            for runtime, devices in available['devices'].items()
            if '.iOS-' in runtime
            for device in devices
            if device.get('isAvailable') and needle in device['name']
        ]
        if not options:
            devices = sorted({
                d['name'] for group in available['devices'].values()
                for d in group if d.get('isAvailable') and 'iPad' in d['name']
            })
            raise RuntimeError(f'No {needle} device installed; available: {devices}')
        _, runtime, device = max(options, key=lambda row: row[0])
        break
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError,
            json.JSONDecodeError) as error:
        last_error = str(error)
        print(f'CoreSimulator device discovery attempt {attempt}/3: {error}', flush=True)
        if attempt < 3:
            time.sleep(5)
else:
    raise RuntimeError(f'CoreSimulator failed three discovery attempts: {last_error}')

template = {'runtime': runtime, 'device': device}
Path('.ci').mkdir(exist_ok=True)
Path('.ci/ipad-template.json').write_text(json.dumps(template, indent=2) + '\n')
profile = hashlib.sha256(Path('tools/ios_ui_qa/layout_profile.json').read_bytes()).hexdigest()
key = hashlib.sha256(json.dumps([
    args.reference, device['deviceTypeIdentifier'], runtime, profile,
]).encode()).hexdigest()
with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
    stream.write('baseline_key=reader-v5-layout-' + key + '\n')
print(f'Using actual {device["name"]} on {runtime}', flush=True)
