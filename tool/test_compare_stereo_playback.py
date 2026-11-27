import subprocess
import unittest
from pathlib import Path

import numpy as np

from compare_stereo_playback import align, audit, compare, raw_pcm, stereo


class StereoPlaybackTest(unittest.TestCase):
    def test_real_fixture_keeps_separate_channels_and_reports_unmatched_tail(self):
        path = Path(__file__).resolve().parents[1] / 'test/fixtures/gapless/alafasy-112002.mp3'
        original = raw_pcm(subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 's16le', '-']))
        row, = audit([path], {'continuous': original[:-47], 'legacy': original})['recordings']
        self.assertEqual(row['continuous']['missingReferenceTail'], 47)
        self.assertEqual(row['legacy']['missingReferenceTail'], 0)
        self.assertEqual(row['backendComparison']['differentSamples'], [0, 0])
        self.assertEqual(row['backendComparison']['framesCompared'], len(original) - 47)

    def test_phase_cancellation_and_channel_loss_are_visible(self):
        channel = np.random.default_rng(1).normal(size=8192) * 1000
        original = np.column_stack([channel, -channel * .95])
        muted = original.copy()
        muted[:, 0] = 0
        self.assertEqual(align([original], muted), [0])
        self.assertLess(stereo(original)['monoMixDbRelativeToStereo'], -30)
        result = compare(original, muted)
        self.assertIsNone(result['channelCorrelationWithReference'][0])
        self.assertEqual(result['differentSamples'], [len(original), 0])
