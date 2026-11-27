#!/usr/bin/env python3
"""Audit selected original EveryAyah MP3s using the pinned maqra mirror."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

from audio_gap_diagnostic import analyze, boundary

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'cf6f004bfb5fa24017db479d39676a4a908f518a'
RELEASES = 'https://github.com/Abdalla-Eldoumani/maqra/releases/download'


def audit_reciter(reciter, folder, manifests, cache):
    catalog = json.loads((manifests / 'reciters.json').read_text())
    slug, = (r['slug'] for r in catalog['reciters'] if r['source_folder'] == folder)
    manifest = json.loads((manifests / 'audio' / f'{slug}.json').read_text())
    expected = {r[0]: dict(zip(manifest['columns'], r)) for r in manifest['files']}
    for entry in manifest.get('extra', []):
        name, size, _, digest = entry[:4]
        expected[Path(name).name] = {'name': Path(name).name, 'bytes': size, 'sha256': digest,
                                     'md5_state': 'mirror-extra'}
    passages = {112: range(1, 5), 2: [255, 282]}
    if reciter == 'abdullah_juhany':
        passages.update({113: range(1, 6), 55: range(1, 11), 2: [253, 254, 255, 282, 283]})
    rows = {}
    joins = []
    directory = cache / reciter
    directory.mkdir(parents=True, exist_ok=True)

    def measure(name, data):
        ref = expected[name]
        if hashlib.sha256(data).hexdigest() != ref['sha256'] or len(data) != ref['bytes']:
            raise ValueError(f'{reciter}/{name} differs from pinned manifest')
        path = directory / name
        path.write_bytes(data)
        row = analyze(path, {'id': name, 'sha256': ref['sha256']})
        rows[name] = {**row, 'providerMd5State': ref['md5_state']}
        return row

    intro = ROOT / 'test' / 'fixtures' / 'bismillah' / f'{reciter}.mp3'
    intro_row = None
    if intro.exists():
        digest = hashlib.sha256(intro.read_bytes()).hexdigest()
        match = next((r for r in expected.values() if r['sha256'] == digest), None)
        if not match:
            raise ValueError(f'{reciter} Bismillah is absent from the pinned manifest')
        intro_row = measure(match['name'], intro.read_bytes())

    for surah, ayahs in passages.items():
        names = [f'{surah:03}{a:03}.mp3' for a in ayahs]
        if all((directory / n).exists() for n in names):
            data = {n: (directory / n).read_bytes() for n in names}
        else:
            with tempfile.NamedTemporaryFile(suffix='.zip') as archive:
                url = f'{RELEASES}/{slug}/{surah:03}.zip'
                subprocess.run(['curl', '-fsSL', '--retry', '2', '--max-time', '180',
                                '-o', archive.name, url], check=True)
                with zipfile.ZipFile(archive.name) as z:
                    data = {n: z.read(n) for n in names}
        previous = None
        for ayah, name in zip(ayahs, names):
            row = measure(name, data[name])
            if previous and ayah == previous[0] + 1:
                joins.append(boundary(previous[1], row))
            if surah == 112 and ayah == 1 and intro_row:
                joins.append(boundary(intro_row, row))
            previous = ayah, row
    return {'reciter': reciter, 'folder': folder, 'slug': slug, 'sources': list(rows.values()),
            'joins': joins, 'nativeAddedFrames': None, 'nativeSampleIntegrity': None,
            'underruns': None, 'fallback': None, 'nativeAcceptance': 'unmeasured'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mirror', type=Path, help=f'Clone maqra at {REVISION}')
    parser.add_argument('cache', type=Path, help='Disposable directory for original MP3s')
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    rev = subprocess.check_output(['git', '-C', args.mirror, 'rev-parse', 'HEAD'], text=True).strip()
    if rev != REVISION:
        parser.error(f'Expected mirror revision {REVISION}')
    reciters = re.findall(r"id: '(\w+)',\s*name: '[^\n]+\n\s*folder: '([^']+)'",
                          (ROOT / 'lib/models/quran_audio.dart').read_text())
    assert len(reciters) == 22
    reciters.sort(key=lambda pair: pair[0] != 'abdullah_juhany')
    def audit(pair):
        result = audit_reciter(*pair, args.mirror / 'manifests', args.cache)
        print(pair[0], len(result['sources']), flush=True)
        return result
    results = [audit(reciters[0])]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results.extend(pool.map(audit, reciters[1:]))
    report = {'mirrorRevision': rev, 'ffmpeg': subprocess.check_output(
        ['ffmpeg', '-version'], text=True).splitlines()[0], 'reciters': results}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
