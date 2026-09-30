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

Also fitted, with the same camera (see each function): the chimneys, as upright prisms
standing on a house's roof (roof_piece); kit buildings assembled from modular sprites plus
building tiles, found over the whole map (kit_clusters, kit_canvas) and fitted as hip-roofed
arms along their fronts with one shared kit geometry (front_polyline, kit_fit); and the
dormers drawn into kit roof panels, as gabled prisms on the roof (dormers, place_dormers).
For the backs, which mirror the fronts, door panels are swapped for their door-less twins
(back_twins).

Usage: /usr/bin/python3 tools/facade_fit.py [--out game/prototype/facades.json] [--sheet DIR]
Verdict (2026-09-29, Opus 5.5): works for seq 63 frames 1, 4, 6, 8; see the sheet for IoU.
Verdict (2026-09-29, Opus 5.5, second pass): chimneys home-11/12 and the Stonebrook inn
(screens 472-474, 504-506, 537-538) and the second kit house (kit-538) fit, with one
kit geometry; see tmp/facades/fit-*.png.
Verdict (2026-09-29, Opus 5.5, third pass): all seven kit buildings on the map are found and
fitted with one geometry (silhouette IoU 0.959-0.971), a four-arm zig-zag (kit-417) among
them; the three dormer panels fit as one dormer in two orientations. See DIRECTION.md.
"""
from __future__ import annotations
import argparse, colorsys, json, math
from pathlib import Path
import numpy as np
from scipy import ndimage
from scipy.signal import find_peaks
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
# (seq, frame, number of stacked blocks, roof pitch per block as rise/run, read from the art)
# Optional fixed params by index. home-04's free fit put a 28 px skirt eave that stands
# out as wings beyond the drawn silhouette; the three single houses from the same kit
# all fit a 10 px eave, so its skirt is held to that.
HOUSES = [(63, 1, 1, [0.9], {}), (63, 4, 2, [0.8, 1.1], {1: 10.0}), (63, 6, 1, [1.1], {}), (63, 8, 1, [1.1], {})]
# Roof pieces: separate sprites the original draws over a house's roof (the chimneys of
# seq 63). Each is an upright prism; see roof_piece().
ROOF_PIECES = [(63, 11), (63, 12)]
# Kit buildings: assembled in the original from modular sprites (seq 33 `outinn`: the stone
# ground floor and the roof) plus building tiles (tilesets 34 and 35 carry the half-timbered
# upper storey and the eave). Doors (seqs 61, 62) are drawn on its walls. See kit_building().
# Every building of the kit is found by kit_clusters() and kit_canvas().
KIT = {'tilesets': [34, 35], 'seqs': [33], 'details': [61, 62]}
# Kit roof panels with a dormer drawn in (seq 33). Each has a plain twin in the kit, the
# same-size panel it differs from least; see dormers().
DORMER_FRAMES = [13, 31, 32]
# Kit stone-storey panels with a door drawn in (seq 33). The original camera never saw a
# building's back, which takes its front mirrored; there each door panel shows its door-less
# twin (the same-anchor panel it differs from least: always the window panel of the same
# wall slot), and door and sign sprites are left off. See back_twins().
DOOR_FRAMES = [3, 4, 5, 6, 20, 21, 22, 23, 33, 34, 38, 39]
# Door sprites drawn over walls: (seq, frame), frame None for the whole sequence. Seq 63
# frames 2 and 3 are the cottages' doorways (one per wall direction), under a seq 61 leaf.
DOOR_SPRITES = [(61, None), (62, None), (63, 2), (63, 3)]
COLS = 32


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


def block_faces(F, L, R, y0, hw, o, pitch, block=0, end_pitch=None):
    """Faces as lists of 3D points (X, Y, Z) with a label. Ground point (x, z) = sprite (x, y).
    The hip ends take the side pitch unless end_pitch is given (a steeper end hip, whose
    ridge runs closer to the end walls)."""
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
    hip = half if end_pitch is None else rise / end_pitch / sin
    P0 = E[0] + half * vh + min(hip, A / 2) * uh
    P1 = E[0] + half * vh + max(A - hip, A / 2) * uh
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


def is_dither(rgba: np.ndarray) -> np.ndarray:
    """The original's shadows: isolated pure-black pixels (a 50% checkerboard)."""
    black = (rgba[..., 3] >= 128) & (rgba[..., :3].astype(int).sum(-1) < 10)
    nb = np.zeros_like(black)
    nb[1:] |= black[:-1]; nb[:-1] |= black[1:]; nb[:, 1:] |= black[:, :-1]; nb[:, :-1] |= black[:, 1:]
    return black & ~nb


def roof_piece(rgba: np.ndarray) -> dict:
    """An upright prism (a chimney) from its sprite, in sprite pixels.

    Its top face is horizontal, so under screen = (X, Z - Y) it appears as its own
    footprint: the parallelogram left/back/right/front. Its two back edges are the top
    outline, fitted as two lines meeting at the back corner; the side columns are those
    whose outline stays near the top (the thatch ring and the dithered shadow at the foot
    lie lower). The foot is the lowest stone pixel under the front edge: where the front
    edge meets the roof as the original camera saw it. The Godot side casts the view ray
    through the foot into the host house's roof for the depth; the height follows.
    """
    body = (rgba[..., 3] >= 128) & ~is_dither(rgba)
    stone = classify(rgba) == 1
    top = np.array([np.nonzero(body[:, x])[0].min() if body[:, x].any() else 10 ** 6 for x in range(body.shape[1])])
    cols = np.nonzero(top <= top.min() + 20)[0]
    xl, xr = int(cols.min()), int(cols.max())
    peak = np.nonzero(top <= top.min() + 1)[0]
    xb0 = int(round(peak.mean()))
    lx, rx = np.arange(xl, xb0 - 1), np.arange(xb0 + 2, xr + 1)
    la, ra = np.polyfit(lx, top[lx], 1), np.polyfit(rx, top[rx], 1)
    xb = (ra[1] - la[1]) / (la[0] - ra[0])
    Pl, Pb, Pr = [xl, np.polyval(la, xl)], [xb, np.polyval(la, xb)], [xr, np.polyval(ra, xr)]
    Pf = [Pl[0] + Pr[0] - Pb[0], Pl[1] + Pr[1] - Pb[1]]
    xf = int(round(Pf[0]))
    foot = [xf, int(np.nonzero(stone[:, xf - 1:xf + 2].any(1))[0].max())]
    return {'top': [[round(float(v), 2) for v in P] for P in (Pl, Pb, Pr, Pf)], 'foot': foot}


def origin(n: int):
    return ((n - 1) % COLS * 600, (n - 1) // COLS * 400)


def is_background(rgb: np.ndarray) -> np.ndarray:
    """Grass or water in a building tile: what stands behind the building, not the building."""
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    return ((g > r + 10) & (g > b + 10)) | ((b > r + 20) & (b > g + 10))


def draw_order(sprites):
    """The original's draw order (as tools/facade_contact_sheet.py): background sprites
    first by y, then the rest by que, or y when que is 0; list order breaks ties."""
    return sorted(range(len(sprites)), key=lambda i: (-10000 + sprites[i]['y'] if sprites[i]['type'] == 0
                                                      else sprites[i]['que'] or sprites[i]['y'], i))


def kit_clusters(world, kit=KIT):
    """Outdoor screens holding any piece of the kit (a building tile or a kit sprite on the
    default story layer), grouped by 8-neighbour adjacency: a building spans adjacent
    screens, and the engine places each piece on every screen it shows on."""
    has = set()
    for n, sc in world['screens'].items():
        if sc.get('indoor'):
            continue
        if any(t['tile'] // 128 + 1 in kit['tilesets'] for t in sc['tiles'][:96]) or any(
                e['seq'] in kit['seqs'] and e['vision'] == 0 and e['type'] != 2 for e in sc['sprites']):
            has.add(int(n))
    seen, clusters = set(), []
    for n in sorted(has):
        if n in seen:
            continue
        stack, comp = [n], []
        seen.add(n)
        while stack:
            m = stack.pop()
            comp.append(m)
            c, r = (m - 1) % COLS, (m - 1) // COLS
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    k = (r + dr) * COLS + c + dc + 1
                    if 0 <= c + dc < COLS and k in has and k not in seen:
                        seen.add(k)
                        stack.append(k)
        clusters.append(sorted(comp))
    return clusters


def kit_canvas(world, seqs, screens, kit=KIT):
    """The kit buildings on a cluster of screens as the original camera saw them: per
    screen, its building tiles (with grass and water knocked out) and its kit and door
    sprites in the original draw order, clipped to the screen as the engine clips them,
    stitched in world source pixels.

    Every connected component that holds a kit sprite is a building (a stray door is not);
    its pieces are the tiles and sprites that lie mostly on it (unclipped, so a copy the
    engine clips away on one screen still counts), and its screens are theirs.
    Returns per building: the canvas cropped to it, its world top-left (world = screen
    origin + (x - 20, y)), its mask, its member pieces [screen, 't'|'s', index] and screens.
    """
    os_ = [origin(n) for n in screens]
    x0, y0 = min(o[0] for o in os_), min(o[1] for o in os_)
    x1, y1 = max(o[0] for o in os_) + 600, max(o[1] for o in os_) + 400
    pad = 400
    canvas = Image.new('RGBA', (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), (0, 0, 0, 0))
    pieces = []  # (key, image, canvas position, is a kit sprite)
    for n, o in zip(screens, os_):
        sc = world['screens'][str(n)]
        at = (pad + o[0] - x0, pad + o[1] - y0)
        im = Image.new('RGBA', (600 + 2 * pad, 400 + 2 * pad), (0, 0, 0, 0))
        for i, t in enumerate(sc['tiles'][:96]):
            k = t['tile']; cell = k % 128
            if k // 128 + 1 not in kit['tilesets']:
                continue
            tile = Image.open(ROOT / f'game/assets/tiles/ts{k // 128 + 1:02}.png').convert('RGBA').crop(
                ((cell % 12) * 50, (cell // 12) * 50, (cell % 12 + 1) * 50, (cell // 12 + 1) * 50))
            im.paste(tile, (pad + i % 12 * 50, pad + i // 12 * 50))
            pieces.append(([n, 't', i], tile, (at[0] + i % 12 * 50, at[1] + i // 12 * 50), False))
        sp = sc['sprites']
        for i in draw_order(sp):
            e = sp[i]
            if e['vision'] != 0 or e['type'] == 2 or e['seq'] not in kit['seqs'] + kit['details']:
                continue
            fs = seqs.get(str(e['seq']), {}).get('frames', [])
            if not 0 < e['frame'] <= len(fs):
                continue
            f = fs[e['frame'] - 1]
            p = Image.open(ROOT / 'game' / f['path']).convert('RGBA')
            xy = (int(e['x'] - 20 - f['dx']), int(e['y'] - f['dy']))
            im.alpha_composite(p, (pad + xy[0], pad + xy[1]))
            pieces.append(([n, 's', i], p, (at[0] + xy[0], at[1] + xy[1]), e['seq'] in kit['seqs']))
        canvas.alpha_composite(im.crop((pad, pad, pad + 600, pad + 400)), at)
    rgba = np.array(canvas)
    # Grass and water in the building tiles are what stands behind the building: remove
    # the background-coloured regions connected to the outside (window glass and moss
    # enclosed by the building stay).
    lab_, _ = ndimage.label((rgba[..., 3] < 128) | is_background(rgba[..., :3]))
    outside = np.unique(np.concatenate([lab_[0], lab_[-1], lab_[:, 0], lab_[:, -1]]))
    rgba[np.isin(lab_, outside[outside > 0]), 3] = 0
    comp, count = ndimage.label((rgba[..., 3] >= 128) & ~is_dither(rgba))
    on = {}  # component -> member pieces
    for key, p, (px, py), is_kit in pieces:
        a = np.array(p)[..., 3] >= 128
        c = comp[py:py + a.shape[0], px:px + a.shape[1]][a]
        c = c[c > 0]
        if not a.sum() or not len(c):
            continue
        best = np.bincount(c).argmax()
        if (c == best).sum() > 0.5 * a.sum():
            on.setdefault(best, []).append((key, is_kit))
    out = []
    for c, members in on.items():
        if not any(is_kit for _, is_kit in members):
            continue
        mask = comp == c
        ys, xs = np.nonzero(mask)
        bx0, by0, bx1, by1 = xs.min() - 8, ys.min() - 8, xs.max() + 9, ys.max() + 9
        crop = rgba[by0:by1, bx0:bx1].copy()
        crop[~ndimage.binary_dilation(mask, iterations=6)[by0:by1, bx0:bx1], 3] = 0
        keys = [k for k, _ in members]
        out.append((crop, (x0 - pad + bx0, y0 - pad + by0), mask[by0:by1, bx0:bx1], keys,
                    sorted({k[0] for k in keys})))
    return out


def robust_line(xs, ys, tol=10.0):
    """Theil-Sen line (median of pairwise slopes), then least squares on the inliers.
    The wall base of a kit building is a sawtooth (door steps, panel joints) under
    overhanging eaves at the ends, which drag an ordinary fit off the wall."""
    i, j = np.triu_indices(len(xs), 25)
    slope = np.median((ys[j] - ys[i]) / (xs[j] - xs[i]))
    keep = np.abs(ys - (np.median(ys - slope * xs) + slope * xs)) < tol
    c = np.polyfit(xs[keep], ys[keep], 1)
    return c, np.abs(ys - np.polyval(c, xs)) < tol


def jettied_faces(F, L, R, h1, h, j, o, pitch, block, end_pitch=None):
    """A jettied block: stone walls on the footprint up to h1, the upper storey on the
    footprint moved out by j (perpendicular, like the eave) up to h, a hip roof over it,
    and the soffit under the overhang (label 3). Blocks `block` (ground floor) and
    `block + 1` (upper storey and roof)."""
    u, v = R - F, L - F
    uh, vh = u / np.linalg.norm(u), v / np.linalg.norm(v)
    d = j / max(abs(uh[0] * vh[1] - uh[1] * vh[0]), 1e-3)
    Fj, Rj, Lj = F - d * (uh + vh), R + d * (uh - vh), L + d * (vh - uh)
    lower = [f for f in block_faces(F, L, R, 0.0, h1, 0.0, pitch, block) if f[0] == 1]
    upper = block_faces(Fj, Lj, Rj, h1, h - h1, o, pitch, block + 1, end_pitch)
    a, b = [F, R, R + v, L], [Fj, Rj, Rj + (Lj - Fj), Lj]
    soffit = [(3, [(a[i][0], h1, a[i][1]), (a[(i + 1) % 4][0], h1, a[(i + 1) % 4][1]),
                   (b[(i + 1) % 4][0], h1, b[(i + 1) % 4][1]), (b[i][0], h1, b[i][1])], block + 1) for i in range(4)]
    return lower + upper + soffit


def front_polyline(mask):
    """The wall bases of a kit building's front: the bottom of its silhouette is a chain of
    straight segments, meeting at convex corners (the lowest points, walls turning toward
    the camera) and concave ones (the highest, walls turning away). Each segment is a
    robust line (see robust_line); the corners are where neighbouring lines meet, and the
    ends are the outermost inliers. Returns the corners left to right, and for each inner
    corner whether it is convex."""
    w = mask.shape[1]
    bot = np.array([np.nonzero(mask[:, x])[0].max() if mask[:, x].any() else -1 for x in range(w)])
    xs = np.nonzero(bot >= 0)[0]
    sm = ndimage.uniform_filter1d(bot[xs].astype(float), 41, mode='nearest')
    peaks = sorted([(int(xs[i]), True) for i in find_peaks(sm, prominence=20)[0]]
                   + [(int(xs[i]), False) for i in find_peaks(-sm, prominence=20)[0]])
    cuts = [int(xs.min()) + 10] + [x for x, _ in peaks] + [int(xs.max()) - 10]
    lines = []
    for k in range(len(cuts) - 1):
        seg = np.arange(cuts[k] + 5, cuts[k + 1] - 5)
        seg = seg[bot[seg] >= 0]
        lines.append((seg, *robust_line(seg, bot[seg].astype(float))))
    pts = [np.array([lines[0][0][lines[0][2]].min(), 0.0])]
    pts[0][1] = np.polyval(lines[0][1], pts[0][0])
    for (_, l0, _), (_, l1, _) in zip(lines, lines[1:]):
        x = (l1[1] - l0[1]) / (l0[0] - l1[0])
        pts.append(np.array([x, np.polyval(l0, x)]))
    x = lines[-1][0][lines[-1][2]].max()
    pts.append(np.array([x, np.polyval(lines[-1][1], x)]))
    return pts, [c for _, c in peaks]


def kit_fit(masks):
    """Kit buildings = hip-roofed arms, one on each straight run of the front wall.

    The front wall bases are the chain of base lines at the bottom of each silhouette
    (front_polyline). Each arm is a block standing on its run and reaching back, away from
    the camera, along the other wall direction. Where the front turns toward the camera
    (a convex corner, the L's outer front corner) two arms share that front corner; where
    it turns away (a concave corner) they share the back corner, so each reaches past the
    corner by the other's depth. The union of hipped blocks is then exactly the building's
    roof: hips at the outer corners, valleys at the inner ones. The half-timbered upper
    storey is jettied out over the stone ground floor (the silhouette shows it at the
    ends), so each arm is jettied_faces(). Its hip ends are steeper than its long slopes
    (an equal-pitch hip left both roof ends short of the art).

    Buildings of one kit share its pieces, so they share its geometry: wall height, stone
    storey height, jetty, eave, pitch and end pitch are fitted jointly to every silhouette
    (fitted one by one, the inn and kit-538 disagreed by 13% on wall height and 2.6x on end
    pitch); only the arm depths are per building.
    """
    geo = []
    for mask in masks:
        pts, convex = front_polyline(mask)
        runs = [(pts[k], pts[k + 1]) for k in range(len(pts) - 1)]
        # The two wall directions (unit, pointing right), each averaged over its runs.
        dirs = {}
        for A, B in runs:
            d = (B - A) / np.linalg.norm(B - A)
            dirs.setdefault(d[1] > 0, []).append(B - A)
        unit = {k: np.sum(v, 0) / np.linalg.norm(np.sum(v, 0)) for k, v in dirs.items()}
        arms = []
        for A, B in runs:
            down = (B - A)[1] > 0
            # Back, away from the camera: up-right behind a run going down, up-left behind one going up.
            back = unit.get(not down, np.array([0.894, -0.447]) if down else np.array([-0.894, -0.447]))
            if not down:
                back = -back if back[1] > 0 else back
            arms.append((A, B, back))
        geo.append((arms, convex))

    def arm_faces(k, p, widths):
        arms, convex = geo[k]
        h, o, pitch, h1, j, pe = p[:6]
        faces = []
        for i, (A, B, back) in enumerate(arms):
            f = (B - A) / np.linalg.norm(B - A)
            a0 = A - f * (widths[i - 1] if i > 0 and not convex[i - 1] else 0.0)
            b0 = B + f * (widths[i + 1] if i + 1 < len(arms) and not convex[i] else 0.0)
            faces += jettied_faces(a0, b0, a0 + widths[i] * back, h1, h, j, o, pitch, 2 * i, pe)
        return faces

    offs = np.cumsum([0] + [len(g[0]) for g in geo])

    def faces(k, p):
        return arm_faces(k, p, p[6 + offs[k]:6 + offs[k + 1]])

    def iou(k, p):
        im = Image.new('L', (masks[k].shape[1], masks[k].shape[0]), 0)
        d = ImageDraw.Draw(im)
        for _, pts, _ in faces(k, p):
            d.polygon([(q[0], q[2] - q[1]) for q in pts], fill=1)
        s = np.array(im) > 0
        return np.logical_and(s, masks[k]).sum() / np.logical_or(s, masks[k]).sum()

    def owner(i):  # the building a parameter belongs to, or None for the shared geometry
        return None if i < 6 else int(np.searchsorted(offs, i - 6, side='right') - 1)

    grids = [np.arange(100, 360, 4), np.arange(0, 32, 2), np.arange(0.4, 1.8, 0.05), np.arange(40, 220, 4),
             np.arange(0, 50, 2), np.arange(0.6, 4.0, 0.1)] + [np.arange(60, 360, 4)] * int(offs[-1])
    top, top_s = None, -1.0
    for h0 in (150.0, 200.0, 250.0):
        cur = [h0, 10.0, 1.0, 100.0, 10.0, 1.0] + [200.0] * int(offs[-1])
        per = [iou(k, cur) for k in range(len(masks))]
        for _ in range(4):
            for i, g in enumerate(grids):
                who = owner(i)
                for val in g:
                    trial = list(cur); trial[i] = float(val)
                    tp = [iou(k, trial) for k in range(len(masks))] if who is None else \
                        per[:who] + [iou(who, trial)] + per[who + 1:]
                    if np.mean(tp) > np.mean(per):
                        cur, per = trial, tp
        if np.mean(per) > top_s:
            top, top_s = cur, float(np.mean(per))
    return [(geo[k], faces(k, top), iou(k, top)) for k in range(len(masks))], top


def back_twins(seqs):
    """Door panel path -> its door-less twin's path (see DOOR_FRAMES)."""
    fr = seqs['33']['frames']
    load = lambda k: np.array(Image.open(ROOT / 'game' / fr[k - 1]['path']).convert('RGBA')).astype(int)
    out = {}
    for k in DOOR_FRAMES:
        x = load(k)
        cands = [j for j in range(1, len(fr) + 1) if j not in DOOR_FRAMES and load(j).shape == x.shape
                 and (fr[j - 1]['dx'], fr[j - 1]['dy']) == (fr[k - 1]['dx'], fr[k - 1]['dy'])]
        diff = lambda j: ((np.abs(x[..., :3] - load(j)[..., :3]).sum(-1) > 60) | ((x[..., 3] > 127) != (load(j)[..., 3] > 127))).sum()
        out[fr[k - 1]['path']] = fr[min(cands, key=diff) - 1]['path']
    return out


def ray_height(faces, x, y, label=2):
    """Height of the nearest face with this label hit by the view ray through canvas point
    (x, y) (the points (x, Y, y + Y)), or None."""
    best = None
    for lab_, pts, _ in faces:
        if lab_ != label:
            continue
        P = np.array(pts, float)
        n = np.cross(P[1] - P[0], P[2] - P[0])
        den = n[1] + n[2]
        if abs(den) < 1e-6:
            continue
        yy = (n @ P[0] - n[0] * x - n[2] * y) / den
        q = np.array([x, yy, y + yy])
        s_ = [np.cross(P[(i + 1) % len(P)] - P[i], q - P[i]) @ n for i in range(len(P))]
        if min(s_) >= -1e-3 * (n @ n) or max(s_) <= 1e-3 * (n @ n):
            best = yy if best is None else max(best, yy)
    return best


def dormer_prism(p, f, b, kb):
    """A gabled dormer standing on a roof slope, in panel pixels with its foot line at Y = 0.

    Its front is a vertical gable parallel to the wall below: bottom centre (xc, 0, yc),
    half-width w along the wall direction f, cheek height hc, gable rise r. It runs back
    along b, away from the camera, until the roof it stands on (rising kb per unit of b)
    closes over it: each front vertex at height Y reaches back Y / kb. That is the dormer
    a roofer builds, so nothing behind the gable is fitted: the roof pitch decides it.
    Faces: gable, two cheeks, two roof slopes."""
    xc, yc, w, hc, r = p
    f3, b3, up = np.array([f[0], 0, f[1]]), np.array([b[0], 0, b[1]]), np.array([0, 1.0, 0])
    C0 = np.array([xc, 0, yc])
    BL, BR = C0 - w * f3, C0 + w * f3
    TL, TR, AP = BL + hc * up, BR + hc * up, C0 + (hc + r) * up
    TLb, TRb, APb = TL + hc / kb * b3, TR + hc / kb * b3, AP + (hc + r) / kb * b3
    return [[BL, BR, TR, AP, TL], [BL, TL, TLb], [BR, TR, TRb], [TL, AP, APb, TLb], [TR, AP, APb, TRb]]


def dormers(seqs, kit_fits, pitch):
    """The dormers of the kit's roof panels, as upright prisms (dormer_prism).

    A dormer panel's plain twin is identical to it except where the dormer and its shadow
    are, so their difference finds both. The shadow keeps the plain roof's texture,
    darkened (high local normalised cross-correlation); the dormer replaces it. The prism is
    fitted to the rest: which way the gable faces (down-left on a roof running down to the
    right, or down-right), and a geometry shared by all the panels (they draw one dormer in
    two orientations: fitted one by one they agreed within 4 px), with each panel's own
    foot. The wall directions and pitch are the kit's (kit_fit)."""
    dn, up = [], []
    for arms, _ in kit_fits:
        for A, B, _ in arms:
            (dn if B[1] > A[1] else up).append(B - A)
    a_, b_ = np.sum(dn, 0), np.sum(up, 0)
    a_, b_ = a_ / np.linalg.norm(a_), b_ / np.linalg.norm(b_)
    orient = {'down-left': (a_, b_), 'down-right': (b_, -a_)}
    frames = seqs['33']['frames']
    load = lambda k: np.array(Image.open(ROOT / 'game' / frames[k - 1]['path']).convert('RGBA')).astype(float)
    panels = []
    for k in DORMER_FRAMES:
        x = load(k)
        twins = [j for j in range(1, len(frames) + 1) if j not in DORMER_FRAMES and load(j).shape == x.shape]
        diffs = [((np.abs(x[..., :3] - load(j)[..., :3]).sum(-1) > 60) | ((x[..., 3] > 127) != (load(j)[..., 3] > 127)))
                 for j in twins]
        j = int(np.argmin([d.sum() for d in diffs]))
        D, y = diffs[j], load(twins[j])
        D = ndimage.binary_opening(D, iterations=1)
        lab_, _ = ndimage.label(D)
        D = lab_ == 1 + np.argmax(np.bincount(lab_.ravel())[1:])
        lx, ly = x[..., :3].mean(-1), y[..., :3].mean(-1)
        m = lambda z: ndimage.uniform_filter(z, 7)
        mx, my = m(lx), m(ly)
        ncc = (m(lx * ly) - mx * my) / np.sqrt(np.maximum((m(lx * lx) - mx * mx) * (m(ly * ly) - my * my), 1e-6))
        body = ndimage.binary_opening(D & (ncc < 0.5), iterations=1)
        lab_, _ = ndimage.label(body)
        body = lab_ == 1 + np.argmax(np.bincount(lab_.ravel())[1:])
        body = ndimage.binary_fill_holes(ndimage.binary_closing(body, iterations=2))
        ys, xs = np.nonzero(body)
        panels.append({'frame': k, 'twin': twins[j], 'body': body, 'foot0': [float(xs[np.argmax(ys)]), float(ys.max())]})

    def iou(pn, p, o):
        f, b = orient[o]
        im = Image.new('L', (pn['body'].shape[1], pn['body'].shape[0]), 0)
        d = ImageDraw.Draw(im)
        for F in dormer_prism(p, f, b, pitch * abs(f[0] * b[1] - f[1] * b[0])):
            d.polygon([(q[0], q[2] - q[1]) for q in F], fill=1)
        s_ = np.array(im) > 0
        return (s_ & pn['body']).sum() / (s_ | pn['body']).sum()

    def descend(cur, score, grids, free):
        best = score(cur)
        for _ in range(5):
            for i in free:
                for v in grids[i]:
                    t = list(cur); t[i] = float(v)
                    s_ = score(t)
                    if s_ > best:
                        cur, best = t, s_
        return cur, best

    # One by one, both orientations: the better one is the panel's.
    g5 = [np.arange(0, 100, 1.0), np.arange(100, 200, 1.0), np.arange(4, 50, 1.0), np.arange(2, 60, 1.0), np.arange(2, 60, 1.0)]
    for pn in panels:
        fits = [(descend(pn['foot0'] + [20.0, 15.0, 15.0], lambda p: iou(pn, p, o), g5, range(5)), o) for o in orient]
        (pn['p'], _), pn['orient'] = max(fits, key=lambda t: t[0][1])
    # Jointly: shared w, hc, r; each panel's foot.
    n = len(panels)
    cur = [float(np.mean([pn['p'][i] for pn in panels])) for i in (2, 3, 4)] + [c for pn in panels for c in pn['p'][:2]]
    grids = g5[2:] + [g5[0], g5[1]] * n
    score = lambda q: np.mean([iou(pn, q[3 + 2 * i:5 + 2 * i] + q[:3], pn['orient']) for i, pn in enumerate(panels)])
    cur, _ = descend(cur, score, grids, range(len(cur)))
    out = {}
    for i, pn in enumerate(panels):
        p = cur[3 + 2 * i:5 + 2 * i] + cur[:3]
        f, b = orient[pn['orient']]
        faces = dormer_prism(p, f, b, pitch * abs(f[0] * b[1] - f[1] * b[0]))
        out[frames[pn['frame'] - 1]['path']] = {
            'twin': frames[pn['twin'] - 1]['path'], 'faces': faces, 'foot': p[:2], 'f': f, 'b': b,
            'orient': pn['orient'], 'iou': round(float(iou(pn, p, pn['orient'])), 3), 'params': [round(v, 1) for v in p]}
    return out


def place_dormers(world, seqs, members, faces, top_left, panels):
    """Each dormer panel of a building: its prism lifted along the view ray onto the
    building's roof (the ray through its foot, as for the chimneys), in building pixels,
    with a texture coordinate (panel pixels) per vertex: the projection for faces the
    original camera saw, the mirror image across the dormer's own middle for the rest."""
    out = []
    for key in members:
        if key[1] != 's':
            continue
        e = world['screens'][str(key[0])]['sprites'][key[2]]
        f_ = seqs[str(e['seq'])]['frames'][e['frame'] - 1]
        pn = panels.get(f_['path'])
        if pn is None:
            continue
        o = origin(key[0])
        at = np.array([o[0] + e['x'] - 20 - f_['dx'] - top_left[0], o[1] + e['y'] - f_['dy'] - top_left[1]], float)
        lift = ray_height(faces, at[0] + pn['foot'][0], at[1] + pn['foot'][1])
        if lift is None:
            continue
        C0 = np.array([pn['foot'][0], 0.0, pn['foot'][1]])
        f3, b3 = np.array([pn['f'][0], 0, pn['f'][1]]), np.array([pn['b'][0], 0, pn['b'][1]])
        basis = np.linalg.inv(np.array([f3[[0, 2]], b3[[0, 2]]]).T)
        centre = np.mean([q for F in pn['faces'] for q in F], 0)
        polys = []
        for F in pn['faces']:
            P = np.array(F)
            nrm = np.cross(P[1] - P[0], P[2] - P[0])
            if nrm @ (P.mean(0) - centre) < 0:
                nrm = -nrm
            seen = nrm @ np.array([0, 1.0, 1.0]) > 0.2 * np.linalg.norm(nrm)
            uv = []
            for q in P:
                if not seen:  # mirror across the plane through the ridge: flip the f component
                    al, be = basis @ (q - C0)[[0, 2]]
                    g = -al * f3 + be * b3
                    q = np.array([C0[0] + g[0], q[1], C0[2] + g[2]])
                uv.append([round(float(q[0]), 2), round(float(q[2] - q[1]), 2)])
            pts = [[round(float(q[0] + at[0]), 2), round(float(q[1] + lift), 2), round(float(q[2] + at[1] + lift), 2)] for q in P]
            polys.append({'pts': pts, 'uv': uv})
        out.append({'member': key, 'path': f_['path'], 'faces': polys})
    return out


def cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def ray_hits(faces, x, y):
    """Whether the view ray through canvas point (x, y), i.e. the points (x, Y, y + Y),
    meets any face of the building."""
    for _, pts, _ in faces:
        P = np.array(pts, float)
        n = np.cross(P[1] - P[0], P[2] - P[0])
        den = n[1] + n[2]
        if abs(den) < 1e-6:
            continue
        yy = (n @ P[0] - n[0] * x - n[2] * y) / den
        q = np.array([x, yy, y + yy])
        s_ = [np.cross(P[(i + 1) % len(P)] - P[i], q - P[i]) @ n for i in range(len(P))]
        if yy >= 0 and (min(s_) >= -1e-3 * (n @ n) or max(s_) <= 1e-3 * (n @ n)):
            return True
    return False


def wall_details(world, seqs, screens, faces, top_left, members, mask, kit=KIT):
    """Sprites the original draws on the building (hanging signs): the view ray through
    the foot of the sprite as the original shows it (the lowest visible pixel of its
    centre column)
    lands on the building, not on the ground in front of it. Their hotspots sit behind the
    drawn wall for the engine's depth sort, where the solid building would swallow them,
    so they join its pieces and are drawn onto its walls in the original draw order, like
    the doors and windows composited onto a house. Whatever the building covers in the
    original (a tree behind it) never qualifies: its foot is not visible. Nor does anything
    standing through the building (a tree beside its back corner): a sign is drawn on the
    building, so most of its visible pixels lie on the building's own mask. Over the seven kit
    buildings, trees and the like have 0-1% there, signs 80-100% (80% overhangs a wall end)."""
    have = {tuple(m) for m in members}
    extra = []
    for n in screens:
        o = origin(n)
        sp = world['screens'][str(n)]['sprites']
        ids = np.full((400, 600), -1, int)
        for i in draw_order(sp):
            e = sp[i]
            fs = seqs.get(str(e['seq']), {}).get('frames', [])
            if e['vision'] != 0 or e['type'] == 2 or not 0 < e['frame'] <= len(fs):
                continue
            f = fs[e['frame'] - 1]
            rgba = np.array(Image.open(ROOT / 'game' / f['path']).convert('RGBA'))
            opaque = (rgba[..., 3] >= 128) & ~is_dither(rgba)
            x0, y0 = int(e['x'] - 20 - f['dx']), int(e['y'] - f['dy'])
            ys, xs = np.nonzero(opaque)
            ys, xs = ys + y0, xs + x0
            k = (xs >= 0) & (xs < 600) & (ys >= 0) & (ys < 400)
            ids[ys[k], xs[k]] = i
        for i, e in enumerate(sp):
            if (n, 's', i) in have or e['seq'] in kit['seqs'] or not (ids == i).any():
                continue
            # The foot: the bottom of the sprite's centre column (a hanging sign's lowest
            # corner can overhang the wall's end).
            ys, xs = np.nonzero(ids == i)
            xc = int(np.median(xs))
            near = np.abs(xs - xc) <= 1
            foot = (xc + o[0] - top_left[0], ys[near].max() + o[1] - top_left[1])
            bx, by = xs + o[0] - top_left[0], ys + o[1] - top_left[1]
            inside = (bx >= 0) & (by >= 0) & (bx < mask.shape[1]) & (by < mask.shape[0])
            on = np.zeros(len(xs), bool)
            on[inside] = mask[by[inside], bx[inside]]
            if ray_hits(faces, *foot) and on.mean() > 0.5:
                extra.append([n, 's', i])
    return extra


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
    out['_roof_pieces'] = {}
    for seq, frame in ROOF_PIECES:
        fr = seqs[str(seq)]['frames'][frame - 1]
        out['_roof_pieces'][fr['path']] = rp = roof_piece(np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA')))
        print(fr['path'], rp)
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    out['_kit_buildings'] = []
    kits = [b for cluster in kit_clusters(world) for b in kit_canvas(world, seqs, cluster)]
    fits, p = kit_fit([k[2] for k in kits])
    print('kit geometry (wall, eave, pitch, stone storey, jetty, end pitch):', [round(x, 2) for x in p[:6]])
    panels = dormers(seqs, [g for g, _, _ in fits], p[2])
    # For the backs (which mirror the fronts): door panels' twins, and the door sprites to leave off.
    out['_kit'] = {'seqs': KIT['seqs'], 'back': back_twins(seqs),
                   'doors': [f['path'] for q, k in DOOR_SPRITES for i, f in enumerate(seqs[str(q)]['frames']) if k in (None, i + 1)]}
    out['_dormer_panels'] = {}
    for path, pn in panels.items():
        # What the dormer covers on its panel from the original camera: the twin shows there.
        out['_dormer_panels'][path] = {'twin': pn['twin'], 'poly': [[[round(float(q[0]), 2), round(float(q[2] - q[1]), 2)] for q in F] for F in pn['faces']]}
        print(path, 'dormer', pn['orient'], 'twin', pn['twin'].split('/')[-1], 'foot, w, hc, r', pn['params'], 'IoU', pn['iou'])
    for (rgba, (wx, wy), mask, members, screens), ((arms, convex), faces, s) in zip(kits, fits):
        # Named after the screen of its lowest front corner (the inn is kit-537).
        front = [arms[0][0]] + [B for _, B, _ in arms]
        low = max(front, key=lambda q: q[1])
        name = 'kit-%d' % (int((wy + low[1]) // 400) * COLS + int((wx + low[0]) // 600) + 1)
        members = members + wall_details(world, seqs, screens, faces, (wx, wy), members, mask)
        out['_kit_buildings'].append({
            'name': name, 'screens': screens, 'members': members, 'rect': [int(wx), int(wy), rgba.shape[1], rgba.shape[0]],
            'score': round(s, 3),
            'faces': [{'label': lab_, 'block': blk, 'pts': [[round(float(c), 2) for c in pt] for pt in pts]} for lab_, pts, blk in faces],
            # Blocks: 2k the stone storey of arm k, 2k + 1 its upper storey and roof. The
            # jetty hides the top of the stone from the original camera as the eave hides
            # the top of the upper storey.
            'centers': [block_center(faces, b) for b in range(2 * len(arms))], 'overhangs': [p[4], p[1]] * len(arms),
            'params': [round(x, 3) for x in p[:6]], 'front': [[round(float(c), 2) for c in q] for q in front],
            'convex': convex, 'dormers': place_dormers(world, seqs, members, faces, (wx, wy), panels)})
        over = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
        over.alpha_composite(Image.fromarray(rgba))
        d = ImageDraw.Draw(over)
        cols = [(0, 255, 255, 255), (255, 255, 0, 255), (0, 255, 0, 255), (255, 128, 0, 255)]
        for _, pts, blk in faces:
            d.polygon([(pt[0], pt[2] - pt[1]) for pt in pts], outline=cols[blk // 2 % 4])
        over.save(Path(args.sheet) / f"fit-{name}.png")
        print(name, screens, 'arms', len(arms), 'silhouette IoU %.3f' % s, len(members), 'pieces')
    Path(args.out).write_text(json.dumps(out, indent=1))


if __name__ == '__main__':
    main()
