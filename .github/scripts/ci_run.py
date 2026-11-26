#!/usr/bin/env python3
"""Bound one simulator operation and retain its output and exact failure stage."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--operation', required=True)
    parser.add_argument('--timeout', required=True, type=float)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--value-file', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    args.output.mkdir(parents=True, exist_ok=True)
    stamp = str(time.time_ns())
    log = args.output / f'{args.operation}-{stamp}.log'
    print(f'BEGIN {args.operation} (timeout {args.timeout:g}s): {command[0]}', flush=True)
    started = time.monotonic()
    timed_out = False
    with log.open('wb') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = 124
    result = {'operation': args.operation, 'command': command, 'exit_code': code,
              'timed_out': timed_out, 'seconds': round(time.monotonic() - started, 2),
              'log': str(log), 'passed': code == 0}
    with (args.output / 'operations.jsonl').open('a') as stream:
        stream.write(json.dumps(result) + '\n')
    print(log.read_text(errors='replace')[-16000:], flush=True)
    if args.value_file is not None and code == 0:
        args.value_file.write_bytes(log.read_bytes())
    print(json.dumps(result), flush=True)
    if code:
        (args.output / 'failure.json').write_text(json.dumps(result, indent=2) + '\n')
        print(f'::error title={args.operation} failed::{args.operation}: '
              f'{"timed out" if timed_out else f"exit {code}"}; see {log}')
    return code


if __name__ == '__main__':
    sys.exit(main())
