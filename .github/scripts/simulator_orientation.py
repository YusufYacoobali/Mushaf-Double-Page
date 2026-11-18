#!/usr/bin/env python3
"""Rotate an explicit iPad using HID and verify the real screenshot dimensions.

Ordinary iPads do not expose Duo's `active` display flag in devicectl. Validate
the rendered orientation using simctl's genuine PNG instead of that flag.
"""
import importlib.machinery
import importlib.util
import json
import pathlib
import shutil
import sys
import struct
import tempfile
import time

path = pathlib.Path(shutil.which('duoctl')).resolve()
loader = importlib.machinery.SourceFileLoader('simulator_controls', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)
udid, desired = sys.argv[1:]
attempts = []
with tempfile.TemporaryDirectory() as directory:
    screenshot = pathlib.Path(directory) / 'orientation.png'
    candidates = [None, 'portrait', 'landscape-left', 'landscape-right', 'pud']
    for orientation in candidates:
        if orientation:
            controls.helper(udid, 'orientation', orientation)
            time.sleep(2)
        controls.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot)])
        data = screenshot.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Not a real PNG'
        width, height = struct.unpack('>II', data[16:24])
        attempts.append({'device_orientation': orientation, 'width': width, 'height': height})
        if (width > height) == (desired == 'landscape'):
            print(json.dumps({'orientation': desired, 'attempts': attempts}, indent=2))
            break
    else:
        raise RuntimeError(f'iPad did not render {desired}: {attempts}')
