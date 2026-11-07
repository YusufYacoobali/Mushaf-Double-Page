"""Audit supplied intervals against the exact MP3 with unprompted Arabic ASR.

Requires sherpa-onnx, soundfile and FFmpeg; model/audio remain outside the repo.
This never generates or adjusts timestamps. Review the emitted transcripts;
content similarity is evidence, not a human or sample-accurate alignment claim.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import unicodedata


def normalized(text):
    text = unicodedata.normalize('NFKD', text).replace('ٱ', 'ا')
    text = ''.join(c for c in text if not unicodedata.combining(c))
    return re.sub('[^ء-ي]', '', text).translate(str.maketrans('ىؤئ', 'يوي'))


def audit(args):
    import sherpa_onnx
    import soundfile as sf
    audio = Path(args.audio)
    identity = json.loads(Path(args.metadata).read_text())['data']['files']['original']
    digest = hashlib.sha256(audio.read_bytes()).hexdigest()
    assert digest == identity['sha256'] and audio.stat().st_size == identity['bytes']
    data = json.loads(Path(args.timings).read_text())
    rows = data['data']['ayahs']
    assert data['data']['complete'] and [r[0] for r in rows] == list(range(31))
    assert all(0 <= a[1] < a[2] <= b[1] for a, b in zip(rows, rows[1:]))
    db = sqlite3.connect(args.text_database)
    expected = dict(db.execute('select ayah,text from verses where surah=67'))
    expected[0] = 'بسم الله الرحمن الرحيم'
    expected[-1] = 'أعوذ بالله من الشيطان الرجيم'
    model = Path(args.model)
    model_files = [model / ('small-' + n) for n in
                   ['encoder.int8.onnx', 'decoder.int8.onnx', 'tokens.txt']]
    recognizer = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(model_files[0]), decoder=str(model_files[1]),
        tokens=str(model_files[2]), language='ar', num_threads=4,
        task='transcribe', decoding_method='greedy_search')
    report = {'recordingSha256': digest, 'bytes': audio.stat().st_size,
              'method': 'Unprompted sherpa-onnx Whisper small int8, Arabic, exact supplied interval cuts',
              'sherpaOnnxVersion': sherpa_onnx.__version__,
              'modelUrl': 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2',
              'modelSha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in model_files},
              'catalogueVersion': data['meta']['catalogue_version'],
              'timestampSource': args.timings, 'clips': [], 'boundaries': [],
              'limitations': ['Automated content audit; no human listening or independent speaker identification.',
                             'ASR can omit/hallucinate words; similarity is not an independent timestamp measurement.',
                             'No word timestamps were produced by this model. No supplied timestamps are modified.',
                             'Device highlighting and native seeking must still be compared on iPhone and Android.']}
    if args.boundary_only:
        previous_report = json.loads(Path(args.output).read_text())
        assert previous_report['recordingSha256'] == digest
        assert previous_report['modelSha256'] == report['modelSha256']
        assert previous_report['catalogueVersion'] == report['catalogueVersion']
        assert [[c['ayah'], c['startMs'], c['endMs']] for c in previous_report['clips'] if c['ayah'] >= 0] == rows
        report['clips'] = previous_report['clips']
    with tempfile.TemporaryDirectory(prefix='mp3quran-audit-') as directory:
        wav = str(Path(directory) / '067.wav')
        subprocess.run(['ffmpeg', '-v', 'error', '-xerror', '-i', str(audio),
                        '-map', '0:a:0', '-ar', '16000', '-ac', '1', wav], check=True)
        samples, sr = sf.read(wav, dtype='float32')
        report['decodedDurationMs'] = len(samples) * 1000 / sr
        assert rows[-1][2] <= report['decodedDurationMs']
        def transcribe(start, end):
            stream = recognizer.create_stream()
            stream.accept_waveform(sr, samples[round(start * sr / 1000):round(end * sr / 1000)])
            recognizer.decode_stream(stream)
            return stream.result.text
        for ayah, start, end in ([] if args.boundary_only else [[-1, 0, rows[0][1]], *rows]):
            text = transcribe(start, end)
            similarity = {a: difflib.SequenceMatcher(None, normalized(t), normalized(text), autojunk=False).ratio()
                          for a, t in expected.items()}
            best = max(similarity, key=similarity.get)
            row = {'ayah': ayah, 'startMs': start, 'endMs': end,
                   'expected': expected[ayah], 'transcript': text,
                   'similarity': round(similarity[ayah], 4), 'nearestAyah': best}
            report['clips'].append(row)
            Path(args.output).write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
            print(f'ayah {ayah}: similarity={row["similarity"]}, nearest={best}: {text}', flush=True)
        for left in [0, 1, 14, 15, 29]:
            previous, following = rows[left], rows[left + 1]
            start, end = max(previous[1], previous[2] - 8000), following[2]
            assert end - start <= 30000
            text = transcribe(start, end)
            row = {'betweenAyahs': [left, left + 1], 'startMs': start, 'endMs': end,
                   'suppliedPreviousEndMs': previous[2], 'suppliedNextStartMs': following[1],
                   'expectedPrevious': expected[left], 'expectedNext': expected[left + 1], 'transcript': text}
            report['boundaries'].append(row)
            Path(args.output).write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
            print(f'boundary {left}/{left+1}: {text}', flush=True)
    report['allIntervalsIdentifyExpectedAyah'] = all(c['ayah'] == c['nearestAyah'] for c in report['clips'])
    Path(args.output).write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--boundary-only', action='store_true', help='Reuse interval transcripts in the existing output; recheck all boundary clips')
    parser.add_argument('--audio', required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--metadata', default='docs/mp3quran-alafasy-evidence/v4-surah.json')
    parser.add_argument('--timings', default='docs/mp3quran-alafasy-evidence/v4-timings.json')
    parser.add_argument('--text-database', default='assets/arabic-text/uthmani.db')
    parser.add_argument('--output', required=True)
    audit(parser.parse_args())
