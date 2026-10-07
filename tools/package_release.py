#!/usr/bin/env python3
"""Package executables with their notices and corresponding audio source."""
from pathlib import Path
import hashlib
import re
import shutil
import zipfile

try:
    from audio_provenance import verify as verify_audio
except ImportError:  # imported as tools.package_release
    from tools.audio_provenance import verify as verify_audio

ROOT = Path(__file__).resolve().parents[1]


def version():
    """The release version, parsed from the project's own config/version."""
    text = (ROOT / 'game' / 'project.godot').read_text()
    return re.search(r'^config/version="([0-9]+\.[0-9]+\.[0-9]+)"', text, re.M).group(1)


def main():
    problems = verify_audio()
    if problems:
        raise SystemExit('Audio provenance check failed; see licenses/AUDIO-FILES.tsv:\n  ' + '\n  '.join(problems))
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
                ignored = shutil.ignore_patterns('NEXT_SESSION.md') if name == 'docs' else None
                shutil.copytree(ROOT / name, folder / name, dirs_exist_ok=True, ignore=ignored)
        # A prior package may have copied this internal handoff note. Keep it
        # out of regenerated archives even when packaging into an existing folder.
        (folder / 'docs' / 'NEXT_SESSION.md').unlink(missing_ok=True)
        archive = output / f'dink-smallwood-3d-{version()}-{platform}-x86_64.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for path in sorted(folder.rglob('*')):
                if path.is_file(): z.write(path, Path('DinkSmallwood3D') / path.relative_to(folder))
        archives.append(archive)
    (output / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in archives))
    for archive in archives: print(archive)


if __name__ == '__main__':
    main()
