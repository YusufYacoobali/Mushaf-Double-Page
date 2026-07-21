"""Detect and validate the ornate Madani ayah medallions on all 604 pages.

Unlike the Indo-Pak circular ring, this 1405H print uses a tall floral marker.
Its outline is an isolated ~82x106 component enclosing a large pale interior.
We detect it at several intensity thresholds, cluster identical detections, and
label them in Quran reading order, and require exactly one marker per ayah.

The scans use the original 1405H pagination.  Some public digital layout data
with the same name has different late-page wrapping, so the scans themselves
are deliberately the source of truth for page membership.

Usage: python extract_madani_markers.py <page-dir>
Output: madani_markers_raw.json as
        [surah, ayah, centre_x, centre_y, half_width, half_height]
"""

import json
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage, signal


D = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(D, '..', '..'))
PAGES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(D, 'madani_pages')
INDOPAK_PAGE_MAP = json.load(
    open(
        os.path.join(ROOT, 'assets', 'arabic-text', 'indopak_page_map.json'),
        encoding='utf-8',
    )
)
SURAH_MAPPER = os.path.join(ROOT, 'lib', 'utils', 'surah_mapper.dart')

WIDTH = 2096
HEIGHT = 3008
PATCH_HEIGHT = 64
PATCH_WIDTH = 54
def canonical_ayahs():
    """Return 1:1 through 114:6 once, independent of page wrapping."""
    output = []
    seen = set()
    for page in sorted(INDOPAK_PAGE_MAP, key=int):
        for surah, first, last in INDOPAK_PAGE_MAP[page]:
            for ayah in range(first, last + 1):
                key = (surah, ayah)
                if key not in seen:
                    output.append(key)
                    seen.add(key)
    if len(output) != 6236 or output[0] != (1, 1) or output[-1] != (114, 6):
        raise ValueError('canonical Quran sequence is incomplete')
    return output


def expected_surah_starts(ayahs):
    text = open(SURAH_MAPPER, encoding='utf-8').read()
    block = text.split('madaniSurahRanges', 1)[1]
    pages = {
        int(match.group(1)): int(match.group(2))
        for match in re.finditer(
            r'SurahRange\((\d+),\s*(\d+),\s*(\d+),', block
        )
        if int(match.group(1)) > 0
    }
    ordinal = {key: index + 1 for index, key in enumerate(ayahs)}
    if len(pages) != 114:
        raise ValueError(f'expected 114 Madani surah starts, found {len(pages)}')
    return {surah: (page, ordinal[(surah, 1)]) for surah, page in pages.items()}


def choose_recoveries(detected, recoveries, ayahs):
    """Maximise template confidence while preserving all printed surah starts.

    A global top-N can choose one calligraphy lookalike on an early page and a
    genuine low-contrast medallion on a later page, leaving the total correct
    but shifting every intervening ayah label. Dynamic programming constrains
    the cumulative marker ordinal at all 114 independently known surah-title
    pages, eliminating that silent failure mode.
    """
    starts = expected_surah_starts(ayahs)
    starts_by_page = {}
    for _, (page, ordinal) in starts.items():
        starts_by_page.setdefault(page, []).append(ordinal)
    candidates_by_page = {page: [] for page in range(4, 608)}
    for candidate in recoveries:
        candidates_by_page[candidate['page']].append(candidate)
    for candidates in candidates_by_page.values():
        candidates.sort(key=lambda item: item['correlation'], reverse=True)

    future_start = {}
    ordered_starts = sorted((page, ordinal) for page, ordinal in starts.values())
    for page in range(4, 608):
        future_start[page] = next(
            (ordinal for start_page, ordinal in ordered_starts if start_page > page),
            None,
        )

    # cumulative marker count -> best summed correlation
    states = {0: 0.0}
    backtrack = []
    for page in range(4, 608):
        strict_count = len(detected[str(page)])
        candidates = candidates_by_page[page]
        prefix = [0.0]
        for candidate in candidates:
            prefix.append(prefix[-1] + candidate['correlation'])
        here = starts_by_page.get(page, [])
        next_ordinal = future_start[page]
        next_states = {}
        links = {}
        for before, total_score in states.items():
            for count in range(len(candidates) + 1):
                after = before + strict_count + count
                if after > len(ayahs):
                    break
                if here and not (before < min(here) and after >= max(here)):
                    continue
                if next_ordinal is not None and after >= next_ordinal:
                    continue
                score = total_score + prefix[count]
                if score > next_states.get(after, float('-inf')):
                    next_states[after] = score
                    links[after] = (before, count)
        if not next_states:
            raise ValueError(f'no valid recovery sequence at page {page}')
        states = next_states
        backtrack.append(links)

    target = len(ayahs)
    if target not in states:
        raise ValueError(
            f'no constrained recovery path reaches {target}; '
            f'possible totals={sorted(states)[-10:]}'
        )
    selected = []
    cumulative = target
    for page_index in range(603, -1, -1):
        page = page_index + 4
        before, count = backtrack[page_index][cumulative]
        selected.extend(candidates_by_page[page][:count])
        cumulative = before
    selected.sort(key=lambda item: (item['page'], item['y'], -item['x']))
    return selected


def candidates_at_threshold(rgb, threshold):
    ink = rgb.mean(axis=2) < threshold
    labels, _ = ndimage.label(ink)
    output = []
    for label_id, slices in enumerate(ndimage.find_objects(labels), 1):
        if slices is None:
            continue
        y0, y1 = slices[0].start, slices[0].stop
        x0, x1 = slices[1].start, slices[1].stop
        width, height = x1 - x0, y1 - y0
        if not (34 <= width <= 49 and 43 <= height <= 59):
            continue
        aspect = width / height
        if not 0.62 <= aspect <= 1.02:
            continue
        component = labels[slices] == label_id
        area = int(component.sum())
        if not 500 <= area <= 1100:
            continue
        hole = int(ndimage.binary_fill_holes(component).sum()) - area
        if not 450 <= hole <= 1100:
            continue
        # Detection runs at half resolution. Convert the component centre and
        # half-extents back to exact source-image coordinates here.
        centre_x = x0 + x1 - 1
        centre_y = y0 + y1 - 1
        if not (200 < centre_x < WIDTH - 200 and 250 < centre_y < HEIGHT - 180):
            continue
        score = (
            abs(width - 41) * 5
            + abs(height - 53) * 4
            + abs(area - 750) * 0.04
            + abs(hole - 780) * 0.03
            + abs(threshold - 200) * 0.08
        )
        output.append(
            {
                'x': centre_x,
                'y': centre_y,
                'rx': width,
                'ry': height,
                'score': score,
                'threshold': threshold,
                'width': width * 2,
                'height': height * 2,
                'area': area,
                'hole': hole,
            }
        )
    return output


def cluster_candidates(candidates):
    clusters = []
    for candidate in sorted(candidates, key=lambda item: item['score']):
        cluster = next(
            (
                group
                for group in clusters
                if (candidate['x'] - group[0]['x']) ** 2
                + (candidate['y'] - group[0]['y']) ** 2
                < 18 ** 2
            ),
            None,
        )
        if cluster is None:
            clusters.append([candidate])
        else:
            cluster.append(candidate)

    output = []
    for cluster in clusters:
        best = dict(min(cluster, key=lambda item: item['score']))
        best['score'] -= min(3, len({item['threshold'] for item in cluster})) * 3
        best['detections'] = len(cluster)
        output.append(best)
    return sorted(output, key=lambda item: item['score'])


def load_page(page):
    with Image.open(os.path.join(PAGES, f'{page}.webp')) as image:
        if image.size != (WIDTH, HEIGHT):
            raise ValueError(f'unexpected image size {image.size}')
        # Nearest-neighbour half resolution preserves the printed component
        # topology while reducing connected-component work by 75%.
        return np.asarray(image.convert('RGB'), dtype=np.uint8)[::2, ::2]


def detect_page(page):
    rgb = load_page(page)
    all_candidates = []
    # Multiple thresholds recover pale or partially joined medallions.  The
    # same physical medallion is merged by cluster_candidates below.
    for threshold in (210, 200, 190, 180):
        all_candidates.extend(candidates_at_threshold(rgb, threshold))
    return cluster_candidates(all_candidates)


def marker_patch(rgb, x, y):
    centre_x = round(x / 2)
    centre_y = round(y / 2)
    return rgb[
        centre_y - PATCH_HEIGHT // 2:centre_y + PATCH_HEIGHT // 2,
        centre_x - PATCH_WIDTH // 2:centre_x + PATCH_WIDTH // 2,
    ].mean(axis=2)


def build_template(training_patches):
    template = np.median(np.stack(training_patches), axis=0).astype(float)
    template -= template.mean()
    energy = np.sqrt((template * template).sum())
    if energy <= 0:
        raise ValueError('empty medallion template')
    return template / energy


def template_recoveries(page, template, existing):
    rgb = load_page(page)
    gray = rgb.mean(axis=2).astype(float)
    numerator = signal.fftconvolve(gray, template[::-1, ::-1], mode='same')
    pixel_count = PATCH_HEIGHT * PATCH_WIDTH
    mean = ndimage.uniform_filter(gray, size=(PATCH_HEIGHT, PATCH_WIDTH))
    mean_square = ndimage.uniform_filter(
        gray * gray, size=(PATCH_HEIGHT, PATCH_WIDTH)
    )
    variance_sum = np.maximum(1, (mean_square - mean * mean) * pixel_count)
    correlation = numerator / np.sqrt(variance_sum)

    # Connected Arabic calligraphy can very rarely have the same bounding box,
    # area and enclosed hole as a medallion. Confirm every first-pass component
    # against the invariant floral template before it is allowed into sequence.
    confirmed = []
    rejected = []
    for candidate in existing:
        x = round(candidate['x'] / 2)
        y = round(candidate['y'] / 2)
        candidate['correlation'] = float(correlation[y, x])
        (confirmed if candidate['correlation'] >= 0.40 else rejected).append(
            candidate
        )
    existing[:] = confirmed

    maxima = ndimage.maximum_filter(correlation, size=(35, 30))
    ys, xs = np.where(correlation == maxima)

    output = []
    for y, x in zip(ys, xs):
        centre_x, centre_y = int(x * 2), int(y * 2)
        score = float(correlation[y, x])
        if score < 0.40:
            continue
        if not (200 < centre_x < WIDTH - 140 and 250 < centre_y < HEIGHT - 180):
            continue
        if any(
            (centre_x - candidate['x']) ** 2
            + (centre_y - candidate['y']) ** 2
            < 35 ** 2
            for candidate in existing
        ):
            continue
        output.append(
            {
                'x': centre_x,
                'y': centre_y,
                'rx': 41,
                'ry': 53,
                'score': -score * 100,
                'correlation': score,
                'threshold': 'template',
                'width': 82,
                'height': 106,
                'area': 0,
                'hole': 0,
            }
        )
    return output, rejected


def main():
    detected = {}
    training_patches = []
    for page in range(4, 608):
        candidates = detect_page(page)
        candidates.sort(key=lambda item: (item['y'], -item['x']))
        detected[str(page)] = candidates
        if len(training_patches) < 600:
            rgb = load_page(page)
            for candidate in candidates:
                patch = marker_patch(rgb, candidate['x'], candidate['y'])
                if patch.shape == (PATCH_HEIGHT, PATCH_WIDTH):
                    training_patches.append(patch.astype(np.uint8))
                if len(training_patches) >= 600:
                    break
        if page % 50 == 0:
            print(f'...page {page}', flush=True)

    ayahs = canonical_ayahs()
    marker_count = sum(len(candidates) for candidates in detected.values())
    needed = len(ayahs) - marker_count
    if needed < 0:
        raise SystemExit(
            f'detected {marker_count} medallions, expected {len(ayahs)}; '
            'strict detector produced false positives'
        )

    recoveries = []
    rejected_components = []
    if needed:
        template = build_template(training_patches)
        for page in range(4, 608):
            page_recoveries, page_rejected = template_recoveries(
                page, template, detected[str(page)]
            )
            for candidate in page_recoveries:
                candidate['page'] = page
                recoveries.append(candidate)
            for candidate in page_rejected:
                rejected_components.append(
                    [
                        page,
                        candidate['x'],
                        candidate['y'],
                        round(candidate['correlation'], 4),
                    ]
                )
            if page % 50 == 0:
                print(f'...template page {page}', flush=True)
        marker_count = sum(len(candidates) for candidates in detected.values())
        needed = len(ayahs) - marker_count
        if needed < 0:
            raise SystemExit(
                f'template-confirmed {marker_count} components for '
                f'{len(ayahs)} ayahs'
            )
        recoveries.sort(key=lambda item: item['correlation'], reverse=True)
        if len(recoveries) < needed:
            raise SystemExit(
                f'template recovered only {len(recoveries)} of {needed} '
                'missing medallions'
            )
        chosen_recoveries = choose_recoveries(detected, recoveries, ayahs)
        if len(chosen_recoveries) != needed:
            raise SystemExit(
                f'constrained recovery selected {len(chosen_recoveries)}, '
                f'expected {needed}'
            )
        cutoff = min(item['correlation'] for item in chosen_recoveries)
        if cutoff < 0.40:
            raise SystemExit(
                f'template recovery cutoff {cutoff:.3f} is not reliable enough'
            )
        for candidate in chosen_recoveries:
            page = str(candidate['page'])
            detected[page].append(candidate)
            detected[page].sort(key=lambda item: (item['y'], -item['x']))

        recovery_path = os.path.join(D, 'madani_marker_recoveries.json')
        with open(recovery_path, 'w', encoding='utf-8') as file:
            json.dump(
                [
                    [
                        candidate['page'],
                        candidate['x'],
                        candidate['y'],
                        round(candidate['correlation'], 4),
                    ]
                    for candidate in chosen_recoveries
                ],
                file,
                separators=(',', ':'),
            )
        rejected_path = os.path.join(D, 'madani_marker_rejections.json')
        with open(rejected_path, 'w', encoding='utf-8') as file:
            json.dump(rejected_components, file, separators=(',', ':'))
        print(
            f'rejected lookalikes={len(rejected_components)}, '
            f'recovered={needed}, correlation cutoff={cutoff:.3f}, '
            f'diagnostics={recovery_path}',
            flush=True,
        )

    marker_count = sum(len(candidates) for candidates in detected.values())
    if marker_count != len(ayahs):
        raise SystemExit(f'final marker count {marker_count} != {len(ayahs)}')

    output = {}
    cursor = 0
    for page, candidates in detected.items():
        rows = []
        for candidate in candidates:
            surah, ayah = ayahs[cursor]
            cursor += 1
            rows.append(
                [
                    surah,
                    ayah,
                    round(candidate['x']),
                    round(candidate['y']),
                    round(candidate['rx']),
                    round(candidate['ry']),
                ]
            )
        output[page] = rows

    path = os.path.join(D, 'madani_markers_raw.json')
    with open(path, 'w', encoding='utf-8') as file:
        json.dump(output, file, separators=(',', ':'))
    print(
        f'wrote {path}; pages={len(output)}, markers={cursor}, '
        'sequence=1:1..114:6, validation=clean'
    )


if __name__ == '__main__':
    main()
