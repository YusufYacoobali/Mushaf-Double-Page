#!/usr/bin/env python3
"""Cross-check real rendered page rectangles with the captured PNG pixels."""
import argparse
from datetime import datetime
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps, ImageStat


def bounds(r):
    return r['left'], r['top'], r['left'] + r['width'], r['top'] + r['height']


def assert_capture_state(data, expected_zoom=None, expected_mode=None, after=None):
    """Reject cached preferences, stale files and incomplete rendered frames."""
    if expected_mode is not None:
        assert data['mode'] == expected_mode, 'wrong reading mode for requested posture'
    if expected_zoom is not None:
        assert math.isclose(data['zoom'] * 100, expected_zoom, abs_tol=.1), 'wrong actual rendered zoom'
    if after is not None:
        stamp = datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
        assert stamp.tzinfo is not None and stamp.timestamp() >= after, 'stale rendered geometry timestamp'
    assert data['mode'] in ('single', 'spread', 'dualScreenBook'), 'unknown reading mode'
    assert len(data['pages']) == (1 if data['mode'] == 'single' else 2), 'wrong rendered page count'
    assert data['fit'], 'foldable capture must use the fitted layout'
    assert data.get('safeRegions'), 'missing independent safe display regions'


def same_rect(actual, expected):
    return all(math.isclose(actual[key], expected[key], abs_tol=.5)
               for key in ('left', 'top', 'width', 'height'))


def fitted_regions(data, aspect):
    """Derive maximum fit from safe display panels, never dock-trimmed bounds."""
    safe = data['safeRegions']
    viewport = data['viewport']
    for region in safe:
        assert all(math.isfinite(value) for value in bounds(region)), 'invalid safe region'
        left, top, right, bottom = bounds(region)
        assert region['width'] > 0 and region['height'] > 0, 'empty safe region'
        assert left >= -.5 and top >= -.5 and right <= viewport['width'] + .5 and bottom <= viewport['height'] + .5, 'safe region outside viewport'
    largest = max(safe, key=lambda r: r['width'] * r['height'])
    row = sorted((r for r in safe if abs(r['top'] - largest['top']) < 1 and
                  abs(bounds(r)[3] - bounds(largest)[3]) < 1), key=lambda r: r['left'])
    candidates = [row[0], row[-1]] if len(row) >= 2 else [largest]
    if data['mode'] == 'single':
        reading = max(candidates, key=lambda r: r['width'] * r['height'])
        regions = [reading]
        maximum = min(reading['width'], reading['height'] * aspect)
    elif len(candidates) == 2:
        regions = candidates
        left = min(r['left'] for r in regions)
        top = min(r['top'] for r in regions)
        right = max(bounds(r)[2] for r in regions)
        bottom = max(bounds(r)[3] for r in regions)
        reading = {'left': left, 'top': top, 'width': right - left, 'height': bottom - top}
        maximum = min(min(r['width'], r['height'] * aspect) for r in regions)
    else:
        assert data['mode'] == 'spread', 'book mode requires separated safe panels'
        reading = largest
        half = (reading['width'] - 1) / 2
        regions = [dict(reading, width=half),
                   dict(reading, left=reading['left'] + half + 1, width=half)]
        maximum = min(half, reading['height'] * aspect)
    assert same_rect(data['readingBounds'], reading), 'reading bounds must use the full safe display, including behind navigation'
    assert len(data['regions']) == len(regions) and all(
        same_rect(actual, expected) for actual, expected in zip(data['regions'], regions)
    ), 'page regions were reduced from the safe display panels'
    return maximum, regions, reading


def verify(png, metadata, expected_zoom=None, expected_mode=None, after=None):
    image = ImageOps.exif_transpose(Image.open(png)).convert('RGB')
    data = json.loads(Path(metadata).read_text())
    assert_capture_state(data, expected_zoom, expected_mode, after)
    dpr = data['pixelRatio']
    assert image.size == (round(data['viewport']['width'] * dpr),
                          round(data['viewport']['height'] * dpr)), 'stale viewport geometry'
    pages = data['pages']
    aspect = 2096 / 3008 if data['edition'] == 'madani' else 721 / 1058
    maximum, region_list, _ = fitted_regions(data, aspect)
    for page, r in pages.items():
        assert math.isclose(r['width'] / r['height'], aspect, abs_tol=.001), 'page distorted'
        assert math.isclose(r['width'], maximum * data['zoom'], abs_tol=.5), 'not scaled from maximum fit'
        l, t, right, bottom = bounds(r)
        region = next((x for x in region_list if x['left'] - .5 <= l and
                       x['top'] - .5 <= t and x['left'] + x['width'] + .5 >= right and
                       x['top'] + x['height'] + .5 >= bottom), None)
        # Centred spreads fit within their virtual leaves; physical panels
        # remain separate even when their posture is flat rather than a book.
        assert region is not None and l >= region['left'] - .5 and t >= region['top'] - .5
        assert right <= region['left'] + region['width'] + .5
        assert bottom <= region['top'] + region['height'] + .5, 'page clipped'
        crop_box = tuple(round(v * dpr) for v in (l, t, right, bottom))
        crop = image.crop(crop_box)
        visible = Image.new('L', crop.size, 255)
        navigation = data.get('navigation')
        if navigation:
            nl, nt, nr, nb = bounds(navigation)
            # Floating controls may cover the fitted paper. Only their measured
            # current footprint (plus antialiasing pixels) is excluded.
            ImageDraw.Draw(visible).rectangle(
                (math.floor(nl * dpr) - crop_box[0] - 2,
                 math.floor(nt * dpr) - crop_box[1] - 2,
                 math.ceil(nr * dpr) - crop_box[0] + 2,
                 math.ceil(nb * dpr) - crop_box[1] + 2), fill=0)
        assert visible.getbbox() is not None, f'paper fully obscured: page {page}'
        assert sum(ImageStat.Stat(crop, visible).var) / 3 > 300, f'blank or unrendered paper: page {page}'
        # The real Quran image has a white outer paper border. Require actual
        # rendered content at all four edges; a blank PNG is not verification.
        checked_edges = 0
        for edge in [(0, 0, crop.width, 3), (0, crop.height - 3, crop.width, crop.height),
                     (0, 0, 3, crop.height), (crop.width - 3, 0, crop.width, crop.height)]:
            pixels = [p for p, mask in zip(crop.crop(edge).getdata(), visible.crop(edge).getdata()) if mask]
            if not pixels:
                continue
            checked_edges += 1
            assert sum(max(p) > 100 for p in pixels) / len(pixels) > .5, f'missing paper edge: page {page}'
        assert checked_edges, f'no visible paper edge: page {page}'
    if data['mode'] == 'dualScreenBook':
        ordered = sorted(pages.items(), key=lambda pair: pair[1]['left'])
        assert int(ordered[1][0]) == data['focusedPage'] and int(ordered[0][0]) == data['focusedPage'] + 1
        assert abs(ordered[0][1]['width'] - ordered[1][1]['width']) < .01, 'book pages differ in size'
    result = {'verified': True, 'zoom': data['zoom'], 'rendered_pages': pages,
              'viewport_pixels': image.size, 'focused_page': data['focusedPage']}
    Path(png).with_suffix('.verification.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('png', type=Path)
    parser.add_argument('metadata', type=Path)
    parser.add_argument('--zoom', type=int)
    parser.add_argument('--mode', choices=['single', 'spread', 'dualScreenBook'])
    parser.add_argument('--after', type=float)
    args = parser.parse_args()
    print(json.dumps(verify(args.png, args.metadata, args.zoom, args.mode, args.after), indent=2))
