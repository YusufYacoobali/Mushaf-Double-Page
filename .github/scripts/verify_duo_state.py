#!/usr/bin/env python3
import json
import sys

state = json.load(open(sys.argv[1]))
label = sys.argv[2]
angle = float(state['hingeAngle'])
if label.startswith('duo-folded'):
    assert state['activeScreen'] == 'cover' and angle <= 15, state
else:
    assert state['activeScreen'] == 'inner', state
    if 'half-open' in label:
        assert 60 <= angle <= 120, state
    else:
        assert angle >= 160, state
if label.endswith('portrait'):
    assert state['orientation'] == 'portrait', state
elif label.endswith('landscape') or label.endswith('wide'):
    assert state['orientation'] in ('landscape', 'landscape-flipped'), state
print(f"Validated actual simulator posture: {state}")
