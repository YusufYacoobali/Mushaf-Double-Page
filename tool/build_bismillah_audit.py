"""Build hash-bound policies from the recorded automated content review.

This consumes actual Arabic ASR results, not filename assertions. It never labels
ASR output as human listening. Missing/ambiguous destinations remain unverified.
See docs/v5-validation.md for corpus, model provenance and limitations.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import unicodedata


def normalized(text):
    text = ''.join(c for c in unicodedata.normalize('NFKD', text) if not unicodedata.combining(c))
    return re.sub('[^ء-ي]', '', text.replace('ى', 'ي').replace('ٱ', 'ا'))


def build(args):
    tiny = json.loads(Path(args.tiny).read_text())
    small = {(r['folder'], r['file']): r for r in json.loads(Path(args.small).read_text())}
    base = {(r['folder'], r['file']): r for r in json.loads(Path(args.base).read_text())}
    registry = {r['source_folder']: r for r in json.loads(Path(args.registry).read_text())['reciters']}
    app = Path('lib/models/quran_audio.dart').read_text()
    reciters = {folder: reciter for reciter, folder in re.findall(
        r"id: '([^']+)'[\s\S]*?folder: '([^']+)'", app)}
    rows = {}
    for raw in tiny:
        row = dict(raw)
        row.pop('tokens', None)
        row.pop('timestamps', None)
        key = (row['folder'], row['file'])
        row['tinyTranscript'] = row.pop('transcript')
        row['smallTranscript'] = small.get(key, {}).get('smallTranscript')
        row['baseTranscript'] = base.get(key, {}).get('baseTranscript')
        manifest = json.loads((Path(args.manifests) / (row['slug'] + '.json')).read_text())
        listing = next((f for f in manifest['files'] + manifest['extra'] if Path(f[0]).name == row['file']), None)
        row['mirrorHashMatches'] = listing is not None and listing[3] == row['sha256']
        row['upstreamMd5State'] = listing[4] if listing and len(listing) > 4 else 'standalone-extra-manifest'
        row['reciterName'] = registry[row['folder']]['name']
        row['style'] = registry[row['folder']]['style']
        rows[key] = row
    phrase = normalized('بسم الله الرحمن الرحيم')
    expected = {2: {normalized('الم'), normalized('ألف لام ميم')},
                112: {normalized('قل هو الله أحد')}, 114: {normalized('قل أعوذ برب الناس')}}
    policies = {}
    for folder, reciter in reciters.items():
        result = {}
        for surah, endings in expected.items():
            opening = rows.get((folder, f'{surah:03}001.mp3'))
            if not opening or not opening['mirrorHashMatches'] or not opening['smallTranscript']:
                continue
            transcript = normalized(opening['smallTranscript'])
            if phrase in transcript and any(transcript.endswith(ending) for ending in endings):
                result[str(surah)] = {'kind': 'embeddedInOpeningAyah', 'openingSha256': opening['sha256'],
                    'evidence': 'Exact automated transcript contains Bismillah and the destination ayah; original file retained.'}
                continue
            if transcript not in endings:
                continue
            candidates = []
            for filename in ['bismillah.mp3', '001001.mp3', f'{surah:03}000.mp3']:
                row = rows.get((folder, filename))
                if not row or not row['mirrorHashMatches'] or normalized(row['smallTranscript'] or '') != phrase:
                    continue
                other = ' '.join([row.get('tinyTranscript') or '', row.get('baseTranscript') or ''])
                if 'شيطان' in normalized(other) or 'seek refuge' in other.lower():
                    continue
                candidates.append({'id': f'{reciter}/{filename}', 'url': f'https://everyayah.com/data/{folder}/{filename}',
                    'cacheFilename': filename, 'sha256': row['sha256'],
                    'verification': 'Arabic Whisper-small transcription matches only Bismillah; mirror SHA-256 checked. '
                        'Source folder identifies reciter/style. Automated content evidence, not human listening; '
                        'see docs/bismillah-content-audit.json.'})
            if candidates:
                result[str(surah)] = {'kind': 'separateVerifiedRecording', 'sources': candidates,
                    'openingSha256': opening['sha256'], 'evidence':
                    'Automated Arabic transcript matches the numbered opening alone, with no Bismillah; '
                    'added source transcript matches only Bismillah. Both files bound to audited SHA-256. '
                    'No human listening or independent voice identification claimed.'}
        if result:
            policies[reciter] = result
    evidence = {'date': '2026-11-06', 'scope': 'EveryAyah files 001000/001001, 002000/002001, 112000/112001, 114000/114001 where available, plus named bismillah.mp3 for Husary, Hani Rifai and Ghamdi',
        'method': 'Actual MP3 bytes decoded with ffmpeg and transcribed with sherpa-onnx multilingual Whisper tiny, base and small int8 (Arabic). '
            'No human listening. Policies require exact normalized small-model phrase and destination text; ambiguous clips remain unverified.',
        'mirror': 'https://github.com/Abdalla-Eldoumani/maqra',
        'mirrorRevision': args.mirror_revision,
        'models': {name: f'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-{name}.tar.bz2'
                   for name in ['tiny', 'base', 'small']},
        'clips': list(rows.values()), 'enabledPolicies': policies,
        'limitations': ['ASR can omit or hallucinate words, especially recitation and muqattaat.',
            'This is automated content review, not human listening or speaker identification.',
            'Only hash-bound enabled destinations are covered; other surahs need further review.']}
    Path(args.output).write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    Path(args.dart_output).write_text('// Generated from the content audit by tool/build_bismillah_audit.py.\n'
        '// Automatic transcription evidence; never a claim of human listening.\n'
        'const Map<String, dynamic> verifiedOpeningData = ' + json.dumps(policies, ensure_ascii=False, indent=2) + ';\n')
    print('Audited clips:', len(rows), 'reciters:', len(reciters))
    print('Enabled destinations:', sum(map(len, policies.values())), 'reciters:', len(policies))
    for reciter, data in policies.items():
        print(reciter, ', '.join(data))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['tiny', 'small', 'base', 'registry', 'manifests', 'mirror-revision', 'output', 'dart-output']:
        parser.add_argument('--' + name, required=True)
    build(parser.parse_args())
