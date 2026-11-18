#!/usr/bin/env python3
"""Cross-check real rendered page rectangles with the captured PNG pixels."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageOps, ImageStat


def bounds(r):
    return r['left'], r['top'], r['left'] + r['width'], r['top'] + r['height']


def verify(png, metadata, expected_zoom=None):
    image = ImageOps.exif_transpose(Image.open(png)).convert('RGB')
    data = json.loads(Path(metadata).read_text())
    dpr = data['pixelRatio']
    assert image.size == (round(data['viewport']['width'] * dpr),
                          round(data['viewport']['height'] * dpr)), 'stale viewport geometry'
    if expected_zoom is not None:
        assert math.isclose(data['zoom'] * 100, expected_zoom, abs_tol=.1), 'wrong actual rendered zoom'
    pages = data['pages']
    assert len(pages) == (1 if data['mode'] == 'single' else 2), 'wrong rendered page count'
    assert data['fit'], 'foldable capture must use the fitted layout'
    aspect = 2096 / 3008 if data['edition'] == 'madani' else 721 / 1058
    region_list = data['regions']
    if data['mode'] == 'single':
        maximum = min(region_list[0]['width'], region_list[0]['height'] * aspect)
    elif data['mode'] == 'dualScreenBook':
        maximum = min(min(r['width'], r['height'] * aspect) for r in region_list)
    else:
        r = data['readingBounds']
        maximum = min((r['width'] - 1) / 2, r['height'] * aspect)
    for page, r in pages.items():
        assert math.isclose(r['width'] / r['height'], aspect, abs_tol=.001), 'page distorted'
        assert math.isclose(r['width'], maximum * data['zoom'], abs_tol=.5), 'not scaled from maximum fit'
        l, t, right, bottom = bounds(r)
        region = next((x for x in region_list if x['left'] - .5 <= l and
                       x['top'] - .5 <= t and x['left'] + x['width'] + .5 >= right and
                       x['top'] + x['height'] + .5 >= bottom), None)
        # A centred spread uses one shared surface split into virtual leaves.
        if data['mode'] == 'spread':
            region = data['readingBounds']
        assert region is not None and l >= region['left'] - .5 and t >= region['top'] - .5
        assert right <= region['left'] + region['width'] + .5
        assert bottom <= region['top'] + region['height'] + .5, 'page clipped'
        crop = image.crop(tuple(round(v * dpr) for v in (l, t, right, bottom)))
        assert sum(ImageStat.Stat(crop).var) / 3 > 300, f'blank or unrendered paper: page {page}'
        # The real Quran image has a white outer paper border. Require actual
        # rendered content at all four edges; a blank PNG is not verification.
        for edge in [(0, 0, crop.width, 3), (0, crop.height - 3, crop.width, crop.height),
                     (0, 0, 3, crop.height), (crop.width - 3, 0, crop.width, crop.height)]:
            pixels = list(crop.crop(edge).getdata())
            assert sum(max(p) > 100 for p in pixels) / len(pixels) > .5, f'missing paper edge: page {page}'
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
    args = parser.parse_args()
    print(json.dumps(verify(args.png, args.metadata, args.zoom), indent=2))
