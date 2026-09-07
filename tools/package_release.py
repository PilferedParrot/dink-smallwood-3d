#!/usr/bin/env python3
"""Package executables with their notices and corresponding audio source."""
from pathlib import Path
import hashlib
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    output = ROOT / 'builds'
    archives = []
    for platform, executable in [('linux', 'DinkSmallwood3D.x86_64'), ('windows', 'DinkSmallwood3D.exe')]:
        folder = output / platform
        if not (folder / executable).is_file():
            raise SystemExit(f'Build missing: {folder / executable}')
        for name in ['LICENSE', 'NOTICE', 'README.md']:
            shutil.copy2(ROOT / name, folder / name)
        for name in ['licenses', 'third_party', 'docs']:
            if (ROOT / name).is_dir():
                shutil.copytree(ROOT / name, folder / name, dirs_exist_ok=True)
        archive = output / f'dink-smallwood-3d-0.1.0-{platform}-x86_64.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for path in sorted(folder.rglob('*')):
                if path.is_file(): z.write(path, Path('DinkSmallwood3D') / path.relative_to(folder))
        archives.append(archive)
    (output / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in archives))
    for archive in archives: print(archive)


if __name__ == '__main__':
    main()
