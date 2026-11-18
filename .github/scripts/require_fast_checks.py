#!/usr/bin/env python3
"""Gate manual simulators on the existing fast check; do not repeat it."""
import json
import os
import urllib.request


def get(path):
    request = urllib.request.Request('https://api.github.com/repos/' +
        os.environ['GITHUB_REPOSITORY'] + path, headers={
            'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
            'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


runs = get('/actions/workflows/flutter-release-checks.yml/runs?head_sha=' +
           os.environ['GITHUB_SHA'] + '&per_page=10')['workflow_runs']
for run in runs:
    jobs = get(f'/actions/runs/{run["id"]}/jobs?per_page=100')['jobs']
    if any(j['name'] == 'analyze-and-test' and j['conclusion'] == 'success' for j in jobs):
        print('Fast analysis/tests passed:', run['html_url'])
        break
else:
    raise SystemExit('Fast checks have not passed for this revision. Let the push check finish, '
                     'or run Flutter release checks first; no simulator was started.')
