#!/usr/bin/env python3
"""Reverify and combine twenty actual Samsung-dimension Android AVD captures."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from verify_android_foldable_capture import verify


PROFILES = [
    ('galaxy-z-fold8', 'Galaxy Z Fold8 · Passport shape'),
    ('galaxy-z-fold8-ultra', 'Galaxy Z Fold8 Ultra · Regular shape'),
]
GROUPS = [
    ('Folded portrait', 'folded', [('min-70', 70, '70%'), ('max-100', 100, '100%'),
                                  ('max-100-collapsed', 100, '100% · arrow')]),
    ('Unfolded portrait', 'unfolded-portrait', [('min-70', 70, '70%'), ('max-100', 100, '100%')]),
    ('Unfolded landscape', 'unfolded-landscape', [('min-60', 60, '60%'), ('max-100', 100, '100% · top'),
                                               ('max-100-bottom', 100, '100% · bottom')]),
    ('Half-open book', 'half-open-book', [('min-60', 60, '60%'), ('max-100', 100, '100%')]),
]


def verified_captures(source):
    captures = {}
    for profile, _ in PROFILES:
        folder = source / profile
        declaration = json.loads((folder / 'profile.json').read_text())
        assert declaration['profileId'] == profile
        assert declaration['emulation']['kind'] == 'samsung-dimensions-stock-android'
        assert declaration['emulation']['oneUi'] is False
        assert declaration['emulation']['realSamsungDevice'] is False
        for _, posture, cases in GROUPS:
            for suffix, zoom, _ in cases:
                path = folder / f'{posture}-{suffix}'
                phase = 'collapsed' if suffix.endswith('collapsed') else 'bottom' if suffix.endswith('bottom') else 'initial'
                before_suffix = 'max-100' if phase != 'initial' else cases[0][0] if zoom == 100 else None
                before = (folder / f'{posture}-{before_suffix}.layout.json') if before_suffix else None
                state = json.loads(Path(str(path) + '-state.json').read_text())
                assert state['profileMetadata'] == declaration, 'capture profile does not match declared AVD'
                verify(str(path) + '.png', str(path) + '.layout.json', zoom, posture,
                       state=state, phase=phase, before=before, expected_page=6, profile=profile)
                captures[(profile, posture, suffix)] = Path(str(path) + '.png')
    assert len(captures) == 20, 'both Samsung profiles need all ten verified original frames'
    return captures


def render(source, output):
    captures = verified_captures(source)
    # Original images are only resized proportionally. Light-grey tile padding
    # is outside the screenshot; genuine black bars remain visible as captured.
    width, height = 6400, 6010
    sheet = Image.new('RGB', (width, height), '#e9edf2')
    draw = ImageDraw.Draw(sheet)
    fonts = {size: ImageFont.truetype('DejaVuSans.ttf', size) for size in (34, 40, 48, 58, 70)}
    draw.text((70, 48), 'Mushaf v6 · Samsung foldable layouts · Pages 6–7', font=fonts[70], fill='#17202b')
    draw.text((70, 142), '20 original Android emulator captures · Samsung screen dimensions · Stock Android, not One UI',
              font=fonts[34], fill='#526171')

    def group(profile, title, posture, cases, x, y, group_width, image_height):
        draw.rounded_rectangle((x, y, x + group_width, y + image_height + 180), radius=25,
                               fill='white', outline='#d6dee7', width=2)
        draw.text((x + 28, y + 18), title, font=fonts[48], fill='#17202b')
        gap, inset = 24, 26
        tile_width = (group_width - 2 * inset - gap * (len(cases) - 1)) // len(cases)
        for i, (suffix, zoom, label) in enumerate(cases):
            left = x + inset + i * (tile_width + gap)
            draw.rounded_rectangle((left, y + 86, left + tile_width, y + 142), radius=12,
                                   fill='#e1f2eb' if zoom == 100 else '#edf1f5')
            draw.text((left + tile_width / 2, y + 114), label, anchor='mm', font=fonts[40],
                      fill='#16624b' if zoom == 100 else '#586777')
            top = y + 158
            draw.rectangle((left, top, left + tile_width, top + image_height), fill='#f2f4f7')
            with Image.open(captures[(profile, posture, suffix)]) as original:
                thumb = ImageOps.exif_transpose(original).convert('RGB')
            thumb.thumbnail((tile_width - 4, image_height - 4), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (round(left + (tile_width - thumb.width) / 2),
                               round(top + (image_height - thumb.height) / 2)))

    for index, (profile, title) in enumerate(PROFILES):
        section = 240 + index * 2830
        draw.text((70, section), title, font=fonts[58], fill='#17202b')
        for i, (label, posture, cases) in enumerate(GROUPS):
            first = i % 2 == 0
            x = 70 if first else 3860
            group_width = 3750 if first else 2470
            y = section + 90 if i < 2 else section + 1590
            group(profile, label, posture, cases, x, y, group_width, 1280 if i < 2 else 990)
    draw.text((width / 2, height - 70),
              'Original screenshots scaled proportionally · Insets and unused aspect-ratio space remain visible · Navigation overlays pages',
              anchor='mm', font=fonts[34], fill='#526171')
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    print(json.dumps({'verified_captures': 20, 'output': str(output), 'pixels': [width, height]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    render(args.source, args.output)


if __name__ == '__main__':
    main()
