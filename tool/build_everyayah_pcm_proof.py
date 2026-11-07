#!/usr/bin/env python3
"""Stage-A only: join ten cached Yasser 55:1-10 EveryAyah files as decoded PCM.

Requires FFmpeg; never modifies source MP3s. No quiet trimming, fades, overlap,
MP3-byte concatenation or external timestamp data. Production streaming is not
implemented by this offline proof builder.
"""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import tempfile
import time
import wave

RATE, CHANNELS, WIDTH = 44100, 2, 2
BISMILLAH_SHA = 'efc922e29b8e10cd09e83617fe85ba09a2a77ed9e449a09b9e515250d2806ce0'


def decode(path, output):
    subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-nostdin', '-y', '-i', str(path),
                    '-map', '0:a:0', '-ar', str(RATE), '-ac', str(CHANNELS),
                    '-c:a', 'pcm_s16le', '-f', 's16le', str(output)], check=True)


def build(cache, output):
    started = time.perf_counter()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError('Use an empty disposable output directory')
    if cache.resolve() == output.resolve():
        raise ValueError('Output must be separate from the MP3 cache')
    paths = [cache / '001001.mp3', *[cache / f'055{a:03}.mp3' for a in range(1, 11)]]
    for path in paths:
        if not path.is_file(): raise ValueError(f'Missing cached recording: {path.name}')
    if hashlib.sha256(paths[0].read_bytes()).hexdigest() != BISMILLAH_SHA:
        raise ValueError('Bismillah differs from the existing verified EveryAyah source')
    frames = 0
    rows = []
    pcm_hash = hashlib.sha256()
    with tempfile.TemporaryDirectory(prefix='everyayah-pcm-decode-') as temp:
        wave_path = output / 'continuous.wav'
        with wave.open(str(wave_path), 'wb') as joined:
            joined.setnchannels(CHANNELS)
            joined.setsampwidth(WIDTH)
            joined.setframerate(RATE)
            for number, path in enumerate(paths):
                pcm = Path(temp) / 'decoded.pcm'
                decode(path, pcm)
                size = pcm.stat().st_size
                if not size or size % (CHANNELS * WIDTH): raise ValueError('Incomplete PCM frame')
                count = size // (CHANNELS * WIDTH)
                digest = hashlib.sha256()
                with pcm.open('rb') as source:
                    for block in iter(lambda: source.read(65536), b''):
                        digest.update(block)
                        pcm_hash.update(block)
                        joined.writeframesraw(block)
                rows.append({'surah': 55, 'ayah': None if number == 0 else number,
                             'cycle': 1, 'occurrence': f'yasser_dussary:55:{number}:1',
                             'startFrame': frames, 'endFrame': frames + count,
                             'sourceFile': path.name, 'sourceSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                             'decodedSha256': digest.hexdigest()})
                frames += count
        # Re-decode every original independently and compare the exact output
        # segment byte-for-byte. This detects missing, inserted or reordered PCM.
        with wave.open(str(wave_path), 'rb') as joined:
            assert joined.getnframes() == frames
            for row, path in zip(rows, paths):
                decode(path, Path(temp) / 'verify.pcm')
                expected = (Path(temp) / 'verify.pcm').read_bytes()
                actual = joined.readframes(row['endFrame'] - row['startFrame'])
                if actual != expected: raise ValueError(f'PCM changed at {path.name}')
            assert joined.readframes(1) == b''
    report = {'schema': 1, 'reciter': 'yasser_dussary', 'surah': 55,
              'fromAyah': 1, 'toAyah': 10, 'sampleRate': RATE, 'channels': CHANNELS,
              'bitsPerSample': WIDTH * 8, 'frames': frames, 'rows': rows,
              'waveSha256': hashlib.sha256(wave_path.read_bytes()).hexdigest(),
              'pcmSha256': pcm_hash.hexdigest(), 'waveBytes': wave_path.stat().st_size,
              'durationMs': frames * 1000 / RATE, 'allDecodedSamplesComparedEqual': True,
              'decoder': subprocess.check_output(['ffmpeg', '-version'], text=True).splitlines()[0],
              'preparationSeconds': time.perf_counter() - started,
              'builderPeakRssKiB': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
              'decodedWorkingSet': 'One recording PCM file at a time; 64 KiB write buffers. Verification reads one recording at a time.',
              'limitations': 'Stage A offline preparation only; no progressive producer. Native output gap, battery and mobile startup unmeasured.'}
    (output / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build(args.cache, args.output)
    print(json.dumps({k: result[k] for k in ['frames', 'durationMs', 'waveBytes', 'preparationSeconds', 'allDecodedSamplesComparedEqual']}, indent=2))
