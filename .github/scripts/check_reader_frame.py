#!/usr/bin/env python3
"""Reject notification alerts and blank frames in the fixed Indo-Pak page-4 QA.

The colored printed border must be present above the toolbar. This supplements
the app's mode/page/zoom metadata and never replaces visual inspection.
"""
import json
from PIL import Image
import sys

im = Image.open(sys.argv[1]).convert('RGB')
corner = im.getpixel((0, 0))
modal = max(corner) - min(corner) < 5 and 180 <= min(corner) <= 230
sample = im.crop((0, 0, im.width, int(im.height * .75)))
sample.thumbnail((240, 240))
pixels = list(sample.getdata())
colored = sum(max(p) - min(p) > 25 and max(p) > 60 for p in pixels) / len(pixels)
print(json.dumps({'notification_alert': modal, 'printed_page_color_fraction': colored,
                  'width': im.width, 'height': im.height}))
raise SystemExit(2 if modal else 0 if colored > .01 else 1)
