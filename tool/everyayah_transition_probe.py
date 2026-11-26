#!/usr/bin/env python3
"""Generate a split-signal native-player probe and measure captured output.

Requires numpy and FFmpeg. No recitation is read or modified. Alignment compares
known signal landmarks, not amplitude-based silence or Dart event timestamps.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import numpy as np


def read_wav(path):
    with wave.open(str(path), 'rb') as wav:
        if wav.getsampwidth() != 2:
            raise ValueError('Capture must be signed 16-bit PCM WAV')
        rate, channels = wav.getframerate(), wav.getnchannels()
        samples = np.frombuffer(wav.readframes(wav.getnframes()), '<i2').astype(np.float64)
    return rate, samples.reshape(-1, channels)


def write_wav(path, rate, samples):
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(samples.shape[1])
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(np.asarray(samples, '<i2').tobytes())


def generate(directory, rate=44100):
    directory.mkdir(parents=True, exist_ok=True)
    if any(directory.iterdir()):
        raise ValueError('Use an empty synthetic fixture directory')
    frames = rate * 3 // 2  # 1.5 s; deliberately not an MPEG frame multiple
    rng = np.random.default_rng(670112)
    raw = rng.normal(size=frames * 2)
    # One continuous band-limited, uniquely coded signal with no inserted gap.
    spectrum = np.fft.rfft(raw)
    hz = np.fft.rfftfreq(len(raw), 1 / rate)
    spectrum[(hz < 350) | (hz > 3500)] = 0
    signal = np.fft.irfft(spectrum, n=len(raw))
    signal *= 6000 / np.max(np.abs(signal))
    samples = np.column_stack([signal, signal]).astype('<i2')
    write_wav(directory / 'unsplit.wav', rate, samples)
    parts, decoded = [], []
    for i in range(2):
        source = directory / f'part-{i}.wav'
        mp3 = directory / f'part-{i}.mp3'
        pcm = directory / f'decoded-{i}.wav'
        write_wav(source, rate, samples[i * frames:(i + 1) * frames])
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source),
                        '-c:a', 'libmp3lame', '-b:a', '128k', '-write_xing', '1', str(mp3)], check=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-y', '-i', str(mp3),
                        '-c:a', 'pcm_s16le', str(pcm)], check=True)
        decoded_rate, data = read_wav(pcm)
        if decoded_rate != rate or len(data) != frames:
            raise ValueError('Decoder did not preserve the known sample count with codec padding metadata')
        decoded.append(data)
        parts.append({'file': mp3.name, 'sha256': hashlib.sha256(mp3.read_bytes()).hexdigest(),
                      'decodedFrames': len(data), 'startFrame': i * frames})
    # Reference is normal decoder output, including reliable codec metadata.
    # No quiet samples are trimmed; no MP3 bytes are concatenated.
    write_wav(directory / 'reference.wav', rate, np.concatenate(decoded))
    manifest = {'sampleRate': rate, 'channels': 2, 'parts': parts,
                'reference': 'reference.wav', 'unsplitControl': 'unsplit.wav',
                'referenceSha256': hashlib.sha256((directory / 'reference.wav').read_bytes()).hexdigest(),
                'unsplitSha256': hashlib.sha256((directory / 'unsplit.wav').read_bytes()).hexdigest(),
                'description': 'Two independent MP3s split from one uninterrupted signal. Synthetic only.'}
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def locate(capture, template):
    """Normalized FFT correlation; returns an interior signal landmark."""
    if len(capture) < len(template):
        raise ValueError('Capture is shorter than its reference')
    template = template - template.mean()
    size = 1 << (len(capture) + len(template) - 2).bit_length()
    dots = np.fft.irfft(np.fft.rfft(capture, size) * np.fft.rfft(template[::-1], size), size)
    dots = dots[len(template) - 1:len(capture)]
    cumulative = np.r_[0., np.cumsum(capture)]
    squares = np.r_[0., np.cumsum(capture * capture)]
    count = len(template)
    energy = squares[count:] - squares[:-count] - (cumulative[count:] - cumulative[:-count]) ** 2 / count
    scores = dots / np.sqrt(np.maximum(energy, 1) * np.dot(template, template))
    index = int(np.argmax(scores))
    if scores[index] < .70:
        raise ValueError(f'Unreliable signal alignment ({scores[index]:.3f}); use a direct capture')
    return index, float(scores[index])


def measure(directory, capture_path, platform, stage):
    manifest = json.loads((directory / 'manifest.json').read_text())
    reference_path = directory / manifest['reference']
    if hashlib.sha256(reference_path.read_bytes()).hexdigest() != manifest['referenceSha256']:
        raise ValueError('Probe reference differs from its manifest')
    rate, reference = read_wav(reference_path)
    capture_rate, captured = read_wav(capture_path)
    if capture_rate != rate:
        raise ValueError('Reference/capture rates must match; do not silently resample measurements')
    # Retain individual channels: mono summation could cancel antiphase routes.
    reference_channel = reference[:, int(np.argmax(np.std(reference, axis=0)))]
    capture_channel = captured[:, int(np.argmax(np.std(captured, axis=0)))]
    anchors = []
    for part in manifest['parts']:
        center = part['startFrame'] + part['decodedFrames'] // 2
        length = rate // 5
        offset = center - length // 2
        observed, correlation = locate(capture_channel, reference_channel[offset:offset + length])
        anchors.append({'referenceFrame': offset, 'captureFrame': observed, 'correlation': correlation})
    boundaries = []
    for a, b in zip(anchors, anchors[1:]):
        difference = (b['captureFrame'] - a['captureFrame']) - (b['referenceFrame'] - a['referenceFrame'])
        boundaries.append({'additionalFrames': difference, 'additionalMs': difference * 1000 / rate})
    return {'platform': platform, 'stage': stage, 'sampleRate': rate, 'anchors': anchors,
            'boundaries': boundaries,
            'limitations': 'Landmark displacement includes route clock drift/resampling effects. Compare an unsplit control capture on the same route. Not Dart-event timing.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['generate', 'measure'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--sample-rate', type=int, choices=[44100, 48000], default=44100)
    parser.add_argument('--platform', choices=['ios', 'android', 'synthetic'])
    parser.add_argument('--stage', choices=['baseline', 'candidate', 'control'])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.directory, args.sample_rate)
    else:
        if not all([args.capture, args.platform, args.stage, args.output]):
            parser.error('measure needs capture, platform, stage and output')
        protected = [args.capture.resolve(), *(p.resolve() for p in args.directory.iterdir())]
        if args.output.resolve() in protected:
            parser.error('measurement output must not overwrite source or capture files')
        result = measure(args.directory, args.capture, args.platform, args.stage)
        args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
