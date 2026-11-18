#!/usr/bin/env python3
"""Gate manual simulator checks on the existing fast CI, without rerunning it.

A workflow may be dispatched immediately after a push. Wait briefly for the
already-triggered Linux analysis/tests job rather than failing the manual
request or starting a second expensive simulator build.
"""
import json
import os
import time
import urllib.request

SHA = os.environ['GITHUB_SHA']
DEADLINE = time.monotonic() + 210
POLL_SECONDS = 12


def get(path):
    request = urllib.request.Request(
        'https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY'] + path,
        headers={
            'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
            'Accept': 'application/vnd.github+json',
        },
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        return json.load(response)


while True:
    runs = get(
        '/actions/workflows/flutter-release-checks.yml/runs?head_sha='
        + SHA + '&per_page=10'
    )['workflow_runs']
    active = not runs
    passed = None
    for run in runs:
        if run['status'] != 'completed':
            active = True
            continue
        jobs = get(f'/actions/runs/{run["id"]}/jobs?per_page=100')['jobs']
        match = next((job for job in jobs if job['name'] == 'analyze-and-test'), None)
        if match is None or match['status'] != 'completed':
            active = True
        elif match['conclusion'] == 'success':
            passed = run['html_url']
            break

    if passed is not None:
        print('Fast analysis/tests passed on the exact requested commit:', passed)
        break
    if not active:
        raise SystemExit(
            'Fast checks completed without a successful analyze-and-test job '
            'for ' + SHA + '. No simulator was started.'
        )
    if time.monotonic() >= DEADLINE:
        raise SystemExit(
            'Timed out waiting for the existing fast checks on ' + SHA
            + '. Check Flutter release checks, then rerun this targeted QA. '
            'No simulator was started.'
        )
    print('Fast checks for ' + SHA[:12]
          + ' are still running; reusing that run instead of starting another.', flush=True)
    time.sleep(min(POLL_SECONDS, max(0, DEADLINE - time.monotonic())))
