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
    verified = sorted(folder.glob("*.verification.json"))
    previous_names = {
        name.removesuffix(".layout.json") for name in archive.namelist()
        if "/" not in name and name.endswith(".layout.json")
        and name.replace(".layout.json", ".verification.json") in archive.namelist()
    }
    compared = set()
    for verification in verified:
        name = verification.name.removesuffix(".verification.json")
        previous = name.replace("duo-folded-max-100-idle", "duo-folded-max-100-collapsed")
        old = json.loads(archive.read(previous + ".layout.json"))
        new = json.loads((folder / (name + ".layout.json")).read_text())
        compared.add(previous)
        keys = ["viewport", "pixelRatio", "focusedPage", "pages", "zoom", "readingBounds",
                "padding", "viewPadding", "mode", "sizing", "regions", "safeRegions"]
        if not name.startswith("duo-folded-"):
            keys += ["navigationExpanded", "navigation", "controls"]
        for key in keys:
            assert old[key] == new[key], f"{folder}/{name}: {key} changed"
        with Image.open(io.BytesIO(archive.read(previous + ".png"))) as a, Image.open(folder / (name + ".png")) as b:
            a, b = (ImageOps.exif_transpose(i).convert("RGB") for i in (a, b))
            assert a.size == b.size, f"{name}: screenshot dimensions changed"
            diff = ImageChops.difference(a, b)
            red, green, blue = diff.split()
            histogram = ImageChops.lighter(ImageChops.lighter(red, green), blue).histogram()
            percent = 100 * histogram[0] / sum(histogram)
            print(f"{folder}/{name}: {percent:.3f}% identical pixels, page frames match")

    assert compared == previous_names, (
        f"{folder}: missing {previous_names - compared}, unexpected {compared - previous_names}"
    )
    print(f"Compared all {len(compared)} verified endpoints in {folder}")


if __name__ == "__main__":
    requests = Path(sys.argv[1]).read_text().splitlines()
    baseline = next((line for line in reversed(requests) if line.startswith("Compare screenshots ")), None)
    if baseline:
        for mapping in baseline.removeprefix("Compare screenshots ").split():
            directory, artifact_id = mapping.split("=")
            endpoint = f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/artifacts/{int(artifact_id)}/zip"
            archive = subprocess.check_output(["gh", "api", endpoint])
            folder = Path(directory)
            assert list(folder.glob("*.verification.json")), f"{folder}: no verified screenshots"
            with ZipFile(io.BytesIO(archive)) as zip_file:
                compare(folder, zip_file)
