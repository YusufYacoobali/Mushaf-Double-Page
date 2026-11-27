#!/usr/bin/env python3
"""Compare original MP3s with stereo S16 captures before the output mixer."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
from everyayah_transition_probe import locate


def db_ratio(energy, reference):
    if energy == 0 or reference == 0:
        return None
    return round(float(10 * np.log10(energy / reference)), 5)


def correlation(left, right):
    if np.ptp(left) == 0 or np.ptp(right) == 0:
        return None
    return float(np.corrcoef(left, right)[0, 1])


def stereo(samples):
    energy = np.mean(samples ** 2)
    return {
        'frames': len(samples),
        'channelCorrelation': correlation(*samples.T),
        'monoMixDbRelativeToStereo': db_ratio(np.mean(samples.mean(axis=1) ** 2), energy),
        'rms': np.sqrt(np.mean(samples ** 2, axis=0)).tolist(),
        'peak': np.max(np.abs(samples), axis=0).tolist(),
        'railSamples': np.sum((samples == -32768) | (samples == 32767), axis=0).tolist(),
    }


def compare(reference, measured):
    delta = reference - measured
    return {
        'framesCompared': len(reference),
        'maxErrorLSB': np.max(np.abs(delta), axis=0).tolist(),
        'rmsErrorLSB': np.sqrt(np.mean(delta ** 2, axis=0)).tolist(),
        'differentSamples': np.count_nonzero(delta, axis=0).tolist(),
        'gainDb': [db_ratio(np.sum(m ** 2), np.sum(r ** 2)) for r, m in zip(reference.T, measured.T)],
        'snrDb': [db_ratio(np.sum(r ** 2), np.sum(d ** 2)) for r, d in zip(reference.T, delta.T)],
        'channelCorrelationWithReference': [correlation(r, m) for r, m in zip(reference.T, measured.T)],
    }


def raw_pcm(data):
    if not data or len(data) % 4:
        raise ValueError('Expected nonempty, whole stereo S16LE frames')
    return np.frombuffer(data, '<i2').reshape(-1, 2).astype(np.float64)


def align(parts, capture):
    """Find timing on both channels independently; retain unmatched edges in the report."""
    starts = []
    for part in parts:
        length = min(4096, len(part))
        offset = (len(part) - length) // 2
        positions = [
            locate(capture[:, c], part[offset:offset + length, c])[0] - offset
            for c in (0, 1) if np.ptp(capture[:, c]) and np.ptp(part[offset:offset + length, c])
        ]
        if not positions:
            raise ValueError('No signal to align on either channel')
        if len(set(positions)) != 1:
            raise ValueError(f'Left/right timing disagrees: {positions}')
        starts.append(positions[0])
    if any(a >= b for a, b in zip(starts, starts[1:])):
        raise ValueError('Recordings out of order or landmarks ambiguous')
    return starts


def audit(paths, captures):
    parts = []
    rows = []
    for path in paths:
        pcm = raw_pcm(subprocess.check_output(['ffmpeg', '-v', 'error', '-xerror', '-i', str(path),
                      '-map', '0:a:0', '-ar', '44100', '-ac', '2', '-f', 's16le', '-']))
        parts.append(pcm)
        rows.append({'file': path.name, 'mp3Sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                     'reference': stereo(pcm)})
    starts = {name: align(parts, pcm) for name, pcm in captures.items()}
    for i, (part, row) in enumerate(zip(parts, rows)):
        ranges = {}
        for name, pcm in captures.items():
            start = starts[name][i]
            end = starts[name][i + 1] if i + 1 < len(parts) else len(pcm)
            lo, hi = max(0, -start), min(len(part), end - start)
            if hi <= lo:
                raise ValueError('No shared frames')
            ranges[name] = (lo, hi)
            clip = pcm[start + lo:start + hi]
            row[name] = {'alignedStart': start, 'missingReferenceHead': lo,
                         'missingReferenceTail': len(part) - hi, 'extraAtEnd': max(0, end - start - len(part)),
                         'stereo': stereo(clip), 'vsReference': compare(part[lo:hi], clip)}
        if len(ranges) == 2:
            lo, hi = max(a for a, _ in ranges.values()), min(b for _, b in ranges.values())
            if hi <= lo:
                raise ValueError('No frames shared by both backends')
            row['backendComparison'] = compare(*[pcm[starts[name][i] + lo:starts[name][i] + hi]
                                                  for name, pcm in captures.items()])
    return {'format': '44100 Hz stereo S16LE', 'captureFrames': {n: len(p) for n, p in captures.items()},
            'recordings': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('originals', type=Path, nargs='+', help='Original MP3 files in playback order')
    parser.add_argument('--continuous', type=Path, help='Raw interleaved stereo S16LE at 44.1 kHz')
    parser.add_argument('--legacy', type=Path, help='Raw interleaved stereo S16LE at 44.1 kHz')
    args = parser.parse_args()
    captures = {name: raw_pcm(path.read_bytes()) for name, path in
                [('continuous', args.continuous), ('legacy', args.legacy)] if path}
    print(json.dumps(audit(args.originals, captures), indent=2, allow_nan=False))
