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
Verdict (2026-09-29, Opus 5.5, fourth pass): seq 63 frames 5 and 7 fit jointly with their mirror
twins 4 and 8; the log cabin (seq 59 frame 1) as a gable block with a standing chimney read from
its foot and top (BUILDINGS); the church (seq 60 frame 1) as nave, chancel, apse, spire and
buttresses, silhouette IoU 0.956 (built by a Sonnet 5.5 subagent). See DIRECTION.md.
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
HOUSES = [(63, 1, 1, [0.9], {}), (63, 4, 2, [0.8, 1.1], {1: 10.0}), (63, 6, 1, [1.1], {}), (63, 8, 1, [1.1], {}),
          (63, 5, 2, [0.8, 1.1], {1: 10.0}), (63, 7, 1, [1.1], {})]
# Mirror twins: frames 5 and 7 are 4 and 8 drawn mirrored (silhouette IoU 0.99 against the
# mirrored twin; the lighting was re-rendered). One house drawn twice has one geometry, so each
# pair is fitted jointly (each sprite keeps its own base lines) and takes its twin's pitches.
# Fitted alone, home-05 settled on a smaller upper block (inset 0.25 against home-04's 0.20)
# whose roof fell 20 px short of the drawn peak on screen 500.
TWINS = {5: 4, 7: 8}
# Roof pieces: separate sprites the original draws over a house's roof (the chimneys of
# seq 63). Each is an upright prism; see roof_piece().
ROOF_PIECES = [(63, 11), (63, 12)]
# Chimneys standing on the ground beside a house, their own sprites; see standing_piece().
GROUND_PIECES = [(63, 13)]
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


def block_faces(F, L, R, y0, hw, o, pitch, block=0, end_pitch=None, thick=0.0, bulge=0.0):
    """Faces as lists of 3D points (X, Y, Z) with a label. Ground point (x, z) = sprite (x, y).
    The hip ends take the side pitch unless end_pitch is given (a steeper end hip, whose
    ridge runs closer to the end walls).

    thick: thatch has a thickness. The slopes are its top; its underside is the same slopes
    lowered by `thick`, and a thatch edge (a fascia) hangs from the eave all round, as the drawn
    eave roll hangs in front of the top of the wall. Without it a thatched roof reads as a thin
    board at eye level. (Raised instead, above the slopes, it was confounded with `bulge`: the
    silhouette cannot tell a thicker roof from a fuller one.)

    bulge: drawn thatch is convex, like a dome. Each slope breaks halfway up its hip lines, where
    the roof is raised by `bulge`: a steeper lower facet and a flatter upper one, all planar (the
    break line is parallel to the eave and the ridge). A straight slope runs under the drawn
    upper edges (home-10's core roof on 318)."""
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
    n_roof = 4
    if not bulge:
        faces.append((2, [e3[0], e3[1], p1, p0], block))      # long side at F
        faces.append((2, [e3[1], e3[2], p1], block))          # hip
        faces.append((2, [e3[2], e3[3], p0, p1], block))      # far long side
        faces.append((2, [e3[3], e3[0], p0], block))          # hip
    else:
        mid = lambda a, b: tuple((a[k] + b[k]) / 2 + (bulge if k == 1 else 0.0) for k in range(3))
        m = [mid(e3[0], p0), mid(e3[1], p1), mid(e3[2], p1), mid(e3[3], p0)]
        faces += [(2, [e3[0], e3[1], m[1], m[0]], block), (2, [e3[1], e3[2], m[2], m[1]], block),
                  (2, [e3[2], e3[3], m[3], m[2]], block), (2, [e3[3], e3[0], m[0], m[3]], block),
                  (2, [m[0], m[1], p1, p0], block), (2, [m[1], m[2], p1], block),
                  (2, [m[2], m[3], p0, p1], block), (2, [m[3], m[0], p0], block)]
        n_roof = 8
    if thick:
        dn = lambda q: (q[0], q[1] - thick, q[2])
        faces += [(2, [dn(q) for q in pts], block) for _, pts, _ in faces[-n_roof:]]
        faces += [(2, [dn(e3[i]), dn(e3[(i + 1) % 4]), e3[(i + 1) % 4], e3[i]], block) for i in range(4)]
    return faces


def block_center(faces, block):
    walls = [p for lab, pts, b in faces if b == block and lab == 1 for p in pts]
    xs, ys, zs = zip(*walls)
    return [round(float(np.mean(xs)), 2), round(float(np.mean(ys)), 2), round(float(np.mean(zs)), 2)]


def house_faces(F, L, R, params, blocks, thick=0.0, bulge=0.0):
    faces = block_faces(F, L, R, 0.0, *params[:3], thick=thick, bulge=bulge)
    if blocks == 2:
        s, h2, o2, p2 = params[3:7]
        C = (L + R) / 2
        k = max(0.2, 1 - s)
        faces += block_faces(C + (F - C) * k, C + (L - C) * k, C + (R - C) * k, params[0], h2, o2, p2, 1, thick=thick, bulge=bulge)
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


def clip_tips(faces, body):
    """Each roof block's two side tips cut where the drawn roof ends. A hip roof's eave, offset o
    from its walls, stands 2.1 o out at the footprint's acute corners (52 degrees: the rhombus the
    1:1 ground makes of a house), the left and right tips on screen: past the drawn roof from the
    original camera, and a flat blade of thatch at eye level. The drawn roof keeps its hip lines
    straight out towards the tips (rounding the eave pulled them in, and every house got worse
    from the original camera) but stops short. So each block's leftmost and rightmost roof points
    are cut by the vertical plane x = the sprite's own extent in the tip's row, and the planes and
    hip lines are left as they are."""
    rows = [np.nonzero(r)[0] for r in body]
    out = list(faces)
    for blk in {b for _, _, b in faces}:
        roof = [q for l_, pts, b in faces if b == blk and l_ == 2 for q in pts]
        for side in (-1, 1):
            tip = min(roof, key=lambda q: q[0]) if side < 0 else max(roof, key=lambda q: q[0])
            y = int(round(tip[2] - tip[1]))
            near = [x for r in range(max(0, y - 1), min(len(rows), y + 2)) for x in rows[r]]
            if not near:
                continue
            cut = min(near) if side < 0 else max(near)
            if side * (tip[0] - cut) <= 1:
                continue
            clipped = []
            for l_, pts, b in out:
                if b != blk or l_ != 2:
                    clipped.append((l_, pts, b)); continue
                P, keep = list(pts), []
                inside = lambda q: side * (q[0] - cut) <= 0
                for i, q in enumerate(P):  # Sutherland-Hodgman against the plane x = cut
                    r_ = P[(i + 1) % len(P)]
                    if inside(q):
                        keep.append(q)
                    if inside(q) != inside(r_):
                        t = (cut - q[0]) / (r_[0] - q[0])
                        keep.append(tuple(float(q[k] + t * (r_[k] - q[k])) for k in range(3)))
                if len(keep) >= 3:
                    clipped.append((l_, keep, b))
            out = clipped
    return out


def fit(labs, blocks, fixed=None):
    """Shared parameters for one or more label maps of the same house (mirror twins), each
    with its own base lines; the score is their mean."""
    fixed = fixed or {}
    bases = [base_lines(lab) for lab in labs]
    sc = lambda p: float(np.mean([score(render(house_faces(F, L, R, p, blocks), lab.shape), lab)
                                  for (F, L, R), lab in zip(bases, labs)]))
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
        cur_s = sc(cur)
        for _ in range(4):
            for i, g in enumerate(grids):
                if i in fixed:
                    continue
                for val in g:
                    trial = list(cur)
                    trial[i] = float(val)
                    s = sc(trial)
                    if s > cur_s:
                        cur, cur_s = trial, s
        if cur_s > top_s:
            top, top_s = cur, cur_s
    return bases, top, top_s


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


def standing_piece(rgba, dR, dL):
    """A chimney standing on the ground beside a house, as its own sprite (home-13): a rubble
    firebox under a tapering stack, read as the frustum from its foot to its top (as the cabin's,
    standing_chimney). The foot's bottom outline is two base lines along the art's wall directions
    meeting at the front corner (the lowest point); the top face is roof_piece's. Its axis is
    taken as vertical (the top's centre stands over the foot's), which fixes the height. Returns
    roof_piece's dict plus 'base', the foot's corners (ground, sprite pixels), and 'height'."""
    rp = roof_piece(rgba)
    body = silhouette(rgba)
    bot = {x: np.nonzero(body[:, x])[0].max() for x in range(body.shape[1]) if body[:, x].any()}
    X = np.array(sorted(bot)); Y = np.array([bot[x] for x in X], float)
    xc = X[np.argmax(Y)]
    sl, sr = dL[1] / dL[0], dR[1] / dR[0]
    cl = np.median((Y - sl * X)[X <= xc]); cr = np.median((Y - sr * X)[X >= xc])
    C = np.array([(cr - cl) / (sl - sr), 0.0]); C[1] = sl * C[0] + cl
    cw, cd = (C[0] - X.min()) / -dL[0], (X.max() - C[0]) / dR[0]
    base = [C, C + cd * dR, C + cd * dR + cw * dL, C + cw * dL]
    mid, top = np.mean(base, 0), np.mean(np.array(rp['top']), 0)
    rp['base'] = [[round(float(v), 2) for v in q] for q in base]
    rp['height'] = round(float(mid[1] - top[1]), 2)
    return rp


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


# --- General buildings: gable blocks and upright pieces (the cabin, the church) ------------
# Buildings that are neither hip-roofed cottages nor kit buildings are described by their
# parts (a gable block, a chimney standing on the ground, ...) in one frame: the art's two wall
# directions, which every fitted house shares to 0.001 (wall_dirs). The parts' dimensions are
# fitted to the sprite; which parts a building has is its description (BUILDINGS). Each face
# carries its texture coordinates (projection, or a mirror for faces the original camera never
# saw), and upright pieces standing in front of the body (a chimney) list their outlines, so the
# body's texture behind them can be filled from its own pixels instead of showing them.

def wall_dirs(houses):
    """The two wall directions of the art (unit, in sprite pixels on the 1:1 ground): dR along
    the walls whose base runs up to the right, dL up to the left, both from the front corner."""
    dr = [np.subtract(h['R'], h['F']) / np.linalg.norm(np.subtract(h['R'], h['F'])) for h in houses]
    dl = [np.subtract(h['L'], h['F']) / np.linalg.norm(np.subtract(h['L'], h['F'])) for h in houses]
    return np.mean(dr, 0), np.mean(dl, 0)


def P3(q, y):
    return (float(q[0]), float(y), float(q[1]))


def gable_faces(F, u, v, y0, hw, o, ov, pitch, block=0):
    """A gabled block on the footprint F, F+u, F+u+v, F+v with its ridge along u. The eaves
    (the sides along u) overhang by o, the verges (the gable ends) by ov, both perpendicular.
    The roof falls from the ridge at `pitch` (rise/run) to the eave edge at y0 + hw; the long
    walls rise to its underside and the end walls into the gable under it."""
    uh, vh = u / np.linalg.norm(u), v / np.linalg.norm(v)
    sin = abs(cross2(uh, vh))
    de, dv = o / sin, ov / sin
    E = [F - dv * uh - de * vh, F + u + dv * uh - de * vh, F + u + v + dv * uh + de * vh, F + v - dv * uh + de * vh]
    ye = y0 + hw
    yr = ye + pitch * (np.linalg.norm(v) * sin / 2 + o)
    yw = ye + pitch * o
    M0, M1 = (E[0] + E[3]) / 2, (E[1] + E[2]) / 2
    C = [F, F + u, F + u + v, F + v]
    faces = [(1, [P3(C[0], y0), P3(C[1], y0), P3(C[1], yw), P3(C[0], yw)], block),
             (1, [P3(C[3], y0), P3(C[2], y0), P3(C[2], yw), P3(C[3], yw)], block),
             (1, [P3(C[0], y0), P3(C[3], y0), P3(C[3], yw), P3((C[0] + C[3]) / 2, yr), P3(C[0], yw)], block),
             (1, [P3(C[1], y0), P3(C[2], y0), P3(C[2], yw), P3((C[1] + C[2]) / 2, yr), P3(C[1], yw)], block),
             (2, [P3(E[0], ye), P3(E[1], ye), P3(M1, yr), P3(M0, yr)], block),
             (2, [P3(E[3], ye), P3(E[2], ye), P3(M1, yr), P3(M0, yr)], block)]
    return faces


def box_faces(P, u, v, y0, y1, label, block):
    """An upright prism on the footprint P, P+u, P+u+v, P+v from y0 to y1, with its top."""
    C = [P, P + u, P + u + v, P + v]
    faces = [(label, [P3(C[i], y0), P3(C[(i + 1) % 4], y0), P3(C[(i + 1) % 4], y1), P3(C[i], y1)], block) for i in range(4)]
    return faces + [(label, [P3(c, y1) for c in C], block)]


def parts_score(faces, pieces, lab):
    """Agreement of a parts model with a sprite's label map (0 air, 1 wall, 2 roof): the mean of
    the silhouette IoU and the wall and roof IoUs. Pieces (a chimney, whose stone the colour
    classes confuse with both) count only in the silhouette: their pixels are left out of the
    class IoUs."""
    pred = render([(9 if b in pieces else l_, pts, b) for l_, pts, b in faces], lab.shape)
    s = [np.logical_and(pred > 0, lab > 0).sum() / max(np.logical_or(pred > 0, lab > 0).sum(), 1)]
    keep = pred != 9
    for c in (1, 2):
        a_, b_ = (pred == c) & keep, (lab == c) & keep
        s.append((a_ & b_).sum() / max((a_ | b_).sum(), 1))
    return float(np.mean(s))


def descend(cur, score_fn, grids, rounds=4):
    """Coordinate descent over the given grids (None = held)."""
    best = score_fn(cur)
    for _ in range(rounds):
        improved = False
        for i, g in enumerate(grids):
            if g is None:
                continue
            for val in g:
                t = list(cur); t[i] = float(val)
                s_ = score_fn(t)
                if s_ > best:
                    cur, best, improved = t, s_, True
        if not improved:
            break
    return cur, best


def frustum_faces(Pb, ub, vb, y0, Pt, ut, vt, y1, label, block):
    """An upright frustum: the footprint Pb, Pb+ub, Pb+ub+vb, Pb+vb at y0, the top Pt, ... at y1."""
    B = [Pb, Pb + ub, Pb + ub + vb, Pb + vb]
    T = [Pt, Pt + ut, Pt + ut + vt, Pt + vt]
    faces = [(label, [P3(B[i], y0), P3(B[(i + 1) % 4], y0), P3(T[(i + 1) % 4], y1), P3(T[i], y1)], block) for i in range(4)]
    return faces + [(label, [P3(c, y1) for c in T], block)]


def silhouette(rgba):
    """The sprite's body: opaque, shadow dither removed, its largest component, holes filled."""
    body = ndimage.binary_opening((rgba[..., 3] >= 128) & ~is_dither(rgba), iterations=1)
    lab_, _ = ndimage.label(body)
    return ndimage.binary_fill_holes(lab_ == 1 + np.argmax(np.bincount(lab_.ravel())[1:]))


def cabin_parts(p, dR, dL):
    """The log cabin (seq 59 frame 1), for the fit: one gable block, its ridge along dR, and a
    box where the stone chimney stands on the ground against the gable end at F -> F + v (centre
    t along the wall, width cw, depth cd, height ch). The box only keeps the chimney's pixels out
    of the block's fit; the chimney itself is read afterwards (standing_chimney). Params: F (2),
    a, b, wall height, eave, verge, pitch, t, cw, cd, ch."""
    fx, fy, a, b, hw, o, ov, pitch, t, cw, cd, ch = p
    F = np.array([fx, fy])
    faces = gable_faces(F, a * dR, b * dL, 0.0, hw, o, ov, pitch, 0)
    faces += box_faces(F + (t - cw / 2) * dL - cd * dR, (cd + 2) * dR, cw * dL, 0.0, ch, 2, 1)
    return faces, {1}, {0: (hw, o)}


def standing_chimney(rgba, p, dR, dL):
    """The cabin's chimney, read from the two parts of it that show against the air: its foot,
    below the gable wall's base, and its top face, above the roof. Its sides lie inside the
    building's silhouette, and its stone and the logs cannot be told apart by colour, so no fit
    sees them (three attempts on 2026-09-29 each settled the silhouette with a wrong chimney).

    The foot's bottom outline is two base lines along the art's wall directions meeting at the
    front corner: the outer face (along dL) from its left end, the side (along dR) back to the
    wall. The top face shows as a parallelogram (as a roof chimney's does, roof_piece): its left
    edge runs along dR to the back corner, which stands on the wall line, so it fixes the height.
    The chimney is the frustum from the foot to the top, against the wall; the art's shoulder
    between firebox and stack is left to the texture."""
    faces, _, eaves = cabin_parts(p, dR, dL)
    faces = [f for f in faces if f[2] == 0]
    F = np.array(p[:2])
    body = silhouette(rgba)
    res = body & ~ndimage.binary_dilation(render(faces, body.shape) > 0, iterations=1)
    lab_, n = ndimage.label(res)
    comps = [np.nonzero(lab_ == k) for k in range(1, n + 1)]
    # Nearest the chimney's box: the foot below it, the top above it.
    cx = F[0] + p[8] * dL[0]
    near = [c for c in comps if len(c[0]) >= 60 and abs(np.median(c[1]) - cx) < p[9]]
    foot = max(near, key=lambda c: c[0].max())
    top = min(near, key=lambda c: c[0].min())
    ys, xs = foot
    bot = {x: ys[xs == x].max() for x in np.unique(xs)}
    X = np.array(sorted(bot)); Y = np.array([bot[x] for x in X], float)
    xc = X[np.argmax(Y)]
    sl, sr = dL[1] / dL[0], dR[1] / dR[0]
    cl = np.median((Y - sl * X)[X <= xc]); cr = np.median((Y - sr * X)[X >= xc])
    C = np.array([(cr - cl) / (sl - sr), 0.0]); C[1] = sl * C[0] + cl
    cw, cd = (C[0] - X.min()) / -dL[0], (X.max() - C[0]) / dR[0]
    ys, xs = top
    tp = {x: ys[xs == x].min() for x in np.unique(xs)}
    X = np.array(sorted(tp)); Y = np.array([tp[x] for x in X], float)
    xb = X[np.argmin(Y)]
    bl = np.median((Y - sr * X)[X <= xb]); br = np.median((Y - sl * X)[X >= xb])
    B = np.array([(br - bl) / (sr - sl), 0.0]); B[1] = sr * B[0] + bl
    dt, wt = (B[0] - X.min()) / dR[0], (X.max() - B[0]) / -dL[0]
    s_ = (B[0] - F[0]) / dL[0]
    ch = F[1] + s_ * dL[1] - B[1]
    W = F + s_ * dL  # the top's back corner on the ground
    faces += frustum_faces(C, (cd + 2) * dR, cw * dL, 0.0, W - wt * dL - dt * dR, (dt + 2) * dR, wt * dL, ch, 2, 1)
    info = {'foot': C.round(1).tolist(), 'width': round(cw, 1), 'depth': round(cd, 1),
            'top width': round(wt, 1), 'top depth': round(dt, 1), 'height': round(ch, 1)}
    return faces, {1}, eaves, info


def smooth_labels(lab, size=5):
    """Majority label in a size x size window (the shingles' rust and moss patches, the dark gaps
    between logs)."""
    counts = [ndimage.uniform_filter((lab == c).astype(float), size) for c in range(3)]
    return np.argmax(counts, 0).astype(np.uint8)


def wood_labels(rgba):
    """Log walls (the warm, saturated class of classify) as walls, grey shingles as roof."""
    lab = classify(rgba)
    out = np.zeros_like(lab)
    out[lab == 2], out[lab == 1] = 1, 2
    return smooth_labels(out)


def uv_polys(faces, pieces, eaves, mirrors=None):
    """Each face with a texture coordinate per vertex, in sprite pixels. A face the original
    camera saw (turned south, as in the prototype's houses) is textured by projection,
    (x, z - y). One it never saw takes the point mirror of its part (about the part's centre), and
    the building's back canvas. On a long wall under an eave the band the eave hid from the camera
    (from the eave's shadow line ye - o/|n.z| up) takes the wall one band further down, shifted up:
    the band just under the eave carries the eave's own marks, and a mirror doubled them into
    chevrons (as in the prototype's _add_house).
    `eaves`: block -> (eave height ye, overhang o) for gable blocks.
    `mirrors`: block -> (origin, direction), both (x, z): a part whose unseen half is the mirror
    image of its seen half across a vertical plane (an apse: the plane through its axis, along
    the ridge) takes that reflection instead of the point mirror."""
    mirrors = mirrors or {}
    cen = {}
    for _, pts, b in faces:
        cen.setdefault(b, []).extend(pts)
    cen = {b: np.mean(np.array(v, float), 0) for b, v in cen.items()}
    out = []
    for lab_, pts, b in faces:
        P = np.array(pts, float)
        n = np.cross(P[1] - P[0], P[2] - P[0])
        n /= np.linalg.norm(n)
        if n @ (P.mean(0) - cen[b]) < 0:
            n = -n
        seen = n[2] >= -1e-6
        bands = [(P, None)]
        if lab_ == 1 and len(P) == 4 and b in eaves:
            ye, o = eaves[b]
            y0, top = P[:, 1].min(), P[:, 1].max()
            hs = max(ye - o / max(abs(n[2]), 0.3), y0 + 0.5 * (top - y0))
            lo = np.array([P[0], P[1], [P[1][0], hs, P[1][2]], [P[0][0], hs, P[0][2]]])
            hi = np.array([lo[3], lo[2], P[2], P[3]])
            bands = [(lo, None), (hi, min(2 * (top - hs), hs - y0))]
        for Q, shift in bands:
            uv = []
            for q in Q:
                q = q.copy()
                if not seen and b in mirrors:
                    o_, d_ = (np.array(c, float) for c in mirrors[b])
                    d_ = d_ / np.linalg.norm(d_)
                    w_ = np.array([q[0], q[2]]) - o_
                    q[0], q[2] = o_ + 2 * (w_ @ d_) * d_ - w_
                elif not seen:
                    q[0], q[2] = 2 * cen[b][0] - q[0], 2 * cen[b][2] - q[2]
                if shift is not None:
                    q[1] -= shift
                uv.append([round(float(q[0]), 2), round(float(q[2] - q[1]), 2)])
            out.append({'pts': [[round(float(c), 2) for c in q] for q in Q], 'uv': uv,
                        'back': bool(not seen), 'piece': bool(b in pieces)})
    return out


def occluders(faces, pieces):
    """Screen outlines (sprite pixels) of the faces of upright pieces the original camera saw:
    there the sprite shows the piece, not the body behind it."""
    polys = []
    for lab_, pts, b in faces:
        if b not in pieces:
            continue
        polys.append([[round(float(q[0]), 2), round(float(q[2] - q[1]), 2)] for q in pts])
    return polys


def church_labels(rgba):
    """The church (seq 60 frame 1): dark blue-grey stone walls, pale warm-grey shingles. Value
    alone loses the shingles in shade (the nave's ridge, the apse cone), so a roof is where the
    local mean of red - blue (shingles run warm, the stone runs cool) or of the value is high."""
    body = (rgba[..., 3] >= 128) & ~is_dither(rgba)
    rgb = rgba[..., :3].astype(float)
    w = body.astype(float)
    mean = lambda x: ndimage.uniform_filter(x * w, 7) / np.maximum(ndimage.uniform_filter(w, 7), 1e-3)
    lab = np.zeros(body.shape, np.uint8)
    lab[body] = 1
    lab[body & ((mean(rgb[..., 0] - rgb[..., 2]) > 5) | (mean(rgb.max(-1)) > 90))] = 2
    return smooth_labels(lab)


def church_layout(p, dR, dL):
    """The church's derived points, in ground pixels (x, z): the nave's front corner F, the
    chancel's (Fc: centred on the nave's axis, ending at the nave's gable wall) and the centre C
    of the apse's semicircle (the middle of the chancel's far gable wall)."""
    fx, fy, a, b, hw, o, ov, pitch, ac, bc = p[:10]
    F = np.array([fx, fy])
    Fc = F + (b - bc) / 2 * dL - ac * dR
    return F, Fc, Fc + bc / 2 * dL


def church_parts(p, dR, dL):
    """The church (seq 60 frame 1), for the fit. Nave: a gable block, ridge along dR, front
    corner F, length a, width b, wall height hw, eaves o, verges ov. Chancel: a lower, narrower
    gable block continuing it along -dR (length ac to the nave's gable wall, width bc, centred, wall
    height hwc, pitch pc, eaves oc; its verges are flush). Apse: a half cylinder against the
    chancel's far gable wall, as wide as the chancel (radius bc / 2 in the walls' own frame, so a
    circle of the true ground), wall height ha, with a half-cone roof (pitch pa, overhang oa).
    Tower: a square box (side ts, top th above the nave's ridge) standing on it, centred tc along
    it from F, under a pyramid of height sh. Buttresses: four tapered prisms against the nave's
    south wall (width bw, projecting bd, height bh), evenly spaced from s0 by ds. The tower, its
    spire and the buttresses are pieces: they stand in front of the body, so their outlines count
    in the silhouette only. Params: F (2), a, b, hw, o, ov, pitch, ac, bc, hwc, pc, oc, ha, pa, oa,
    tc, ts, th, sh, bw, bd, bh, s0, ds."""
    fx, fy, a, b, hw, o, ov, pitch, ac, bc, hwc, pc, oc, ha, pa, oa, tc, ts, th, sh, bw, bd, bh, s0, ds = p
    F, Fc, C = church_layout(p, dR, dL)
    sin = abs(cross2(dR, dL))
    faces = gable_faces(F, a * dR, b * dL, 0.0, hw, o, ov, pitch, 0)
    faces += gable_faces(Fc, (ac + 3) * dR, bc * dL, 0.0, hwc, oc, 0.0, pc, 1)
    r = bc / 2
    ring = lambda th, rad: C + rad * (math.cos(th) * dR + math.sin(th) * dL)
    ths = [math.pi / 2 + k * math.pi / 12 for k in range(13)]
    for t0, t1 in zip(ths, ths[1:]):
        faces.append((1, [P3(ring(t0, r), 0.0), P3(ring(t1, r), 0.0), P3(ring(t1, r), ha + pa * oa), P3(ring(t0, r), ha + pa * oa)], 2))
        faces.append((2, [P3(ring(t0, r + oa), ha), P3(ring(t1, r + oa), ha), P3(C, ha + pa * (r + oa))], 2))
    ridge = hw + pitch * (b * sin / 2 + o)  # the nave's ridge height
    T = F + tc * dR + b / 2 * dL
    yt = ridge + th
    y0 = ridge - pitch * ts * sin / 2 - 2  # low enough for the box's corners to meet the roof
    faces += box_faces(T - ts / 2 * (dR + dL), ts * dR, ts * dL, y0, yt, 1, 3)
    so = 2.0  # the spire's eave
    faces += frustum_faces(T - (ts / 2 + so) * (dR + dL), (ts + 2 * so) * dR, (ts + 2 * so) * dL, yt,
                           T - 0.25 * (dR + dL), 0.5 * dR, 0.5 * dL, yt + sh, 2, 4)
    for k in range(4):
        B = F + (s0 + k * ds - bw / 2) * dR
        faces += frustum_faces(B, bw * dR, -bd * dL, 0.0, B, bw * dR, -0.3 * bd * dL, bh, 1, 5 + k)
    return faces, {3, 4, 5, 6, 7, 8}, {0: (hw, o), 1: (hwc, oc)}


def church_score(faces, pieces, lab):
    """parts_score, plus the silhouette agreement in two windows that the whole sprite's area
    would drown: around the spire (the tower's height and the pyramid's are fixed only by its
    outline against the air) and along the nave's south base line, where the buttresses' feet
    show as bumps (the first face is the nave's south wall, whose base is that line)."""
    pred = render([(9 if b in pieces else l_, pts, b) for l_, pts, b in faces], lab.shape) > 0
    (x0, _, z0), (x1, _, z1) = faces[0][1][0], faces[0][1][1]
    yy, xx = np.mgrid[:lab.shape[0], :lab.shape[1]]
    zl = z0 + (xx - x0) * (z1 - z0) / (x1 - x0)
    wins = [(xx >= 270) & (xx < 370) & (yy < 125), (xx >= x0 - 5) & (xx < x1 + 25) & (yy > zl - 12) & (yy < zl + 18)]
    iou = [np.logical_and(pred & w, lab > 0).sum() / max(np.logical_or(pred & w, (lab > 0) & w).sum(), 1) for w in wins]
    return 0.6 * parts_score(faces, pieces, lab) + 0.2 * iou[0] + 0.2 * iou[1]


def church_spire_score(faces, pieces, lab):
    """The tower and spire, refined once the body is fitted: in the spire window (church_score) the
    tower's stone and the spire's shingles count by label as well as by outline. By outline alone
    the pyramid swallowed the tower's shaft (its top fitted at the grid's floor, 4 px above the
    ridge, under the art's dark louvred shaft). Depth-tested (render_z): in painter's order by whole
    faces the near roof slope sorted in front of the tower and hid its shaft."""
    lp = render_z(faces, lab.shape)
    win = np.zeros(lab.shape, bool)
    win[:125, 270:370] = True
    cls = [((lp == c) & (lab == c) & win).sum() / max((((lp == c) | (lab == c)) & win).sum(), 1) for c in (1, 2)]
    sil = ((lp > 0) & (lab > 0) & win).sum() / max((((lp > 0) | (lab > 0)) & win).sum(), 1)
    return 0.5 * sil + 0.5 * float(np.mean(cls))


def church_mirrors(p, dR, dL):
    """The apse's unseen (north) half is the mirror of its seen half across the vertical plane
    through the semicircle's centre along the ridge."""
    return {2: (church_layout(p, dR, dL)[2].tolist(), dR.tolist())}


# Buildings described by parts (see cabin_parts ...): the sprite, its parts, how its pixels are
# labelled, a start, the grids searched, and the starts tried for one parameter (the wall height,
# which has local optima as in fit()).
BUILDINGS = [
    {'seq': 59, 'frame': 1, 'parts': cabin_parts, 'labels': wood_labels,
     'p0': [120., 220., 208., 117., 80., 10., 15., 0.8, 58., 40., 30., 160.], 'starts': (4, [60., 90., 120.]),
     'grids': [np.arange(100, 140, 2.), np.arange(200, 235, 2.), np.arange(160, 260, 4.), np.arange(80, 160, 4.),
               np.arange(40, 140, 4.), np.arange(0, 30, 2.), np.arange(0, 40, 2.), np.arange(0.3, 1.6, 0.05),
               np.arange(20, 110, 2.), np.arange(16, 70, 2.), np.arange(8, 60, 2.), np.arange(80, 220, 4.)],
     'read': standing_chimney},
    # The church. The buttresses' height (bh) is held at the caps read from the art: their tops
    # lie inside the silhouette, so no score sees it. The tower's top is fitted as its height above
    # the ridge (th): free in absolute height, the descent sank the box and the pyramid's base into the roof.
    {'seq': 60, 'frame': 1, 'parts': church_parts, 'labels': church_labels, 'score': church_score,
     'mirrors': church_mirrors, 'refine': ([16, 17, 18, 19], church_spire_score),
     'p0': [194., 372., 226., 105., 127., 8., 4., 1.1, 96., 88., 114., 0.9, 8., 68., 0.8, 4.,
            191., 26., 8., 74., 14., 8., 86., 74., 52.],
     'starts': (4, [110., 130.]),
     'grids': [np.arange(186, 204, 1.), np.arange(364, 392, 1.), np.arange(200, 250, 2.), np.arange(90, 125, 1.),
               np.arange(100, 150, 2.), np.arange(0, 20, 1.), np.arange(0, 20, 1.), np.arange(0.7, 1.6, 0.05),
               np.arange(70, 120, 2.), np.arange(70, 105, 1.), np.arange(90, 140, 2.), np.arange(0.6, 1.4, 0.05),
               np.arange(0, 20, 1.), np.arange(40, 100, 2.), np.arange(0.3, 1.4, 0.05), np.arange(0, 14, 1.),
               np.arange(150, 230, 2.), np.arange(16, 50, 1.), np.arange(4, 50, 1.), np.arange(30, 100, 2.),
               np.arange(6, 32, 1.), np.arange(4, 16, 1.), None, np.arange(50, 110, 2.), np.arange(40, 70, 1.)]},
]


# ---- Cross-wing house: seq 63 frame 10, and frame 9 drawn mirrored -------------------------------
# A two-storey stone core with a hip thatch roof at the crossing of two one-storey hip-roofed wings.
# The bottom of the silhouette is a zig-zag of four straight runs (down, up, down, up) along the
# art's two wall directions: runs 0-1 are the long wing's front wall and its end wall up to the
# front wing, runs 2-3 the front wing's two walls. The "right wing behind the front wing" seen
# above its roof is the long wing's other end: its end wall (the stone patch between the two roofs)
# continues on the far side of the front wing, and the fit puts the long wing's width at 180 px.
# The plan is one rectangle per wing plus the core, each hip-roofed (block_faces), in plan
# coordinates (s along the wall direction of run 1, t along the direction of run 0) from the long
# wing's front corner C1. Frame 9 is frame 10 mirrored (silhouette IoU 0.99), so its zig-zag is
# read in reverse with the two directions swapped; the dimensions are shared, each sprite keeps
# its own zig-zag.
CROSS = (10, 9)
# Thatch thickness shared by every thatched house, set by main() from its search (block_faces).
THATCH = [0.0, 0.0]  # thickness, bulge
FLAT_HOUSES = False  # every thatched house takes the shared profile (see main)
# home-10's wing pitch is read from the art, as the other thatched houses' are: the front wing's
# hip end, its one ridge end drawn against contrast, peaks on the 1.05 line of an overlay of 0.65,
# 0.85 and 1.05 (2026-09-30). Fitted freely it went to 0.65, and the wings read as flat slabs.
# The core's pitch is read from the sprite's top 80 rows, where only the core's roof stands against
# the air (screen 318 shows exactly those rows): silhouette IoU there, both twins, at the fitted
# rest, peaks at 1.5 (1.1: 0.886, 1.3: 0.915, 1.5: 0.923, 1.7: 0.899, 2.0: 0.848). Fitted over the
# whole sprite it went to 1.25, and the core's roof stood a band below the drawn top edges.
CROSS_NAMES = ['long wing', 'front wing', 'core']


def render_z(faces, shape) -> np.ndarray:
    """Label map with a per-pixel depth test. The painter's order of render() sorts whole faces by
    their mean depth, wrong for a tall core wall beside low wing roofs; the prototype has a depth
    buffer, so the fit draws the same way. Depth along the view ray (0, 1, 1) is Y + Z."""
    h, w = shape
    zbuf = np.full((h, w), -1e18)
    out = np.zeros((h, w), np.uint8)
    for label, pts, _ in faces:
        P = np.array(pts, float)
        n = np.cross(P[1] - P[0], P[2] - P[0])
        if abs(n[1] + n[2]) < 1e-9:
            continue
        sx, sy = P[:, 0], P[:, 2] - P[:, 1]
        x0, x1 = max(int(np.floor(sx.min())), 0), min(int(np.ceil(sx.max())) + 1, w)
        y0, y1 = max(int(np.floor(sy.min())), 0), min(int(np.ceil(sy.max())) + 1, h)
        if x1 <= x0 or y1 <= y0:
            continue
        im = Image.new('L', (x1 - x0, y1 - y0), 0)
        ImageDraw.Draw(im).polygon([(a - x0, b - y0) for a, b in zip(sx, sy)], fill=1)
        yy, xx = np.nonzero(np.array(im))
        xx, yy = xx + x0, yy + y0
        Y = (n[0] * (P[0, 0] - xx) + n[1] * P[0, 1] + n[2] * (P[0, 2] - yy)) / (n[1] + n[2])
        depth = 2 * Y + yy
        upd = depth > zbuf[yy, xx]
        zbuf[yy[upd], xx[upd]] = depth[upd]
        out[yy[upd], xx[upd]] = label
    return out


def zigzag(mask, dR, dL):
    """Fit the bottom of a silhouette with the chain [down, up, down, up] whose runs follow the
    art's wall directions (slopes fixed): three breakpoints and one height, by a truncated
    absolute-error search. front_polyline() smooths over 41 px and merges runs this short.
    Returns the five points left to right: the wall base's two ends and the three corners."""
    bot = np.array([np.nonzero(mask[:, x])[0].max() if mask[:, x].any() else -1 for x in range(mask.shape[1])], float)
    xs = np.nonzero(bot >= 0)[0]
    md, mu = dL[1] / dL[0], dR[1] / dR[0]
    lo, hi = int(xs.min()) + 10, int(xs.max()) - 10
    x = np.arange(lo, hi + 1).astype(float)
    y = bot[lo:hi + 1]

    def shape_(x1, x2, x3, x=x):
        yk = mu * (x2 - x1)
        yc = yk + md * (x3 - x2)
        return np.where(x < x1, md * (x - x1), np.where(x < x2, mu * (x - x1),
                                                        np.where(x < x3, yk + md * (x - x2), yc + mu * (x - x3))))

    def cost(x1, x2, x3):
        r = y - shape_(x1, x2, x3)
        return float(np.minimum(np.abs(r - np.median(r)), 6).sum())
    best, best_c = None, 1e18
    for step, span in ((3, None), (1, 3)):
        cands = [(a, b, c) for a in range(lo + 20, hi - 40, 3) for b in range(a + 15, hi - 25, 3) for c in range(b + 15, hi - 10, 3)] \
            if span is None else [(a + i, b + j, c + k) for a, b, c in [best] for i in range(-3, 4) for j in range(-3, 4) for k in range(-3, 4)]
        for a, b, c in cands:
            v = cost(a, b, c)
            if v < best_c:
                best, best_c = (a, b, c), v
    x1, x2, x3 = best
    off = float(np.median(y - shape_(x1, x2, x3)))
    f = lambda xq: off + float(shape_(x1, x2, x3, x=np.array([float(xq)]))[0])
    xa = np.arange(int(xs.min()), int(xs.max()) + 1)
    ok = np.array([bot[i] >= 0 and abs(bot[i] - f(i)) < 3 for i in xa])
    left = [i for i, o_ in zip(xa, ok) if i <= x1 and o_]
    right = [i for i, o_ in zip(xa, ok) if i >= x3 and o_]
    xl, xr = min(left), max(right)
    return [np.array([q, f(q)]) for q in (xl, x1, x2, x3, xr)]


def cross_plan(Q, mirrored, dR, dL):
    """(C1, e_s, e_t, dims) from the zig-zag Q: C1 the left wing's front corner (Q[1], or Q[3] read
    in reverse for the mirrored sprite), e_s the direction of run 1, e_t of run 0, and the
    measured run extents in plan coordinates: tL (the left wing's long wall), sK (its end wall,
    to the concave corner), tC (how far the front wing's front corner stands in front), sE (its
    right wall's end)."""
    Qc = Q[::-1] if mirrored else Q
    es, et = (dL, dR) if mirrored else (dR, dL)
    C1 = Qc[1]
    st = [np.linalg.solve(np.array([es, et]).T, q - C1) for q in Qc]
    dims = {'tL': float(st[0][1]), 'sK': float((st[2][0] + st[3][0]) / 2), 'tC': float((st[3][1] + st[4][1]) / 2),
            'sE': float(st[4][0])}
    return C1, es, et, dims


CROSS_P0 = [80., 10., 1.05, 180., 200., 42., 24., 118., 102., 10., 1.5, 1.25]
CROSS_GRIDS = [np.arange(50, 110, 2.), np.arange(0, 24, 2.), None, np.arange(100, 260, 4.),
               np.arange(60, 260, 4.), np.arange(10, 120, 2.), np.arange(-10, 100, 2.), np.arange(60, 160, 2.),
               np.arange(60, 160, 2.), np.arange(0, 24, 2.), None, np.arange(0.9, 3.2, 0.1)]


def cross_labels(rgba):
    """Label map for the fit and a mask of pixels it cannot read. classify() takes the cast
    shadows (near-black, opaque) for air and speckles the walls and roofs with the other class;
    here each pixel takes the majority of stone and thatch in its 5 x 5 window, inside the drawn
    silhouette, and where the window holds (almost) none of either the pixel is unread, shadow."""
    lab = classify(rgba)
    sil = silhouette(rgba)
    c1 = ndimage.uniform_filter((lab == 1).astype(float), 5)
    c2 = ndimage.uniform_filter((lab == 2).astype(float), 5)
    out = np.where(c2 > c1, 2, 1).astype(np.uint8)
    out[~sil] = 0
    return out, sil & (c1 + c2 < 0.2)


def cross_score(pred, lab, unk):
    """score() with the unread pixels taking the model's label where it has one (a shadow on
    the roof may be anything the model draws there) and thatch where it has none."""
    ref = lab.copy()
    ref[unk] = np.where(pred[unk] > 0, pred[unk], 2)
    return score(pred, ref)


def cross_faces(plan, p):
    """Blocks 0 long wing, 1 front wing, 2 core. p = [h1, o, pitch, long wing width (s), front
    wing depth (t, from its front corner), core s0, t0, size s, size t, core eave, core pitch].
    The wings share wall height h1, eave o and pitch; the core is two storeys, 2 h1 (a rule: its
    foot is hidden by the wings' roofs, so its height and its ground position trade off along the
    view ray and the silhouette cannot tell them apart)."""
    C1, es, et, d = plan
    h1, o, pw, wL, fD, cs0, ct0, ca, cb, oc, pc = p[:11]
    pe = p[11] if len(p) > 11 else None  # the core's hip ends, steeper: its rounded thatch ends (318)
    G = lambda s, t: C1 + s * es + t * et
    rect = lambda s0, t0, ds, dt: (G(s0, t0), G(s0, t0 + dt), G(s0 + ds, t0))  # F, L, R
    fD = max(fD, -d['tC'] + 8)
    spec = [(rect(0, 0, wL, d['tL']), h1, o, pw), (rect(d['sK'], d['tC'], d['sE'] - d['sK'], fD), h1, o, pw),
            (rect(cs0, ct0, ca, cb), 2 * h1, oc, pc)]
    faces = []
    for k, ((F, L, R), hw, oo, pp) in enumerate(spec):
        faces += block_faces(F, L, R, 0.0, hw, oo, pp, k, end_pitch=pe if k == 2 else None, thick=THATCH[0], bulge=THATCH[1])
    return faces


def cross_fit(labs, unks, plans, grids=None, starts=(66., 80., 96.), p0=None):
    """Shared parameters for the twin sprites (mean of cross_score), coordinate descent from
    three wall heights as fit() does."""
    grids = CROSS_GRIDS if grids is None else grids
    sc = lambda p: float(np.mean([cross_score(render_z(cross_faces(pl, p), lab.shape), lab, u)
                                  for pl, lab, u in zip(plans, labs, unks)]))
    top, top_s = None, -1.0
    for h0 in starts:
        cur = list(CROSS_P0 if p0 is None else p0)
        cur[0] = h0
        cur, s_ = descend(cur, sc, grids, rounds=6)
        if s_ > top_s:
            top, top_s = cur, s_
    return top, top_s

def cross_houses(seqs, dR, dL, sheet, p=None):
    """Fit the cross-wing house and its mirror twin jointly (see CROSS); returns {sprite path:
    entry} in the format of the other houses (faces, centers, overhangs, score, params) plus
    'blocks' (names, in order) and 'front' (the zig-zag). No F, L, R: they would enter wall_dirs()."""
    rgbas, labs, unks, raws, plans, paths, zz = [], [], [], [], [], [], []
    for fr in CROSS:
        f = seqs['63']['frames'][fr - 1]
        rgba = np.array(Image.open(ROOT / 'game' / f['path']).convert('RGBA'))
        raw = classify(rgba)
        lab, unk = cross_labels(rgba)
        Q = zigzag(raw > 0, dR, dL)
        plans.append(cross_plan(Q, fr == CROSS[1], dR, dL))
        rgbas.append(rgba); labs.append(lab); unks.append(unk); raws.append(raw); paths.append(f['path']); zz.append(Q)
    if p is None:
        p, s_fit = cross_fit(labs, unks, plans)
    out = {}
    for k, fr in enumerate(CROSS):
        lab, rgba = labs[k], rgbas[k]
        s = cross_score(render_z(cross_faces(plans[k], p), lab.shape), lab, unks[k])
        s_raw = score(render_z(cross_faces(plans[k], p), lab.shape), raws[k])
        faces = clip_tips(cross_faces(plans[k], p), silhouette(rgba))
        pred = render_z(faces, lab.shape)
        iou = float(((pred > 0) & (lab > 0)).sum() / ((pred > 0) | (lab > 0)).sum())
        out[paths[k]] = {
            'score': round(s_raw, 3), 'score_clean': round(s, 3), 'iou': round(iou, 3),
            'faces': [{'label': l_, 'block': b, 'pts': [[round(float(c), 2) for c in pt] for pt in pts]} for l_, pts, b in faces],
            'centers': [block_center(faces, b) for b in range(3)],
            'overhangs': [p[1], p[1], p[9]],
            'params': [round(float(x), 3) for x in p], 'blocks': CROSS_NAMES,
            'front': [[round(float(c), 2) for c in q] for q in zz[k]]}
        pal = np.array([[255, 0, 255], [120, 120, 110], [220, 170, 60]], np.uint8)
        bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
        bg.alpha_composite(Image.fromarray(rgba))
        over = bg.copy()
        d = ImageDraw.Draw(over)
        cols = [(0, 255, 255, 255), (255, 255, 0, 255), (255, 128, 0, 255)]
        for _, pts, b in faces:
            d.polygon([(pt[0], pt[2] - pt[1]) for pt in pts], outline=cols[b])
        row = [bg, Image.fromarray(pal[lab]).convert('RGBA'), Image.fromarray(pal[pred]).convert('RGBA'), over]
        sh = Image.new('RGBA', (sum(r.width for r in row) + 30, row[0].height), (20, 20, 20, 255))
        x = 0
        for r in row:
            sh.paste(r, (x, 0)); x += r.width + 10
        sh.resize((sh.width * 2, sh.height * 2), Image.NEAREST).save(Path(sheet) / f'fit-63-{fr}.png')
        print(paths[k], 'score raw %.3f clean %.3f (after tips %.3f)' % (s_raw, s, cross_score(pred, lab, unks[k])), 'silhouette IoU %.3f' % iou, 'params', [round(float(x), 2) for x in p])
    return out


# --- The castle (struct/Castle, seq 67): walls and towers ----------------------------------------
# The same camera as the houses: screen = (X, Z - Y), the ground 1:1 in source px, so the drawn
# base of a wall standing on the ground IS its base line in plan, and a vertical face is the sprite
# sheared by its plan direction. Each castle sprite is a piece of wall, and a piece is a prism:
#   * the front face: the wall's base line (x, b(x)) up to a height; the drawn bricks;
#   * the walkway: a horizontal band of depth T behind the front face's top edge, seen from 45 degrees
#     (vertical screen extent Tv = T sqrt(1 + s^2) at a fixed x, s the base line's slope);
#   * the parapet: a thin crenellated wall standing on the walkway's far edge (frames 6, 8: the
#     inner face, walkway visible and the merlons behind it) or on its near edge (frames 7, 9: the
#     outer face, the merlons rise from the front face and hide the walkway). It stays in the
#     texture, as a strip with the sprite's own alpha (the gaps between merlons are see-through);
#   * the far face and the ends: the far face mirrors the front through the prism's centre.
# The base line is the least-squares line through the lowest drawn pixel of each column (the shadow
# dither, isolated black pixels, is left out). The face's top and the walkway's depth are found from
# the median brightness along the base line's parallels, u = (b(x) - y): the brick face, the dark
# walkway tiles and the bright merlon faces are three levels, and the best three-level fit puts the
# two edges. Frames 7 and 9 draw no walkway: they take their sibling's (6 and 8: the same wall seen
# from its other side, the same slope), and show their height as the top of the silhouette.
CASTLE = 'assets/graphics/struct/Castle/castl-%02d.png'
CASTLE_SEQ = 67
CASTLE_WALLS = {6: None, 8: None, 7: 6, 9: 8}  # frame -> the sibling whose walkway it takes
CASTLE_TOWERS = [4, 3, 1, 2]


def castle_rgba(frame: int) -> np.ndarray:
    return np.array(Image.open(ROOT / 'game' / (CASTLE % frame)).convert('RGBA'))


def castle_body(rgba: np.ndarray) -> np.ndarray:
    return (rgba[..., 3] >= 128) & ~is_dither(rgba)


def base_line(body: np.ndarray):
    """Slope and intercept of the wall's base: the lowest drawn pixel of each column, robust."""
    w = body.shape[1]
    xs = np.arange(w)
    bot = np.array([np.nonzero(body[:, x])[0].max() for x in range(w)])
    keep = np.ones(w, bool)
    for _ in range(4):
        s, c = np.polyfit(xs[keep], bot[keep], 1)
        keep = np.abs(bot - (s * xs + c)) <= 1.5
    return float(s), float(c), float(np.abs(bot - (s * xs + c)).std())


def wall_profile(rgba, body, s, c, u_max):
    """Median brightness of the drawn pixels on the base line's parallel u px above it (nan: fewer
    than 20 drawn)."""
    h, w = body.shape
    lum = rgba[..., :3].astype(float).mean(-1)
    prof = np.full(u_max, np.nan)
    xs = np.arange(w)
    for u in range(u_max):
        ys = np.round(s * xs + c).astype(int) - u
        ok = (ys >= 0) & (ys < h)
        ok[ok] = body[ys[ok], xs[ok]]
        if ok.sum() >= 20:
            prof[u] = np.median(lum[ys[ok], xs[ok]])
    return prof


def three_levels(prof, lo, hi):
    """The edges u1 < u2 in [lo, hi) where a three-level step through the profile fits best, the
    middle level darker than both outer ones (face, walkway, merlons). Returns (u1, u2, levels, sse)."""
    p = ndimage.median_filter(np.nan_to_num(prof, nan=0.0), size=3)
    best = None
    for u1 in range(lo + 10, hi - 12):
        a = p[lo:u1]
        for u2 in range(u1 + 8, hi - 6):
            b, d = p[u1:u2], p[u2:hi]
            la, lb, ld = a.mean(), b.mean(), d.mean()
            if not (lb < la - 15 and lb < ld - 15):
                continue
            sse = ((a - la) ** 2).sum() + ((b - lb) ** 2).sum() + ((d - ld) ** 2).sum()
            if best is None or sse < best[3]:
                best = (u1, u2, (round(la, 1), round(lb, 1), round(ld, 1)), float(sse))
    return best


def wall_fit(frame: int, fits: dict):
    """One wall sprite as a prism (see the section's comment); `fits` holds the siblings fitted so far."""
    rgba = castle_rgba(frame)
    body = castle_body(rgba)
    h, w = body.shape
    s, c, res = base_line(body)
    top = np.array([np.nonzero(body[:, x])[0].min() for x in range(w)])
    u_top = float(np.median(s * np.arange(w) + c - top))
    root = math.sqrt(1 + s * s)
    sib = CASTLE_WALLS[frame]
    if sib is None:
        u1, u2, levels, sse = three_levels(wall_profile(rgba, body, s, c, int(u_top) + 8), 60, int(u_top))
        hw, tv = float(u1), float(u2 - u1)
        parapet, y_top = 'back', u_top - tv  # the back plane's height: u = Y + Tv there
        info = {'levels': [float(v) for v in levels]}
    else:
        hw, tv = fits[sib]['parts'][0]['hw'], fits[sib]['parts'][0]['tv']
        parapet, y_top = 'front', u_top
        info = {'sibling': CASTLE % sib, 'dz': round(fits[sib]['parts'][0]['c'] - c, 2)}
    return {'size': [int(w), int(h)], 'resid': round(res, 2), 'parts': [{
        'type': 'wall', 'x0': 0, 'x1': int(w), 's': round(s, 4), 'c': round(c, 2), 'hw': hw, 'tv': tv,
        't': round(tv / root, 2), 'parapet': parapet, 'y_top': round(y_top, 1), 'u_top': round(u_top, 1), **info}]}


# Round towers (frames 1-4). The art draws a horizontal circle of the ground as an ellipse (the
# houses' rhombi are the same fact: the 2D game's ground is its screen), so a tower is an elliptic
# cylinder in the 1:1 ground, its ellipse one aspect k = b / a for the whole castle (measured on the
# plain tower, frame 4). A tower is a shaft (radius a, up to h1) and a wider body or crown (radius ar,
# up to the platform at h3), with the parapet (merlons, m high) around the platform. The sprites differ in
# the radii: the plain tower's wide body stands on a narrower plinth, frames 1 and 3 have a straight shaft
# under a corbelled crown. Fitted from the silhouette's edges and the lowest drawn pixels:
#   * the base arc (the lowest drawn pixel of the columns on the shaft's ellipse) and the silhouette's
#     left/right edge row by row are what a swept stack of ellipses predicts: half(y) = the widest ellipse
#     (a for heights up to h1, ar above) whose rows include y; least squares over (cx, cz, a, ar) for each h1
#     in turn, the h1 with the smallest residual;
#   * the parapet's height m is the walls' (the same castle: their measured merlon height above the walkway),
#     and the platform's height h3 follows from the silhouette's top row (the far merlons).
def swept(rows, cz, k, specs):
    """Per row: the half-width of the union of the ellipses of aspect k centred on rows cz - Y: specs
    [(radius, y_lo, y_hi), ...], or [(radius0, y0, radius1, y1)] for a frustum (a flare)."""
    half = np.zeros(len(rows))
    for sp in specs:
        if len(sp) == 3:
            r, y_lo, y_hi = sp
            ys = np.arange(int(y_lo), int(y_hi) + 1, 2)
            rs = np.full(len(ys), float(r))
        else:
            r0, y0, r1, y1 = sp
            ys = np.arange(int(y0), int(y1) + 1, 2)
            rs = r0 + (r1 - r0) * (ys - y0) / max(y1 - y0, 1e-9)
        if not len(ys):
            continue
        t = 1 - ((rows[:, None] - (cz - ys)[None, :]) / (k * rs[None, :])) ** 2
        half = np.maximum(half, (rs[None, :] * np.sqrt(np.clip(t, 0, None))).max(1))
    return half


def tower_edges(sil):
    rows = np.nonzero(sil.any(1))[0]
    left = np.array([np.nonzero(sil[y])[0].min() for y in rows], float)
    right = np.array([np.nonzero(sil[y])[0].max() + 1 for y in rows], float)
    return rows.astype(float), left, right


def tower_solve(frame, k, parapet, sides, arc_cols=None, top_row=None):
    """Fit one tower sprite: `sides` is which silhouette edges are the tower's ('L', 'R' or 'LR'), `arc_cols`
    the columns of its base arc, if drawn."""
    from scipy.optimize import least_squares
    rgba = castle_rgba(frame)
    body = castle_body(rgba)
    sil = silhouette(rgba)
    h, w = body.shape
    rows, left, right = tower_edges(sil)
    top_y = float(rows.min())
    bot = np.array([np.nonzero(body[:, x])[0].max() for x in range(w)])
    best = None
    ar0 = 96.0
    for h1, f in [(h1, f) for h1 in range(0, 230, 6) for f in (0, 8, 16, 24, 32, 40, 48) if h1 + f <= 230]:
        def resid(q):
            cx, cz, a, ar = q
            h3 = cz - k * ar - top_y - parapet
            half = swept(rows, cz, k, [(a, 0, h1), (a, h1, ar, h1 + f), (ar, h1 + f, h3 + parapet)] if f else [(a, 0, h1), (ar, h1, h3 + parapet)])
            r = []
            if 'L' in sides:
                r.append((cx - half) - left)
            if 'R' in sides:
                r.append((cx + half) - right)
            if arc_cols is not None:
                t = 1 - ((arc_cols - cx) / a) ** 2
                r.append(10 * (bot[arc_cols] - (cz + k * a * np.sqrt(np.clip(t, 0, None)))) / 10.0)
            return np.concatenate(r)
        r = least_squares(resid, [w / 2.0, 335.0, 80.0, ar0], loss='soft_l1', f_scale=2.0, bounds=([0, 250, 50, 60], [w, 400, 120, 120]))
        if best is None or r.cost < best[0]:
            best = (r.cost, h1, f, r.x, float(np.abs(r.fun).mean()))
    cost, h1, f, (cx, cz, a, ar), mean_err = best
    h3 = cz - k * ar - top_y - parapet
    return {'size': [int(w), int(h)], 'cx': round(float(cx), 2), 'cz': round(float(cz), 2), 'a': round(float(a), 2), 'ar': round(float(ar), 2),
            'h1': float(h1), 'flare': float(f), 'h3': round(float(h3), 1), 'm': round(float(parapet), 1), 'k': round(k, 4), 'edge_err': round(mean_err, 2)}, rows


def plain_arc(frame):
    """The plain tower's base ellipse aspect: the shaft's columns are those between the two big jumps of the
    lowest drawn pixel (where the crown's underside takes over), a free ellipse through them."""
    from scipy.optimize import least_squares
    body = castle_body(castle_rgba(frame))
    w = body.shape[1]
    bot = np.array([np.nonzero(body[:, x])[0].max() for x in range(w)])
    x0 = int(np.argmax(bot))
    lo = hi = x0
    while lo > 0 and abs(bot[lo - 1] - bot[lo]) <= 25:
        lo -= 1
    while hi < w - 1 and abs(bot[hi + 1] - bot[hi]) <= 25:
        hi += 1
    xs = np.arange(lo, hi + 1)

    def resid(q):
        cx, cz, a, b = q
        return bot[xs] - (cz + b * np.sqrt(np.clip(1 - ((xs - cx) / a) ** 2, 0, None)))
    r = least_squares(resid, [(lo + hi) / 2, bot.max() - 40, (hi - lo) / 2 + 1, 40.0], loss='soft_l1', f_scale=1.5)
    cx, cz, a, b = (float(v) for v in r.x)
    return b / a, (lo, hi)


def attached_tower(frame: int, k: float, parapet: float, walls: dict):
    """Frames 3 and 1 stand on a stub of wall (to the left, to the right) that ends at the sprite's edge, frame 2
    in the corner of two walls (a V on the ground, the tower behind it, its shaft hidden). Each wall is a prism
    with the castle wall's walkway (hw, tv: the stub's cap and the corner's dark tiles are that walkway) and no
    parapet drawn."""
    rgba = castle_rgba(frame)
    body = castle_body(rgba)
    h, w = body.shape
    bot = np.array([np.nonzero(body[:, x])[0].max() for x in range(w)])
    xs = np.arange(w)
    wl, wr = walls[6]['parts'][0], walls[8]['parts'][0]  # the two directions: '/' (s < 0) and '\\' (s > 0)

    def line_c(wall, cols):
        return float(np.median(bot[cols] - wall['s'] * xs[cols]))

    def prism(wall, x0, x1, c):
        return {'type': 'wall', 'x0': round(float(x0), 2), 'x1': round(float(x1), 2), 's': wall['s'], 'c': round(c, 2), 'hw': wall['hw'],
                'tv': wall['tv'], 't': wall['t'], 'parapet': 'none'}
    if frame == 2:
        xa = int(np.argmin(bot))  # the corner's apex, the farthest point of the V
        walls_out = [prism(wl, 0, xa, line_c(wl, xs[:xa - 6])), prism(wr, xa, w, line_c(wr, xs[xa + 6:]))]
        # The shaft is hidden behind the walls: only the crown shows. Its radius is the widest crown row's, the
        # shaft's the other towers' (taken below), its centre the crown's.
        sil = silhouette(rgba)
        rows, left, right = tower_edges(sil)
        crown = rows < 90
        ar = float(((right - left)[crown].max()) / 2.0)
        cx = float(((right + left) / 2.0)[crown][-1])
        tw = {'size': [int(w), int(h)], 'cx': round(cx, 2), 'ar': round(ar, 2), 'h1': None, 'h3': None, 'm': round(parapet, 1), 'k': round(k, 4),
              'cz': None, 'a': None, 'flare': None}
        top_y = float(rows.min())
        tw['top_y'] = top_y
        return walls_out, tw, {'apex': xa}
    left = frame == 3
    wall = wl if left else wr
    edge = xs[:24] if left else xs[-24:]
    c = line_c(wall, edge)
    resid = bot - (wall['s'] * xs + c)
    run = 0
    while run < w and abs(resid[run if left else w - 1 - run]) <= 1.5:
        run += 1
    xj = run if left else w - run  # where the bottom leaves the stub's line: the tower's plinth takes over
    far = (xj + w) // 2 if left else xj // 2
    step = 1 if left else -1
    while 0 < far < w - 1 and abs(bot[far + step] - bot[far]) <= 25:
        far += step
    cols = xs[xj + 8:far - 8] if left else xs[far + 8:xj - 8]
    tw, _ = tower_solve(frame, k, parapet, 'R' if left else 'L', cols)
    tw['stub_junction'] = int(xj)
    cx = tw['cx']
    return [prism(wall, 0 if left else cx, cx if left else w, c)], tw, {'stub': 'left' if left else 'right'}


def castle_fit(sheet: Path) -> dict:
    """The castle's fitted pieces, keyed by sprite path (facades.json "_walls")."""
    walls = {}
    for frame in (6, 8, 7, 9):
        walls[frame] = wall_fit(frame, walls)
    parapet = float(np.mean([walls[f]['parts'][0]['y_top'] - walls[f]['parts'][0]['hw'] for f in (6, 8)]))
    k, (lo, hi) = plain_arc(4)
    towers = {}
    tw, _ = tower_solve(4, k, parapet, 'LR', np.arange(lo, hi + 1))
    towers[4] = {'size': tw.pop('size'), 'parts': [tw | {'type': 'tower'}]}
    pending = {}
    for frame in (3, 1, 2):
        wl, tw, info = attached_tower(frame, k, parapet, walls)
        pending[frame] = (wl, tw, info)
    shafts = [pending[f][1]['a'] for f in (3, 1)]
    for frame in (3, 1, 2):
        wl, tw, info = pending[frame]
        size = tw.pop('size')
        if frame == 2:
            # The shaft is the other attached towers' (hidden here); the platform's height the same stack's.
            tw['a'] = round(float(np.mean(shafts)), 2)
            tw['h3'] = round(float(np.mean([pending[f][1]['h3'] for f in (3, 1)])), 1)
            tw['cz'] = round(tw.pop('top_y') + k * tw['ar'] + tw['h3'] + parapet, 2)
            tw['h1'] = round(float(np.mean([pending[f][1]['h1'] for f in (3, 1)])), 1)
            tw['flare'] = round(float(np.mean([pending[f][1]['flare'] for f in (3, 1)])), 1)
        towers[frame] = {'size': size, 'parts': wl + [tw | {'type': 'tower'}], **info}
    out = {}
    for frame, entry in {**walls, **towers}.items():
        out[CASTLE % frame] = entry
        castle_overlay(frame, entry).save(sheet / f'castle-{frame:02d}.png')
        print(CASTLE % frame, json.dumps(entry['parts']))
    return out


def castle_overlay(frame: int, entry: dict) -> Image.Image:
    """The fitted parts drawn over the sprite (x2): cyan the front face, yellow the walkway, green the
    parapet's strip, magenta the tower's ellipses (base, crown, platform, merlon tops)."""
    rgba = castle_rgba(frame)
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    d = ImageDraw.Draw(bg)
    for q in entry['parts']:
        if q['type'] == 'wall':
            x0, x1, sl, c, hw, tv = q['x0'], q['x1'], q['s'], q['c'], q['hw'], q['tv']
            b = lambda x: sl * x + c
            d.polygon([(x0, b(x0)), (x1, b(x1)), (x1, b(x1) - hw), (x0, b(x0) - hw)], outline=(0, 255, 255, 255))
            d.polygon([(x0, b(x0) - hw), (x1, b(x1) - hw), (x1, b(x1) - hw - tv), (x0, b(x0) - hw - tv)], outline=(255, 255, 0, 255))
            off = tv if q['parapet'] == 'back' else 0.0
            if q['parapet'] != 'none':
                d.polygon([(x0, b(x0) - off - hw), (x1, b(x1) - off - hw), (x1, b(x1) - off - q['y_top']), (x0, b(x0) - off - q['y_top'])],
                          outline=(0, 255, 0, 255))
        else:
            cx, cz, a, ar, k = q['cx'], q['cz'], q['a'], q['ar'], q['k']
            for (rx, ry, y) in [(a, k * a, 0), (a, k * a, q['h1']), (ar, k * ar, q['h1']), (ar, k * ar, q['h3']), (ar, k * ar, q['h3'] + q['m'])]:
                d.ellipse((cx - rx, cz - y - ry, cx + rx, cz - y + ry), outline=(255, 0, 255, 255))
    return bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/prototype/facades.json'))
    ap.add_argument('--sheet', default=str(ROOT / 'tmp/facades'))
    ap.add_argument('--castle-only', action='store_true',
                    help='fit only the castle and write it into the existing --out under "_walls"')
    args = ap.parse_args()
    if args.castle_only:
        Path(args.sheet).mkdir(parents=True, exist_ok=True)
        existing = json.loads(Path(args.out).read_text())
        existing['_walls'] = castle_fit(Path(args.sheet))
        Path(args.out).write_text(json.dumps(existing, indent=1))
        return
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    out = {}
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    twin_of = {f: t for f, t in TWINS.items()}
    shared = {}
    def house_fit(seq, frame, blocks, pitches, fixed):
        group = sorted({frame, twin_of.get(frame, frame)} | {f for f, t in TWINS.items() if t == frame})
        if tuple(group) not in shared:
            labs = [classify(np.array(Image.open(ROOT / 'game' / seqs[str(seq)]['frames'][g - 1]['path']).convert('RGBA')))
                    for g in group]
            shared[tuple(group)] = fit(labs, blocks, fixed)
        bases, p, _ = shared[tuple(group)]
        (F, L, R), p = bases[group.index(frame)], list(p)
        p[2] = pitches[0]
        if blocks == 2:
            p[6] = pitches[1]
        return F, L, R, p
    # Thatch thickness and bulge (block_faces): one profile for the thatch of this art, the mean
    # label score over every house's sprite (faces as built): flat 0.6715, best 0.6796 at 2 px
    # hanging, 8 px bulge. Read per house instead, the label score and the original camera
    # disagreed (home-01 flat by labels, fullest by colour), so the profile is shared, as the kit's
    # geometry is. Every thatched house takes it (FLAT_HOUSES).
    pre = []
    for seq, frame, blocks, pitches, fixed in HOUSES:
        rgba = np.array(Image.open(ROOT / 'game' / seqs[str(seq)]['frames'][frame - 1]['path']).convert('RGBA'))
        pre.append((house_fit(seq, frame, blocks, pitches, fixed), blocks, classify(rgba), silhouette(rgba)))
    grid = [(t, g) for t in np.arange(0, 18, 2.) for g in np.arange(0, 18, 2.)]
    tsc = {tg: float(np.mean([score(render(clip_tips(house_faces(*h, b, *tg), sil), lab.shape), lab) for h, b, lab, sil in pre]))
           for tg in grid}
    THATCH[:] = list(max(tsc, key=tsc.get))
    print('thatch thickness, bulge', THATCH, 'score %.4f' % tsc[tuple(THATCH)], 'flat %.4f' % tsc[(0.0, 0.0)])
    house_thatch = (0.0, 0.0) if FLAT_HOUSES else tuple(THATCH)
    for seq, frame, blocks, pitches, fixed in HOUSES:
        fr = seqs[str(seq)]['frames'][frame - 1]
        rgba = np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA'))
        lab = classify(rgba)
        group = sorted({frame, twin_of.get(frame, frame)} | {f for f, t in TWINS.items() if t == frame})
        if tuple(group) not in shared:
            labs = [classify(np.array(Image.open(ROOT / 'game' / seqs[str(seq)]['frames'][g - 1]['path']).convert('RGBA')))
                    for g in group]
            # The descent fits the pitch too, then the pitch read from the art replaces it.
            # Holding the read pitch during the descent lands in worse optima (home-04 0.573
            # against 0.605 on 2026-09-29): coordinate descent, not the model, decides that.
            shared[tuple(group)] = fit(labs, blocks, fixed)
        bases, p, s = shared[tuple(group)]
        (F, L, R), p = bases[group.index(frame)], list(p)
        s = score(render(house_faces(F, L, R, p, blocks), lab.shape), lab)
        p[2] = pitches[0]
        if blocks == 2:
            p[6] = pitches[1]
        faces = clip_tips(house_faces(F, L, R, p, blocks, *house_thatch), silhouette(rgba))
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
    houses_only = list(out.values())  # the wall directions come from these alone
    out.update(cross_houses(seqs, *wall_dirs(houses_only), args.sheet))
    out['_roof_pieces'] = {}
    for seq, frame in ROOF_PIECES:
        fr = seqs[str(seq)]['frames'][frame - 1]
        out['_roof_pieces'][fr['path']] = rp = roof_piece(np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA')))
        print(fr['path'], rp)
    dR, dL = wall_dirs(houses_only)
    for seq, frame in GROUND_PIECES:
        fr = seqs[str(seq)]['frames'][frame - 1]
        out['_roof_pieces'][fr['path']] = rp = standing_piece(np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA')), dR, dL)
        print(fr['path'], 'standing:', rp)
    dR, dL = wall_dirs(houses_only)
    print('wall directions', dR.round(4), dL.round(4))
    for bd in BUILDINGS:
        fr = seqs[str(bd['seq'])]['frames'][bd['frame'] - 1]
        rgba = np.array(Image.open(ROOT / 'game' / fr['path']).convert('RGBA'))
        lab = bd['labels'](rgba)
        sc = lambda q: bd.get('score', parts_score)(*bd['parts'](q, dR, dL)[:2], lab)
        best = None
        i, vals = bd['starts']
        for v0 in vals:
            q = list(bd['p0']); q[i] = v0
            q, s_ = descend(q, sc, bd['grids'], rounds=6)
            if best is None or s_ > best[1]:
                best = (q, s_)
        p, s_ = best
        if 'refine' in bd:  # some parts refined on their own score once the body is fitted
            idx, rsc = bd['refine']
            p, _ = descend(p, lambda q: rsc(*bd['parts'](q, dR, dL)[:2], lab),
                           [bd['grids'][i] if i in idx else None for i in range(len(p))], rounds=6)
        faces, pieces, eaves = bd['parts'](p, dR, dL)
        if 'read' in bd:  # parts read from the pixels once the body is fitted
            faces, pieces, eaves, info = bd['read'](rgba, p, dR, dL)
            print('  read:', info)
        out[fr['path']] = {
            'score': round(s_, 3), 'params': [round(x, 3) for x in p],
            'faces': [{'label': l_, 'block': blk, 'pts': [[round(float(c), 2) for c in pt] for pt in pts]} for l_, pts, blk in faces],
            'polys': uv_polys(faces, pieces, eaves, bd['mirrors'](p, dR, dL) if 'mirrors' in bd else None),
            'occluders': occluders(faces, pieces)}
        over = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
        over.alpha_composite(Image.fromarray(rgba))
        d = ImageDraw.Draw(over)
        for _, pts, blk in faces:
            d.polygon([(pt[0], pt[2] - pt[1]) for pt in pts], outline=(255, 255, 0, 255) if blk in pieces else (0, 255, 255, 255))
        over.save(Path(args.sheet) / f"fit-{bd['seq']}-{bd['frame']}.png")
        print(fr['path'], 'score %.3f' % s_, 'params', [round(x, 2) for x in p])
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
    out['_walls'] = castle_fit(Path(args.sheet))
    Path(args.out).write_text(json.dumps(out, indent=1))


if __name__ == '__main__':
    main()
