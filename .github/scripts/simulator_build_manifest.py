#!/usr/bin/env python3
"""Identify compatible simulator builds independently of the QA commit/run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

APP_PATHS = ['lib', 'ios', 'assets', 'pubspec.yaml', 'pubspec.lock']


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def application_hash(ref='HEAD'):
    tree = subprocess.check_output(['git', 'ls-tree', '-r', '-z', ref, '--', *APP_PATHS])
    return hashlib.sha256(tree).hexdigest()


def validate_manifest(saved, expected, archive_hash):
    for key in ['schema', 'application_hash', 'configuration', 'fingerprint']:
        if saved.get(key) != expected[key]:
            raise ValueError(f'Incompatible simulator build: {key} differs')
    if not saved.get('build_completed') or saved.get('archive_sha256') != archive_hash:
        raise ValueError('Simulator archive is incomplete or its SHA-256 does not match')


def check_producer(saved):
    # A cancelled visual run can contain a successful build job. Check that job
    # explicitly; an artifact's presence or whole-workflow colour is insufficient.
    repo = os.environ['GITHUB_REPOSITORY']
    url = f'https://api.github.com/repos/{repo}/actions/runs/{saved["producer_run_id"]}/jobs?filter=all&per_page=100'
    request = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'Accept': 'application/vnd.github+json',
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        jobs = json.load(response)['jobs']
    if not any(job['name'].endswith(saved['producer_job_name']) and
               job['conclusion'] == 'success' for job in jobs):
        raise ValueError('Cached artifact producer build job was not successful; use policy=rebuild')


def write_output(name, value):
    if 'GITHUB_OUTPUT' in os.environ:
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write(f'{name}={value}\n')
    print(f'{name}={value}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['source', 'identify', 'reuse', 'record'])
    parser.add_argument('--directory', type=Path, default=Path('.ci/simulator-build'))
    parser.add_argument('--expected', type=Path, default=Path('.ci/expected-build.json'))
    parser.add_argument('--policy', choices=['auto', 'reuse-only', 'rebuild'], default='auto')
    parser.add_argument('--role', default='reader')
    args = parser.parse_args()
    if args.action == 'source':
        write_output('application_hash', application_hash())
        write_output('source_commit', subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip())
        return
    if args.action == 'identify':
        configuration = {
            'flutter': '3.38.1', 'mode': 'debug', 'architecture': 'arm64',
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'sdk': subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip(),
            'deployment_target': '15.0',
            'dart_defines': {'READER_LAYOUT_QA': 'true'},
            'builder_sha256': sha256(Path(__file__).with_name('build_ios_simulator.sh')),
        }
        expected = {'schema': 1, 'application_hash': application_hash(), 'configuration': configuration}
        expected['fingerprint'] = hashlib.sha256(json.dumps(expected, sort_keys=True).encode()).hexdigest()
        args.expected.parent.mkdir(parents=True, exist_ok=True)
        args.expected.write_text(json.dumps(expected, indent=2) + '\n')
        write_output('fingerprint', expected['fingerprint'])
        write_output('artifact_name', 'reader-ios-' + expected['fingerprint'])
        return
    expected = json.loads(args.expected.read_text())
    archive = args.directory / 'ios-simulator-runner.tgz'
    metadata = args.directory / 'build.json'
    if args.action == 'reuse':
        if args.policy == 'rebuild':
            write_output('reuse', 'false')
            return
        if not metadata.exists():
            if args.policy == 'reuse-only':
                raise ValueError('No compatible build cache is available. Use auto or rebuild for this application revision.')
            print('No compatible simulator artifact exists; one build is required.')
            write_output('reuse', 'false')
            return
        saved = json.loads(metadata.read_text())
        validate_manifest(saved, expected, sha256(archive))
        check_producer(saved)
        write_output('reuse', 'true')
        write_output('built_from_commit', saved['source_commit'])
        return
    saved = expected | {
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'archive_sha256': sha256(archive), 'build_completed': True,
        'producer_run_id': os.environ['GITHUB_RUN_ID'],
        'producer_job_name': f'Build {args.role} simulator ({expected["application_hash"]})',
    }
    metadata.write_text(json.dumps(saved, indent=2) + '\n')


if __name__ == '__main__':
    main()
