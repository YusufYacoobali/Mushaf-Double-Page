"""
Build the Indo-Pak per-page ayah map asset from the scraped QUL layout, and
validate it against the app's existing ground-truth surah->page ranges.

Input:   tool/qul_layout_raw.json     (QUL page -> ["surah:ayah", ...])
Output:  assets/arabic-text/indopak_page_map.json
            { "<appLogicalPage>": [[surah, firstAyah, lastAyah], ...], ... }

Page numbering:
  QUL page 1 == Al-Fatiha == app logical page 4 (pages 1-3 are cover screens),
  so  app_logical_page = qul_page + PAGE_OFFSET  with PAGE_OFFSET = 3.
  This is verified below against indopakSurahRanges in surah_mapper.dart.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(__file__)
RAW = os.path.join(HERE, "qul_layout_raw.json")
OUT = os.path.join(HERE, "..", "assets", "arabic-text", "indopak_page_map.json")
SURAH_MAPPER = os.path.join(HERE, "..", "lib", "utils", "surah_mapper.dart")

PAGE_OFFSET = 3
TOTAL_QUL_PAGES = 847

# Canonical ayah count per surah (1..114) — used for coverage validation.
AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
    111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
    54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
    49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30,
    20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4,
    5, 6,
]


def parse_groundtruth_starts():
    """Parse indopakSurahRanges -> {surah: start_page} from the dart source."""
    text = open(SURAH_MAPPER, encoding="utf-8").read()
    block = text.split("indopakSurahRanges", 1)[1]
    block = block.split("madaniSurahRanges", 1)[0]
    starts = {}
    ends = {}
    for m in re.finditer(r"SurahRange\((\d+),\s*(\d+),\s*(\d+),", block):
        surah, start, end = int(m.group(1)), int(m.group(2)), int(m.group(3))
        starts[surah] = start
        ends[surah] = end
    return starts, ends


def main():
    if not os.path.exists(RAW):
        sys.exit(f"Missing {RAW}; run fetch_qul_layout.py first.")

    raw = json.load(open(RAW, encoding="utf-8"))

    # qul page -> list of (surah, ayah)
    pages = {}
    for p_str, keys in raw.items():
        p = int(p_str)
        pairs = []
        for k in keys:
            s, a = k.split(":")
            pairs.append((int(s), int(a)))
        pages[p] = sorted(set(pairs))

    # Build app-page -> segments [[surah, first, last], ...]
    out = {}
    first_appearance = {}  # (surah, ayah) -> min app page
    all_ayahs_seen = set()
    for p in range(1, TOTAL_QUL_PAGES + 1):
        pairs = pages.get(p, [])
        app_page = p + PAGE_OFFSET
        by_surah = {}
        for (s, a) in pairs:
            by_surah.setdefault(s, []).append(a)
            all_ayahs_seen.add((s, a))
            key = (s, a)
            if key not in first_appearance:
                first_appearance[key] = app_page
            else:
                first_appearance[key] = min(first_appearance[key], app_page)
        segments = []
        for s in sorted(by_surah):
            ayahs = by_surah[s]
            segments.append([s, min(ayahs), max(ayahs)])
        out[str(app_page)] = segments

    # ---- Validation -------------------------------------------------------
    problems = []

    # 1. Surah-start pages must match the ground-truth ranges (page where S:1
    #    first appears == indopakSurahRanges start).
    gt_starts, gt_ends = parse_groundtruth_starts()
    start_mismatch = []
    for s in range(1, 115):
        want = gt_starts.get(s)
        got = first_appearance.get((s, 1))
        if got != want:
            start_mismatch.append((s, want, got))
    if start_mismatch:
        problems.append(f"{len(start_mismatch)} surah-start mismatches: " +
                        ", ".join(f"S{s}: want {w} got {g}" for s, w, g in start_mismatch[:12]) +
                        (" ..." if len(start_mismatch) > 12 else ""))

    # 2. Full ayah coverage: every (surah, ayah) must appear on some page.
    missing = []
    for s in range(1, 115):
        for a in range(1, AYAH_COUNTS[s - 1] + 1):
            if (s, a) not in all_ayahs_seen:
                missing.append(f"{s}:{a}")
    if missing:
        problems.append(f"{len(missing)} ayahs missing from layout: {missing[:20]}" +
                        (" ..." if len(missing) > 20 else ""))

    # 3. Total ayah count sanity.
    total = sum(AYAH_COUNTS)
    if len(all_ayahs_seen) != total:
        problems.append(f"distinct ayah count {len(all_ayahs_seen)} != expected {total}")

    # 4. Contiguity: each content page should continue where the previous ended
    #    (first ayah of page N is the same as, or the successor of, last ayah of N-1).
    content_pages = sorted(int(k) for k in out if out[k])
    flat_index = {}
    idx = 0
    for s in range(1, 115):
        for a in range(1, AYAH_COUNTS[s - 1] + 1):
            flat_index[(s, a)] = idx
            idx += 1
    gap_errors = []
    prev_last = None
    for ap in content_pages:
        segs = out[str(ap)]
        first = (segs[0][0], segs[0][1])
        last = (segs[-1][0], segs[-1][2])
        if prev_last is not None:
            # first of this page should be prev_last (straddling ayah) or prev_last+1
            if flat_index[first] not in (flat_index[prev_last], flat_index[prev_last] + 1):
                gap_errors.append((ap, prev_last, first))
        prev_last = last
    if gap_errors:
        problems.append(f"{len(gap_errors)} page-contiguity gaps: " +
                        ", ".join(f"p{ap}: prev {pl} -> {fr}" for ap, pl, fr in gap_errors[:10]))

    # ---- Report -----------------------------------------------------------
    print("=" * 60)
    print(f"QUL pages parsed     : {len(raw)}")
    print(f"Content app-pages    : {len(content_pages)}  (range {content_pages[0]}..{content_pages[-1]})")
    print(f"Distinct ayahs       : {len(all_ayahs_seen)} (expected {total})")
    print(f"Surah-start matches  : {114 - len(start_mismatch)}/114")
    print("=" * 60)
    if problems:
        print("VALIDATION PROBLEMS:")
        for p in problems:
            print("  - " + p)
        print("=" * 60)
        print("NOT writing asset until validation is clean (or differences are understood).")
        # Still write to a .candidate file for inspection.
        cand = OUT + ".candidate"
        json.dump(out, open(cand, "w", encoding="utf-8"), ensure_ascii=False)
        print(f"Wrote candidate for inspection: {cand}")
        sys.exit(2)

    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False,
              separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"VALIDATION CLEAN. Wrote {OUT} ({size/1024:.1f} KB)")


if __name__ == "__main__":
    main()
