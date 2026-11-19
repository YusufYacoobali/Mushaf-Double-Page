#!/usr/bin/env python3
"""Dismiss a real, observed iOS notification dialog on the disposable Duo.

Do not alter app permissions, source code, or screenshots. Capture the active
panel and detect the actual 'Don't Allow' button before sending a real touch.
"""
import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

from inspect_reader_frame import inspect_frame

def run(command, timeout):
    print('Duo permission:', command[:3], flush=True)
    return subprocess.run(command, text=True, capture_output=True,
                          check=True, timeout=timeout)

def screen_geometry(udid):
    data = json.loads(run(['xcrun','devicectl','device','info','displays',
                          '-d',udid,'--json-output','-'], 65).stdout)
    active = [d for d in data['result']['displays']
              if d.get('active') and d.get('name','').startswith('LCD')]
    if len(active) != 1:
        raise RuntimeError(f'Expected one active Duo LCD, got {active}')
    display = active[0]
    bounds = display['bounds'][1]
    scale = display.get('pointScale') or 1
    width, height = bounds[0]/scale, bounds[1]/scale
    if display.get('currentOrientation') in ('rot90','rot270'):
        width,height = height,width
    return width,height

def screenshot(path):
    run(['duoctl','screenshot',str(path)], 95)
    if not path.is_file() or path.stat().st_size < 20000:
        raise RuntimeError('No genuine Duo screenshot after capture')
    return inspect_frame(path, dock='bottom')

def main():
    p = argparse.ArgumentParser()
    p.add_argument('udid')
    p.add_argument('output',type=Path)
    args = p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    assert shutil.which('duoctl') and shutil.which('tesseract')
    evidence=[]
    for attempt in range(3):
        path=args.output/f'notification-check-{attempt}.png'
        frame=screenshot(path)
        button=frame.get('denyNotification')
        evidence.append({'attempt':attempt,'screenshot':str(path),
                         'denyNotificationDetected':bool(button)})
        if button is None:
            (args.output/'permission-verification.json').write_text(
                json.dumps({'verified':True,'attempts':evidence},indent=2)+'\n')
            print('PASS: real Duo screenshot has no notification permission dialog',flush=True)
            return
        if attempt==2:
            break
        width,height=screen_geometry(args.udid)
        x=round(button['x']*width,2)
        y=round(button['y']*height,2)
        print(f'Observed system permission at ({x},{y}) in {width}x{height} points; tapping actual button',flush=True)
        run(['duoctl','tap',str(x),str(y)], 95)
        time.sleep(2)
    (args.output/'permission-verification.json').write_text(
        json.dumps({'verified':False,'attempts':evidence},indent=2)+'\n')
    raise RuntimeError('First-run notification permission dialog still covers Quran')

if __name__ == '__main__':
    main()
