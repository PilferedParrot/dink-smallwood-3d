#!/usr/bin/env python3
"""Mean |RGB| of a render through the original camera against the original's picture of a screen, the picture drawn as the
original draws it: tools/facade_contact_sheet.reference() ignores a sprite's clip_rect (the map's "alt" rectangle, which trims
the image: game.gd's 2D path honours it), which the pigpen's two gate pieces use (407: fence-01 at (526, 144) cut to its left 65
columns, at (126, 359) to its right 57). Also the mean over the pixels within 5 px of the picture's fences.

    /usr/bin/python3 tools/fence_original_diff.py SCREEN render.png [render.png ...]

Verdict (2026-10-07, Sonnet 5.5, solid-fences unit): works; the 0.3.0 package and this build on 407 are in docs/DIRECTION.md,
"Solid fences". Needs numpy, scipy and PIL.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]


def reference(n: int) -> Image.Image:
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    im = Image.new("RGBA", (640, 400), (0, 0, 0, 255))
    sc = world["screens"][str(n)]
    for i, t in enumerate(sc["tiles"][:96]):
        k = t["tile"]
        cell = k % 128
        sheet = ROOT / f"game/assets/tiles/ts{k // 128 + 1:02}.png"
        if sheet.exists():
            tile = Image.open(sheet).convert("RGBA").crop(((cell % 12) * 50, (cell // 12) * 50, (cell % 12 + 1) * 50, (cell // 12 + 1) * 50))
            im.paste(tile, (20 + i % 12 * 50, i // 12 * 50))
    for e in sorted(sc["sprites"], key=lambda e: -10000 + e["y"] if e["type"] == 0 else e["que"] or e["y"]):
        if e["vision"] != 0 or e["type"] == 2:
            continue
        fs = seqs.get(str(e["seq"]), {}).get("frames", [])
        if not fs or not 0 < e["frame"] <= len(fs):
            continue
        f = fs[e["frame"] - 1]
        k = e["size"] / 100
        p = Image.open(ROOT / "game" / f["path"]).convert("RGBA")
        left, top, right, bottom = e["clip_rect"]
        ox, oy = 0, 0
        if right > 0 or bottom > 0:  # the alt rectangle trims the image, which keeps its place
            p = p.crop((left, top, right, bottom))
            ox, oy = left, top
        p = p.resize((max(1, int(p.width * k)), max(1, int(p.height * k))))
        im.alpha_composite(p, (int(e["x"] - f["dx"] * k + ox * k), int(e["y"] - f["dy"] * k + oy * k)))
    return im.crop((20, 0, 620, 400)).convert("RGB")


def main():
    screen = int(sys.argv[1])
    ref = np.array(reference(screen)).astype(int)
    r, g, b = ref[..., 0], ref[..., 1], ref[..., 2]
    wood = (((r > g + 12) & (r > b + 30) & (ref.sum(-1) > 120)) | (ref.sum(-1) < 60)) & (r < 200)
    near = ndi.binary_dilation(wood, iterations=5)
    for path in sys.argv[2:]:
        o = np.array(Image.open(path).convert("RGB").resize((600, 400))).astype(int)
        e = np.abs(o - ref).sum(-1) / 3.0
        print("%s: all %.2f, near the picture's wood %.2f, elsewhere %.2f" % (path, e.mean(), e[near].mean(), e[~near].mean()))


if __name__ == "__main__":
    main()
