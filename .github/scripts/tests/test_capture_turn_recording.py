"""Contract checks for opt-in native recording, without a device or synthetic video."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_android_foldable as capture


def frame(page, single):
    rect = {"left": 65, "top": -12, "width": 50, "height": 100}
    pages = {str(page): rect}
    if not single:
        pages[str(page + 1)] = dict(rect, left=15)
    return {"pages": pages, "focusedPage": page, "mode": "single" if single else "spread",
            "readingBounds": {"left": 10, "top": 5, "width": 110, "height": 60},
            "pixelRatio": 2, "zoom": .7 if single else .6}


class TurnRecordingTest(unittest.TestCase):
    def test_swipe_uses_visible_outgoing_leaf_in_both_directions(self):
        spread = frame(6, False)
        self.assertEqual(capture.turn_swipe(spread, True), [42, 70, 118, 70])
        self.assertEqual(capture.turn_swipe(spread, False), [218, 70, 142, 70])

    def exercise(self, posture, *, fail_settlement=False, end_early=False):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        output = Path(directory.name)
        reader = capture.Capture("emulator", "galaxy-z-fold8", {}, output, 6)
        capture.write_json(output / "seed-state.json", {
            "physicalDisplayId": "10102", "focusedDisplayId": 0, "pixelSize": [2000, 1000],
        })
        sha = "a" * 40
        digest = "d" * 64
        capture.write_json(output / "build.json", {"package": capture.PACKAGE, "commit": sha, "sha256": digest})
        def shell(*args, **kwargs):
            return {
                "pm": "package:/data/app/base.apk", "sha256sum": digest + "  base.apk",
                "settings": "0", "stat": "32",
            }.get(args[0], "")
        reader.shell = MagicMock(side_effect=shell)
        reader.adb = MagicMock()
        single = posture == "folded"
        reader.dock = MagicMock(return_value=frame(6, single))
        reader.device_clock = MagicMock(side_effect=[101, 102])
        def settled(predicate, *, after, timeout, expected_page):
            if fail_settlement:
                raise RuntimeError("wrong requested Quran pages")
            result = frame(expected_page, single)
            self.assertTrue(predicate(result))
            return result
        reader.wait_frame = MagicMock(side_effect=settled)
        video_probe = MagicMock(stdout=json.dumps({"streams": [
            {"width": 1280, "height": 640, "duration": "13.6", "nb_frames": "36"},
        ]}))
        with patch.object(capture, "ThreadPoolExecutor") as executor, \
             patch.object(capture.time, "sleep"), \
             patch.object(capture, "foreground_window", return_value={"displayId": 0, "package": capture.PACKAGE}), \
             patch.object(capture.subprocess, "run", return_value=video_probe):
            worker = executor.return_value.__enter__.return_value
            recording = worker.submit.return_value
            recording.done.return_value = end_early
            if fail_settlement or end_early:
                with self.assertRaisesRegex((RuntimeError, AssertionError), "wrong requested|ended before"):
                    reader.record_turns(posture, "seed")
            else:
                reader.record_turns(posture, "seed")
            self.assertIn("10102", worker.submit.call_args.args)
        reader.shell.assert_any_call("settings", "put", "global", "animator_duration_scale", "0")
        evidence = output / (posture + "-page-turns.json")
        if fail_settlement or end_early:
            self.assertFalse(evidence.exists())
            reader.adb.assert_not_called()
        else:
            report = json.loads(evidence.read_text())
            neighbour = 7 if single else 8
            self.assertEqual([f["focusedPage"] for f in report["settledFrames"]], [6, neighbour, 6])
            self.assertEqual([c.kwargs["after"] for c in reader.wait_frame.call_args_list], [101, 102])
            self.assertEqual(report["commit"], sha)
            self.assertEqual(report["apkSha256"], digest)
            actions = [c.args[4:] for c in reader.shell.call_args_list if c.args[:4] == ("input", "-d", 0, "swipe")]
            self.assertEqual(len(actions), 2)
            self.assertLess(actions[0][0], actions[0][2])
            self.assertGreater(actions[1][0], actions[1][2])

    def test_records_both_directions_and_restores_the_native_setting(self):
        for posture in capture.TURN_POSTURES:
            with self.subTest(posture=posture):
                self.exercise(posture)

    def test_does_not_accept_an_unsettled_destination(self):
        self.exercise("unfolded-landscape", fail_settlement=True)

    def test_does_not_accept_recording_that_ended_before_the_return(self):
        self.exercise("folded", end_early=True)

    def test_recordings_require_a_returnable_seed_before_touching_the_device(self):
        with tempfile.TemporaryDirectory() as directory:
            for page in (1, 7, 851):
                reader = capture.Capture("emulator", "galaxy-z-fold8", {}, directory, page)
                reader.prepare = MagicMock()
                with self.subTest(page=page), self.assertRaisesRegex(ValueError, "exact seed"):
                    reader.run(record_turns=True)
                reader.prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
