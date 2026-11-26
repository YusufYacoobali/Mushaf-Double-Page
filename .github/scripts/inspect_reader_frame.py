#!/usr/bin/env python3
"""Inspect copies of real PNG pixels with CPU OCR; preserve the original file."""
import csv
import io
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageOps


def words(image, numeric=False):
    stream = io.BytesIO()
    image.save(stream, format='PNG')
    command = ['tesseract', 'stdin', 'stdout', '-l', 'eng', '--psm', '11']
    if numeric:
        command += ['-c', 'tessedit_char_whitelist=0123456789%']
    result = subprocess.run(command + ['tsv'], input=stream.getvalue(), capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return [row for row in csv.DictReader(io.StringIO(result.stdout.decode()), delimiter='\t', quoting=csv.QUOTE_NONE)
            if row['text'].strip()]


def inspect_frame(path, dock='side', scale=3):
    image = Image.open(path).convert('RGB')
    width, height = image.size
    state = {'width': width, 'height': height}
    # System permission alerts are centred. Only an observed "Don't Allow"
    # button is touched; page text and application state are never changed.
    box = (round(width * .05), round(height * .25), round(width * .95), round(height * .78))
    rows = words(image.crop(box))
    for index, row in enumerate(rows):
        normalized = re.sub(r'\W', '', row['text']).lower()
        group = [row]
        if normalized == 'dont' and index + 1 < len(rows):
            following = rows[index + 1]
            same_line = abs((int(row['top']) + int(row['height']) / 2) -
                            (int(following['top']) + int(following['height']) / 2)) < max(int(row['height']), int(following['height']))
            if same_line and following['text'].lower() == 'allow':
                normalized = 'dontallow'
                group.append(following)
        if normalized == 'dontallow':
            left = min(int(item['left']) for item in group)
            top = min(int(item['top']) for item in group)
            right = max(int(item['left']) + int(item['width']) for item in group)
            bottom = max(int(item['top']) + int(item['height']) for item in group)
            state['denyNotification'] = {'x': (box[0] + (left + right) / 2) / width,
                                         'y': (box[1] + (top + bottom) / 2) / height}
            break
    if dock == 'bottom':
        box = (0, max(0, height - round(100 * scale)), min(width, round(150 * scale)), height)
    else:
        box = (max(0, width - round(64 * scale)), 0, width, height)
    crop = ImageOps.autocontrast(image.crop(box).convert('L'))
    enlarged = crop.resize((crop.width * 3, crop.height * 3), Image.Resampling.LANCZOS)
    candidates = [row for row in words(enlarged, numeric=True)
                  if re.fullmatch(r'(60|65|70|75|80|85|90|95|100)%', row['text']) and float(row['conf']) >= 35]
    if candidates:
        row = max(candidates, key=lambda item: float(item['conf']))
        state['zoom'] = row['text']
        state['zoomBounds'] = {'x': (box[0] + (int(row['left']) + int(row['width']) / 2) / 3) / width,
                               'y': (box[1] + (int(row['top']) + int(row['height']) / 2) / 3) / height}
    return state


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('png', type=Path)
    parser.add_argument('--dock', choices=['bottom', 'side'], default='side')
    parser.add_argument('--scale', type=float, default=3)
    args = parser.parse_args()
    print(json.dumps(inspect_frame(args.png, args.dock, args.scale), sort_keys=True))
