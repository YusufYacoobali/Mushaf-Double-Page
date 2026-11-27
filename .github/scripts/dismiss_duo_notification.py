#!/usr/bin/env python3
"""Dismiss a real, observed iOS notification dialog on the disposable Duo.

Do not alter app permissions, source code, or screenshots. Capture the active
panel and detect the actual 'Don't Allow' button before sending a real touch.
"""
import argparse
import json
import os
import plistlib
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
    display = os.getenv('DUO_PERMISSION_DISPLAY')
    if display:
        command = ['xcrun', 'simctl', 'io', os.environ['DUOCTL_UDID'], 'screenshot',
                   '--display=' + display, str(path)]
    else:
        command = ['duoctl', 'screenshot', str(path)]
    try:
        run(command, 60)
    except subprocess.TimeoutExpired:
        path.unlink(missing_ok=True)
        run(command, 60)
    if not path.is_file() or path.stat().st_size < 20000:
        raise RuntimeError('No genuine Duo screenshot after capture')
    return inspect_frame(path, dock='bottom')

def springboard_denied(udid, bundle):
    """Read back the per-app decision from the simulator's notification store."""
    folder = Path.home() / 'Library/Developer/CoreSimulator/Devices' / udid / 'data/Library/BulletinBoard'
    for name in ('VersionedSectionInfo.plist', 'SectionInfo.plist'):
        try:
            store = plistlib.loads((folder / name).read_bytes())
            section = plistlib.loads(store.get('sectionInfo', store)[bundle])
            values = section['$objects']
            if bundle in values and any(isinstance(v, dict) and v.get('allowsNotifications') is False for v in values):
                return str(folder / name)
        except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
            continue
    return None


def wait_for_decision(udid, output, authorization, bundle=None):
    # A fresh simulator reports 0 (notDetermined) until SpringBoard accepts a
    # choice. In the failed run the alert first appeared AFTER the setup tap.
    evidence = []
    deadline = time.monotonic() + 120
    clear = 0
    taps = 0
    tried_xctest = False
    while time.monotonic() < deadline:
        authorization.with_name("duo-refresh-permission").touch()
        index = len(evidence)
        path = output / f'notification-check-{index}.png'
        frame = screenshot(path)
        status = int(authorization.read_text()) if authorization.exists() else None
        source = 'UNUserNotificationCenter'
        if status is None and bundle:
            store = springboard_denied(udid, bundle)
            if store:
                source, status = store, 1
        button = frame.get('denyNotification')
        evidence.append({'status': status, 'source': source, 'screen': path.name, 'nearWhiteFraction': frame['nearWhiteFraction'],
                         'notificationPrompt': frame['notificationPrompt'], 'button': button})
        (output / 'permission-verification.json').write_text(json.dumps(evidence, indent=2))
        print('Notification check:', evidence[-1], flush=True)
        if status in (1, 2, 3, 4) and not button and not frame['notificationPrompt'] and frame['nearWhiteFraction'] > .08:
            clear += 1
            if clear == 2:
                return
        else:
            clear = 0
        if frame['notificationPrompt'] and button and status in (0, None) and taps < 2:
            try:
                width, height = screen_geometry(udid)
                run(['duoctl', '-d', udid, 'tap', str(button['x'] * width), str(button['y'] * height)], 35)
                taps += 1
            except (subprocess.SubprocessError, RuntimeError) as error:
                print(f'Duo input unavailable for observed alert: {error}', flush=True)
                taps = 2
        if status in (0, None) and (taps == 2 or index >= 6) and not tried_xctest:
            # The iPad optical/AX harness independently foregrounds the reader
            # and dismisses only its observed SpringBoard notifications alert.
            tried_xctest = True
            subprocess.run([
                'xcodebuild', 'test-without-building', '-project', 'tools/ios_ui_qa/ReaderUIHarness.xcodeproj',
                '-scheme', 'ReaderVisualTests', '-derivedDataPath', 'ui-build',
                '-destination', 'platform=iOS Simulator,id=' + udid, '-parallel-testing-enabled', 'NO',
                '-only-testing:ReaderVisualTests/ReaderVisualTests/testPreparePortrait',
                '-resultBundlePath', str(output / 'permission.xcresult'), 'CODE_SIGNING_ALLOWED=NO'
            ], check=True, timeout=230)
            deadline = time.monotonic() + 90
        time.sleep(1)
    raise RuntimeError('No confirmed OS notification decision followed by two unobstructed reader frames')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('udid')
    p.add_argument('output',type=Path)
    p.add_argument('--bundle', help='Reader bundle for the SpringBoard decision read-back')
    p.add_argument('--authorization', type=Path, help='OS authorization status from the disposable native probe')
    args = p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    assert shutil.which('duoctl') and shutil.which('tesseract')
    if args.authorization:
        wait_for_decision(args.udid, args.output, args.authorization, args.bundle)
        return
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
