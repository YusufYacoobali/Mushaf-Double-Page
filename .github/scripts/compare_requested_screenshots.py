"""Compare verified captures when a request names a previous original-frame artifact."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile

from PIL import Image, ImageChops, ImageOps


def compare(folder, archive):
    for verification in sorted(folder.glob("*.verification.json")):
        name = verification.name.removesuffix(".verification.json")
        previous = name.replace("duo-folded-max-100-idle", "duo-folded-max-100-collapsed")
        old = json.loads(archive.read(previous + ".layout.json"))
        new = json.loads((folder / (name + ".layout.json")).read_text())
        for key in ("viewport", "pixelRatio", "focusedPage", "pages", "zoom", "readingBounds"):
            assert old[key] == new[key], f"{folder}/{name}: {key} changed"
        with Image.open(io.BytesIO(archive.read(previous + ".png"))) as a, Image.open(folder / (name + ".png")) as b:
            a, b = (ImageOps.exif_transpose(i).convert("RGB") for i in (a, b))
            assert a.size == b.size, f"{name}: screenshot dimensions changed"
            diff = ImageChops.difference(a, b)
            red, green, blue = diff.split()
            histogram = ImageChops.lighter(ImageChops.lighter(red, green), blue).histogram()
            percent = 100 * histogram[0] / sum(histogram)
            print(f"{folder}/{name}: {percent:.3f}% identical pixels, page frames match")


if __name__ == "__main__":
    last = Path(sys.argv[1]).read_text().strip().splitlines()[-1]
    if last.startswith("Compare screenshots "):
        for mapping in last.removeprefix("Compare screenshots ").split():
            directory, artifact_id = mapping.split("=")
            endpoint = f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/artifacts/{int(artifact_id)}/zip"
            archive = subprocess.check_output(["gh", "api", endpoint])
            folder = Path(directory)
            assert list(folder.glob("*.verification.json")), f"{folder}: no verified screenshots"
            with ZipFile(io.BytesIO(archive)) as zip_file:
                compare(folder, zip_file)
