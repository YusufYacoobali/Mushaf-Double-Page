#!/usr/bin/env python3
"""Compare every real simulator iPad capture with the same v5 device/zoom."""
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops, ImageDraw

root, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
results = []
for family in ['mini', 'ipad', 'air11', 'air13', 'pro11', 'pro13']:
    for orientation, minimum in [('portrait', 70), ('landscape', 60)]:
        rows = []
        for percent in range(minimum, 101, 5):
            name = f'ipad-{family}-{orientation}-{percent}.png'
            paths = []
            for version in ['v5', 'v6']:
                matches = list(root.glob(f'quran-ipad-{family}-{version}*/{name}'))
                paths.append(matches[0] if matches else root / 'missing' / name)
            if not all(p.exists() for p in paths):
                results.append({'capture': name, 'error': 'Missing screenshot', 'pass': False})
                continue
            before, after = [Image.open(p).convert('RGB') for p in paths]
            if before.size != after.size:
                results.append({'capture': name, 'error': 'Different viewport size', 'pass': False})
                continue
            diff = ImageChops.difference(before, after)
            # Ignore subpixel antialiasing noise, but report every material
            # changed pixel. Stills remain the evidence for visual inspection.
            changed = sum(max(pixel) > 8 for pixel in diff.getdata())
            fraction = changed / (before.width * before.height)
            results.append({'capture': name, 'changed_fraction': fraction, 'pass': fraction < .001})
            row = Image.new('RGB', (680, 300), '#ddd8cd')
            draw = ImageDraw.Draw(row)
            for i, (label, picture) in enumerate([('v5', before), ('v6', after)]):
                picture.thumbnail((330, 265))
                row.paste(picture, (i * 340 + (340 - picture.width) // 2, 30))
                draw.text((i * 340 + 12, 8), f'{label} {percent}%', fill='black')
            rows.append(row)
        if rows:
            sheet = Image.new('RGB', (680, len(rows) * 300))
            for i, row in enumerate(rows):
                sheet.paste(row, (0, i * 300))
            sheet.save(output / f'ipad-{family}-{orientation}-v5-v6.jpg', quality=90)
(output / 'comparison.json').write_text(json.dumps(results, indent=2) + '\n')
failed = [result for result in results if not result['pass']]
print(f"Compared {len(results)} screenshots; {len(failed)} require inspection")
for result in failed:
    print(result)
if failed:
    raise SystemExit(1)
