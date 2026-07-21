"""Build precise ayah highlight geometry from the printed page layout.

Every Indo-Pak page uses numbered text lines. QUL's page HTML tells us exactly
which ayah occupies each of those lines, while markers_raw.json gives the
centre and radius of every printed ayah circle. Combining both avoids the two
failure modes of the old generator: fragmented Arabic glyphs being mistaken
for separate lines and approximate boundaries extending into adjacent ayahs.

The resulting path follows Quran reading order (right-to-left, then down): it
starts immediately to the left of the previous ayah circle and includes the
selected ayah through the left edge of its own ending circle. Surah headings
and Bismillah rows are omitted because they contain no ayah data.

Usage:
  python build_geometry.py <page-image-dir> <QUL-html-dir>

Outputs:
  tool/cv_work/ayah_rects_raw.json                 pixel coordinates
  assets/arabic-text/indopak_ayah_rects.json      compact normalised geometry
"""

import json
import os
import re
import sys

import numpy as np
from PIL import Image


D = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(D, '..', '..'))
PAGES = (
    sys.argv[1]
    if len(sys.argv) > 1
    else os.environ.get('MUSHAF_PAGES', os.path.join(D, 'pages'))
)
QUL_PAGES = (
    sys.argv[2]
    if len(sys.argv) > 2
    else os.environ.get('QUL_PAGES', os.path.join(D, 'qul_pages'))
)
PAGE_MAP = json.load(
    open(
        os.path.join(ROOT, 'assets', 'arabic-text', 'indopak_page_map.json'),
        encoding='utf-8',
    )
)
MARKERS = json.load(open(os.path.join(D, 'markers_raw.json'), encoding='utf-8'))

IMAGE_WIDTH = 721
IMAGE_HEIGHT = 1058
LINE_COUNT = 13
LINE_STEP = 77.55
REGULAR_TOP = 26.0
SPECIAL_TOP = 337.0
TEXT_LEFT = 32
TEXT_RIGHT = 689
SPECIAL_TEXT_LEFT = 90
SPECIAL_TEXT_RIGHT = 631

LINE_CONTAINER_RE = re.compile(
    r'<div class="line-container" data-line="(\d+)">'
)
AYAH_RE = re.compile(r'data-ayah="(\d+):(\d+)"')


def ordered_ayahs(page):
    output = []
    for surah, first, last in PAGE_MAP[str(page)]:
        output.extend((surah, ayah) for ayah in range(first, last + 1))
    return output


def straddles(page):
    segments = PAGE_MAP[str(page)]
    next_segments = PAGE_MAP.get(str(page + 1))
    return bool(
        next_segments
        and (next_segments[0][0], next_segments[0][1])
        == (segments[-1][0], segments[-1][2])
    )


def read_line_ayahs(page):
    """Return the ordered unique ayah keys in each of the 13 printed lines."""
    path = os.path.join(QUL_PAGES, f'{page - 3}.html')
    html = open(path, encoding='utf-8').read()
    matches = list(LINE_CONTAINER_RE.finditer(html))
    if len(matches) != LINE_COUNT:
        raise ValueError(
            f'page {page}: expected {LINE_COUNT} QUL lines, found {len(matches)}'
        )

    output = [[] for _ in range(LINE_COUNT)]
    for index, match in enumerate(matches):
        line_number = int(match.group(1))
        end = matches[index + 1].start() if index + 1 < len(matches) else len(html)
        seen = set()
        for surah, ayah in AYAH_RE.findall(html[match.end():end]):
            key = (int(surah), int(ayah))
            if key not in seen:
                output[line_number - 1].append(key)
                seen.add(key)
    return output


def line_edges(page, line_index):
    top = SPECIAL_TOP if page in (4, 5) else REGULAR_TOP
    return top + line_index * LINE_STEP, top + (line_index + 1) * LINE_STEP


def line_of_marker(page, y):
    top = SPECIAL_TOP if page in (4, 5) else REGULAR_TOP
    return min(LINE_COUNT - 1, max(0, int((y - top) // LINE_STEP)))


def visible_ink_bounds(rgb, page, line_index):
    """Tight bounds around all printed Quran ink in one ruled text line."""
    row_top, row_bottom = line_edges(page, line_index)
    y0 = max(0, int(round(row_top)) + 4)
    y1 = min(IMAGE_HEIGHT, int(round(row_bottom)) - 4)
    text_left, text_right = (
        (SPECIAL_TEXT_LEFT, SPECIAL_TEXT_RIGHT)
        if page in (4, 5)
        else (TEXT_LEFT, TEXT_RIGHT)
    )
    crop = rgb[y0:y1, text_left:text_right + 1]

    # Any channel below 247 retains pale grey outlines and coloured tajweed
    # marks. Requiring multiple pixels per row/column suppresses isolated scan
    # noise without trimming vowel marks.
    ink = np.any(crop < 247, axis=2)
    y_profile = ink.sum(axis=1)
    x_profile = ink.sum(axis=0)
    ys = np.flatnonzero(y_profile >= 3)
    xs = np.flatnonzero(x_profile >= 2)
    if len(ys) == 0 or len(xs) == 0:
        return (text_left, y0, text_right, y1)

    left = max(text_left, text_left + int(xs[0]) - 2)
    right = min(text_right, text_left + int(xs[-1]) + 3)
    top = max(y0, y0 + int(ys[0]) - 2)
    bottom = min(y1, y0 + int(ys[-1]) + 3)
    return (left, top, right, bottom)


def build_page(page):
    ayahs = ordered_ayahs(page)
    line_ayahs = read_line_ayahs(page)
    occurrences = {ayah: [] for ayah in ayahs}
    for line_index, keys in enumerate(line_ayahs):
        for key in keys:
            if key in occurrences:
                occurrences[key].append(line_index)

    missing = [key for key, lines in occurrences.items() if not lines]
    if missing:
        raise ValueError(f'page {page}: QUL line data is missing {missing}')

    expected_marker_ayahs = ayahs[:-1] if straddles(page) else ayahs
    markers = [tuple(marker) for marker in MARKERS.get(str(page), [])]
    markers.sort(key=lambda marker: (line_of_marker(page, marker[1]), -marker[0]))
    if len(markers) != len(expected_marker_ayahs):
        raise ValueError(
            f'page {page}: {len(markers)} circles for '
            f'{len(expected_marker_ayahs)} completed ayahs'
        )

    marker_for = {}
    for ayah, marker in zip(expected_marker_ayahs, markers):
        actual_line = line_of_marker(page, marker[1])
        expected_line = occurrences[ayah][-1]
        if actual_line != expected_line:
            raise ValueError(
                f'page {page}: circle for {ayah[0]}:{ayah[1]} is on line '
                f'{actual_line + 1}, expected line {expected_line + 1}; '
                f'circle={marker}'
            )
        marker_for[ayah] = marker

    with Image.open(os.path.join(PAGES, f'{page}.webp')) as image:
        if image.size != (IMAGE_WIDTH, IMAGE_HEIGHT):
            raise ValueError(f'page {page}: unexpected image size {image.size}')
        rgb = np.asarray(image.convert('RGB'), dtype=np.uint8)
    ink_bounds = [visible_ink_bounds(rgb, page, i) for i in range(LINE_COUNT)]

    result = []
    for ayah_index, (surah, ayah) in enumerate(ayahs):
        key = (surah, ayah)
        first_line = occurrences[key][0]
        last_line = occurrences[key][-1]
        previous_key = ayahs[ayah_index - 1] if ayah_index > 0 else None
        previous_marker = marker_for.get(previous_key)
        ending_marker = marker_for.get(key)
        rects = []

        for line_index in range(first_line, last_line + 1):
            line_left, y0, line_right, y1 = ink_bounds[line_index]
            left = float(line_left)
            right = float(line_right)

            # On the ayah's first line, exclude the preceding ayah and its
            # circle. Arabic continues to the left of that boundary.
            if (
                line_index == first_line
                and previous_marker is not None
                and line_of_marker(page, previous_marker[1]) == first_line
            ):
                right = min(right, previous_marker[0] - previous_marker[2] - 2)

            # On the final line, stop at the selected ayah's own circle. The
            # two-pixel allowance includes its antialiased outer edge.
            if line_index == last_line and ending_marker is not None:
                left = max(left, ending_marker[0] - ending_marker[2] - 2)

            if right - left < 3:
                raise ValueError(
                    f'page {page} {surah}:{ayah}: collapsed line '
                    f'{line_index + 1} ({left}, {right})'
                )
            rects.append(
                [
                    int(round(left)),
                    int(round(y0)),
                    int(round(right)),
                    int(round(y1)),
                ]
            )

        result.append({'s': surah, 'a': ayah, 'r': rects})
    return result


def compact_page(rows):
    output = []
    for row in rows:
        compact = [row['s'], row['a']]
        for left, top, right, bottom in row['r']:
            compact.extend(
                [
                    round(left / IMAGE_WIDTH * 1000),
                    round(top / IMAGE_HEIGHT * 1000),
                    round(right / IMAGE_WIDTH * 1000),
                    round(bottom / IMAGE_HEIGHT * 1000),
                ]
            )
        output.append(compact)
    return output


def main():
    raw = {}
    compact = {}
    problems = []
    for page in range(4, 851):
        try:
            rows = build_page(page)
            raw[str(page)] = rows
            compact[str(page)] = compact_page(rows)
        except (OSError, ValueError) as error:
            problems.append(str(error))
        if page % 100 == 0:
            print(f'  ...page {page}', flush=True)

    if problems:
        print('\nGEOMETRY VALIDATION FAILED:')
        for problem in problems:
            print(f'  {problem}')
        raise SystemExit(2)

    raw_path = os.path.join(D, 'ayah_rects_raw.json')
    asset_path = os.path.join(
        ROOT, 'assets', 'arabic-text', 'indopak_ayah_rects.json'
    )
    with open(raw_path, 'w', encoding='utf-8') as file:
        json.dump(raw, file, separators=(',', ':'))
    with open(asset_path, 'w', encoding='utf-8') as file:
        json.dump(compact, file, separators=(',', ':'))
    print(
        f'wrote {raw_path} and {asset_path}; '
        f'pages={len(raw)}, validation=clean'
    )


if __name__ == '__main__':
    main()
