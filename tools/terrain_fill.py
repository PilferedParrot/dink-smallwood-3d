#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Solid bodies behind terrain rims: the pixels the original's hard rims enclose.

hard.dat draws a boulder or a rock band as a 1-3 px rim. Stood as columns, the rim alone is a ragged
shell: edge-on it reads as a picket fence. The body behind it is licensed by the art (raised-class tiles,
tools/terrain_tile_classes.py) and by enclosure: a non-hard 4-connected region of the screen that holds no
floor-class pixel at all is not part of the walkable floor, so the rim encloses it and no player can be in it.
Fill = those regions' raised-class pixels. They are drawn, never collided: the player meets the same
collision as before.

Usage: python3 tools/terrain_fill.py --write     # game/data/terrain_fill.json (screen -> [x, y, w, h] rects, source px)
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game/data/terrain_fill.json"
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from terrain_columns import _effective_hard, raised_tiles, X_ORIGIN


def fill_mask(world: dict, footprints: dict, screen: int, raised: set[int] | None = None) -> np.ndarray:
    """Boolean [400, 600] (x rebased to 0): the enclosed raised-class pixels of an interior screen."""
    src = world["screens"][str(screen)]
    raised = raised_tiles() if raised is None else raised
    hard = _effective_hard(world, footprints, screen)
    if not hard.any():
        return np.zeros_like(hard)  # nothing stands here to enclose anything
    tile = np.repeat(np.repeat(np.array([int(t["tile"]) for t in src["tiles"][:96]]).reshape(8, 12), 50, 0), 50, 1)
    is_raised = np.isin(tile, list(raised))
    labels, count = ndimage.label(~hard)
    out = np.zeros_like(hard)
    for i in range(1, count + 1):
        region = labels == i
        if (region & ~is_raised).any():
            continue  # holds floor-class art: walkable floor
        out |= region & is_raised
    return out


def rects(mask: np.ndarray) -> list[list[int]]:
    """Row spans merged vertically where equal; source px [x, y, w, h]."""
    result: list[list[int]] = []
    previous: dict[tuple[int, int], int] = {}
    for y in range(mask.shape[0]):
        row = np.pad(mask[y].astype(np.int8), (1, 1))
        edges = np.flatnonzero(np.diff(row))
        current = {}
        for a, b in zip(edges[::2], edges[1::2]):
            span = (int(a), int(b))
            if span in previous:
                index = previous[span]
                result[index][3] += 1
            else:
                index = len(result)
                result.append([span[0] + X_ORIGIN, y, span[1] - span[0], 1])
            current[span] = index
        previous = current
    return result


def build(world: dict, footprints: dict) -> dict:
    out = {}
    for key, screen in world["screens"].items():
        if screen.get("indoor"):
            mask = fill_mask(world, footprints, int(key))
            if mask.any():
                out[key] = rects(mask)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    world = json.loads((ROOT / "game/data/world.json").read_text())
    footprints = json.loads((ROOT / "game/data/footprints.json").read_text())["screens"]
    data = build(world, footprints)
    print({k: len(v) for k, v in data.items()}, sum(len(v) for v in data.values()), "rects")
    if args.write:
        OUT.write_text(json.dumps({"schema": "terrain-fill-1", "screens": data}, separators=(",", ":"), sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
