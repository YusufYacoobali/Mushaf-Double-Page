#!/usr/bin/env python3
"""Dismiss the observed iPad notification alert through its sole touchscreen.

The tested iPads render at 2x. The Don't Allow button is centered 74 points
left of the screen midpoint and 70 points below it (verified on the actual
744x1133 iPad alert screenshot). Never depend on Duo's active-display flag.
"""
import importlib.machinery
import importlib.util
from pathlib import Path
from PIL import Image
import shutil
import sys
import subprocess

loader = importlib.machinery.SourceFileLoader('ipad_controls', str(Path(shutil.which('duoctl')).resolve()))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)
udid, screenshot = sys.argv[1:]
width, height = Image.open(screenshot).size
if shutil.which('axe'):
    try:
        subprocess.run(['axe', 'tap', '-x', str(width / 4 - 74),
                        '-y', str(height / 4 + 70), '--udid', udid],
                       check=True, timeout=20)
        print('Dismissed the iPad notification alert using its observed button coordinates')
        raise SystemExit(0)
    except (subprocess.SubprocessError, OSError) as error:
        print(f'Primary iPad tap failed; trying direct HID: {error}', file=sys.stderr)
touchscreens = controls.helper(udid, 'touchscreens').splitlines()
ids = {line.split()[0] for line in touchscreens if line.strip()}
assert len(ids) == 1, f'Expected exactly one iPad touchscreen: {touchscreens}'
nx, ny = .5 - 148 / width, .5 + 140 / height
controls.helper(udid, 'tap', ids.pop(), f'{nx:.5f}', f'{ny:.5f}', .08)
print('Tapped the observed iPad notification alert: Don\'t Allow')
