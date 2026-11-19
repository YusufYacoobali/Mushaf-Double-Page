#!/usr/bin/env python3
"""Accept visual QA only when genuine, independently checked screenshots exist.

Runs on an ordinary Ubuntu runner AFTER the simulator jobs. A green Flutter
build, CoreSimulator boot, XCTest runner or isolated 'PASS' line is insufficient.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load(path):
    require(path.is_file(), f'Missing evidence: {path}')
    return json.loads(path.read_text())


def png(path, landscape=None):
    require(path.is_file() and path.stat().st_size > 18000,
            f'Missing/too-small real PNG: {path}')
    data = path.read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n', f'Not a PNG: {path}')
    width, height = struct.unpack('>II', data[16:24])
    require(width >= 320 and height >= 320, f'Unexpected screenshot size: {path}: {width}x{height}')
    if landscape is not None:
        # XCUIScreen PNGs are physically encoded in the natural device
        # orientation and carry EXIF orientation=8 in landscape. Check the
        # displayed pixels after honouring EXIF, not the raw IHDR axes.
        from PIL import Image, ImageOps
        with Image.open(path) as original:
            displayed = ImageOps.exif_transpose(original)
            displayed.load()
            visual_width, visual_height = displayed.size
        require((visual_width > visual_height) == landscape,
                f'Wrong displayed screenshot orientation: {path}: '
                f'raw={width}x{height}, visual={visual_width}x{visual_height}')
    return hashlib.sha256(data).hexdigest()


def pick_dir(root, name, sentinel):
    folders = [p for p in root.rglob(name) if p.is_dir() and (p / sentinel).exists()]
    if root.name == name and (root / sentinel).exists():
        folders.append(root)
    folders = list(dict.fromkeys(folders))
    require(len(folders) == 1, f'Expected one {name} in {root}, got {folders}')
    return folders[0]


def verify_fitted_image(folder, name, expected_zoom, expected_mode):
    image = folder / (name + '.png')
    png(image)
    result = load(folder / (name + '.verification.json'))
    geometry = load(folder / (name + '.layout.json'))
    require(result.get('verified') is True, f'Fitted-page verification missing: {name}')
    require(abs(result['zoom'] * 100 - expected_zoom) < .1, f'Wrong rendered zoom: {name}')
    require(geometry.get('mode') == expected_mode, f'Wrong display posture: {name}')
    require(geometry.get('fit') is True, f'Foldable not proportionally fitted: {name}')
    require(len(geometry.get('pages', {})) == (1 if expected_mode == 'single' else 2),
            f'Incorrect page count: {name}')
    return hashlib.sha256(image.read_bytes()).hexdigest()


def verify_duo(root):
    folder = root
    require((folder / 'case-results.txt').exists(), 'Duo produced no completed posture cases')
    cases = (folder / 'case-results.txt').read_text()
    result = {'device': 'duo', 'postures': {}, 'verified': False}
    for label, minimum, mode in (
        ('duo-folded', 70, 'single'),
        ('duo-unfolded-portrait', 70, 'single'),
        ('duo-unfolded-wide', 60, 'spread'),
        ('duo-half-open-book', 60, 'dualScreenBook'),
    ):
        require(f'PASS {label} all' in cases, f'Missing actual completed posture: {label}')
        low = verify_fitted_image(folder, f'{label}-min-{minimum}', minimum, mode)
        high = verify_fitted_image(folder, f'{label}-max-100', 100, mode)
        require(low != high, f'Identical min/max images: {label}')
        shots = []
        for value in range(minimum, 101, 5):
            shots.append(verify_fitted_image(folder, f'{label}-zoom-{value}', value, mode))
        require(len(set(shots)) == len(shots), f'Zoom screenshots not distinct at every 5%: {label}')
        nav_hashes = []
        for state in ('closed', 'open'):
            name = f'{label}-navigation-{state}'
            shot = folder / (name + '.png')
            nav_hashes.append(png(shot))
            require(load(folder / (name + '.verification.json')).get('verified') is True,
                    f'Navigation screenshot not verified: {name}')
        require(nav_hashes[0] != nav_hashes[1],
                f'Duo {label} navigation did not change screenshot')
        result['postures'][label] = {'min': minimum, 'max': 100,
                                      'zoom_captures': len(shots), 'navigation': 'verified'}
    verify_fitted_image(folder, 'duo-half-open-book-after-swipe', 100, 'dualScreenBook')
    swipe = load(folder / 'duo-book-swipe-result.json')
    require(swipe.get('observedFocusedPage') == swipe.get('expectedFocusedPage') == 6,
            f'RTL book page turn did not advance as expected: {swipe}')
    result['rtl_swipe'] = True
    result['verified'] = True
    return result


def verify_ipad(root, device):
    folder = pick_dir(root, f'{device}-v6', 'cases.json')
    require(all(load(folder / 'cases.json').get(name, {}).get('passed') is True
                for name in ('rotation', 'navigation', 'zoom')),
            f'iPad {device} XCTest cases did not ALL pass')
    geometry = load(folder / 'geometry-verification.json')
    require(geometry.get('verified') is True and geometry.get('device') == device,
            f'iPad {device} v5/v6 pixel+paper geometry comparison did not pass')
    png(folder / f'ipad-{device}-portrait-after-18s.png', landscape=False)
    png(folder / f'ipad-{device}-landscape.png', landscape=True)
    closed = png(folder / f'ipad-{device}-navigation-closed.png', landscape=True)
    opened = png(folder / f'ipad-{device}-navigation-open.png', landscape=True)
    require(closed != opened,
            f'iPad {device} navigation tab did not reveal controls: screenshots identical')
    for orientation, minimum in (('portrait', 70), ('landscape', 60)):
        hashes = []
        for value in range(minimum, 101, 5):
            shot = folder / f'ipad-{device}-{orientation}-{value}.png'
            hashes.append(png(shot, landscape=(orientation == 'landscape')))
            require((folder / (shot.name + '.json')).is_file(),
                    f'XCTest reader size metadata missing: {shot}')
        require(len(set(hashes)) == len(hashes),
                f'iPad {device} {orientation}: multiple zoom screenshots identical')
    return {'device': device, 'verified': True, 'v5_pixel_comparison': True,
            'orientations': ['portrait', 'landscape'],
            'zoom_steps': {'portrait': 7, 'landscape': 9}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--duo', type=Path, required=True)
    parser.add_argument('--mini', type=Path, required=True)
    parser.add_argument('--pro13', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = {'verified': True, 'source': 'real simulator screenshots',
              'duo': verify_duo(args.duo),
              'ipad_mini': verify_ipad(args.mini, 'mini'),
              'ipad_pro13': verify_ipad(args.pro13, 'pro13'),
              'excluded': ['iPad Pro 11-inch']}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
