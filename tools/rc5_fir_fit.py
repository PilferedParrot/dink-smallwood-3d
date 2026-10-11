#!/usr/bin/env python3
"""Measure source fir parts and the complete original fir for RC5.

Run with the project's Python environment. This reads source art only; it does
not decide scene ownership. fp_world.seam_parts makes that decision at runtime.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SEQUENCES = ROOT / "game/data/sequences.json"
OUTPUT = ROOT / "game/prototype/rc5_firs.json"
SCALE = 0.025


def measure(path: str, row0: int = 0, row1: int | None = None) -> dict:
    art = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
    if row1 is None:
        row1 = len(art)
    crop = art[row0:row1]
    # Exactly fp_world.sprite_foot's alpha and nonblack thresholds on 8-bit art.
    drawn = (crop[:, :, 3] > 127) & (crop[:, :, :3].astype(np.int32).sum(axis=2) >= 11)
    yy, xx = np.where(drawn)
    if not len(yy):
        raise ValueError(f"No nonblack crown pixels: {path} rows {row0}:{row1}")
    bottom = int(yy.max())
    foot_x = float(np.where(drawn[bottom])[0].mean() + 0.5)
    return {
        "rows": [row0, row1],
        "source_foot_px": [foot_x, bottom + 1],
        "crown_bbox_px": [int(xx.min()), int(yy.min()), int(xx.max() + 1), bottom + 1],
        "crown_height_px": bottom + 1 - int(yy.min()),
        "image_size_px": [int(crop.shape[1]), int(crop.shape[0])],
    }


def main() -> None:
    frames = json.loads(SEQUENCES.read_text())["sequences"]["32"]["frames"]
    template = frames[0]
    template_path = template["path"]
    whole = measure(template_path)
    parts: dict[str, list[dict]] = {}
    hashes = {"sequences.json": hashlib.sha256(SEQUENCES.read_bytes()).hexdigest()}
    for frame in (9, 10):
        source = frames[frame - 1]
        path = source["path"]
        art = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
        occupied = np.where((art[:, :, 3] > 127).any(axis=1))[0]
        breaks = np.where(np.diff(occupied) > 3)[0]
        if len(breaks) != 1:
            raise ValueError(f"Expected exactly two source crowns: {path}")
        cuts = [(int(occupied[0]), int(occupied[breaks[0]] + 1)),
                (int(occupied[breaks[0] + 1]), int(occupied[-1] + 1))]
        measured = []
        for row0, row1 in cuts:
            part = measure(path, row0, row1)
            part["source_foot_in_full_art_px"] = [part["source_foot_px"][0],
                                                  row0 + part["source_foot_px"][1]]
            part["uniform_scale"] = part["crown_height_px"] / whole["crown_height_px"]
            measured.append(part)
        parts[path] = measured
        hashes[path] = hashlib.sha256((ROOT / "game" / path).read_bytes()).hexdigest()
    hashes[template_path] = hashlib.sha256((ROOT / "game" / template_path).read_bytes()).hexdigest()
    output = {
        "schema": "rc5-whole-fir-fit-1",
        "method": "alpha>127 and RGB sum>=11; lowest row mean pixel center; crown height from nonblack y span",
        "world_units_per_source_px": SCALE,
        "template": {"path": template_path, "seq": 32, "frame": 1,
                     "frame_hotspot_px": [template["dx"], template["dy"]], **whole},
        "source_parts": parts,
        "source_sha256": hashes,
    }
    OUTPUT.write_text(json.dumps(output, indent=2) + "\n")
    print(f"Wrote {OUTPUT}; complete fir {template_path}, height {whole['crown_height_px']} px")


if __name__ == "__main__":
    main()
