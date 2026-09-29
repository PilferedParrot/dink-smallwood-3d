#!/usr/bin/env python3
"""Recover 3D house blocks from original Dink building sprites (docs/DIRECTION.md, "Buildings").

The original buildings are pre-rendered from one raised camera. With the prototype's
1:1 ground (source pixel = ground unit), that camera is the oblique projection
    screen = (X, Z - Y)                      # X east, Z south, Y up, all in source px
i.e. an orthographic view 45 degrees down, stretched sqrt(2) vertically. Every house
sprite is fitted with the same model, so the mechanism travels to any house sprite:

  * footprint: the two wall-base lines at the bottom of the silhouette (least squares);
    the ground plane is 1:1, so the base lines ARE the footprint (a parallelogram);
  * wall height, eave overhang and roof pitch: grid + coordinate search maximising the
    agreement of a rendered label map (stone walls / thatch roof / air) with the
    sprite's own pixels classified the same way;
  * hip roof with equal pitch on all sides; stacked blocks for two-tier houses;
  * roof PITCH is read from the art, not fitted: the label map cannot see the ridge
    (score is flat in pitch), and two automatic criteria failed on 2026-09-29 -- pooled
    within-plane luminance variance degenerates to the lowest pitch, and gradient
    alignment along the projected creases is swamped by the thatch texture. The pitch
    table below was read from overlays of the projected hip/ridge lines on each sprite
    (sheet: tmp/facades/pitch.png); all land at 42-48 degrees, a normal thatch pitch.

The Godot prototype builds the meshes from the JSON this writes and textures them by
projecting the sprite back through the same camera (UV = (X, Z - Y), exact on planes).

Usage: /usr/bin/python3 tools/facade_fit.py [--out game/prototype/facades.json] [--sheet DIR]
Verdict (2026-09-29, Opus 5.5): works for seq 63 frames 1, 4, 6, 8; see the sheet for IoU.
"""
from __future__ import annotations
import argparse, colorsys, json, math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
# (seq, frame, number of stacked blocks, roof pitch per block as rise/run, read from the art)
# Optional fixed params by index. home-04's free fit put a 28 px skirt eave that stands
# out as wings beyond the drawn silhouette; the three single houses from the same kit
# all fit a 10 px eave, so its skirt is held to that.
HOUSES = [(63, 1, 1, [0.9], {}), (63, 4, 2, [0.8, 1.1], {1: 10.0}), (63, 6, 1, [1.1], {}), (63, 8, 1, [1.1], {})]


def classify(rgba: np.ndarray) -> np.ndarray:
    """0 air (incl. black shadow dither), 1 stone, 2 thatch."""
    h, w = rgba.shape[:2]
    lab = np.zeros((h, w), np.uint8)
    for y in range(h):
        for x in range(w):
            r, g, b, a = (int(v) for v in rgba[y, x])
            if a < 128 or r + g + b < 40:
                continue
            hue, sat, val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            lab[y, x] = 2 if sat > 0.45 and 0.03 < hue < 0.2 else 1
    return lab


def base_lines(lab: np.ndarray):
    body = lab > 0
    w = body.shape[1]
    bot = np.array([np.nonzero(body[:, x])[0].max() if body[:, x].any() else -1 for x in range(w)])
    xs = np.nonzero(bot >= 0)[0]
    xf = xs[np.argmax(bot[xs])]
    left = np.polyfit(np.arange(xs.min() + 15, xf - 5), bot[xs.min() + 15:xf - 5], 1)
    right = np.polyfit(np.arange(xf + 5, xs.max() - 15), bot[xf + 5:xs.max() - 15], 1)
    on_l = [x for x in range(0, xf) if abs(bot[x] - np.polyval(left, x)) < 3]
    on_r = [x for x in range(xf, w) if abs(bot[x] - np.polyval(right, x)) < 3]
    fx = (right[1] - left[1]) / (left[0] - right[0])
    F = np.array([fx, np.polyval(left, fx)])
    L = np.array([min(on_l), np.polyval(left, min(on_l))])
    R = np.array([max(on_r), np.polyval(right, max(on_r))])
    return F, L, R


def block_faces(F, L, R, y0, hw, o, pitch, block=0):
    """Faces as lists of 3D points (X, Y, Z) with a label. Ground point (x, z) = sprite (x, y)."""
    u, v = R - F, L - F
    if np.linalg.norm(v) > np.linalg.norm(u):  # u = long axis
        u, v = v, u
    a, b = np.linalg.norm(u), np.linalg.norm(v)
    uh, vh = u / a, v / b
    sin = abs(uh[0] * vh[1] - uh[1] * vh[0])
    corners = [F, F + u, F + u + v, F + v]
    faces = []
    for i in range(4):
        p, q = corners[i], corners[(i + 1) % 4]
        faces.append((1, [(p[0], y0, p[1]), (q[0], y0, q[1]), (q[0], y0 + hw, q[1]), (p[0], y0 + hw, p[1])], block))
    # Eave: offset each edge outward by o (perpendicular), i.e. corners move o/sin along the edges.
    d = o / max(sin, 1e-3)
    E = [F - d * uh - d * vh, F + u + d * uh - d * vh, F + u + v + d * uh + d * vh, F + v - d * uh + d * vh]
    A, B = a + 2 * d, b + 2 * d
    ye = y0 + hw
    rise = pitch * (B / 2) * sin
    half = B / 2
    P0 = E[0] + half * vh + min(half, A / 2) * uh
    P1 = E[0] + half * vh + max(A - half, A / 2) * uh
    yr = ye + rise
    e3 = [(e[0], ye, e[1]) for e in E]
    p0, p1 = (P0[0], yr, P0[1]), (P1[0], yr, P1[1])
    faces.append((2, [e3[0], e3[1], p1, p0], block))      # long side at F
    faces.append((2, [e3[1], e3[2], p1], block))          # hip
    faces.append((2, [e3[2], e3[3], p0, p1], block))      # far long side
    faces.append((2, [e3[3], e3[0], p0], block))          # hip
    return faces


def block_center(faces, block):
    walls = [p for lab, pts, b in faces if b == block and lab == 1 for p in pts]
    xs, ys, zs = zip(*walls)
    return [round(float(np.mean(xs)), 2), round(float(np.mean(ys)), 2), round(float(np.mean(zs)), 2)]


def house_faces(F, L, R, params, blocks):
    faces = block_faces(F, L, R, 0.0, *params[:3])
    if blocks == 2:
        s, h2, o2, p2 = params[3:7]
        C = (L + R) / 2
        k = max(0.2, 1 - s)
        faces += block_faces(C + (F - C) * k, C + (L - C) * k, C + (R - C) * k, params[0], h2, o2, p2, 1)
    return faces


def render(faces, shape) -> np.ndarray:
    im = Image.new('L', (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    # Painter's order along the view ray (0, 1, 1): larger Y + Z is nearer the camera.
    for label, pts, _ in sorted(faces, key=lambda f: np.mean([p[1] + p[2] for p in f[1]])):
        d.polygon([(p[0], p[2] - p[1]) for p in pts], fill=label)
    return np.array(im)


def score(pred, lab):
    s = 0.0
    for c in (1, 2):
        i = np.logical_and(pred == c, lab == c).sum()
        u = np.logical_or(pred == c, lab == c).sum()
        s += i / max(u, 1)
    return s / 2


def fit(lab, blocks, fixed=None):
    fixed = fixed or {}
    F, L, R = base_lines(lab)
    grids = [np.arange(20, 130, 4), np.arange(0, 30, 2), np.arange(0.3, 1.8, 0.1)]
    if blocks == 2:
        grids += [np.arange(0.05, 0.6, 0.05), np.arange(20, 130, 4), np.arange(0, 30, 2), np.arange(0.3, 1.8, 0.1)]
        best = [40.0, 10.0, 0.5, 0.25, 50.0, 10.0, 0.8]
    else:
        best = [60.0, 8.0, 0.8]
    # Coordinate descent from several wall heights; it has local optima (a tall lower
    # wall can absorb a skirt roof), so keep the best of the starts.
    top, top_s = None, -1.0
    for h0 in (40.0, 60.0, 80.0, 100.0):
        cur = [h0] + best[1:]
        for i, v in fixed.items():
            cur[i] = v
        cur_s = score(render(house_faces(F, L, R, cur, blocks), lab.shape), lab)
        for _ in range(4):
            for i, g in enumerate(grids):
                if i in fixed:
                    continue
                for val in g:
                    trial = list(cur)
                    trial[i] = float(val)
                    s = score(render(house_faces(F, L, R, trial, blocks), lab.shape), lab)
                    if s > cur_s:
                        cur, cur_s = trial, s
        if cur_s > top_s:
            top, top_s = cur, cur_s
    return F, L, R, top, top_s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/prototype/facades.json'))
    ap.add_argument('--sheet', default=str(ROOT / 'tmp/facades'))
    args = ap.parse_args()
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    out = {}
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    for seq, frame, blocks, pitches, fixed in HOUSES:
        fr = seqs[str(seq)]['frames'][frame - 1]
        rgba = np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA'))
        lab = classify(rgba)
        F, L, R, p, s = fit(lab, blocks, fixed)
        p[2] = pitches[0]
        if blocks == 2:
            p[6] = pitches[1]
        faces = house_faces(F, L, R, p, blocks)
        out[fr['path']] = {
            'score': round(s, 3),
            'faces': [{'label': lab_, 'block': blk, 'pts': [[round(float(c), 2) for c in pt] for pt in pts]} for lab_, pts, blk in faces],
            # Per block: footprint centre (x, z) and the height of its wall mid-line, for
            # orienting normals and mirroring faces the original camera never saw.
            'centers': [block_center(faces, b) for b in range(blocks)],
            'overhangs': [p[1]] + ([p[5]] if blocks == 2 else []),
            'params': [round(x, 3) for x in p], 'F': F.round(2).tolist(), 'L': L.round(2).tolist(), 'R': R.round(2).tolist(),
        }
        pred = render(faces, lab.shape)
        pal = np.array([[255, 0, 255], [120, 120, 110], [220, 170, 60]], np.uint8)
        bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
        bg.alpha_composite(Image.fromarray(rgba))
        over = bg.copy()
        d = ImageDraw.Draw(over)
        for _, pts, _ in faces:
            d.polygon([(pt[0], pt[2] - pt[1]) for pt in pts], outline=(0, 255, 255, 255))
        row = [bg, Image.fromarray(pal[lab]).convert('RGBA'), Image.fromarray(pal[pred]).convert('RGBA'), over]
        sheet = Image.new('RGBA', (sum(r.width for r in row) + 30, row[0].height), (20, 20, 20, 255))
        x = 0
        for r in row:
            sheet.paste(r, (x, 0)); x += r.width + 10
        sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
        sheet.save(Path(args.sheet) / f'fit-{seq}-{frame}.png')
        print(fr['path'], 'score %.3f' % s, 'params', [round(x, 2) for x in p])
    Path(args.out).write_text(json.dumps(out, indent=1))


if __name__ == '__main__':
    main()
