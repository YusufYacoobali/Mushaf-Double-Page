# Ayah-region extraction

These pipelines derive per-ayah highlight rectangles from the exact page
images shipped by the app. They detect each ayah-ending marker, label it in
Quran reading order, then trace line rectangles from one marker to the next.

## Indo-Pak Taj 13-line mushaf

1. `extract_markers.py` -> `markers_raw.json`
2. `build_geometry.py` -> `ayah_rects_raw.json`
3. Compact output -> `assets/arabic-text/indopak_ayah_rects.json`

## Madani 1405H mushaf

1. `extract_madani_markers.py` builds initial floral-marker candidates.
2. `scan_madani_template_peaks.py` confirms the floral template across all
   604 pages and produces `madani_markers_raw.json`.
3. `../build_madani_page_map.py` validates all 6,236 ayahs and produces
   `assets/arabic-text/madani_page_map.json`.
4. `build_madani_geometry.py` detects each scan's text frame, line ink, and
   surah-header placement, then produces `madani_ayah_rects_raw.json` and
   `assets/arabic-text/madani_ayah_rects.json`.

The Madani detector uses a strict corpus-wide floral-template threshold. The
single joined marker at page 580 / ayah 75:12 is documented as a full-resolution
source-image-verified exception in `scan_madani_template_peaks.py`.
