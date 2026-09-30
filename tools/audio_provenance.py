#!/usr/bin/env python3
"""Check that every shipped sound is the GNU FreeDink file it claims to be.

Usage:
    python3 tools/audio_provenance.py                 # check game/assets/sound
    python3 tools/audio_provenance.py --sound-dir DIR # check another folder

The table of record is licenses/AUDIO-FILES.tsv: one row per shipped file,
with its SHA-256, the FreeDink file it comes from (freedink-data
1.08.20190120, Sound/), that file's SHA-256, the in-repo source copy, the
license and the credit.

FreeDink leaves 27 effect files silent (GAP_FILLS). Those are filled by
tools/build_sfx.py, and their rows say freedink_file "-". Such a row passes only
for a name in GAP_FILLS, with a license from FILL_LICENSES, source_in_repo
tools/build_sfx.py, and source_sha256 either "-" (synthesized) or the pinned
hashes of the downloads it was built from, each one a source build_sfx.py pins.
A fill must be mono 16-bit PCM WAV. The shipped hash is still pinned, so an
original v1.08 file under a fill's name fails. The check fails on any file missing from the table,
any hash mismatch, a copied file that differs from its FreeDink source, a
sounds.json entry the table does not cover, or a music file that is
effectively empty (a failed MIDI render). If the FreeDink data package is
installed (/usr/share/games/dink/dink/Sound, or --freedink), the source
hashes are also checked against it.

Provenance: written 2026-09-30 for the FreeDink audio swap
(docs/AUDIO_FREEDINK_SWAP.md). Verdict: works. It passes the 39 shipped FreeDink
files, flags 87 of the 88 files in a folder rebuilt from the original v1.08
sounds (only secret.wav, which both sets share, passes), and flags the silent
pre-fix 104.ogg render. Extended the same day for the 27 gap fills; the v1.08
folder still fails on every one of them (sha256 differs).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLE = ROOT / "licenses" / "AUDIO-FILES.tsv"
FREEDINK_SOUND = Path("/usr/share/games/dink/dink/Sound")
COLUMNS = ["file", "cue", "freedink_file", "source_in_repo", "sha256", "source_sha256", "license", "credit"]
MIN_MUSIC_SECONDS = 1.0  # A failed FluidSynth render is ~0 s; shipped music is 26 s or longer.
# The original v1.08 effects that FreeDink has no free replacement for
# (docs/AUDIO_FREEDINK_SWAP.md). Only these names may ship as non-FreeDink files.
GAP_FILLS = frozenset({
    "attack1.wav", "caveent.wav", "drag1.wav", "drag2.wav", "escape.wav", "flyby.wav",
    "hurt1.wav", "hurt2.wav", "knock.wav", "level.wav", "picker.wav", "pig1.wav",
    "pig2.wav", "pig3.wav", "pig4.wav", "quack.wav", "sel2.wav", "sel3.wav",
    "select.wav", "snarl1.wav", "snarl2.wav", "snarl3.wav", "spell1.wav", "splash.wav",
    "squish.wav", "steps.wav", "sword1.wav",
})
FILL_BUILDER = "tools/build_sfx.py"
# Licenses a fill may carry: free, compatible with the audio already shipped, and
# attributable per file. A fill built from several sources lists each, joined by " AND ".
FILL_LICENSES = frozenset({"CC0-1.0", "public domain", "Apache-2.0", "CC-BY-3.0", "CC-BY-4.0",
                           "CC-BY-SA-3.0", "CC-BY-SA-4.0"})


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_table(path: Path = TABLE) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        cells = line.split("\t")
        if cells == COLUMNS:
            continue
        if len(cells) != len(COLUMNS):
            raise ValueError(f"{path.name}: expected {len(COLUMNS)} columns: {line[:60]}")
        rows.append(dict(zip(COLUMNS, cells)))
    return rows


def ogg_vorbis_seconds(data: bytes) -> float:
    """Duration from the Vorbis identification header and the last page's granule."""
    ident = data.find(b"\x01vorbis")
    last = data.rfind(b"OggS")
    if ident < 0 or last < 0 or ident + 16 > len(data) or last + 14 > len(data):
        raise ValueError("not an Ogg Vorbis stream")
    rate = struct.unpack_from("<I", data, ident + 12)[0]
    granule = struct.unpack_from("<q", data, last + 6)[0]
    if rate <= 0:
        raise ValueError("Vorbis sample rate is zero")
    return max(granule, 0) / rate


def wav_data_bytes(data: bytes) -> int:
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos = 12
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack_from("<I", data, pos + 4)[0]
        if cid == b"data":
            return min(size, len(data) - pos - 8)
        pos += 8 + size + (size & 1)
    raise ValueError("WAVE file has no data chunk")


def pinned_fill_sources() -> set[str]:
    """SHA-256 of every download tools/build_sfx.py pins, read from its source text."""
    import re
    text = (ROOT / FILL_BUILDER).read_text(encoding="utf-8")
    return set(re.findall(r'"([0-9a-f]{64})"', text))


def wav_format(data: bytes) -> tuple[int, int, int]:
    """(format tag, channels, bits per sample) from the fmt chunk."""
    pos = 12
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack_from("<I", data, pos + 4)[0]
        if cid == b"fmt ":
            tag, channels = struct.unpack_from("<HH", data, pos + 8)
            bits = struct.unpack_from("<H", data, pos + 22)[0]
            return tag, channels, bits
        pos += 8 + size + (size & 1)
    raise ValueError("WAVE file has no fmt chunk")


def fill_problems(row: dict, data: bytes, pinned: set[str]) -> list[str]:
    name, out = row["file"], []
    if name not in GAP_FILLS:
        out.append(f"{name}: not a FreeDink file and not one of the FreeDink gaps")
    parts = [p.strip() for p in row["license"].split(" AND ")]
    bad = [p for p in parts if p not in FILL_LICENSES]
    if bad:
        out.append(f"{name}: license {bad} is not an allowed fill license")
    if row["source_in_repo"] != FILL_BUILDER or not (ROOT / FILL_BUILDER).is_file():
        out.append(f"{name}: a fill must name {FILL_BUILDER} as its source")
    hashes = row["source_sha256"].split()
    if hashes != ["-"]:
        unpinned = [h for h in hashes if h not in pinned]
        if unpinned:
            out.append(f"{name}: source hashes not pinned in {FILL_BUILDER}: {unpinned}")
        if "http" not in row["credit"]:
            out.append(f"{name}: a sourced fill's credit must give the source URL")
    elif parts != ["Apache-2.0"]:
        out.append(f"{name}: a fill with no downloaded source must be our own work (Apache-2.0)")
    try:
        if wav_format(data) != (1, 1, 16):
            out.append(f"{name}: a fill must be mono 16-bit PCM WAV, got {wav_format(data)}")
    except ValueError as exc:
        out.append(f"{name}: {exc}")
    return out


def verify(sound_dir: Path = ROOT / "game" / "assets" / "sound", table: Path = TABLE,
           manifest: Path | None = ROOT / "game" / "data" / "sounds.json",
           freedink: Path | None = FREEDINK_SOUND) -> list[str]:
    problems: list[str] = []
    rows = {row["file"]: row for row in read_table(table)}
    shipped = sorted(p for p in sound_dir.iterdir() if p.is_file() and p.suffix != ".import")
    shipped_names = {p.name for p in shipped}
    for name in sorted(shipped_names - rows.keys()):
        problems.append(f"{name}: shipped but not in {table.name} (not a known FreeDink file)")
    for name in sorted(rows.keys() - shipped_names):
        problems.append(f"{name}: listed in {table.name} but not shipped")
    fd_index = {}
    pinned = pinned_fill_sources() if any(r["freedink_file"] == "-" for r in rows.values()) else set()
    if freedink is not None and freedink.is_dir():
        fd_index = {p.name.lower(): p for p in freedink.iterdir() if p.is_file()}
    for path in shipped:
        row = rows.get(path.name)
        if row is None:
            continue
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != row["sha256"]:
            problems.append(f"{path.name}: sha256 differs from {table.name}")
        if row["freedink_file"] == "-":
            problems.extend(fill_problems(row, data, pinned))
            try:
                if wav_data_bytes(data) <= 0:
                    problems.append(f"{path.name}: WAVE data chunk is empty")
            except ValueError as exc:
                problems.append(f"{path.name}: {exc}")
            continue
        copied = not row["freedink_file"].lower().endswith((".mid", ".midi"))
        if copied and row["sha256"] != row["source_sha256"]:
            problems.append(f"{path.name}: copied file is not byte-identical to FreeDink {row['freedink_file']}")
        if row["source_in_repo"]:
            src = ROOT / row["source_in_repo"]
            if not src.is_file():
                problems.append(f"{path.name}: source copy missing: {row['source_in_repo']}")
            elif sha256(src) != row["source_sha256"]:
                problems.append(f"{path.name}: source copy differs from FreeDink {row['freedink_file']}")
        if fd_index:
            fd = fd_index.get(Path(row["freedink_file"]).name.lower())
            if fd is None:
                problems.append(f"{path.name}: {row['freedink_file']} not in installed FreeDink data")
            elif sha256(fd) != row["source_sha256"]:
                problems.append(f"{path.name}: installed FreeDink {row['freedink_file']} has a different hash")
        try:
            if path.suffix.lower() == ".ogg":
                seconds = ogg_vorbis_seconds(data)
                if seconds < MIN_MUSIC_SECONDS:
                    problems.append(f"{path.name}: {seconds:.4f} s of audio; the render is empty")
            elif path.suffix.lower() == ".wav" and wav_data_bytes(data) <= 0:
                problems.append(f"{path.name}: WAVE data chunk is empty")
        except ValueError as exc:
            problems.append(f"{path.name}: {exc}")
    if manifest is not None and manifest.is_file():
        sounds = json.loads(manifest.read_text())
        for kind in ("music", "effects"):
            for cue, entry in sounds.get(kind, {}).items():
                name = Path(entry["path"]).name
                row = rows.get(name)
                if row is None:
                    problems.append(f"sounds.json {kind}/{cue}: {name} not in {table.name}")
                elif entry.get("source", "").lower() != row["freedink_file"].lower():
                    problems.append(f"sounds.json {kind}/{cue}: source {entry.get('source')} != {row['freedink_file']}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sound-dir", type=Path, default=ROOT / "game" / "assets" / "sound")
    ap.add_argument("--table", type=Path, default=TABLE)
    ap.add_argument("--manifest", type=Path, default=ROOT / "game" / "data" / "sounds.json")
    ap.add_argument("--freedink", type=Path, default=FREEDINK_SOUND)
    a = ap.parse_args()
    problems = verify(a.sound_dir, a.table, a.manifest, a.freedink)
    rows = read_table(a.table)
    checked = "and installed FreeDink data" if a.freedink.is_dir() else "(FreeDink data not installed)"
    if problems:
        print(f"AUDIO PROVENANCE FAIL: {len(problems)} problem(s) in {a.sound_dir}")
        for p in problems:
            print("  " + p)
        return 1
    print(f"AUDIO PROVENANCE PASS: {len(rows)} files match {a.table.name} {checked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
