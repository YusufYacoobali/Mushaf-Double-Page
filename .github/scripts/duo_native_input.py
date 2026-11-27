"""Submit real device gestures and match their UIKit and Flutter coordinates."""
import json
import math
import os
from pathlib import Path
import subprocess
import time
from uuid import uuid4


def read(path):
    return json.loads(path.read_text())


def atomic(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(data)
    tmp.replace(path)


def wait_for(fn, description, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(.15)
    raise RuntimeError(f"Timed out waiting for {description}")


class NativeInput:
    def __init__(self, source):
        self.docs = source.parent
        self.udid = os.environ['DUOCTL_UDID']
        self.display = json.loads(subprocess.check_output(['duoctl', '-d', self.udid, 'state']))
        self.size = self.display['sizePoints']
        frame = read(source)
        assert self.size == [frame['viewport']['width'], frame['viewport']['height']], (self.display, frame['viewport'])
        assert self.display['activeScreen'] == ('cover' if frame['native']['closed'] else 'inner')
        self.out = Path('screenshots/interactions')
        self.out.mkdir(parents=True, exist_ok=True)
        self.driver = None
        self.xc_dir = None
        self.use_xctest = False
        self.record({'display': self.display, 'native': frame['native']})

    def record(self, row):
        with (self.out / 'interaction.jsonl').open('a') as f:
            f.write(json.dumps(row) + '\n')
        print(json.dumps(row, ensure_ascii=False), flush=True)

    def snapshot(self):
        token = uuid4().hex
        atomic(self.docs / 'duo-request', token)
        path = self.docs / 'duo-snapshot.json'
        def current():
            if path.exists():
                data = read(path)
                if data['id'] == token:
                    return data
        return wait_for(current, 'fresh reader snapshot', 10)

    def xc(self, **command):
        if not self.driver:
            self.log = (self.out / f'xc-{uuid4().hex[:8]}.log').open('w')
            root = Path.home() / 'Library/Developer/CoreSimulator/Devices' / self.udid / 'data/Containers/Data/Application'
            for marker in root.glob('*/Documents/duo-input-ready'):
                marker.unlink()
            self.driver = subprocess.Popen([
                'xcodebuild', 'test-without-building', '-project', 'tools/ios_ui_qa/ReaderUIHarness.xcodeproj',
                '-scheme', 'ReaderVisualTests', '-derivedDataPath', 'ui-build',
                '-destination', 'platform=iOS Simulator,id=' + self.udid, '-parallel-testing-enabled', 'NO',
                '-only-testing:ReaderVisualTests/DuoInputTests/testInput',
                '-resultBundlePath', str(self.out / f'input-{uuid4().hex[:8]}.xcresult'), 'CODE_SIGNING_ALLOWED=NO'
            ], stdout=self.log, stderr=subprocess.STDOUT)
            def ready():
                if self.driver.poll() is not None:
                    raise RuntimeError('XCTest input runner exited before readiness')
                return next(root.glob('*/Documents/duo-input-ready'), None)
            self.xc_dir = wait_for(ready, 'foreground XCTest input driver', 190).parent
        token = uuid4().hex
        atomic(self.xc_dir / 'duo-command.json', json.dumps(dict(command, id=token, size=self.size)))
        reply = self.xc_dir / 'duo-reply.json'
        wait_for(lambda: reply.exists() and reply.read_text() == token, f'XCTest {command}', 45)

    def close(self):
        try:
            if self.driver and self.driver.poll() is None and self.xc_dir:
                self.xc(action='finish')
                if self.driver.wait(timeout=55):
                    raise RuntimeError('XCTest input failed')
        finally:
            for name in ('duo-uikit.jsonl', 'duo-flutter.jsonl'):
                path = self.docs / name
                if path.exists():
                    (self.out / name).write_bytes(path.read_bytes())

    def gesture(self, label, point, end=None):
        action = 'swipe' if end else 'tap'
        for route in (['xc'] if self.use_xctest else ['duoctl', 'xc']):
            start = time.time()
            if route == 'xc':
                self.xc(action=action, point=point, end=end)
            else:
                args = ['duoctl', '-d', self.udid, action, *map(str, point)]
                if end:
                    args += [*map(str, end), '--duration', '.3']
                subprocess.run(args, check=True, timeout=35)
            def events(name):
                path = self.docs / ('duo-' + name + '.jsonl')
                rows = [json.loads(s) for s in path.read_text().splitlines()] if path.exists() else []
                return [r for r in rows if r['time'] >= start - .01]
            def matched(rows):
                return any('x' in row and math.dist(point, (row['x'], row['y'])) <= 2 for row in rows)
            time.sleep(.25)
            native = events('uikit')
            flutter = events('flutter')
            self.record(dict(label=label, via=route, point=point, end=end, uikit=native, flutter=flutter))
            if matched(native) and matched([r for r in flutter if r.get('pointer') == 'PointerDownEvent']):
                self.use_xctest = route == 'xc'
                return
            if route == 'xc' or matched(native):
                raise RuntimeError(f'{label}: input reached an unexpected native or Flutter target')
        raise RuntimeError(f'{label}: no verified touch')
