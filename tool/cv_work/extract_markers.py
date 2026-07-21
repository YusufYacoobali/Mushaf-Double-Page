"""Extract the printed ayah-circle coordinates from every Indo-Pak page.

The previous extractor searched for generic dark annuli. Arabic glyphs contain
many annulus-like shapes, so its count-guided top-N step could silently choose a
letter instead of an ayah marker. That produced geometrically valid but visibly
wrong highlights.

The Taj Company page images contain a much stronger invariant: every ayah
marker has a separate, closed, near-24px circular outline component. We detect
those closed components directly (including coloured tajweed circles), then
validate the count against the authoritative per-page ayah map.

Output: markers_raw.json { "<logical page>": [[centre_x, centre_y, radius], ...] }
Coordinates are in the source 721x1058 image space.
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


D = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(D, '..', '..'))
PAGES = (
    sys.argv[1]
    if len(sys.argv) > 1
    else os.environ.get('MUSHAF_PAGES', os.path.join(D, 'pages'))
)
PAGE_MAP = json.load(
    open(
        os.path.join(ROOT, 'assets', 'arabic-text', 'indopak_page_map.json'),
        encoding='utf-8',
    )
)


def expected_markers(page):
    segments = PAGE_MAP.get(str(page))
    if not segments:
        return 0
    count = sum(segment[2] - segment[1] + 1 for segment in segments)
    next_segments = PAGE_MAP.get(str(page + 1))
    straddles = (
        next_segments
        and (next_segments[0][0], next_segments[0][1])
        == (segments[-1][0], segments[-1][2])
    )
    return count - (1 if straddles else 0)


def _component_candidates(image):
    rgb = np.asarray(image.convert('RGB'), dtype=np.uint8)

    # Mean-channel intensity deliberately retains coloured tajweed markers.
    # A four-connected label keeps the isolated printed ring separate from
    # nearby vowel marks that only touch it diagonally.
    ink = rgb.mean(axis=2) < 230
    labels, _ = ndimage.label(ink)
    objects = ndimage.find_objects(labels)
    candidates = []

    for label_id, slices in enumerate(objects, 1):
        if slices is None:
            continue
        y0, y1 = slices[0].start, slices[0].stop
        x0, x1 = slices[1].start, slices[1].stop
        width, height = x1 - x0, y1 - y0
        if not (18 <= width <= 32 and 18 <= height <= 32):
            continue
        aspect = width / height
        if not 0.75 <= aspect <= 1.30:
            continue

        component = labels[slices] == label_id
        area = int(component.sum())
        if not 60 <= area <= 300:
            continue
        centre_x = (x0 + x1 - 1) / 2
        centre_y = (y0 + y1 - 1) / 2
        component_y, component_x = np.nonzero(component)
        radii = np.hypot(
            component_x + x0 - centre_x,
            component_y + y0 - centre_y,
        )
        ring_fraction = float(((radii >= 8) & (radii <= 14)).mean())
        angles = (
            np.arctan2(
                component_y + y0 - centre_y,
                component_x + x0 - centre_x,
            )
            + 2 * np.pi
        ) % (2 * np.pi)
        angle_bins = np.unique((angles / (2 * np.pi) * 24).astype(int))
        angular_coverage = len(angle_bins) / 24

        filled_area = int(ndimage.binary_fill_holes(component).sum())
        hole_area = filled_area - area
        # A handful of lightly printed circles have a one-pixel break, so
        # binary hole filling cannot see their interior. Their ink still forms
        # a near-complete annulus. Accept that geometric invariant too.
        if hole_area < 25 and not (
            ring_fraction >= 0.72 and angular_coverage >= 0.88
        ):
            continue

        radius = max(width, height) / 2
        local_x = int(round(centre_x))
        local_y = int(round(centre_y))
        inner_y, inner_x = np.ogrid[-7:8, -7:8]
        inner_mask = inner_x * inner_x + inner_y * inner_y < 43
        inner_crop = ink[
            local_y - 7:local_y + 8,
            local_x - 7:local_x + 8,
        ]
        if inner_crop.shape != inner_mask.shape:
            continue
        inner_ink = int(inner_crop[inner_mask].sum())
        # Surah/Bismillah ornaments contain a similarly sized empty circle at
        # a fixed position. A real ayah ring always contains a printed number.
        if inner_ink < 5:
            continue

        # True outlines in these 721x1058 images are normally 24-25px across,
        # ~130px of ink and enclose ~330px. This score is only a tie-breaker on
        # pages with extra closed glyph components; count validation remains
        # mandatory below.
        score = (
            abs(width - 24.5) * 8
            + abs(height - 24.5) * 8
            + abs(area - 135) * 0.10
            + abs(hole_area - 330) * 0.025
            + abs(1 - aspect) * 20
            + (1 - ring_fraction) * 20
            + (1 - angular_coverage) * 20
        )
        candidates.append(
            {
                'x': centre_x,
                'y': centre_y,
                'r': radius,
                'score': score,
                'width': width,
                'height': height,
                'area': area,
                'hole': hole_area,
                'inner_ink': inner_ink,
                'ring_fraction': ring_fraction,
                'angular_coverage': angular_coverage,
            }
        )

    return sorted(candidates, key=lambda candidate: candidate['score'])


def _empty_ring_candidates(image, existing):
    """Recover verse-one markers whose printed circle intentionally is empty.

    This is kept as the final fallback only. Decorative Bismillah circles have
    the same appearance, but they can never displace a normal numbered marker.
    """
    rgb = np.asarray(image.convert('RGB'), dtype=np.uint8)
    ink = rgb.mean(axis=2) < 230
    labels, _ = ndimage.label(ink)
    output = []
    for label_id, slices in enumerate(ndimage.find_objects(labels), 1):
        if slices is None:
            continue
        y0, y1 = slices[0].start, slices[0].stop
        x0, x1 = slices[1].start, slices[1].stop
        width, height = x1 - x0, y1 - y0
        if not (20 <= width <= 27 and 20 <= height <= 27):
            continue
        component = labels[slices] == label_id
        area = int(component.sum())
        if not 90 <= area <= 175:
            continue
        centre_x = (x0 + x1 - 1) / 2
        centre_y = (y0 + y1 - 1) / 2
        if any(
            (centre_x - c['x']) ** 2 + (centre_y - c['y']) ** 2 < 18 ** 2
            for c in existing
        ):
            continue
        component_y, component_x = np.nonzero(component)
        radii = np.hypot(
            component_x + x0 - centre_x,
            component_y + y0 - centre_y,
        )
        ring_fraction = float(((radii >= 8) & (radii <= 14)).mean())
        angles = (
            np.arctan2(
                component_y + y0 - centre_y,
                component_x + x0 - centre_x,
            )
            + 2 * np.pi
        ) % (2 * np.pi)
        angular_coverage = len(
            np.unique((angles / (2 * np.pi) * 24).astype(int))
        ) / 24
        if ring_fraction < 0.72 or angular_coverage < 0.88:
            continue
        output.append(
            {
                'x': centre_x,
                'y': centre_y,
                'r': max(width, height) / 2,
                'score': (
                    abs(width - 24.5) * 8
                    + abs(height - 24.5) * 8
                    + abs(area - 135) * 0.10
                    + (1 - ring_fraction) * 20
                    + (1 - angular_coverage) * 20
                ),
                'width': width,
                'height': height,
                'area': area,
                'hole': 0,
                'inner_ink': 0,
                'ring_fraction': ring_fraction,
                'angular_coverage': angular_coverage,
                'fallback': True,
                'empty_ring': True,
            }
        )
    return sorted(output, key=lambda candidate: candidate['score'])


def detect_page(page):
    path = os.path.join(PAGES, f'{page}.webp')
    with Image.open(path) as image:
        if image.size != (721, 1058):
            raise ValueError(f'page {page}: unexpected image size {image.size}')
        return _component_candidates(image)


def _hole_fallback_candidates(image, existing):
    """Recover marker rings connected to adjacent coloured tajweed glyphs.

    Even when a coloured outline joins neighbouring text into one foreground
    component, its enclosed white interior remains an isolated, near-circular
    background component. The printed number check rejects empty ornaments.
    """
    rgb = np.asarray(image.convert('RGB'), dtype=np.uint8)
    ink = rgb.mean(axis=2) < 230
    labels, _ = ndimage.label(~ink)
    objects = ndimage.find_objects(labels)
    raw = []
    for label_id, slices in enumerate(objects, 1):
        if slices is None:
            continue
        y0, y1 = slices[0].start, slices[0].stop
        x0, x1 = slices[1].start, slices[1].stop
        width, height = x1 - x0, y1 - y0
        if not (12 <= width <= 27 and 12 <= height <= 27):
            continue
        aspect = width / height
        if not 0.70 <= aspect <= 1.40:
            continue
        area = int((labels[slices] == label_id).sum())
        if not 100 <= area <= 450:
            continue

        centre_x = (x0 + x1 - 1) / 2
        centre_y = (y0 + y1 - 1) / 2
        x = int(round(centre_x))
        y = int(round(centre_y))
        if x < 30 or x >= ink.shape[1] - 30 or y < 35 or y >= ink.shape[0] - 35:
            continue
        inner_y, inner_x = np.ogrid[-7:8, -7:8]
        inner_mask = inner_x * inner_x + inner_y * inner_y < 43
        inner_ink = int(ink[y - 7:y + 8, x - 7:x + 8][inner_mask].sum())
        if inner_ink < 5:
            continue
        if any(
            (centre_x - c['x']) ** 2 + (centre_y - c['y']) ** 2 < 18 ** 2
            for c in existing
        ):
            continue

        score = (
            abs(width - 20.5) * 7
            + abs(height - 20.5) * 7
            + abs(area - 275) * 0.035
            + abs(1 - aspect) * 15
        )
        raw.append(
            {
                'x': centre_x,
                'y': centre_y,
                'r': max(width, height) / 2 + 2,
                'score': score,
                'width': width,
                'height': height,
                'area': area,
                'hole': area,
                'inner_ink': inner_ink,
                'fallback': True,
            }
        )

    # A numeral can touch the ring and split its interior into two white
    # components. Collapse such near-identical centres into one marker.
    clusters = []
    for candidate in sorted(raw, key=lambda item: item['score']):
        cluster = next(
            (
                group
                for group in clusters
                if (candidate['x'] - group[0]['x']) ** 2
                + (candidate['y'] - group[0]['y']) ** 2
                < 12 ** 2
            ),
            None,
        )
        if cluster is None:
            clusters.append([candidate])
        else:
            cluster.append(candidate)

    output = []
    for cluster in clusters:
        best = min(cluster, key=lambda item: item['score'])
        if len(cluster) > 1:
            best = dict(best)
            best['x'] = sum(item['x'] for item in cluster) / len(cluster)
            best['y'] = sum(item['y'] for item in cluster) / len(cluster)
        output.append(best)
    return sorted(output, key=lambda candidate: candidate['score'])


def detect_page_with_fallback(page, expected):
    path = os.path.join(PAGES, f'{page}.webp')
    with Image.open(path) as image:
        if image.size != (721, 1058):
            raise ValueError(f'page {page}: unexpected image size {image.size}')
        candidates = _component_candidates(image)
        chosen = candidates[:expected]
        if len(chosen) < expected:
            needed = expected - len(chosen)
            fallback = _hole_fallback_candidates(image, chosen)
            chosen.extend(fallback[:needed])
            if len(chosen) < expected:
                needed = expected - len(chosen)
                empty_rings = _empty_ring_candidates(image, chosen)
                chosen.extend(empty_rings[:needed])
                fallback.extend(empty_rings)
            return candidates, chosen, fallback
        return candidates, chosen, []


def main():
    output = {}
    problems = []
    pages_with_rejected_extras = 0
    for page in range(4, 851):
        path = os.path.join(PAGES, f'{page}.webp')
        if not os.path.exists(path):
            problems.append(f'page {page}: image missing')
            continue

        expected = expected_markers(page)
        candidates, chosen, fallback = detect_page_with_fallback(page, expected)
        if len(chosen) < expected:
            problems.append(
                f'page {page}: found {len(chosen)}, expected {expected}; '
                f'candidates={[(round(c["x"], 1), round(c["y"], 1), c["width"], c["height"], c["area"], c["hole"]) for c in candidates]}'
            )
        elif len(candidates) > expected:
            pages_with_rejected_extras += 1
        if fallback:
            selected_fallback = [c for c in chosen if c.get('fallback')]
            print(
                f'  page {page} fallback selected: '
                f'{[(round(c["x"]), round(c["y"]), round(c["score"], 3)) for c in selected_fallback]}'
            )

        # Geometry consumes markers in reading order, not component-score order.
        output[str(page)] = [
            [round(c['x']), round(c['y']), round(c['r'])]
            for c in sorted(chosen, key=lambda c: (c['y'], -c['x']))
        ]
        if page % 100 == 0:
            print(f'  ...page {page}', flush=True)

    if problems:
        print('\nMARKER VALIDATION FAILED:')
        for problem in problems:
            print(f'  {problem}')
        raise SystemExit(2)

    output_path = os.path.join(D, 'markers_raw.json')
    with open(output_path, 'w', encoding='utf-8') as file:
        json.dump(output, file, separators=(',', ':'))
    print(
        f'wrote {output_path}; pages={len(output)}, validation=clean, '
        f'pages_with_rejected_extras={pages_with_rejected_extras}'
    )


if __name__ == '__main__':
    main()
