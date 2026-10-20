#!/usr/bin/env python3
"""G1 for the well (docs/DIRECTION.md, "P4d: the well"): the BUILT solid, rendered alone through the sprite's own camera by
tests/fps_well_g1.gd, measured by the same instrument as the sprite (landmark_fit.roof_edges), beside the sprite's own numbers.

    /usr/bin/python3 tools/well_g1.py <render dir> [--label NAME] [--json out.json]

The render (magenta background) is resampled onto the sprite's pixel grid (the registration is the capture's g1.json:
x = target_x + (col - W/2)/sx, row = (cz - 55) + (r - H/2)/(sx cos(theta))), its roof mesh (roof.png) is a mask, and roof_edges reads
that mask exactly as it reads the sprite's roof: a pitch in the picture is the rake's slope, a flat slab's rake has slope k tan(psi).
Pre-registered before the first measurement (the tolerances and why):
  T1 rake slope (dy/dx) of the built roof within 0.15 of the sprite's (1.44): the picture's edge sd is 0.4 px over 20 rows, a slope
     error of 0.05; a flat slab's rake is 0.56 and fails by 0.88.
  T2 prism gap <= 3 px: the far rake's corner D - BC lands on the ridge line (the sprite: 1.8 px; a flat slab's: about 20 px).
  T3 apparent pitch rise / run within 0.10 of the sprite's measured 0.62 (the spread over k 0.49-0.56 is 0.62-0.76: the tolerance is
     the edge measurement's, not the choice of k).
  IoU of the built roof's silhouette with the sprite's roof mask is REPORTED, not gated: the flat slab's best fit (0.84) beats the
  edge-derived gable (0.80) because the roof mask lacks the thin sliver of the ridge's overhang and includes a post's knob, so the
  silhouette alone cannot tell the two apart (the brief's expected look-alike).
Verdict (2026-10-20, Sonnet 5.5): see docs/DIRECTION.md.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import landmark_fit as L  # noqa: E402
import prop_fit as P  # noqa: E402

ROOT = L.ROOT


def to_sprite(png: Path, g: dict, shape) -> np.ndarray:
    img = np.array(Image.open(png).convert('RGB')).astype(int)
    H, W = img.shape[:2]
    live = ~((img[..., 0] > 240) & (img[..., 1] < 20) & (img[..., 2] > 240))  # not the magenta background
    sx = W / g['width_px']
    th = g['theta']
    ys, xs = np.mgrid[0:shape[0], 0:shape[1]]
    acc = np.zeros(shape)
    sub = 3
    for dy in range(sub):
        for dx in range(sub):
            x = xs + (dx + 0.5) / sub - 0.5
            y = ys + (dy + 0.5) / sub - 0.5
            c = np.round((x - g['target'][0]) * sx + W / 2 - 0.5).astype(int)
            r = np.round((y - (g['cz'] - g['target'][1])) * sx * np.cos(th) + H / 2 - 0.5).astype(int)
            ok = (c >= 0) & (c < W) & (r >= 0) & (r < H)
            acc += np.where(ok, live[np.clip(r, 0, H - 1), np.clip(c, 0, W - 1)], 0)
    return acc / (sub * sub) >= 0.5


def measure(mask: np.ndarray) -> dict:
    E = L.roof_edges(mask, None)
    return {'k': E['k'], 'psi_deg': float(np.degrees(E['psi'])), 'slope_ridge': E['slope_ridge'], 'slope_eave': E['slope_eave'],
            'rake_slope': E['rake_slope'], 'flat_rake_slope': E['flat_rake_slope'], 'w': E['w'], 'rise': E['rise'],
            'apparent_pitch': E['rise'] / E['w'], 'length': E['length'], 'prism_gap': E['prism_gap']}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--label', default='')
    ap.add_argument('--json')
    a = ap.parse_args()
    d = Path(a.dir)
    g = json.loads((d / 'g1.json').read_text())
    rgba = P.load('assets/graphics/struct/Landmark/landm-01.png')
    body, roof, base, posts, warm = L.segment(rgba)
    built_roof = to_sprite(d / 'roof.png', g, roof.shape)
    built_all = to_sprite(d / 'all.png', g, roof.shape)
    out = {'label': a.label, 'sprite': measure(roof)}
    try:
        out['built'] = measure(built_roof)
    except Exception as e:  # a flat slab has no rake to read: say so
        out['built'] = {'error': repr(e)}
    iou = lambda p, q: float((p & q).sum() / max(1, (p | q).sum()))
    out['roof_iou_vs_sprite_roof'] = iou(built_roof, roof)
    out['whole_iou_vs_sprite_body'] = iou(built_all, body)
    s, b = out['sprite'], out['built']
    if 'rake_slope' in b:
        out['T1_rake'] = {'built': b['rake_slope'], 'sprite': s['rake_slope'], 'pass': abs(b['rake_slope'] - s['rake_slope']) <= 0.15}
        out['T2_prism'] = {'built': b['prism_gap'], 'pass': b['prism_gap'] <= 3.0}
        out['T3_pitch'] = {'built': b['apparent_pitch'], 'sprite': s['apparent_pitch'], 'pass': abs(b['apparent_pitch'] - s['apparent_pitch']) <= 0.10}
    print(json.dumps(out, indent=1))
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=1))
    Image.fromarray(np.dstack([built_roof * 255, roof * 255, np.zeros(roof.shape)]).astype(np.uint8)).resize(
        (roof.shape[1] * 5, roof.shape[0] * 5), Image.NEAREST).save(d / 'roof-overlay.png')  # red: built only, green: sprite only, yellow: both


if __name__ == '__main__':
    main()
