"""Build the final Madani marker index directly from floral template peaks."""

import json
import os
import sys

import numpy as np

sys.argv = [sys.argv[0], sys.argv[1] if len(sys.argv) > 1 else 'madani_pages']
import extract_madani_markers as extractor


D = os.path.dirname(__file__)
RAW_PATH = os.path.join(D, 'madani_markers_raw.json')
PEAK_PATH = os.path.join(D, 'madani_template_peaks.json')

# Page 580, ayah 75:12 is joined to the preceding word strongly enough that its
# floral match falls below the strict corpus-wide threshold.  Its centre was
# verified on the source image at full resolution (the local maximum is 334,
# 2180).  Keeping the exception here makes the generated data reproducible and
# auditable instead of silently lowering the threshold for every page.
MANUAL_CONFIRMED = {
    580: {'x': 334, 'y': 2180, 'correlation': 0.4300, 'manual': True},
}


def reading_key(page, candidate):
    if page in (4, 5):
        top, step = 939.0, 133.0
    else:
        top, step = 307.0, 164.5
    line = max(0, min(14, int((candidate['y'] - top) // step)))
    return line, -candidate['x']


def main():
    raw = json.load(open(RAW_PATH, encoding='utf-8'))
    training = []
    for page in range(4, 608):
        if len(training) >= 600:
            break
        rgb = extractor.load_page(page)
        for _, _, x, y, _, _ in raw[str(page)]:
            patch = extractor.marker_patch(rgb, x, y)
            if patch.shape == (extractor.PATCH_HEIGHT, extractor.PATCH_WIDTH):
                training.append(patch.astype(np.uint8))
            if len(training) >= 600:
                break
    template = extractor.build_template(training)

    peaks_by_page = {str(page): [] for page in range(4, 608)}
    all_peaks = []
    for page in range(4, 608):
        peaks, _ = extractor.template_recoveries(page, template, [])
        for peak in peaks:
            peak['page'] = page
            all_peaks.append(peak)
        peaks_by_page[str(page)] = peaks
        if page % 50 == 0:
            print(f'...template page {page}', flush=True)

    for threshold in (0.48, 0.50, 0.51, 0.52, 0.53, 0.54, 0.55):
        print(
            f'correlation >= {threshold:.2f}: '
            f'{sum(1 for peak in all_peaks if peak["correlation"] >= threshold)}'
        )

    # 0.50 is the clean corpus-wide cut: 6,235 genuine floral markers and no
    # calligraphy matches. Add the single source-image-verified joined marker.
    selected_by_page = {
        str(page): [
            peak
            for peak in peaks_by_page[str(page)]
            if peak['correlation'] >= 0.50
        ]
        for page in range(4, 608)
    }
    for page, candidate in MANUAL_CONFIRMED.items():
        selected_by_page[str(page)].append(dict(candidate))
    count = sum(len(rows) for rows in selected_by_page.values())
    ayahs = extractor.canonical_ayahs()
    if count != len(ayahs):
        raise SystemExit(
            f'0.50 template threshold plus verified exceptions yielded {count}, '
            f'expected {len(ayahs)}'
        )

    output = {}
    cursor = 0
    selected_diagnostics = []
    for page in range(4, 608):
        rows = selected_by_page[str(page)]
        rows.sort(key=lambda candidate: reading_key(page, candidate))
        output[str(page)] = []
        for candidate in rows:
            surah, ayah = ayahs[cursor]
            cursor += 1
            output[str(page)].append(
                [surah, ayah, candidate['x'], candidate['y'], 41, 53]
            )
            selected_diagnostics.append(
                [page, candidate['x'], candidate['y'], round(candidate['correlation'], 4)]
            )

    with open(PEAK_PATH, 'w', encoding='utf-8') as file:
        json.dump(selected_diagnostics, file, separators=(',', ':'))
    with open(RAW_PATH, 'w', encoding='utf-8') as file:
        json.dump(output, file, separators=(',', ':'))
    print(f'wrote {RAW_PATH}; markers={cursor}, threshold=0.50')


if __name__ == '__main__':
    main()
