"""Focused tests for the read-only source diagnostic, never a native gap test."""
from array import array
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import wave

from audio_gap_diagnostic import analyze, boundary, edge_counts, xing_info


class BoundaryDiagnosticTest(unittest.TestCase):
    def test_all_channels_protect_antiphase_and_quiet_vocal_decay(self):
        pcm = array('f', [0, 0, .0001, -.0001, .25, -.25, .0001, -.0001, 0, 0])
        self.assertEqual(edge_counts(pcm, 2, [0, .00001, .001]), [1, 1, 2])
        self.assertEqual(edge_counts(pcm, 2, [0, .00001, .001], reverse=True), [1, 1, 2])
        self.assertEqual(edge_counts(array('f', [0, 0] * 4), 2, [0, .001]), [4, 4])
        self.assertIsNone(xing_info(b'ID3'))

    def test_metadata_aware_decode_reports_padding_without_double_trimming_or_editing(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            wav, mp3 = root / 'source.wav', root / 'source.mp3'
            # 40 ms exact digital silence, 200 ms antiphase signal, 60 ms silence.
            samples = array('h', [0, 0] * 1764 + [8192, -8192] * 8820 + [0, 0] * 2646)
            with wave.open(str(wav), 'wb') as f:
                f.setnchannels(2)
                f.setsampwidth(2)
                f.setframerate(44100)
                f.writeframes(samples.tobytes())
            row = analyze(wav, {'id': 'uncompressed'})
            self.assertEqual(row['edges']['digitalZero']['leadingMs'], 40)
            self.assertEqual(row['edges']['digitalZero']['trailingMs'], 60)
            self.assertFalse(row['automaticTrimApproved'])
            subprocess.run(['ffmpeg', '-v', 'error', '-i', str(wav), '-c:a', 'libmp3lame',
                            '-q:a', '4', str(mp3)], check=True)
            digest = hashlib.sha256(mp3.read_bytes()).hexdigest()
            encoded = analyze(mp3, {'id': 'encoded', 'sha256': digest})
            self.assertGreater(encoded['metadata']['ffmpegSkipSamples'], 0)
            self.assertGreater(encoded['metadata']['ffmpegDiscardPaddingSamples'], 0)
            self.assertEqual(encoded['pcmFrames'], row['pcmFrames'])
            self.assertEqual(hashlib.sha256(mp3.read_bytes()).hexdigest(), digest)
            self.assertFalse(encoded['automaticTrimApproved'])
            pair = boundary(row, encoded)
            self.assertIsNone(pair['nativePlayerDelayMs'])
            row['edges']['digitalZero']['allBelowThreshold'] = True
            self.assertIsNone(boundary(row, encoded)['recordingQuietMs']['digitalZero'])
            with self.assertRaises(ValueError):
                analyze(mp3, {'id': 'changed', 'sha256': '0' * 64})
            result = subprocess.run(['python3', str(Path(__file__).with_name('audio_gap_diagnostic.py')),
                                     str(mp3), '--output', str(mp3)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(hashlib.sha256(mp3.read_bytes()).hexdigest(), digest)

    def test_committed_measurements_are_hash_bound_and_never_claim_output_latency(self):
        repo = Path(__file__).resolve().parent.parent
        manifest = json.loads((repo / 'tool/audio_gap_samples.json').read_text())
        report = json.loads((repo / 'docs/audio-gap-analysis.json').read_text())
        actual = {r['id']: r for r in report['recordings']}
        self.assertEqual(len(actual), len(manifest['recordings']))
        for row in manifest['recordings']:
            digest = hashlib.sha256((repo / 'tool' / row['path']).read_bytes()).hexdigest()
            self.assertEqual(digest, row['sha256'])
            self.assertEqual(actual[row['id']]['sha256'], digest)
            self.assertFalse(actual[row['id']]['automaticTrimApproved'])
        for case in report['cases']:
            for pair in case['boundaries']:
                self.assertIsNone(pair['nativePlayerDelayMs'])


if __name__ == '__main__':
    unittest.main()
