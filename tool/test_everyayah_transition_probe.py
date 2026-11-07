import tempfile
import unittest
from pathlib import Path
import numpy as np
from everyayah_transition_probe import generate, read_wav, write_wav, measure


class TransitionProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temp.name)
        cls.manifest = generate(cls.directory)
        cls.rate, cls.signal = read_wav(cls.directory / 'reference.wav')

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def capture(self, extra_frames):
        boundary = self.manifest['parts'][1]['startFrame']
        signal = np.concatenate([self.signal[:boundary], np.zeros((extra_frames, 2)), self.signal[boundary:]])
        # Arbitrary startup latency and gain do not count as a boundary gap.
        signal = np.concatenate([np.zeros((1234, 2)), signal * .55])
        path = self.directory / 'capture.wav'
        write_wav(path, self.rate, signal)
        return measure(self.directory, path, 'synthetic', 'baseline')

    def test_two_mp3s_preserve_exact_source_sample_counts(self):
        self.assertEqual([p['decodedFrames'] for p in self.manifest['parts']], [66150, 66150])
        self.assertEqual(len(self.signal), 132300)
        self.assertEqual(self.capture(0)['boundaries'][0]['additionalFrames'], 0)

    def test_output_measurement_detects_100ms_without_quiet_thresholds(self):
        result = self.capture(self.rate // 10)
        self.assertEqual(result['boundaries'][0]['additionalFrames'], 4410)
        self.assertEqual(result['boundaries'][0]['additionalMs'], 100)

    def test_bad_capture_is_rejected(self):
        path = self.directory / 'silent.wav'
        write_wav(path, self.rate, np.zeros_like(self.signal))
        with self.assertRaises(ValueError):
            measure(self.directory, path, 'synthetic', 'control')


if __name__ == '__main__':
    unittest.main()
