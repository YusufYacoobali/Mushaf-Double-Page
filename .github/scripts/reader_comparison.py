"""Make a labelled contact sheet of the verified original simulator frames."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

rows = [
    (
        "Folded portrait",
        "duo-folded",
        ("min-70", "70%"),
        ("max-100", "100%"),
        ("max-100-idle", "100% · after 11 s idle"),
    ),
    ("Unfolded portrait", "duo-unfolded-portrait", ("min-70", "70%"), ("max-100", "100%")),
    (
        "Unfolded landscape",
        "duo-unfolded-wide",
        ("min-60", "60%"),
        ("max-100", "100% · top"),
        ("max-100-bottom", "100% · bottom"),
    ),
    ("Half-open book", "duo-half-open-book", ("min-60", "60%"), ("max-100", "100%")),
    ("iPad mini", "ipad-mini", ("portrait", "portrait · 100%"), ("landscape", "landscape · 100%")),
]
cell_width, cell_height = 460, 392
sheet = Image.new("RGB", (3 * cell_width, len(rows) * cell_height), "#f1eee8")
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype("DejaVuSans.ttf", 18)
for row, (label, prefix, *cases) in enumerate(rows):
    folder = Path("screenshots-ipad" if prefix == "ipad-mini" else "screenshots")
    for column, (suffix, caption) in enumerate(cases):
        png = folder / f"{prefix}-{suffix}.png"
        assert png.with_suffix(".verification.json").is_file()
        with Image.open(png) as original:
            thumb = ImageOps.exif_transpose(original).convert("RGB")
        thumb.thumbnail((cell_width - 20, cell_height - 44), Image.Resampling.LANCZOS)
        x = column * cell_width + (cell_width - thumb.width) // 2
        y = row * cell_height
        sheet.paste(thumb, (x, y + 34))
        draw.text(
            (column * cell_width + cell_width // 2, y + 16),
            f"{label} · {caption}",
            anchor="mm",
            font=font,
            fill="#242924",
        )
sheet.save("reader-comparison.png")
