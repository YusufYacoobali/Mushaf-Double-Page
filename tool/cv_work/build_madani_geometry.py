"""Build medallion-to-medallion ayah geometry for the 1405H Madani images.

The layout uses 15 lines and a tall floral ayah medallion.  The labelled
`madani_markers_raw.json` supplies the actual page membership and every
medallion's extent.  Ayah rectangles follow Quran reading order from the
previous medallion to the next, excluding surah headers and Bismillah rows.

Usage: python build_madani_geometry.py <page-dir>
Outputs the raw pixel geometry and `assets/arabic-text/madani_ayah_rects.json`.
"""

import json
import os
import sys

import numpy as np
from PIL import Image


D = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(D, '..', '..'))
PAGES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(D, 'madani_pages')
MARKERS = json.load(
    open(os.path.join(D, 'madani_markers_raw.json'), encoding='utf-8')
)

WIDTH = 2096
HEIGHT = 3008
LINE_COUNT = 15
REGULAR_TOP = 307.0
REGULAR_STEP = 164.5
SPECIAL_TOP = 939.0
SPECIAL_STEP = 133.0
def line_metrics(page):
    return (
        (SPECIAL_TOP, SPECIAL_STEP)
        if page in (4, 5)
        else (REGULAR_TOP, REGULAR_STEP)
    )


def line_edges(page, line_index):
    top, step = line_metrics(page)
    return top + line_index * step, top + (line_index + 1) * step


def line_of(page, y):
    top, step = line_metrics(page)
    return min(LINE_COUNT - 1, max(0, int((y - top) // step)))


def text_limits(gray, page):
    if page == 4:
        return 255, 1470
    if page == 5:
        return 610, 1845
    # The scans alternate/shift horizontally and occasionally reserve a wide
    # outer gutter for a juz ornament. Find the two long inner-frame rules on
    # each actual image instead of assuming a fixed x offset.
    column_ink = (gray[250:2820] < 160).sum(axis=0)
    strong = np.flatnonzero(column_ink > 2450)
    left = strong[strong < WIDTH // 2]
    right = strong[strong > WIDTH // 2]
    if len(left) == 0 or len(right) == 0:
        raise ValueError('could not locate inner text frame')
    return int(left[-1]) + 12, int(right[0]) - 12


def visible_ink_bounds(gray, page, line_index, limits):
    row_top, row_bottom = line_edges(page, line_index)
    y0 = max(0, int(round(row_top)) + 8)
    y1 = min(HEIGHT, int(round(row_bottom)) - 8)
    text_left, text_right = limits
    crop = gray[y0:y1, text_left:text_right + 1]

    ink = crop < 210
    ys = np.flatnonzero(ink.sum(axis=1) >= 5)
    xs = np.flatnonzero(ink.sum(axis=0) >= 3)
    if len(ys) == 0 or len(xs) == 0:
        return text_left, y0, text_right, y1
    return (
        max(text_left, text_left + int(xs[0]) - 4),
        max(y0, y0 + int(ys[0]) - 4),
        min(text_right, text_left + int(xs[-1]) + 5),
        min(y1, y0 + int(ys[-1]) + 5),
    )


def has_ink_left_of_marker(gray, page, marker, limits):
    """Whether the next RTL ayah begins on the marker's physical line."""
    _, _, x, _, rx, _ = marker
    line_index = line_of(page, marker[3])
    row_top, row_bottom = line_edges(page, line_index)
    text_left, _ = limits
    x1 = int(x - rx - 10)
    if x1 <= text_left + 8:
        return False
    y0 = max(0, int(row_top) + 10)
    y1 = min(HEIGHT, int(row_bottom) - 10)
    crop = gray[y0:y1, text_left:x1]
    # Quran text is near-black; requiring a small cluster avoids treating the
    # pale page texture or a stray ornament speck as the next ayah.
    return int((crop < 145).sum()) >= 35


def has_opening_header_banner(gray, page, limits):
    """Whether the first inner row is an ornamental surah-title banner."""
    row_top, row_bottom = line_edges(page, 0)
    text_left, text_right = limits
    crop = gray[
        int(row_top):int(row_bottom),
        text_left:text_right + 1,
    ]
    # A banner has long horizontal rules; Bismillah/calligraphy does not.
    return int((crop < 160).sum(axis=1).max(initial=0)) >= 700


def first_line_for(gray, page, index, markers, limits):
    current = markers[index]
    surah, ayah = current[:2]
    ending_line = line_of(page, current[3])

    if page in (4, 5):
        if index == 0:
            return ending_line
    elif index == 0:
        if ayah == 1:
            # Most opening-page titles sit in row 1, but several scans print
            # the title above the inner frame. Detect the banner itself rather
            # than using a page list. Bismillah then uses one row (except At-
            # Tawbah), after which ayah 1 begins.
            header_rows = 1 if has_opening_header_banner(gray, page, limits) else 0
            bismillah_rows = 0 if surah == 9 else 1
            return header_rows + bismillah_rows
        return 0

    previous = markers[index - 1]
    previous_line = line_of(page, previous[3])
    if ayah == 1 and previous[0] != surah:
        return previous_line + (2 if surah == 9 else 3)
    return (
        previous_line
        if has_ink_left_of_marker(gray, page, previous, limits)
        else previous_line + 1
    )


def build_page(page):
    markers = [tuple(marker) for marker in MARKERS[str(page)]]

    with Image.open(os.path.join(PAGES, f'{page}.webp')) as image:
        if image.size != (WIDTH, HEIGHT):
            raise ValueError(f'unexpected image size {image.size}')
        gray = np.asarray(image.convert('L'), dtype=np.uint8)
    limits = text_limits(gray, page)
    ink_bounds = [
        visible_ink_bounds(gray, page, line, limits) for line in range(15)
    ]

    output = []
    for index, ending in enumerate(markers):
        surah, ayah, x, y, rx, ry = ending
        first_line = first_line_for(gray, page, index, markers, limits)
        last_line = line_of(page, y)
        if not 0 <= first_line <= last_line < LINE_COUNT:
            raise ValueError(
                f'{surah}:{ayah} invalid line span {first_line + 1}..{last_line + 1}'
            )
        previous = markers[index - 1] if index > 0 else None
        rects = []
        for line_index in range(first_line, last_line + 1):
            line_left, y0, line_right, y1 = ink_bounds[line_index]
            left = float(line_left)
            right = float(line_right)
            if (
                line_index == first_line
                and previous is not None
                and line_of(page, previous[3]) == first_line
                and ayah != 1
            ):
                right = min(right, previous[2] - previous[4] - 4)
            if line_index == last_line:
                left = max(left, x - rx - 4)
            if right - left < 5:
                raise ValueError(
                    f'{surah}:{ayah} collapsed line {line_index + 1}: '
                    f'{left}..{right}'
                )
            rects.append(
                [
                    round(left),
                    round(y0),
                    round(right),
                    round(y1),
                ]
            )
        output.append({'s': surah, 'a': ayah, 'r': rects})
    return output


def compact_page(rows):
    output = []
    for row in rows:
        compact = [row['s'], row['a']]
        for left, top, right, bottom in row['r']:
            compact.extend(
                [
                    round(left / WIDTH * 1000),
                    round(top / HEIGHT * 1000),
                    round(right / WIDTH * 1000),
                    round(bottom / HEIGHT * 1000),
                ]
            )
        output.append(compact)
    return output


def main():
    raw = {}
    compact = {}
    problems = []
    for page in range(4, 608):
        try:
            rows = build_page(page)
            raw[str(page)] = rows
            compact[str(page)] = compact_page(rows)
        except (OSError, ValueError) as error:
            problems.append(f'page {page}: {error}')
        if page % 50 == 0:
            print(f'...page {page}', flush=True)

    if problems:
        print('\nMADANI GEOMETRY VALIDATION FAILED:')
        for problem in problems:
            print(f'  {problem}')
        raise SystemExit(2)

    raw_path = os.path.join(D, 'madani_ayah_rects_raw.json')
    asset_path = os.path.join(
        ROOT, 'assets', 'arabic-text', 'madani_ayah_rects.json'
    )
    with open(raw_path, 'w', encoding='utf-8') as file:
        json.dump(raw, file, separators=(',', ':'))
    with open(asset_path, 'w', encoding='utf-8') as file:
        json.dump(compact, file, separators=(',', ':'))
    print(
        f'wrote {raw_path} and {asset_path}; pages={len(raw)}, '
        'validation=clean'
    )


if __name__ == '__main__':
    main()
