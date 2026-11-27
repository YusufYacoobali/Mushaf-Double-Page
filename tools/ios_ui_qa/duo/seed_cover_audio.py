"""Seed only the nine original Alafasy ayahs on QA page six."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from zipfile import ZipFile

slug = 'mishari-alafasy-128kbps'
revision = 'cf6f004bfb5fa24017db479d39676a4a908f518a'
base = 'https://github.com/Abdalla-Eldoumani/maqra'
folder = Path(sys.argv[1]) / 'audio/alafasy'
folder.mkdir(parents=True, exist_ok=True)
curl = ['curl', '-fLsS', '--retry', '2', '--max-time', '150']
manifest = json.loads(subprocess.check_output(curl + [
    f'https://raw.githubusercontent.com/Abdalla-Eldoumani/maqra/{revision}/manifests/audio/{slug}.json']))
with tempfile.TemporaryDirectory() as tmp:
    archive = Path(tmp) / '002.zip'
    subprocess.run(curl + [f'{base}/releases/download/{slug}/002.zip', '-o', str(archive)], check=True)
    with ZipFile(archive) as source:
        for ayah in range(5, 14):
            name = f'002{ayah:03}.mp3'
            row, = (r for r in manifest['files'] if r[0] == name)
            data = source.read(name)
            digest = hashlib.sha256(data).hexdigest()
            assert digest == row[3] and row[4] == 'upstream-match' and hashlib.md5(data).hexdigest() == row[2], name
            (folder / name).write_bytes(data)
            print(name, digest)
