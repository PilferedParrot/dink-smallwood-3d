#!/usr/bin/env python3
"""The small props (barrels, sacks, pies, bottles, crates, chests...) as solids derived from their own sprite
(docs/DIRECTION.md, "The small props are solid").

A prop sprite is a picture of a small object taken by the camera of every other fitted sprite (tools/facade_fit.py,
tools/hut_fit.py): screen = (X, Z - Y) with a ground circle drawn as an ellipse of aspect k = 0.4878 (the castle's, one
camera). One rule per shape class, and the class is the art's (classify()):
  * round (barrel, sack, bottle, vase, bowl, fruit, a rounded gravestone): a solid of revolution, fitted with the huts'
    machinery (hut_fit.profile_fit, node spacing and ring size as parameters): the profile r(h) from the silhouette's four
    edges. The ground circle's centre row cz is not given by a base arc (a barrel's belly stands wider than its base): the lowest
    drawn row is the front of the base circle, B = cz + k a, so the base radius a is swept and the profile that explains the
    silhouette best (robust least-squares cost) is taken. 'lid' (barrels, vases): the flattest top the outline tolerates.
    'drum' (the pie, the plate, the save machine): analytic, r = widest half-width, H = height - 2 k r.
  * box (crates, chests): a box yawed about the vertical, by maximising the overlap of its projected hexagon with the
    silhouette (box_fit); 'stack' (box-01..06): the unit crate repeated on its own lattice (stack_fit).
  * pillow (grain bags, a ham, a loaf): an ellipsoid lying on a yawed elliptic footprint (pillow_fit).
  * flat (scrolls, coin piles, splinters): too low to stand: a quad lying on the ground.
A round fit whose outline is off by more than EDGE_MAX px stays a billboard (not fitted).
The game (scripts/prop_solids.gd) builds the meshes from game/prototype/props.json (by sprite path) and textures them by
projecting the sprite back through the camera (UV = (x, z - Y)); what the camera never saw takes the picture of what it did.

Usage: /usr/bin/python3 tools/prop_fit.py [--out game/prototype/props.json] [--sheet tmp/props] [sprite paths under game/ ...]
  with no names: every frame of FOLDERS, overwriting the file (the stacks need the two single crates' fits: run the crates
  first, by name, on a fresh checkout); with names: those only, merged into the file. 6 workers; about 3 minutes for all.
Verdict (2026-10-07, Sonnet 5.5 subagent): works; deterministic (differential evolution is seeded); 172 frames fitted, round
  outline residual median 0.2-0.7 px, boxes IoU 0.81-0.98 (the chests' open-lid frames lowest), stacks 0.86-0.92, bags 0.85-0.96.
  Known limits: a pie/barrel top is decided by class, not by the pixels (the outline cannot say); chests have no vault; a
  hollow ring (the save machine) is only a drum.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import facade_fit as F  # noqa: E402
import hut_fit as H  # noqa: E402

ROOT = F.ROOT
RING = 32          # ring points per node (the huts' are 48: a prop is small)
STAND = 4.0        # weight of the prior that a prop stands on its base: the wall leaves the ground straight
SLOPE = (1.5, 8.0)  # a profile steeper than 1.5 px of radius per px of height (a pedestal under a belly) is penalised
FLAT_TOL = 1.5     # a flat top may cost this much more than the best profile's (the tolerance of the outline's dome-or-lid ambiguity)
NODES = 14         # nodes up a round prop's height, about (spacing d = height / NODES, 1.5 to 6 px)


def load(path: str) -> np.ndarray:
    return np.array(Image.open(ROOT / 'game' / path).convert('RGBA'))


def round_fit(rgba: np.ndarray, k: float, flat_top: bool = False) -> dict | None:
    sil = F.silhouette(rgba)
    if sil.sum() < 20:
        return None
    rows, left, right, cols, top, bot = H.edges(sil)
    hgt = len(rows)
    wmax = float((right - left).max())
    mid = (left + right) / 2
    wide = (right - left) >= 0.6 * wmax
    cx = float(np.median(mid[wide]))
    bmax = float(rows.max() + 1)
    d = float(np.clip(hgt / NODES, 1.5, 6.0))
    # The cost over a is not convex (the optimiser lands in different minima from different starts): sweep a up and then
    # down, each fit starting from its neighbour's profile, and keep the best fit of each a.
    grid = np.arange(max(2.0, wmax * 0.15), wmax / 2 + 3.0, 0.5)
    fits = {}
    for order in (grid, grid[::-1]):
        init = None
        for a in order:
            cz = bmax - k * a
            res = H.profile_fit(sil, cx, cz, k, a, reg=0.3, d=d, apex=False, full=True, stand=STAND, slope=SLOPE, init=init)
            init = res.x.copy()
            init[0] = a
            if a not in fits or res.cost < fits[a][0]:
                fits[a] = (res.cost, a, cz, res.x)
    best = min(fits.values(), key=lambda t: t[0])
    cost, a, cz, R = best
    # Trim the nodes standing above the body (their radius is zero) and keep the highest that has any.
    keep = np.nonzero(R > 0.3)[0]
    top_i = int(keep.max())
    R = R[:top_i + 1]
    if flat_top:
        # A lid, not a dome: the outline cannot tell them apart (it is the same union of ellipses), and a barrel's, a
        # vase's or a pie's top is flat. The flattest top the outline tolerates: the fewest nodes whose cost stays within
        # FLAT_TOL of the best, the last node's ring closed by a flat cap (the game's top).
        lo = max(4, int(0.5 * len(R)))
        costs = {}
        for t in range(len(R), lo - 1, -1):
            res = H.profile_fit(sil, cx, cz, k, a, reg=0.3, d=d, apex=False, full=True, stand=STAND, slope=SLOPE, init=R[:t], nodes=t)
            costs[t] = (res.cost, res.x)
        c0 = min(c for c, _ in costs.values())
        t = min(t for t, (c, _) in costs.items() if c <= FLAT_TOL * c0)
        R = costs[t][1]
    nodes_h = np.arange(len(R)) * d
    vis = H.ring_visibility(R, cx, cz, k, nodes_h, d=d, ring=RING)
    half, tp, bt = H.predict(R, cx, cz, k, rows, cols, d)
    res = np.concatenate([(cx - half) - left, (cx + half) - right])
    return {'class': 'round', 'size': [rgba.shape[1], rgba.shape[0]], 'cx': round(cx, 2), 'cz': round(float(cz), 2),
            'k': round(k, 4), 'a': round(float(a), 2), 'd': round(d, 2), 'ring': RING,
            'nodes': [[round(float(h), 1), round(float(r), 2), v] for h, r, v in zip(nodes_h, R, vis)],
            'edge_med': round(float(np.median(np.abs(res))), 2), 'sil_px': int(sil.sum())}


def drum_fit(rgba: np.ndarray, k: float) -> dict | None:
    """A dish (a pie, a plate): a short drum, a round thing whose outline cannot tell a dome from a flat top (the pie fitted
    as a bun: 2026-10-07). Its top is the ellipse of the widest row, so r = half that width, and the silhouette's height is
    the drum's height plus the top ellipse's 2 k r: H = height - 2 k r. Same entry as round_fit's."""
    sil = F.silhouette(rgba)
    rows, left, right, cols, top, bot = H.edges(sil)
    r = float((right - left).max()) / 2
    cx = float(np.median(((left + right) / 2)[(right - left) >= 0.6 * 2 * r]))
    hgt = float(rows.max() + 1 - rows.min())
    hh = max(1.0, hgt - 2 * k * r)
    cz = float(rows.max() + 1) - k * r
    nodes_h = np.array([0.0, hh])
    R = np.array([r, r])
    vis = H.ring_visibility(R, cx, cz, k, nodes_h, d=hh, ring=RING)
    return {'class': 'round', 'size': [rgba.shape[1], rgba.shape[0]], 'cx': round(cx, 2), 'cz': round(cz, 2), 'k': round(k, 4),
            'a': round(r, 2), 'd': round(hh, 2), 'ring': RING, 'nodes': [[0.0, round(r, 2), vis[0]], [round(hh, 2), round(r, 2), vis[1]]],
            'edge_med': 0.0, 'sil_px': int(sil.sum())}


def round_overlay(rgba: np.ndarray, e: dict) -> Image.Image:
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    S = 6
    bg = bg.resize((bg.width * S, bg.height * S), Image.NEAREST)
    dr = ImageDraw.Draw(bg)
    cx, cz, k, d = e['cx'], e['cz'], e['k'], e['d']
    R = np.array([n[1] for n in e['nodes']])
    for i, (h, r, _) in enumerate(e['nodes']):
        if r > 0.5:
            col = (255, 255, 0, 255) if i == 0 else (0, 255, 255, 255)
            dr.ellipse(((cx - r) * S, (cz - h - k * r) * S, (cx + r) * S, (cz - h + k * r) * S), outline=col)
    rows = np.arange(rgba.shape[0], dtype=float)
    cols = np.arange(rgba.shape[1], dtype=float)
    half, _, _ = H.predict(R, cx, cz, k, rows, cols, d)
    for y in range(len(rows)):
        if half[y] > 0:
            for xx in (cx - half[y], cx + half[y]):
                dr.rectangle((xx * S - 1, y * S, xx * S + 1, y * S + 1), fill=(255, 255, 255, 255))
    return bg


def box_corners(p, k):
    """The eight corners of a box fitted by p = (cx, cz, w, d, alpha, H) as sprite pixels: the footprint's centre projects to
    (cx, cz), the rectangle w x d (true ground units: the picture's z is k times the ground's) yawed by alpha about the
    vertical, height H; screen = (cx + X, cz + k Z - Y). Returns ([[X, Z] x4 ground corners], pixels [4 ground, 4 top])."""
    cx, cz, w, d, al, hh = p
    c, s = np.cos(al), np.sin(al)
    g = [(sx * w / 2 * c - sz * d / 2 * s, sx * w / 2 * s + sz * d / 2 * c) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    px = [(cx + X, cz + k * Z) for X, Z in g] + [(cx + X, cz + k * Z - hh) for X, Z in g]
    return g, px


def hull_mask(px, shape, ss=2):
    from scipy.spatial import ConvexHull
    pts = np.array(px)
    hull = pts[ConvexHull(pts).vertices]
    img = Image.new('L', (shape[1] * ss, shape[0] * ss), 0)
    ImageDraw.Draw(img).polygon([(x * ss, y * ss) for x, y in hull], fill=1)
    return np.array(img, dtype=np.uint8).reshape(shape[0], ss, shape[1], ss).mean((1, 3)) >= 0.5


def box_fit(rgba: np.ndarray, k: float) -> dict | None:
    from scipy.optimize import differential_evolution
    sil = F.silhouette(rgba)
    if sil.sum() < 20:
        return None
    rows, left, right, cols, top, bot = H.edges(sil)
    x0, x1, y0, y1 = left.min(), right.max(), rows.min(), rows.max() + 1
    wd, ht = x1 - x0, y1 - y0

    def cost(p):
        _, px = box_corners(p, k)
        m = hull_mask(px, sil.shape)
        return 1.0 - (m & sil).sum() / max(1, (m | sil).sum())
    bounds = [(x0 + 0.2 * wd, x1 - 0.2 * wd), (y0, y1), (4, 1.3 * wd), (4, 1.3 * wd), (-np.pi / 4, np.pi / 4), (3, ht)]
    r = differential_evolution(cost, bounds, seed=1, popsize=24, maxiter=150, tol=1e-6, polish=False)
    cx, cz, w, d, al, hh = r.x
    return {'class': 'box', 'size': [rgba.shape[1], rgba.shape[0]], 'cx': round(float(cx), 2), 'cz': round(float(cz), 2),
            'k': round(k, 4), 'w': round(float(w), 2), 'd': round(float(d), 2), 'yaw': round(float(al), 4), 'h': round(float(hh), 2),
            'iou': round(1.0 - float(r.fun), 4), 'sil_px': int(sil.sum())}


def stack_fit(rgba: np.ndarray, k: float, unit: tuple) -> dict | None:
    """A stack of crates (box-01..06): the unit crate (w, d, h, yaw: the mean of the single crates boxb1-01 and boxb3-01, the
    same crates in the same folder) repeated on its own lattice, boxes added greedily (each resting on the one below it) while
    the union's silhouette overlap with the sprite's improves; the lattice origin (cx0, cz0) is searched, the yaw taken
    both ways (a stack is drawn either way round)."""
    from scipy.optimize import differential_evolution
    sil = F.silhouette(rgba)
    rows, left, right, cols, top, bot = H.edges(sil)
    x0, x1, y0, y1 = left.min(), right.max(), rows.min(), rows.max() + 1
    w, d, hh, yaw0 = unit
    cand = [(i, j, l) for i in range(-3, 4) for j in range(-3, 4) for l in range(0, 4)]

    def build(cx0, cz0, yaw):
        c, s = np.cos(yaw), np.sin(yaw)
        masks = {}
        for (i, j, l) in cand:
            X, Z = i * w * c - j * d * s, i * w * s + j * d * c
            _, px = box_corners((cx0 + X, cz0 + k * Z - l * hh, w, d, yaw, hh), k)
            masks[(i, j, l)] = hull_mask(px, sil.shape, ss=1)
        return masks

    def greedy(masks):
        have, union = [], np.zeros(sil.shape, bool)
        score = 0.0
        while True:
            best = None
            for key, m in masks.items():
                if key in have or (key[2] > 0 and (key[0], key[1], key[2] - 1) not in have):
                    continue
                # a pile is in one piece: a box on the floor shares a face with one already there
                if key[2] == 0 and have and not any((key[0] + a, key[1] + b, 0) in have for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                u = union | m
                iou = (u & sil).sum() / max(1, (u | sil).sum())
                if best is None or iou > best[0]:
                    best = (iou, key, u)
            if best is None or best[0] < score + 0.002:
                return have, score
            score, union = best[0], best[2]
            have.append(best[1])

    result = None
    for yaw in (yaw0, -yaw0):
        def cost(q):
            return 1.0 - greedy(build(q[0], q[1], yaw))[1]
        r = differential_evolution(cost, [(x0, x1), (y0, y1)], seed=1, popsize=12, maxiter=30, tol=1e-6, polish=False)
        if result is None or r.fun < result[0]:
            result = (r.fun, r.x, yaw)
    fun, (cx0, cz0), yaw = result
    have, score = greedy(build(cx0, cz0, yaw))
    c, s = np.cos(yaw), np.sin(yaw)
    boxes = [[round(float(i * w * c - j * d * s), 2), round(float(i * w * s + j * d * c), 2), round(float(l * hh), 2)] for i, j, l in have]
    return {'class': 'box', 'size': [rgba.shape[1], rgba.shape[0]], 'cx': round(float(cx0), 2), 'cz': round(float(cz0), 2),
            'k': round(k, 4), 'w': round(w, 2), 'd': round(d, 2), 'yaw': round(float(yaw), 4), 'h': round(hh, 2), 'boxes': boxes,
            'iou': round(float(score), 4), 'sil_px': int(sil.sum())}


PILLOW_C = 0.5     # a lying thing's height over its ground, as a fraction of its narrower half-width (the outline cannot say)


def pillow_mask(q, k, shape):
    """The silhouette of an ellipsoid lying on the ground: semi-axes A, B along and across its yaw, height C = PILLOW_C min(A, B)
    over a footprint centred (cx, cz): an orthographic view of an ellipsoid is an ellipse, with covariance M diag(A2, B2, C2) M^T."""
    cx, cz, A, B, al = q
    C = PILLOW_C * min(A, B)
    c, s = np.cos(al), np.sin(al)
    M = np.array([[c, -s, 0.0], [k * s, k * c, -1.0]])
    cov = M @ np.diag([A * A, B * B, C * C]) @ M.T
    inv = np.linalg.inv(cov)
    ys, xs = np.mgrid[0:shape[0], 0:shape[1]]
    dx, dy = xs + 0.5 - cx, ys + 0.5 - (cz - C)
    return inv[0, 0] * dx * dx + 2 * inv[0, 1] * dx * dy + inv[1, 1] * dy * dy <= 1.0


def pillow_fit(rgba: np.ndarray, k: float) -> dict | None:
    """A thing lying on the ground (a grain bag, a ham, a loaf): an ellipsoid with a yawed elliptic footprint."""
    from scipy.optimize import differential_evolution
    sil = F.silhouette(rgba)
    rows, left, right, cols, top, bot = H.edges(sil)
    x0, x1, y0, y1 = left.min(), right.max(), rows.min(), rows.max() + 1
    wd, ht = x1 - x0, y1 - y0

    def cost(q):
        m = pillow_mask(q, k, sil.shape)
        return 1.0 - (m & sil).sum() / max(1, (m | sil).sum())
    r = differential_evolution(cost, [(x0, x1), (y0, y1), (3, wd), (3, wd), (-np.pi / 2, np.pi / 2)], seed=1, popsize=24, maxiter=150,
                               tol=1e-6, polish=False)
    cx, cz, A, B, al = r.x
    return {'class': 'pillow', 'size': [rgba.shape[1], rgba.shape[0]], 'cx': round(float(cx), 2), 'cz': round(float(cz), 2),
            'k': round(k, 4), 'a': round(float(A), 2), 'b': round(float(B), 2), 'c': round(float(PILLOW_C * min(A, B)), 2),
            'yaw': round(float(al), 4), 'iou': round(1.0 - float(r.fun), 4), 'sil_px': int(sil.sum())}


def pillow_overlay(rgba: np.ndarray, e: dict) -> Image.Image:
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    S = 6
    m = pillow_mask((e['cx'], e['cz'], e['a'], e['b'], e['yaw']), e['k'], rgba.shape[:2])
    edge = m & ~ndimage.binary_erosion(m)
    bg = bg.resize((bg.width * S, bg.height * S), Image.NEAREST)
    dr = ImageDraw.Draw(bg)
    for y, x in zip(*np.nonzero(edge)):
        dr.rectangle((x * S, y * S, x * S + S - 1, y * S + S - 1), outline=(255, 255, 0, 255))
    return bg


def box_overlay(rgba: np.ndarray, e: dict) -> Image.Image:
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    S = 6
    bg = bg.resize((bg.width * S, bg.height * S), Image.NEAREST)
    dr = ImageDraw.Draw(bg)
    for X, Z, Y0 in e.get('boxes', [[0, 0, 0]]):
        g, px = box_corners((e['cx'] + X, e['cz'] + e['k'] * Z - Y0, e['w'], e['d'], e['yaw'], e['h']), e['k'])
        for i in range(4):
            j = (i + 1) % 4
            dr.line([(px[i][0] * S, px[i][1] * S), (px[j][0] * S, px[j][1] * S)], fill=(255, 255, 0, 255), width=2)
            dr.line([(px[4 + i][0] * S, px[4 + i][1] * S), (px[4 + j][0] * S, px[4 + j][1] * S)], fill=(0, 255, 255, 255), width=2)
            dr.line([(px[i][0] * S, px[i][1] * S), (px[4 + i][0] * S, px[4 + i][1] * S)], fill=(255, 255, 255, 255), width=1)
    return bg


FOLDERS = ['Bonuses/Barrels', 'Bonuses/bottles', 'Bonuses/Chest', 'Bonuses/Coins', 'Items/Boxes', 'Items/Cup', 'Items/Food',
           'Items/grain', 'Items/Paper', 'Items/Tomb', 'inter/save']  # struct/Teleport (a gold lattice cage) is not a solid: it stays a billboard
SKIP = {'food-31'}  # a person's picture in the food folder (the king), not a prop
# Billboards still (docs/DIRECTION.md): the tools (poles and blades, a few px thick), the hearts (a pickup hovering over its
# own shadow) and the status bars are not in FOLDERS.
DRUMS = {'food-11', 'cup-02', 'save-01', 'save-02', 'save-03', 'save-04', 'save-05'}  # the pie, the plate, the save machine (a low drum whose top is the picture of its hollow)
PILLOWS = {'food-01', 'food-02', 'food-03', 'food-07', 'food-08', 'food-29', 'food-30'}  # a ham, a steak, loaves, a root: lying on the ground
EDGE_MAX = 3.0     # a round fit whose outline is off by more than this (px, median) is not a solid of revolution (antlers, grapes): it stays a billboard
BOX_STEMS = ('box-', 'boxb1-01', 'boxb3-01', 'chst')


def classify(path: str) -> str | None:
    stem = Path(path).stem
    if stem in SKIP:
        return None
    if stem.startswith(('paper-0', 'coin-')) or stem in ('barel-03', 'barel-04', 'barel-05', 'barel-06') or \
            (stem.startswith(('boxb1-', 'boxb3-')) and stem not in ('boxb1-01', 'boxb3-01')):
        return 'flat'
    if stem.startswith('bag-') or stem in PILLOWS:
        return 'pillow'
    if stem.startswith('box-'):
        return 'stack'
    if stem.startswith(BOX_STEMS):
        return 'box'
    return 'drum' if stem in DRUMS else 'lid' if stem.startswith(('barel-', 'cup-')) else 'round'


def flat_entry(rgba: np.ndarray) -> dict:
    body = (rgba[..., 3] >= 128) & ~F.is_dither(rgba)
    ys, xs = np.nonzero(body)
    return {'class': 'flat', 'size': [rgba.shape[1], rgba.shape[0]], 'rows': [int(ys.min()), int(ys.max()) + 1],
            'cols': [int(xs.min()), int(xs.max()) + 1], 'k': round(F.plain_arc(4)[0], 4)}


def fit_one(path: str, unit=None):
    k, _ = F.plain_arc(4)
    rgba = load(path)
    cls = classify(path)
    if cls == 'flat':
        return path, flat_entry(rgba), None
    if cls == 'stack':
        e = stack_fit(rgba, k, unit)
    elif cls == 'pillow':
        e = pillow_fit(rgba, k)
    else:
        e = round_fit(rgba, k, cls == 'lid') if cls in ('round', 'lid') else drum_fit(rgba, k) if cls == 'drum' else box_fit(rgba, k)
    return path, e, (box_overlay if cls in ('box', 'stack') else pillow_overlay if cls == 'pillow' else round_overlay)(rgba, e) if e else None


def all_paths():
    out = []
    for f in FOLDERS:
        out += sorted(str(p.relative_to(ROOT / 'game')) for p in (ROOT / 'game/assets/graphics' / f).glob('*.png'))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/prototype/props.json'))
    ap.add_argument('--sheet', default=str(ROOT / 'tmp/props'))
    ap.add_argument('names', nargs='*', help='sprite paths under game/ (default: every frame of FOLDERS)')
    args = ap.parse_args()
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    paths = [n for n in (args.names or all_paths()) if classify(n)]
    from multiprocessing import Pool
    out = json.loads(Path(args.out).read_text()) if args.names and Path(args.out).exists() else {}  # named sprites: update those only
    unit = None
    if Path(args.out).exists():
        have = json.loads(Path(args.out).read_text())
        crates = [have[q] for q in have if Path(q).stem in ('boxb1-01', 'boxb3-01')]
        if len(crates) == 2:
            unit = (float(np.mean([c['w'] for c in crates])), float(np.mean([c['d'] for c in crates])),
                    float(np.mean([c['h'] for c in crates])), float(np.mean([abs(c['yaw']) for c in crates])))
            print('unit crate', unit, flush=True)
    from functools import partial
    with Pool(6) as pool:
        for path, e, ov in pool.imap_unordered(partial(fit_one, unit=unit), paths):
            if e is None or (e['class'] == 'round' and e['edge_med'] > EDGE_MAX):
                out.pop(path, None)
                print('not fitted', path, flush=True)
                continue
            out[path] = e
            if ov is not None:
                ov.save(Path(args.sheet) / (Path(path).stem + '.png'))
            print(path, json.dumps({q: v for q, v in e.items() if q != 'nodes'}), flush=True)
    Path(args.out).write_text(json.dumps(dict(sorted(out.items())), indent=0, separators=(',', ':')))


if __name__ == '__main__':
    main()
