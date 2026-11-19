#!/usr/bin/env python3
"""Real simulator input and OCR-checked captures; never modify the app."""
import argparse
import json
import re
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import time

from PIL import Image, ImageOps

from inspect_reader_frame import inspect_frame


def run(args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f'{args!r}: {result.stdout}\n{result.stderr}')
    return result.stdout


parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['landscape', 'capture'])
parser.add_argument('udid')
parser.add_argument('output', nargs='?')
parser.add_argument('--require-zoom', action='store_true')
parser.add_argument('--zoom', type=int)
parser.add_argument('--layout-metadata', type=Path)
parser.add_argument('--expected-mode')
parser.add_argument('--dock', choices=['bottom', 'side'], default='side')
parser.add_argument('--bottom-tab-from-edge', type=float, default=60)
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


def display_info():
    displays = native['displays'](args.udid)
    active = [display for display in displays if display.get('active')]
    if len(active) == 1:
        return active[0]
    # A conventional iPad exposes one LCD without the Duo active-panel flag.
    # Select that actual LCD; never guess between multiple inactive panels.
    if 'iPad' in target[0]['deviceTypeIdentifier'] and len(displays) == 1:
        return displays[0]
    raise RuntimeError(f'Cannot select a unique display: {displays!r}')


def capture_png(path):
    display = display_info()
    run(['xcrun', 'simctl', 'io', args.udid, 'screenshot',
         f"--display={display['displayId']}", str(path)])
    return display


def tap(x, y, display):
    nx, ny = native['to_native'](display, x, y)
    native['helper'](args.udid, 'tap', display['uniqueId'], f'{nx:.5f}', f'{ny:.5f}', 0.08)


def rendered_landscape():
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'rotation-check.png'
        capture_png(path)
        # Some iPad simulator PNGs encode landscape via EXIF orientation while
        # retaining portrait pixel storage. Check the displayed image size.
        with Image.open(path) as image:
            width, height = ImageOps.exif_transpose(image).size
        print(f'Rotation rendered PNG: {width}x{height}', flush=True)
        return width > height


if args.action == 'landscape':
    try:
        for orientation in ['landscape-left', 'landscape-right']:
            native['helper'](args.udid, 'orientation', orientation)
            time.sleep(1)
            if rendered_landscape():
                break
        else:
            raise RuntimeError('Native orientation events did not render landscape')
        print('Verified native simulator landscape render')
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
    print(json.dumps(display_info(), sort_keys=True))
else:
    assert args.output, 'Capture needs an output PNG path'
    for attempt in range(12 if args.zoom and not args.layout_metadata else 4):
        display = capture_png(args.output)
        state = inspect_frame(args.output, args.dock, display.get('pointScale') or 1)
        print(f'Original frame inspection {attempt + 1}: {json.dumps(state)}', flush=True)
        if attempt == 0:
            print(f'Native display metadata: {json.dumps(display, sort_keys=True)}', flush=True)
        width, height = native['ui_size'](display)
        assert (width > height) == (state['width'] > state['height']), 'Display and rendered PNG orientations disagree'
        if 'denyNotification' in state:
            button = state['denyNotification']
            tap(button['x'] * width, button['y'] * height, display)
            time.sleep(1)
        elif args.layout_metadata:
            if not args.layout_metadata.exists():
                raise RuntimeError('layout: rendered geometry missing; acquire a compatible QA build')
            snapshot = json.loads(args.layout_metadata.read_text())
            assert snapshot['mode'] == args.expected_mode, 'layout: wrong reading mode for requested posture'
            if args.zoom is not None:
                assert abs(snapshot['zoom'] * 100 - args.zoom) < .1, 'layout: app did not apply requested zoom'
            destination = Path(args.output).with_suffix('.layout.json')
            destination.write_text(json.dumps(snapshot, indent=2) + '\n')
            from verify_fitted_capture import verify
            verify(args.output, destination, args.zoom)
            break
        elif (args.require_zoom or args.zoom) and 'zoom' not in state:
            # The collapsed side pull-tab occupies the physical right edge.
            # Capture again after a real touch; do not alter saved PNG pixels.
            x, y = (width / 2, height - args.bottom_tab_from_edge) if args.dock == 'bottom' else (width - 15, height / 2)
            tap(x, y, display)
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
            tap(x, y, display)
            time.sleep(0.15)
        else:
            break
    else:
        raise RuntimeError('Could not obtain a clean reader frame with visible controls')
