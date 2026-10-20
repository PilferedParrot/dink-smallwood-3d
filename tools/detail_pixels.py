"""Partial source-pixel evidence for raised Details art.

Shadow extraction follows the pre-existing facade_fit.is_dither convention.
No asset name, sequence, authored label or world metadata enters measure().
Rule1 is a partial cue detector, with known outline-dither false positives.
A negative result means undecidable, never proof of a ground surface.
"""
from __future__ import annotations

import json
from pathlib import Path
import numpy as np
from PIL import Image


def measure(rgba: np.ndarray) -> dict:
    opaque = rgba[..., 3] >= 128
    black = opaque & (rgba[..., :3].astype(int).sum(-1) < 10)
    adjacent = np.zeros_like(black)
    adjacent[1:] |= black[:-1]
    adjacent[:-1] |= black[1:]
    adjacent[:, 1:] |= black[:, :-1]
    adjacent[:, :-1] |= black[:, 1:]
    shadow = black & ~adjacent
    body = opaque & ~shadow
    ys, xs = np.nonzero(body)
    sy, sx = np.nonzero(shadow)
    if not len(xs):
        return {"class": "undecidable", "reason": "no measurable body"}
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    width, height = x1-x0+1, y1-y0+1
    below = 0
    for y, x in zip(sy, sx):
        column = np.flatnonzero(body[:, x])
        if len(column) and y > column[-1]:
            below += 1
    count = len(sx)
    base_fraction = below/count if count else 0.0
    lower = bool(count and sy.mean() > ys.mean())
    raised = count >= 4 and base_fraction >= .5 and lower and min(width, height) >= 2
    return {"class": "upright_cue" if raised else "undecidable", "body_bbox": [x0,y0,width,height],
            "body_pixels": len(xs), "body_fill": len(xs)/(width*height), "body_aspect": width/height,
            "shadow_pixels": count, "below_body_shadow_pixels": below,
            "base_shadow_fraction": base_fraction,
            "shadow_body_centroid_delta_y": float(sy.mean()-ys.mean()) if count else None}


def inspect(path: Path) -> dict:
    return measure(np.asarray(Image.open(path).convert("RGBA")))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    print(json.dumps({p.name: inspect(p) for p in sorted((root/"game/assets/graphics/lands/Details").glob("*.png"))}, indent=2))
