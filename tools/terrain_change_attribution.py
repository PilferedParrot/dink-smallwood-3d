#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Attribute changed original-camera frames to the terrain they show, from the terrain ALONE, old against new.

Usage: terrain_change_attribution.py BEFORE_DIR AFTER_DIR TERRAIN_OLD_DIR TERRAIN_NEW_DIR OUT.json

TERRAIN_*_DIR hold NAME.png renders of the terrain boxes alone, with their own materials, in the scene's own light (tests/terrain_delta_capture.gd
--textured), from the old and the new tree, in the frames' camera and resize. The claim for a frame is the pixels where those two
terrain-only pictures differ (dilated by two output pixels: the resize filter's tails round to white or to the same value in the
terrain-only pictures). The earlier test claimed the projected bounds of every terrain box, which covered 97.8% of screen 98 and
90.8% of 100: containment, not cause. Here a change to a floor, sprite or wall seen through a gap, or any pixel the terrain's own
picture did not change, is outside the claim. Each frame carries its unclaimed-pixel negative control.
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def rgb(path):
    return np.asarray(Image.open(path).convert("RGB"))


def attribute(before_dir, after_dir, old_dir, new_dir):
    frames = []
    for path in sorted(Path(new_dir).glob("*.png"), key=lambda p: int(p.stem)):
        name = path.stem
        a, b = rgb(Path(before_dir) / f"{name}.png"), rgb(Path(after_dir) / f"{name}.png")
        moved = np.any(rgb(Path(old_dir) / f"{name}.png") != rgb(path), axis=2)
        allowed = ndi.binary_dilation(moved, structure=np.ones((7, 7), bool))
        changed = np.any(a != b, axis=2)
        outside = int((changed & ~allowed).sum())
        # A wholly unrelated pixel must fail the same rule: flip one that is neither claimed nor changed.
        free = np.argwhere(~allowed & ~changed)
        assert free.size, ("no unclaimed negative-control pixel", name)
        y, x = free[len(free) // 2]
        control = changed.copy()
        control[y, x] = True
        control_outside = int((control & ~allowed).sum())
        assert control_outside == outside + 1
        frames.append({
            "screen": int(name),
            "changed_pixels": int(changed.sum()),
            "outside_terrain_change": outside,
            "allowed_pixels": int(allowed.sum()),
            "allowed_fraction": round(float(allowed.mean()), 4),
            "negative_control_outside": control_outside,
            "before_rgb_sha256": hashlib.sha256(a.tobytes()).hexdigest(),
            "after_rgb_sha256": hashlib.sha256(b.tobytes()).hexdigest(),
        })
    return frames


if __name__ == "__main__":
    before, after, old_terrain, new_terrain, out = sys.argv[1:6]
    frames = attribute(before, after, old_terrain, new_terrain)
    record = {
        "baseline": "918551f",
        "filter": "terrain boxes alone with their own materials, old tree against new, original camera, same Lanczos resize; claimed = where those two pictures differ, dilated 7x7 (the Lanczos3 support, three output pixels); the unclaimed negative control must still fail",
        "different_frames": sum(f["changed_pixels"] > 0 for f in frames),
        "changed_pixels": sum(f["changed_pixels"] for f in frames),
        "outside_terrain_change": sum(f["outside_terrain_change"] for f in frames),
        "frames": frames,
    }
    Path(out).write_text(json.dumps(record, indent=1) + "\n")
    print({k: v for k, v in record.items() if k != "frames"})
    for f in frames:
        print(f["screen"], f["changed_pixels"], f["outside_terrain_change"], f["allowed_fraction"])
    raise SystemExit(bool(record["outside_terrain_change"]))
