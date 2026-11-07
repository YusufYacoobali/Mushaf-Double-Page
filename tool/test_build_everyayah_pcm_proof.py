from array import array
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import wave
from build_everyayah_pcm_proof import build


class PcmProofBuilderTests(unittest.TestCase):
    def test_sample_order_and_offsets_preserve_every_frame(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cache = root / 'cache'
            cache.mkdir()
            shutil.copyfile('test/fixtures/bismillah/yasser_dussary.mp3', cache / '001001.mp3')
            for a in range(1, 11): (cache / f'055{a:03}.mp3').write_bytes(bytes([a]))
            def decoded(path, target):
                number = 0 if path.name == '001001.mp3' else int(path.stem[-3:])
                target.write_bytes(array('h', [100 + number] * ((number + 1) * 2)).tobytes())
            with patch('build_everyayah_pcm_proof.decode', side_effect=decoded):
                report = build(cache, root / 'out')
            self.assertEqual(report['frames'], sum(range(1, 12)))
            expected_start = 0
            with wave.open(str(root / 'out/continuous.wav'), 'rb') as wav:
                for i, row in enumerate(report['rows']):
                    self.assertEqual(row['startFrame'], expected_start)
                    self.assertEqual(row['endFrame'] - row['startFrame'], i + 1)
                    self.assertEqual(wav.readframes(i + 1), array('h', [100 + i] * ((i + 1) * 2)).tobytes())
                    expected_start += i + 1
                self.assertEqual(wav.readframes(1), b'')
            self.assertTrue(report['allDecodedSamplesComparedEqual'])

    def test_output_cannot_overwrite_cached_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            source = cache / 'keep.mp3'
            source.write_bytes(b'original')
            with self.assertRaises(ValueError): build(cache, cache)
            self.assertEqual(source.read_bytes(), b'original')


if __name__ == '__main__': unittest.main()
