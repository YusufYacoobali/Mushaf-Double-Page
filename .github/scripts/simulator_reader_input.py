#!/usr/bin/env python3
"""Real simulator input and OCR-checked captures; never modify the app."""
import argparse
import json
import re
from pathlib import Path
import runpy
import shutil
import struct
import subprocess
import tempfile
import time


def run(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args!r}: {result.stdout}\n{result.stderr}')
    return result.stdout


parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['landscape', 'capture'])
parser.add_argument('udid')
parser.add_argument('output', nargs='?')
parser.add_argument('--require-zoom', action='store_true')
parser.add_argument('--zoom', type=int)
parser.add_argument('--dock', choices=['bottom', 'side'], default='side')
args = parser.parse_args()
devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'booted', '-j']))
target = [d for group in devices['devices'].values() for d in group if d['udid'] == args.udid]
assert len(target) == 1 and any(name in target[0]['deviceTypeIdentifier'] for name in ['iPad', 'iPhone-Duo']), target
assert args.zoom is None or args.zoom in range(60, 101, 5), args.zoom

# Reuse the same native HID implementation as the proven Duo workflow. Its
# library functions accept an explicit simulator; the CLI selects only Duos.
executable = shutil.which('duoctl')
assert executable, 'Install skarol/tap/duoctl first'
native = runpy.run_path(str(Path(executable).resolve()), run_name='reader_simulator_input')


def rendered_landscape():
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'rotation-check.png'
        run(['xcrun', 'simctl', 'io', args.udid, 'screenshot', str(path)])
        width, height = struct.unpack('>II', path.read_bytes()[16:24])
        print(f'Rotation rendered PNG: {width}x{height}', flush=True)
        return width > height


if args.action == 'landscape':
    try:
        native['rotate'](args.udid, 'landscape')
        print('Sent native simulator orientation event')
        time.sleep(1)
        if not rendered_landscape():
            raise RuntimeError('Native display flags changed without a landscape render')
    except Exception as error:
        print(f'Native rotation unavailable: {error}; using Simulator action')
        developer = run(['xcode-select', '-p']).strip()
        simulator = Path(developer) / 'Applications/Simulator.app'
        # Xcode's nested app need not be registered with Launch Services.
        run(['open', '-a', str(simulator), '--args', '-CurrentDeviceUDID', args.udid])
        time.sleep(3)
        for _ in range(4):
            run(['osascript', '-e', 'tell application "Simulator" to activate',
                 '-e', 'tell application "System Events" to key code 123 using command down'])
            time.sleep(1)
            if rendered_landscape():
                break
        else:
            raise RuntimeError('Simulator action did not render landscape')
    print(json.dumps(native['active_display'](args.udid), sort_keys=True))
else:
    assert args.output, 'Capture needs an output PNG path'
    ocr = Path(__file__).with_name('simulator_reader_ocr.swift')
    compiled_ocr = Path('.qa-reader-ocr').resolve()
    for attempt in range(24 if args.zoom else 4):
        run(['xcrun', 'simctl', 'io', args.udid, 'screenshot', args.output])
        command = [str(compiled_ocr)] if compiled_ocr.exists() else ['xcrun', 'swift', str(ocr)]
        state = json.loads(run(command + [args.output]))
        print(f'Original frame inspection {attempt + 1}: {json.dumps(state)}', flush=True)
        display = native['active_display'](args.udid)
        width, height = native['ui_size'](display)
        assert (width > height) == (state['width'] > state['height']), 'Display and rendered PNG orientations disagree'
        if 'denyNotification' in state:
            button = state['denyNotification']
            native['tap'](args.udid, button['x'] * width, button['y'] * height, 0.08)
            time.sleep(1)
        elif (args.require_zoom or args.zoom) and 'zoom' not in state:
            # The collapsed side pull-tab occupies the physical right edge.
            # Capture again after a real touch; do not alter saved PNG pixels.
            x, y = (width / 2, height - 38) if args.dock == 'bottom' else (width - 15, height / 2)
            native['tap'](args.udid, x, y, 0.08)
            time.sleep(0.4)
        elif args.zoom:
            current = int(re.sub(r'\D', '', state['zoom']))
            assert current in range(60, 101, 5), state
            if current == args.zoom:
                break
            label = state['zoomBounds']
            increase = current < args.zoom
            if args.dock == 'bottom':
                x = label['x'] * width + (34 if increase else -34)
                y = label['y'] * height
            else:
                x = label['x'] * width
                y = label['y'] * height + (-29 if increase else 29)
            native['tap'](args.udid, x, y, 0.08)
            time.sleep(0.15)
        else:
            break
    else:
        raise RuntimeError('Could not obtain a clean reader frame with visible controls')
