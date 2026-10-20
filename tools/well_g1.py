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
Round 2 (finding 2 of the blind review: T1-T3 are a roof-shape discriminator, not a picture match, and the save machine had none).
G1 now also registers the WHOLE built object against its sprite under the original projection, for the well and the save machine. The
tolerance is stated here, before the round-2 numbers were measured, and derived from the sprite itself, not from the build:
  R1 whole silhouette: IoU(built, sprite body) >= the IoU the sprite has with ITSELF moved by a band of b = 2 px (the worse of its
     2 px dilation and its 2 px erosion). Why 2 px: the sprite's own black outline is 2 px, the capture is resampled to the sprite grid
     (3x3 supersampled, +-0.5 px) and the fit's rim and roof edges are fitted to a boundary the outline blurs. The bound is the shape's own
     (a long thin object tolerates less), so it is not one number for both objects.
  R2 each part of the well (roof, stone base, the posts): the share of the sprite part's pixels the built silhouette covers >= 1 minus the
     share of the part within b px of its own boundary (the most a b px boundary error can uncover): b = 2, and 1 for the posts (four px
     wide: a 2 px band erodes them away and the floor would be 0). The posts count only where they stand against the background (the
     union silhouette cannot see a post misplaced over the roof or the stone). A roof above a missing base or post fails its part.
The sprite body is the sprite's opaque pixels without the shadow's dither (the solid draws no shadow).
Look-alike controls, measured by the same code on the same render: the wrong landmark's sprite as the reference (the well's solid against
the save machine's body and the reverse), the well mirrored about its axis (the reference mirrored), and the old flat-slab well (rendered
from the fit before the pitch: it keeps T1/T3 as its discriminator; R1 and R2 do not claim to separate a pitch).
Verdict (2026-10-20, Sonnet 5.5): see docs/DIRECTION.md.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import landmark_fit as L  # noqa: E402
import prop_fit as P  # noqa: E402

ROOT = L.ROOT


def to_sprite(png: Path, g: dict, shape) -> np.ndarray:
    shape = tuple(shape)
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


BAND = 2  # px: the registration band (R1, R2)


def _disc(r: int) -> np.ndarray:
    return np.hypot(*np.mgrid[-r:r + 1, -r:r + 1]) <= r


def iou(p: np.ndarray, q: np.ndarray) -> float:
    return float((p & q).sum() / max(1, (p | q).sum()))


def sprite_body(rgba: np.ndarray) -> np.ndarray:
    return (rgba[..., 3] >= 128) & ~L.F.is_dither(rgba)


def iou_floor(mask: np.ndarray) -> float:
    """R1's bound: the sprite's IoU with itself shifted by BAND px at the boundary (the worse of dilated and eroded)."""
    return min(iou(mask, ndimage.binary_dilation(mask, _disc(BAND))), iou(mask, ndimage.binary_erosion(mask, _disc(BAND))))


def cover_floor(region: np.ndarray, band: int = BAND) -> float:
    """R2's bound: the share of a part the built silhouette must cover, 1 - the share within `band` px of its own boundary."""
    return 1.0 - float((region & ~ndimage.binary_erosion(region, _disc(band))).sum() / max(1, region.sum()))


def mirror(mask: np.ndarray, cx: float) -> np.ndarray:
    """The mask mirrored about the vertical axis at column cx (sprite px)."""
    out = np.zeros_like(mask)
    xs = np.arange(mask.shape[1])
    src = np.round(2 * cx - 1 - xs).astype(int)
    ok = (src >= 0) & (src < mask.shape[1])
    out[:, xs[ok]] = mask[:, src[ok]]
    return out


def registration(built_all: np.ndarray, rgba: np.ndarray, cx: float, well: bool) -> dict:
    """R1 and R2 for one object, with the controls' numbers beside them (the controls are references, not builds: the same measure)."""
    body = sprite_body(rgba)
    out = {'R1': {'iou': iou(built_all, body), 'floor': iou_floor(body)}}
    out['R1']['pass'] = out['R1']['iou'] >= out['R1']['floor']
    out['mirrored_iou'] = iou(built_all, mirror(body, cx))
    if well:
        _, roof, base, posts, _ = L.segment(rgba)
        post_px = np.zeros_like(body)
        for p in posts[:2]:
            post_px[p['top']:p['foot'], p['x0']:p['x1']] = True
        out['R2'] = {}
        # The posts are four px wide: a 2 px band erodes them away (a floor of 0 could never fail), so their band is 1 px, and only the part
        # of them that stands against the background counts (not over the roof or the stone, where the union silhouette hides a misplaced post).
        for name, region, band in (('roof', roof, BAND), ('base', base & ~post_px, BAND), ('posts', post_px & ~roof & ~base, 1)):
            cov = float((built_all & region).sum() / max(1, region.sum()))
            mcov = float((built_all & mirror(region, cx)).sum() / max(1, region.sum()))
            out['R2'][name] = {'cover': cov, 'floor': cover_floor(region, band), 'pass': cov >= cover_floor(region, band), 'mirrored_cover': mcov, 'band': band, 'n': int(region.sum())}
    return out


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
    ap.add_argument('--target', default='well', choices=['well', 'save'])
    a = ap.parse_args()
    d = Path(a.dir)
    g = json.loads((d / 'g1.json').read_text())
    out = run(d, g, a.target, a.label)
    print(json.dumps(out, indent=1))
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=1))


def run(d: Path, g: dict, target: str, label: str = '') -> dict:
    well = target == 'well'
    rgba = P.load(g['path'])
    other = P.load('assets/graphics/inter/save/save-01.png' if well else 'assets/graphics/struct/Landmark/landm-01.png')
    out = {'label': label, 'target': target, 'path': g['path']}
    built_all = to_sprite(d / 'all.png', g, rgba.shape[:2])
    out.update(registration(built_all, rgba, g['cx'], well))
    # the wrong landmark's sprite as the reference, drawn on the same canvas (centred on the same axis) so the comparison is the same measure
    ob = sprite_body(other)
    canvas = np.zeros(rgba.shape[:2], bool)
    oy, ox = other.shape[0], other.shape[1]
    top, left = max(0, (rgba.shape[0] - oy) // 2), max(0, int(round(g['cx'])) - ox // 2)
    h, w = min(oy, canvas.shape[0] - top), min(ox, canvas.shape[1] - left)
    canvas[top:top + h, left:left + w] = ob[:h, :w]
    out['wrong_landmark_iou'] = iou(built_all, canvas)
    if not well:
        return out
    body, roof, base, posts, warm = L.segment(rgba)
    built_roof = to_sprite(d / 'roof.png', g, roof.shape)
    out['sprite'] = measure(roof)
    try:
        out['built'] = measure(built_roof)
    except Exception as e:  # a flat slab has no rake to read: say so
        out['built'] = {'error': repr(e)}
    out['roof_iou_vs_sprite_roof'] = iou(built_roof, roof)
    s, b = out['sprite'], out['built']
    if 'rake_slope' in b:
        out['T1_rake'] = {'built': b['rake_slope'], 'sprite': s['rake_slope'], 'pass': abs(b['rake_slope'] - s['rake_slope']) <= 0.15}
        out['T2_prism'] = {'built': b['prism_gap'], 'pass': b['prism_gap'] <= 3.0}
        out['T3_pitch'] = {'built': b['apparent_pitch'], 'sprite': s['apparent_pitch'], 'pass': abs(b['apparent_pitch'] - s['apparent_pitch']) <= 0.10}
    Image.fromarray(np.dstack([built_roof * 255, roof * 255, np.zeros(roof.shape)]).astype(np.uint8)).resize(
        (roof.shape[1] * 5, roof.shape[0] * 5), Image.NEAREST).save(d / 'roof-overlay.png')  # red: built only, green: sprite only, yellow: both
    return out


if __name__ == '__main__':
    main()
