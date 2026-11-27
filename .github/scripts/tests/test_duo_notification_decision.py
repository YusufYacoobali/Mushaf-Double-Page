import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dismiss_duo_notification as permission


class DuoPermissionTest(unittest.TestCase):
    def test_clear_reader_before_late_prompt_is_not_a_decision(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            authorization = output / 'duo-notification.json'
            button = {'x': .25, 'y': .60}
            frames = iter([
                (0, False, None, .25),  # Clear reader before the delayed alert.
                (0, False, button, .00),  # Unidentified prompt must never be tapped.
                (0, True, button, .00),
                (1, False, None, .01),  # OS decision arrived while still dimmed.
                (1, False, None, .25),
                (1, False, None, .25),
            ])

            def screen(_):
                status, prompt, deny, white = next(frames)
                authorization.write_text(str(status))
                return dict(notificationPrompt=prompt, denyNotification=deny, nearWhiteFraction=white)

            with patch.object(permission, 'screenshot', side_effect=screen), \
                 patch.object(permission, 'screen_geometry', return_value=(466, 678)), \
                 patch.object(permission, 'run') as send, patch.object(permission.time, 'sleep'):
                permission.wait_for_decision('simulator', output, authorization)

            send.assert_called_once_with(['duoctl', '-d', 'simulator', 'tap', '116.5', '406.8'], 35)
            audit = json.loads((output / 'permission-verification.json').read_text())
            self.assertEqual([f['status'] for f in audit], [0, 0, 0, 1, 1, 1])

    def test_display_timeout_uses_xctest_and_requires_the_os_decision(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            authorization = output / 'duo-notification.json'
            authorization.write_text('0')

            def screen(_):
                pending = authorization.read_text() == '0'
                return dict(notificationPrompt=pending, denyNotification={'x': .25, 'y': .6} if pending else None,
                            nearWhiteFraction=0 if pending else .25)

            def xctest(command, **kwargs):
                self.assertIn('xcodebuild', command)
                self.assertIn('platform=iOS Simulator,id=cover', command)
                authorization.write_text('1')

            timeout = subprocess.TimeoutExpired('devicectl', 65)
            with patch.object(permission, 'screenshot', side_effect=screen), \
                 patch.object(permission, 'screen_geometry', side_effect=timeout), \
                 patch.object(permission.subprocess, 'run', side_effect=xctest) as runner, \
                 patch.object(permission.time, 'sleep'):
                permission.wait_for_decision('cover', output, authorization)
            runner.assert_called_once()
            audit = json.loads((output / 'permission-verification.json').read_text())
            self.assertEqual([row['status'] for row in audit], [0, 1, 1])

    def test_springboard_decision_requires_exact_app_and_explicit_denial(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(Path, 'home', return_value=Path(tmp)):
            folder = Path(tmp) / 'Library/Developer/CoreSimulator/Devices/cover/data/Library/BulletinBoard'
            folder.mkdir(parents=True)
            path = folder / 'VersionedSectionInfo.plist'
            bundle = 'test.reader'
            for allowed in (True, False):
                settings = plistlib.dumps({'$objects': [bundle, {'allowsNotifications': allowed}]},
                                          fmt=plistlib.FMT_BINARY)
                path.write_bytes(plistlib.dumps({'sectionInfo': {bundle: settings}}, fmt=plistlib.FMT_BINARY))
                self.assertIsNone(permission.springboard_denied('cover', 'other.app'))
                self.assertEqual(permission.springboard_denied('cover', bundle), None if allowed else str(path))
