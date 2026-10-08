#!/usr/bin/env python3
"""The house interior's solids (docs/DIRECTION.md, "The interior stands solid"): walls, the exit door, a round table, a bed.

The interior sprites (inside/innwalls, inside/details, struct/Details/Door) are pictures of 3D things taken by the original
camera: a point at ground (X, Z) and height Y is drawn at the sprite pixel (X, Z - Y) (the facades' projection), the ground
circle as an ellipse of aspect k. This reads each shape from its own pixels; nothing is fitted to one sprite by hand.

  wall    a span of wall (innwalls): its top face is the light cap above the first big luminance step (a row of the stone
          after a row of cap, ratio >= CAP_RATIO, in the first rows), its seen face is everything below; a frame with no
          such step (the piers, inn-23) is a top face seen end-on. Heights are in rows: the face's rows are its height.
  door    a door sprite (struct/Details/Door/odor1-01, Dink's own door on screen 439): the parallelogram its opaque pixels fill:
          columns c0..c1, a top line and a base line of one slope. The game maps it onto an upright rectangle (a shear removed).
  round   a top of revolution on legs (table-09): the plate's top edge is an ellipse (cx, c, r, k) fitted to the silhouette's
          top edge, its underside a second ellipse of the same aspect fitted to the columns without a leg, the legs the
          columns that hang below it; their feet lie on a ground ring (rho, cz) with the legs' angles read from the feet,
          and the unseen legs are the point reflections of the seen ones.
  bed     a box turned on its axis (inacc-03): the convex hull of the silhouette has six corners, the two vertical edges at
          its left and right ends are the box's height, the top and bottom corners with them fix the footprint.

Run: /usr/bin/python3 tools/interior_fit.py [--out game/data/interior.json] [--sheet tmp/interior]
Verdict (2026-10-07, Sonnet 5.5 subagent): works, deterministic; see the docstrings of each fit for what it is blind to.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy.optimize import least_squares

sys.path.insert(0, str(Path(__file__).resolve().parent))
import facade_fit as F  # noqa: E402

ROOT = F.ROOT
GRAPHICS = ROOT / 'game' / 'assets' / 'graphics'
CAP_RATIO = 1.2  # the mean luminance of the 3 rows above a step over the 4 rows below it: the caps measure 1.26 to 1.58, a column 1.04
CAP_ROWS = 40    # the cap is looked for in the first rows only


def rgba(path: str) -> np.ndarray:
    return np.array(Image.open(GRAPHICS / path).convert('RGBA'))


def lum(a: np.ndarray) -> np.ndarray:
    return 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]


def r2(v: float, n: int = 2) -> float:
    return round(float(v), n)


def cap_split(a: np.ndarray):
    """(row, ratio) of the biggest luminance drop in the first rows: the rows above are the top face."""
    al = a[..., 3] >= 128
    L = lum(a.astype(float))
    rl = np.array([L[y][al[y]].mean() if al[y].any() else np.nan for y in range(a.shape[0])])
    best = (0.0, 0)
    for y in range(3, min(a.shape[0] - 4, CAP_ROWS)):
        ratio = np.nanmean(rl[y - 3:y]) / max(np.nanmean(rl[y:y + 4]), 1.0)
        if ratio > best[0]:
            best = (ratio, y)
    return best[1], best[0]


def wall_fit(path: str) -> dict:
    a = rgba(path)
    al = a[..., 3] >= 128
    rows = np.nonzero(al.any(1))[0]
    cols = np.nonzero(al.any(0))[0]
    cap, ratio = cap_split(a)
    out = {'kind': 'wall', 'size': [a.shape[1], a.shape[0]], 'cols': [int(cols.min()), int(cols.max()) + 1],
           'base': int(rows.max()) + 1, 'ratio': r2(ratio)}
    if ratio >= CAP_RATIO:
        out['cap'] = int(cap)   # rows 0..cap: the top face; cap..base: the face
        out['height'] = int(rows.max()) + 1 - int(cap)
        # the plain stone of the face: its rows between the cap and the baseboard (the strongest drop in the lower rows)
        L = lum(a.astype(float))
        rl = np.array([L[y][al[y]].mean() if al[y].any() else np.nan for y in range(a.shape[0])])
        base = int(rows.max()) + 1
        best = (0.0, base - 1)
        for y in range(int(0.6 * base), base - 3):
            q = np.nanmean(rl[y - 3:y]) / max(np.nanmean(rl[y:y + 4]), 1.0)
            if q > best[0]:
                best = (q, y)
        out['stone'] = [int(cap) + 1, int(best[1]) - 1]
    else:
        out['cap'] = 0          # a top seen end-on: the whole frame is the cap, there is no seen face
        out['height'] = 0
    return out


def door_fit(path: str) -> dict:
    a = rgba(path)
    al = a[..., 3] >= 128
    cols = np.nonzero(al.any(0))[0]
    xs = cols.astype(float) + 0.5
    top = np.array([np.nonzero(al[:, x])[0].min() for x in cols], float)
    bot = np.array([np.nonzero(al[:, x])[0].max() + 1 for x in cols], float)
    # one slope for both lines: the door's top and base are parallel on the ground plane it stands in
    A = np.zeros((2 * len(xs), 3))
    A[:len(xs), 0] = 1; A[len(xs):, 1] = 1; A[:, 2] = np.concatenate([xs, xs])
    sol, *_ = np.linalg.lstsq(A, np.concatenate([top, bot]), rcond=None)
    res = A @ sol - np.concatenate([top, bot])
    return {'kind': 'door', 'size': [a.shape[1], a.shape[0]], 'cols': [int(cols.min()), int(cols.max()) + 1],
            'top': r2(sol[0]), 'base': r2(sol[1]), 'slope': r2(sol[2], 4), 'height': r2(sol[1] - sol[0]), 'rms': r2(np.sqrt(np.mean(res ** 2)))}


def ell(p, x):
    cx, c, r, k = p
    return c - k * r * np.sqrt(np.clip(1 - ((x - cx) / r) ** 2, 0, None))


def round_fit(path: str) -> dict:
    a = rgba(path)
    sil = F.silhouette(a)
    H, W = sil.shape
    cols = np.arange(W)
    xs = cols + 0.5
    top = np.array([np.nonzero(sil[:, x])[0].min() for x in cols], float)
    bot = np.array([np.nonzero(sil[:, x])[0].max() + 1 for x in cols], float)
    fit = least_squares(lambda p: ell(p, xs) - top, [W / 2, H / 3, W / 2, 0.5], loss='soft_l1', f_scale=1.0)
    cx, c, r, k = (float(v) for v in fit.x)
    # the underside: the same ellipse shape, lower; fitted to the columns that carry no leg. A leg's column is one whose lowest
    # pixel hangs more than a third of the silhouette's height below the plate's own lowest edge.
    def ellb(q, x):
        c2, r2_ = q
        return c2 + k * r2_ * np.sqrt(np.clip(1 - ((x - cx) / r2_) ** 2, 0, None))
    nolegs = bot <= np.median(bot) + 2.0
    for _ in range(4):  # the columns the underside explains, to 2 px: the legs' columns hang far below it
        fit2 = least_squares(lambda q: ellb(q, xs[nolegs]) - bot[nolegs], [c + 4, r], loss='soft_l1')
        c2, rb = (float(v) for v in fit2.x)
        nolegs = np.abs(ellb([c2, rb], xs) - bot) < 2.0
    leg_cols = bot > ellb([c2, rb], xs) + 3.0
    legs = []
    x = 0
    while x < W:
        if leg_cols[x]:
            x0 = x
            while x < W and leg_cols[x]:
                x += 1
            legs.append((x0, x))
        else:
            x += 1
    feet = []  # (u centre, foot row, half width)
    for x0, x1 in legs:
        feet.append((0.5 * (x0 + x1), float(bot[x0:x1].max()), 0.5 * (x1 - x0)))
    # the ground ring (rho, cz): the feet at (cx + rho cos t, cz + k rho sin t); the angles t are free, five unknowns for
    # six numbers when three legs show
    def ring(q):
        cz, rho = q[0], q[1]
        t = q[2:]
        out = []
        for i, (u, v, _) in enumerate(feet):
            out += [cx + rho * np.cos(t[i]) - u, cz + k * rho * np.sin(t[i]) - v]
        return out
    t0 = [np.arctan2((v - np.mean([f[1] for f in feet])) / k, u - cx) for u, v, _ in feet]
    sol = least_squares(ring, [np.mean([f[1] for f in feet]) - k * 20, 25.0] + t0)
    cz, rho = float(sol.x[0]), float(sol.x[1])
    angles = [float(np.mod(t, 2 * np.pi)) for t in sol.x[2:]]
    # the unseen legs are the seen ones through the axis (a table's legs are evenly spread): the point reflections
    for t in list(angles):
        o = float(np.mod(t + np.pi, 2 * np.pi))
        if all(abs(np.angle(np.exp(1j * (o - q)))) > 0.35 for q in angles):
            angles.append(o)
    seen = [True] * len(feet) + [False] * (len(angles) - len(feet))
    return {'kind': 'round', 'size': [W, H], 'cx': r2(cx), 'k': r2(k, 4), 'cz': r2(cz),
            'top': {'r': r2(r), 'height': r2(cz - c)}, 'under': {'r': r2(rb), 'height': r2(cz - c2)},
            'rho': r2(rho), 'legs': [{'angle': r2(t, 4), 'seen': s, 'half': r2(feet[i][2] if i < len(feet) else feet[i % len(feet)][2]),
                                       'source': i if i < len(feet) else int(np.argmin([abs(np.angle(np.exp(1j * (angles[j] + np.pi - t)))) for j in range(len(feet))]))}
                                      for i, (t, s) in enumerate(zip(angles, seen))],
            'rms_top': r2(np.sqrt(np.mean(fit.fun ** 2)), 3), 'rms_under': r2(np.sqrt(np.mean(fit2.fun ** 2)), 3)}


def bed_fit(path: str) -> dict:
    a = rgba(path)
    sil = F.silhouette(a)
    H, W = sil.shape
    cols = np.nonzero(sil.any(0))[0]
    rows = np.nonzero(sil.any(1))[0]
    x0, x1 = int(cols.min()), int(cols.max()) + 1
    def col_span(x):
        ys = np.nonzero(sil[:, x])[0]
        return float(ys.min()), float(ys.max()) + 1
    lt, lb = col_span(x0)
    rt, rb = col_span(x1 - 1)
    yt = float(rows.min())
    xt = float(np.nonzero(sil[int(yt)])[0].mean() + 0.5)
    yb = float(rows.max()) + 1
    xb = float(np.nonzero(sil[int(yb) - 1])[0].mean() + 0.5)
    h = 0.5 * ((lb - lt) + (rb - rt))
    # base corners: left (x0, lb), right (x1, rb), front (xb, yb); the back one completes the parallelogram
    B3 = np.array([x0, lb]); B1 = np.array([x1, rb]); B2 = np.array([xb, yb]); B0 = B3 + B1 - B2
    top_back = np.array([xt, yt])
    return {'kind': 'bed', 'size': [W, H], 'height': r2(h), 'base': [[r2(p[0]), r2(p[1])] for p in (B0, B1, B2, B3)],
            'top_back_error': r2(np.linalg.norm((B0 - [0, h]) - top_back)),
            'consistency': r2(abs(xb - (x0 + x1 - xt)))}


def bands(sil: np.ndarray, ratio: float = 1.5, min_rows: int = 3):
    """Row bands of one width (the pixels a row holds): a new band wherever it jumps by `ratio` between rows (the chimney over
    the hearth, the legs under a table top); a band under `min_rows` rows is a lone edge row and joins the band before it.
    [(first row, end row, x0, x1)]."""
    rows = np.nonzero(sil.any(1))[0]
    cnt = {int(y): int(sil[y].sum()) for y in rows}
    cuts, start = [], int(rows[0])
    for y in range(int(rows[0]), int(rows[-1])):
        w0, w1 = cnt[y], cnt[y + 1]
        if max(w0, w1) / max(min(w0, w1), 1) >= ratio:
            cuts.append((start, y + 1)); start = y + 1
    cuts.append((start, int(rows[-1]) + 1))
    merged = []
    for a, b in cuts:
        if merged and b - a < min_rows:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    res = []
    for a, b in merged:
        xs = [(int(np.nonzero(sil[y])[0].min()), int(np.nonzero(sil[y])[0].max()) + 1) for y in range(a, b)]
        res.append((a, b, min(q[0] for q in xs), max(q[1] for q in xs)))
    return res


def step_row(a: np.ndarray, r0: int, r1: int, x0: int, x1: int):
    """The strongest luminance drop between rows r0..r1 over columns x0..x1: (row, ratio), the rows above brighter."""
    al = a[..., 3] >= 128
    L = lum(a.astype(float))
    rl = np.array([L[y, x0:x1][al[y, x0:x1]].mean() if al[y, x0:x1].any() else np.nan for y in range(a.shape[0])])
    best = (0.0, r0)
    for y in range(r0 + 3, r1 - 1):
        ratio = np.nanmean(rl[y - 3:y]) / max(np.nanmean(rl[y:min(y + 4, r1)]), 1.0)
        if ratio > best[0]:
            best = (ratio, y)
    return best[1], best[0]


def frontal_fit(path: str) -> dict:
    """A thing that faces the original camera square on (the hearth, a shelf, a table): bands of the silhouette by width. The
    widest-and-tallest band is the body; a narrower band above it is a stack on the body's back edge (the chimney); what hangs
    below the body is legs (column groups). The body's rows split into its top face (above) and its front face (below) at the
    strongest luminance drop, if there is one of CAP_RATIO (a plain rectangle, as a shelf, has none: the game gives it the depth
    the wall behind it leaves). `opening`: the largest region of the front face darker than half its upper-quartile luminance, if jambs stand either side (the firebox)."""
    a = rgba(path)
    sil = F.silhouette(a)
    H, W = sil.shape
    bs = bands(sil)
    areas = [(b - a_) * (x1 - x0) for a_, b, x0, x1 in bs]
    mi = int(np.argmax(areas))
    r0, r1, x0, x1 = bs[mi]
    out = {'kind': 'frontal', 'size': [W, H], 'base': int(bs[-1][1]), 'body': {'rows': [r0, r1], 'cols': [x0, x1]}}
    s, ratio = step_row(a, r0, r1, x0, x1)
    # a body with something above it or under it has a top face and a front face; a plain rectangle (a shelf's front) is a face
    if ratio >= CAP_RATIO and r1 - r0 > 12 and (bs[:mi] or bs[mi + 1:]):
        out['body']['split'] = int(s)       # rows r0..s: the top face; s..r1: the front face
        out['body']['ratio'] = r2(ratio)
    else:
        out['body']['split'] = int(r0)      # no top face seen
    out['above'] = [{'rows': [b[0], b[1]], 'cols': [b[2], b[3]]} for b in bs[:mi]]
    legs = []
    below = bs[mi + 1:]
    if below:  # the lowest band is the feet: its column groups are the legs; the bands between (brackets) are the apron's
        b = below[-1]
        cols = sil[b[0]:b[1]].any(0)
        x = 0
        while x < W:
            if cols[x]:
                xa = x
                while x < W and cols[x]:
                    x += 1
                legs.append({'cols': [xa, x], 'rows': [b[0], b[1]]})
            else:
                x += 1
    out['legs'] = legs
    # a hole in the front face: pixels darker than a third of the face's median luminance, the largest connected region
    from scipy import ndimage
    f0 = out['body']['split']
    L = lum(a.astype(float))
    face = sil[f0:r1, x0:x1]
    upper = np.percentile(L[f0:r1, x0:x1][face], 75) if face.any() else 0
    dark = (L[f0:r1, x0:x1] < upper / 2.0) & face
    lab, n = ndimage.label(ndimage.binary_opening(dark, iterations=2))
    if n:
        sizes = np.bincount(lab.ravel())[1:]
        j = int(np.argmax(sizes)) + 1
        ys, xs_ = np.nonzero(lab == j)
        if sizes[j - 1] > 0.08 * face.sum() and xs_.min() > 2 and xs_.max() < face.shape[1] - 3:  # a hole, with jambs either side
            out['opening'] = {'rows': [int(ys.min()) + f0, int(ys.max()) + 1 + f0], 'cols': [int(xs_.min()) + x0, int(xs_.max()) + 1 + x0]}
    return out


def post_fit(path: str) -> dict:
    """A post (table-10: a stone footing, a shaft, braces and a crossbar), which the old game took for a chair. Its rows grouped into runs
    of one extent; the footing is the lowest rows still at 0.85 of the widest of the lowest third, one run, a square block (its depth
    its width); every run above is a slab as deep as the shaft is wide (the narrowest run of 10 rows or more). The axis is
    where the footing's front-bottom edge, the sprite's last row, puts its centre."""
    a = rgba(path)
    sil = F.silhouette(a)
    H, W = sil.shape
    rows = [(int(np.nonzero(sil[y])[0].min()), int(np.nonzero(sil[y])[0].max()) + 1) for y in range(H)]
    widths = np.array([r[1] - r[0] for r in rows])
    third = widths[2 * H // 3:]
    foot0 = H - 1
    while foot0 > 0 and widths[foot0 - 1] >= 0.85 * third.max():
        foot0 -= 1
    runs, y = [], 0
    while y < foot0:
        y1 = y + 1
        while y1 < foot0 and abs(rows[y1][0] - rows[y][0]) == 0 and abs(rows[y1][1] - rows[y][1]) == 0:
            y1 += 1
        runs.append([y, y1, rows[y][0], rows[y][1]])
        y = y1
    tall = [r[3] - r[2] for r in runs if r[1] - r[0] >= 10]
    shaft = float(min(tall))
    foot = [foot0, H, min(r[0] for r in rows[foot0:]), max(r[1] for r in rows[foot0:])]
    foot_d = float(foot[3] - foot[2])
    return {'kind': 'post', 'size': [W, H], 'runs': runs + [foot], 'shaft': shaft, 'footing': foot_d, 'z_axis': r2(H - foot_d / 2)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/data/interior.json'))
    ap.add_argument('--sheet', default='')
    args = ap.parse_args()
    out = {}
    for n in list(range(19, 31)) + [33, 34, 35, 36]:
        p = f'inside/innwalls/Walls/inn-{n:02d}.png'
        out['assets/graphics/' + p] = wall_fit(p)
    p = 'struct/Details/Door/odor1-01.png'
    out['assets/graphics/' + p] = door_fit(p)
    p = 'inside/details/table-09.png'
    out['assets/graphics/' + p] = round_fit(p)
    p = 'inside/details/inacc-03.png'
    out['assets/graphics/' + p] = bed_fit(p)
    for p in ('inacc-05', 'inacc-01', 'table-01', 'table-07'):
        out['assets/graphics/inside/details/' + p + '.png'] = frontal_fit('inside/details/' + p + '.png')
    out['assets/graphics/inside/details/table-10.png'] = post_fit('inside/details/table-10.png')
    for k, v in out.items():
        print(k.split('graphics/')[1], json.dumps(v))
    Path(args.out).write_text(json.dumps(out, indent=1, sort_keys=True))


if __name__ == '__main__':
    main()
