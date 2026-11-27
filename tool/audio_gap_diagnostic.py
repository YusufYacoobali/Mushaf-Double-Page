#!/usr/bin/env python3
"""Read-only PCM boundary diagnostics; requires ffmpeg and ffprobe on PATH.

This measures recording content after FFmpeg's normal gapless decoding. Low-level
edges can be breathing, room tone or vocal decay, so measurements NEVER authorize
trimming. It cannot measure ExoPlayer/AVQueuePlayer output or native transition
latency. See docs/v5-gapless-validation.md for scope and device capture procedure.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

LEVELS_DBFS = (-90, -75, -60, -45)


def run(args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def edge_counts(samples, channels, thresholds, reverse=False):
    """Contiguous below-threshold frames, using peak across ALL channels.

    Mono downmixing would mistake antiphase stereo for silence. A single sample
    above a threshold ends that edge; no RMS averaging can hide a quiet consonant.
    """
    if channels < 1 or len(samples) % channels:
        raise ValueError('Incomplete interleaved PCM frame')
    frames = len(samples) // channels
    counts = [None] * len(thresholds)
    for elapsed in range(frames):
        frame = frames - elapsed - 1 if reverse else elapsed
        peak = max(abs(samples[frame * channels + c]) for c in range(channels))
        if not math.isfinite(peak):
            raise ValueError('Non-finite PCM sample')
        for i, threshold in enumerate(thresholds):
            if counts[i] is None and peak > threshold:
                counts[i] = elapsed
        if all(c is not None for c in counts):
            break
    return [frames if c is None else c for c in counts]


def xing_info(payload):
    """Inspect first MPEG frame only; unknown/absent tags stay unknown.

    LAME values are reported separately from FFmpeg's skip/discard side data,
    which can include decoder priming. These are never applied a second time.
    """
    offset = 0
    if payload[:3] == b'ID3' and len(payload) >= 10:
        offset = 10 + sum((payload[6 + i] & 127) << (7 * (3 - i)) for i in range(4))
        if payload[5] & 16:
            offset += 10
    if offset + 4 > len(payload):
        return None
    header = int.from_bytes(payload[offset:offset + 4], 'big')
    if header & 0xffe00000 != 0xffe00000:
        return None
    version = (header >> 19) & 3
    mono = (header >> 6) & 3 == 3
    side = (17 if mono else 32) if version == 3 else (9 if mono else 17)
    for crc in (0, 2):
        pos = offset + 4 + side + crc
        signature = payload[pos:pos + 4]
        if signature not in (b'Xing', b'Info') or pos + 8 > len(payload):
            continue
        flags = int.from_bytes(payload[pos + 4:pos + 8], 'big')
        encoder = pos + 8 + sum(length for flag, length in ((1, 4), (2, 4), (4, 100), (8, 4)) if flags & flag)
        result = {'header': signature.decode('ascii'), 'lameDelaySamples': None, 'lamePaddingSamples': None}
        if payload[encoder:encoder + 4] == b'LAME' and encoder + 24 <= len(payload):
            result['encoder'] = payload[encoder:encoder + 9].decode('ascii', errors='replace')
            packed = int.from_bytes(payload[encoder + 21:encoder + 24], 'big')
            result['lameDelaySamples'] = packed >> 12
            result['lamePaddingSamples'] = packed & 4095
        return result
    return None


def analyze(path, identity):
    original = path.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    if identity.get('sha256') and digest != identity['sha256']:
        raise ValueError(f'Audit hash mismatch: {identity["id"]}')
    probe = json.loads(run(['ffprobe', '-v', 'error', '-select_streams', 'a:0',
                           '-show_streams', '-show_format', '-show_packets', '-of', 'json', str(path)]))
    stream = probe['streams'][0]
    rate, channels = int(stream['sample_rate']), int(stream['channels'])
    pcm = array('f')
    pcm.frombytes(run(['ffmpeg', '-v', 'error', '-xerror', '-i', str(path), '-map', '0:a:0',
                      '-vn', '-sn', '-dn', '-c:a', 'pcm_f32le', '-f', 'f32le', '-']))
    pcm_digest = hashlib.sha256(memoryview(pcm).cast('B')).hexdigest()
    if sys.byteorder != 'little':
        pcm.byteswap()
    frames = len(pcm) // channels
    if not frames:
        raise ValueError(f'Empty PCM: {path}')
    thresholds = [0.0] + [10 ** (db / 20) for db in LEVELS_DBFS]
    heads = edge_counts(pcm, channels, thresholds)
    tails = edge_counts(pcm, channels, thresholds, reverse=True)
    labels = ['digitalZero'] + [f'{db}dBFS' for db in LEVELS_DBFS]
    edges = {label: {'leadingMs': round(head * 1000 / rate, 3),
                     'trailingMs': round(tail * 1000 / rate, 3),
                     'allBelowThreshold': head == frames}
             for label, head, tail in zip(labels, heads, tails)}
    skip = discard = 0
    for packet in probe.get('packets', []):
        for side in packet.get('side_data_list', []):
            if side.get('side_data_type') == 'Skip Samples':
                skip += side.get('skip_samples', 0)
                discard += side.get('discard_padding', 0)
    tags = {**probe.get('format', {}).get('tags', {}), **stream.get('tags', {})}
    gapless_tags = {k: v for k, v in tags.items() if k.lower() in ('encoder', 'itunsmpb')}
    # Explicit integrity check protects the read-only diagnostic contract.
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Original changed during diagnostic: {path}')
    return {**identity, 'sha256': digest, 'codec': stream['codec_name'],
            'pcmSha256': pcm_digest,
            'firstFrame': list(pcm[:channels]), 'lastFrame': list(pcm[-channels:]),
            'sampleRate': rate, 'channels': channels,
            'pcmFrames': frames, 'pcmDurationMs': round(frames * 1000 / rate, 3),
            'containerDurationMs': round(float(probe['format']['duration']) * 1000, 3),
            'edges': edges, 'metadata': {'tags': gapless_tags, 'xing': xing_info(original),
                'ffmpegSkipSamples': skip, 'ffmpegDiscardPaddingSamples': discard,
                'ffmpegSkipMs': round(skip * 1000 / rate, 3),
                'ffmpegDiscardMs': round(discard * 1000 / rate, 3)},
            'automaticTrimApproved': False}


def boundary(left, right):
    quiet = {}
    for label, a in left['edges'].items():
        b = right['edges'][label]
        quiet[label] = None if a['allBelowThreshold'] or b['allBelowThreshold'] else round(a['trailingMs'] + b['leadingMs'], 3)
    return {'from': left['id'], 'to': right['id'], 'recordingQuietMs': quiet,
            'nativePlayerDelayMs': None,
            'interpretation': 'Source PCM edge quiet only, not a measured output gap or permission to trim.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='*', type=Path)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.manifest:
        if args.files:
            parser.error('Use either a manifest or files')
        manifest = json.loads(args.manifest.read_text())
        identities = manifest['recordings']
        paths = [args.manifest.parent / row['path'] for row in identities]
        cases = manifest['cases']
    else:
        if not args.files:
            parser.error('Supply MP3 files or --manifest')
        identities = [{'id': str(p), 'path': str(p)} for p in args.files]
        paths = args.files
        cases = [{'id': 'command-line-order', 'items': [r['id'] for r in identities]}]
    if args.output.resolve() in {p.resolve() for p in paths}:
        parser.error('Output must not overwrite a recording')
    recordings = [analyze(p, row) for p, row in zip(paths, identities)]
    by_id = {r['id']: r for r in recordings}
    if len(by_id) != len(recordings):
        raise ValueError('Duplicate recording IDs')
    report = {'schemaVersion': 1, 'ffmpeg': run(['ffmpeg', '-version']).decode().splitlines()[0],
              'method': 'Native-rate interleaved float PCM, FFmpeg normal metadata-aware decode. '
                'Contiguous per-sample peak across every channel at digital zero and -90/-75/-60/-45 dBFS. '
                'No downmix, resampling, RMS gating, trimming, overlap, speed/pitch changes or cache writes.',
              'limitations': ['Low-level audio may be pronunciation, decay, breathing, noise or deliberate pause.',
                'No native player output was captured. Null nativePlayerDelayMs means unmeasured, never zero.',
                'FFmpeg skip/discard metadata is already applied in decoded PCM; subtracting it again risks clipping.'],
              'recordings': recordings, 'cases': [{**case, 'boundaries': [boundary(by_id[a], by_id[b])
                  for a, b in zip(case['items'], case['items'][1:])]} for case in cases]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(f'{len(recordings)} recordings; {sum(len(c["boundaries"]) for c in report["cases"])} boundaries; native output delay unmeasured')


if __name__ == '__main__':
    main()
