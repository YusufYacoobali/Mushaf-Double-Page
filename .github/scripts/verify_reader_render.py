#!/usr/bin/env python3
"""Validate app-rendered geometry separately from simulator hinge state."""
import json
import pathlib
import sys

log, mode, percent, output = sys.argv[1:5]
first = int(sys.argv[5]) if len(sys.argv) > 5 else 4
renders = []
content = pathlib.Path(log).read_text(errors='replace')
if content.lstrip().startswith('{'):
    renders.append(json.loads(content))
for line in content.splitlines():
    if 'MUSHAF_READER ' in line:
        renders.append(json.loads(line.split('MUSHAF_READER ', 1)[1]))
assert renders, f'No actual reader geometry found in {log}'
render = renders[-1]
assert render['mode'] == mode, render
assert render['zoom'] == int(percent), render
assert render['pages'] == ([first] if mode == 'single' else [first, first + 1]), render
regions = render['regions']
assert len(regions) == (1 if mode == 'single' else 2), render
if mode == 'dualScreenBook':
    assert regions[0][0] + regions[0][2] <= regions[1][0], render
pathlib.Path(output).write_text(json.dumps(render, indent=2) + '\n')
print(f'PASS: actual Flutter render {render}')
