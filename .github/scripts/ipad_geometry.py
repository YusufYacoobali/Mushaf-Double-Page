#!/usr/bin/env python3
"""Validate actual v5 paper geometry, then compare v6 without masking pages."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageOps, ImageChops


def image(path):
    return ImageOps.exif_transpose(Image.open(path)).convert('RGB')


def paper_bounds(im, landscape, scale):
    # Baseline 80% portrait is separated from the collapsed tab by black space.
    # At 70% landscape the complete papers lie outside the side-dock envelope.
    w, h = im.size
    pixels = im.load()
    if not landscape:
        rows = [y for y in range(h) if sum(max(pixels[x, y]) > 80
                 for x in range(0, w, 4)) > w / 4 * .7]
        assert rows, 'No actual Quran paper rendered in portrait'
        return [[0, rows[0], w, rows[-1] + 1]]
    columns = [x for x in range(w - round(140 * scale)) if
               sum(max(pixels[x, y]) > 80 for y in range(0, h, 4)) > h / 4 * .1]
    # Ornamental Quran page borders contain 1-3 pixel dark vertical strips.
    # Counting every bright-column run as a separate page is wrong on the
    # higher-resolution 13-inch iPad (six runs across TWO visible pages).
    # The actual book spread is two equal halves separated at the centre.
    # Independently measure each half; don't assume the expected boundaries.
    centre = w // 2
    halves = [[x for x in columns if x < centre],
              [x for x in columns if x > centre]]
    assert all(len(xs) > 80 for xs in halves), (
        f'Expected two distinct Quran papers split at {centre}; '
        f'observed bright columns per half: {[len(xs) for xs in halves]}')
    assert centre not in columns, 'Expected a real centre seam between pages'
    result = []
    for xs in halves:
        rows = [y for y in range(h) if any(max(pixels[x, y]) > 80
                 for x in range(xs[0], xs[-1] + 1, 4))]
        assert rows, 'Quran page has no visible paper rows'
        result.append([xs[0], rows[0], xs[-1] + 1, rows[-1] + 1])
    return result


def inspect(folder, device):
    result = {}
    for mode, landscape in [('portrait-after-18s', False), ('landscape', True)]:
        path = folder / f'ipad-{device}-{mode}.png'
        im = image(path)
        dimensions = json.loads(path.with_suffix('.png.json').read_text())
        scale = im.width / dimensions['width']
        assert abs(im.height / dimensions['height'] - scale) < .001, 'incorrect rotation'
        boxes = paper_bounds(im, landscape, scale)
        if landscape:
            width = (dimensions['width'] - 1) / 2 * .7 * scale
            height = width / (721 / 1058)
            left = (im.width - (2 * width + scale)) / 2
            expected = [[left, 0, left + width, height],
                        [left + width + scale, 0, left + 2 * width + scale, height]]
        else:
            expected = [[0, im.height * .1, im.width, im.height * .9]]
        assert all(abs(a-b) <= 3 for x,y in zip(boxes, expected) for a,b in zip(x,y)), \
            f'{mode}: paper bounds changed from v5: {boxes}, expected {expected}'
        result[mode] = {'pixels': im.size, 'scale': scale, 'paper_bounds': boxes,
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return result


def compare(current, reference, device):
    a, b = inspect(current, device), inspect(reference, device)
    for mode in a:
        assert a[mode]['pixels'] == b[mode]['pixels']
        assert all(abs(x-y) <= 1 for first,second in zip(a[mode]['paper_bounds'],b[mode]['paper_bounds'])
                   for x,y in zip(first,second)), f'{mode}: v6 page rectangles differ from v5'
        left, right = image(current / f'ipad-{device}-{mode}.png'), image(reference / f'ipad-{device}-{mode}.png')
        diff = ImageChops.difference(left, right)
        if mode == 'landscape':
            # This envelope contains only the intentionally repositioned dock;
            # paper geometry is checked above across each complete page.
            diff = diff.crop((0, 0, left.width - round(140 * a[mode]['scale']), left.height))
        a[mode]['pixel_difference_outside_navigation'] = diff.getbbox()
        assert diff.getbbox() is None, f'{mode}: pixels changed outside the approved navigation area'
    return {'verified': True, 'device': device, 'geometry': a}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--device', required=True)
    parser.add_argument('--reference', type=Path)
    args = parser.parse_args()
    result = compare(args.folder, args.reference, args.device) if args.reference else inspect(args.folder,args.device)
    (args.folder / 'geometry-verification.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
