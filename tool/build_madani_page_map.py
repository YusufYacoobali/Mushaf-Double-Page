"""Build and validate the app's Madani logical-page ayah map.

The marker extractor labels every printed ayah medallion in Quran order.  That
is the page-membership source of truth because this scan's original 1405H line
wrapping differs from later digital layouts on a number of pages.
"""

import json
import os
import re


HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, '..'))
RAW = os.path.join(HERE, 'cv_work', 'madani_markers_raw.json')
OUTPUT = os.path.join(ROOT, 'assets', 'arabic-text', 'madani_page_map.json')
SURAH_MAPPER = os.path.join(ROOT, 'lib', 'utils', 'surah_mapper.dart')
TOTAL_PAGES = 604
AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99,
    128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34,
    30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29,
    18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12,
    12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19,
    36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]


def ground_truth_starts():
    text = open(SURAH_MAPPER, encoding='utf-8').read()
    block = text.split('madaniSurahRanges', 1)[1]
    output = {}
    for match in re.finditer(r'SurahRange\((\d+),\s*(\d+),\s*(\d+),', block):
        output[int(match.group(1))] = int(match.group(2))
    return output


def main():
    raw = json.load(open(RAW, encoding='utf-8'))
    output = {}
    first_appearance = {}
    seen = set()
    for logical_page in range(4, 608):
        by_surah = {}
        for row in raw[str(logical_page)]:
            surah, ayah = row[:2]
            by_surah.setdefault(surah, []).append(ayah)
            seen.add((surah, ayah))
            first_appearance.setdefault((surah, ayah), logical_page)
        output[str(logical_page)] = [
            [surah, min(ayahs), max(ayahs)]
            for surah, ayahs in by_surah.items()
        ]

    missing = [
        (surah, ayah)
        for surah, count in enumerate(AYAH_COUNTS, 1)
        for ayah in range(1, count + 1)
        if (surah, ayah) not in seen
    ]
    mismatches = [
        (surah, page, first_appearance.get((surah, 1)))
        for surah, page in ground_truth_starts().items()
        if surah > 0 and first_appearance.get((surah, 1)) != page
    ]
    if (
        missing
        or mismatches
        or len(seen) != sum(AYAH_COUNTS)
        or len(output) != TOTAL_PAGES
    ):
        raise SystemExit(
            f'validation failed: missing={missing[:10]}, '
            f'surah starts={mismatches[:10]}, seen={len(seen)}'
        )

    with open(OUTPUT, 'w', encoding='utf-8') as file:
        json.dump(output, file, separators=(',', ':'))
    print(
        f'wrote {OUTPUT}; pages={len(output)}, ayahs={len(seen)}, '
        'validation=clean'
    )


if __name__ == '__main__':
    main()
