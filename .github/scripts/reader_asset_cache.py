#!/usr/bin/env python3
"""Reuse checksum-verified, real downloaded pages in disposable simulators."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import time

EDITION = 'indopak_tajweed'
VERSION_KEY = f'flutter.{EDITION}_version3'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['import', 'export', 'wait'])
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--prefs', type=Path)
    parser.add_argument('--cache', type=Path)
    args = parser.parse_args()
    pages = args.data / 'Documents' / EDITION
    if args.action == 'wait':
        # ci_run.py supplies the wall-clock download timeout and stage report.
        while True:
            count = len(list(pages.glob('*.webp')))
            print(f'Actual Quran pages: {count}/851', flush=True)
            if count == 851 and (pages / '1.webp').stat().st_size and (pages / '851.webp').stat().st_size:
                return
            time.sleep(2)
    manifest_path = args.cache / 'pages.json'
    if args.action == 'import':
        if not manifest_path.exists():
            print('No saved Quran pages; the real app will download them.')
            return
        manifest = json.loads(manifest_path.read_text())
        assert manifest['edition'] == EDITION and len(manifest['files']) == 851
        for name, checksum in manifest['files'].items():
            assert Path(name).name == name and digest(args.cache / EDITION / name) == checksum
        shutil.copytree(args.cache / EDITION, pages, dirs_exist_ok=True)
        with args.prefs.open('rb') as stream:
            preferences = plistlib.load(stream)
        preferences[VERSION_KEY] = manifest['version']
        with args.prefs.open('wb') as stream:
            plistlib.dump(preferences, stream, fmt=plistlib.FMT_BINARY)
        print('Restored all 851 real, checksum-verified pages and their original data-version marker.')
        return
    with args.prefs.open('rb') as stream:
        version = plistlib.load(stream).get(VERSION_KEY)
    if not isinstance(version, int) or version <= 0:
        print('Asset cache not saved: app data-version marker is not yet persisted.')
        return
    files = {f'{index}.webp': digest(pages / f'{index}.webp') for index in range(1, 852)}
    args.cache.mkdir(parents=True, exist_ok=True)
    shutil.copytree(pages, args.cache / EDITION, dirs_exist_ok=True)
    manifest_path.write_text(json.dumps({'edition': EDITION, 'version': version,
                                         'files': files}, sort_keys=True) + '\n')
    print('Saved the existing real Quran pages; application/repository assets were not modified.')


if __name__ == '__main__':
    main()
