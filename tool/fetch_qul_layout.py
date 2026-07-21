"""
Fetch the QUL "Indopak 13 lines (Taj company)" mushaf layout (resource 313)
and extract, per page, the list of verse keys (surah:ayah) that appear on it.

Source: https://qul.tarteel.ai/resources/mushaf-layout/313
Each word in the rendered layout carries a `data-ayah="surah:ayah"` attribute,
so the set of verse keys on a page is exactly the ayahs printed on that physical
page of the Taj 13-line Indo-Pak mushaf.

Output: tool/qul_layout_raw.json  ->  { "<qul_page>": ["2:20", "2:21", ...], ... }

This is a one-time build step. Pages are cached as raw HTML under CACHE_DIR so
re-runs are cheap and resumable. Politeness: limited concurrency + backoff.
"""

import os
import re
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = "https://qul.tarteel.ai/resources/mushaf-layout/313?page={}"
TOTAL_PAGES = 847
CACHE_DIR = os.environ.get("QUL_CACHE", "/tmp/qul_pages")
OUT_JSON = os.path.join(os.path.dirname(__file__), "qul_layout_raw.json")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")

VERSE_KEY_RE = re.compile(rb'data-ayah="(\d+):(\d+)"')

os.makedirs(CACHE_DIR, exist_ok=True)


def fetch_one(page):
    """Download a single page to cache (resumable). Returns (page, ok)."""
    path = os.path.join(CACHE_DIR, f"{page}.html")
    if os.path.exists(path) and os.path.getsize(path) > 5000:
        return page, True
    req = urllib.request.Request(BASE.format(page), headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if len(data) < 5000:
                raise ValueError(f"suspiciously small response ({len(data)} bytes)")
            with open(path, "wb") as f:
                f.write(data)
            return page, True
        except Exception as e:  # noqa: BLE001 - one-time build script
            wait = 1.5 * (attempt + 1)
            print(f"  page {page} attempt {attempt + 1} failed: {e} (retry in {wait}s)", flush=True)
            time.sleep(wait)
    return page, False


def parse_one(page):
    """Extract sorted unique verse keys from a cached page."""
    path = os.path.join(CACHE_DIR, f"{page}.html")
    with open(path, "rb") as f:
        html = f.read()
    keys = {(int(s), int(a)) for s, a in VERSE_KEY_RE.findall(html)}
    return sorted(keys)


def main():
    print(f"Fetching {TOTAL_PAGES} QUL layout pages -> {CACHE_DIR}", flush=True)
    fails = []
    done = 0
    with ThreadPoolExecutor(max_workers=6) as ex:
        futures = {ex.submit(fetch_one, p): p for p in range(1, TOTAL_PAGES + 1)}
        for fut in as_completed(futures):
            page, ok = fut.result()
            done += 1
            if not ok:
                fails.append(page)
            if done % 50 == 0:
                print(f"  {done}/{TOTAL_PAGES} fetched ({len(fails)} failed)", flush=True)

    if fails:
        print(f"FAILED pages: {sorted(fails)}", flush=True)
        raise SystemExit(1)

    print("All pages fetched. Parsing verse keys...", flush=True)
    result = {}
    empty = []
    for p in range(1, TOTAL_PAGES + 1):
        keys = parse_one(p)
        if not keys:
            empty.append(p)
        result[str(p)] = [f"{s}:{a}" for s, a in keys]

    if empty:
        print(f"WARNING: pages with no verse keys: {empty}", flush=True)

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)
    print(f"Wrote {OUT_JSON} ({len(result)} pages)", flush=True)


if __name__ == "__main__":
    main()
