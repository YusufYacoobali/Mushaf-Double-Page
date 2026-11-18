#!/usr/bin/env python3
"""Use duoctl's verified HID orientation helper on an explicit iPad UDID.

The CLI intentionally only discovers Duos, while its orientation implementation
can target a supplied simulator and verifies the actual active display rotation.
"""
import importlib.machinery
import importlib.util
import json
import pathlib
import shutil
import sys

path = pathlib.Path(shutil.which('duoctl')).resolve()
loader = importlib.machinery.SourceFileLoader('simulator_controls', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)
controls.rotate(sys.argv[1], sys.argv[2])
display = controls.active_display(sys.argv[1])
print(json.dumps({'orientation': sys.argv[2], 'display': display}, indent=2))
