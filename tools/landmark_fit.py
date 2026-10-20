#!/usr/bin/env python3
"""Landmarks (the well, struct/Landmark landm-01..03) as solids derived from their own sprite (docs/DIRECTION.md, "The
landmarks are solid"). One camera, as every other fitted sprite (facade_fit, hut_fit, prop_fit): screen = (X, Z - Y), a ground
circle drawn as an ellipse of aspect k = 0.4878.

The well is three things, split by SHAPE, never by colour: opening the silhouette with a disc wider than a post (OPEN px) keeps
the two fat things, the roof (the upper) and the stone base (the lower), and removes the posts that join them.
  * base: prop_fit.round_fit (a solid of revolution, the huts' machinery) on the opened base, its flat top the rim. The posts'
    pixels are not the base's (its texture is inpainted there).
  * posts: the warm pixels outside the roof that stand as long vertical runs (opening by a vertical line of POST_RUN px); each
    run's column is a post, its lowest row the post's front foot. A post stands on the rim: its foot is at the rim's height H, so
    its row gives its depth Z = (foot row - cz + H)/k - w/2 (w: its drawn width, a square post yawed like the roof shows
    s (|cos| + |sin|)). Its width is the run's plus its shaded face (DARK px each way).
  * roof: a thin slab on the ground rectangle w x d yawed about the vertical, fitted so its projected top parallelogram
    overlaps the roof silhouette best (differential evolution, seeded). Its thickness is a post's width (a beam). It stands over
    the posts' middle in depth, so its height y0 follows from where its centre is drawn: row = cz + k Z - y0.
  * the roof is ONE visible slope (the far slope is hidden behind the ridge), so its silhouette is a parallelogram and its IoU cannot
    tell a pitch from a flat slab (0.88 against 0.83, depth and height degenerate). The clean EDGES can (roof_edges): the ridge and the
    eave are horizontal and parallel; the right rake runs from the ridge's end to the eave's end. Under the sprite's own camera
    (screen = (X, k Z - Y)) a flat slab's rake would have slope k tan(psi) ~ 0.5, the picture's is 1.44, and the difference is the rise.
    The roof is aligned with the scene's axes (psi = 45 degrees: the ridge's slope IS k), the rake gives the half-run w and the rise,
    and the far rake's corner lands on the ridge line (the prism check). The pitch is therefore a measurement (about 0.68 apparent,
    0.80 true), not the cottages' borrowed 1.1. A gable roof (class 'gable'): two planes ridge to eaves, a thatch thickness, gable
    ends closed; the posts end at its underside.
The roof takes its slope's picture on its underside, its far slope and its ends (prop_solids.gd _gable). Its texture is the roof's lit
planks (the warm pixels): the dark band the original draws under the eave is a shadow, not a plank.
The entry is {'class': 'compound', base, parts[...]}: every part keeps its own mask (the sprite pixels it was fitted from; the
game inpaints the rest, so the posts' wood does not paint the rim). prop_solids.gd builds it.
Usage: /usr/bin/python3 tools/landmark_fit.py [--out game/prototype/landmarks.json] [--sheet tmp/landmarks]
Verdict: (see docs/DIRECTION.md, "The landmarks are solid")
"""
from __future__ import annotations
import argparse, base64, json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import facade_fit as F  # noqa: E402
import prop_fit as P  # noqa: E402

ROOT = F.ROOT
OPEN = 5        # radius (px) of the disc a roof or a base survives and a post (<= 8 px wide) does not
POST_RUN = 10   # a post is a run of warm pixels at least this long in one column
WARM = 8        # red minus blue: wood is warm, the well's stone is not
D_MIN = 65      # the roof is at least this long (px): the free fit (55) stops short of the left tip the picture draws, leaving a post's top uncovered
EDGE_FIT = {'ridge': (42, 78), 'eave': (66, 104), 'rake': (3, 23)}  # the roof's clean edges, in sprite px (columns, columns, rows)
DARK = 2        # a post's shaded face is as wide again as its lit run's edge: px added each side


def pack(mask: np.ndarray) -> str:
    return base64.b64encode(np.packbits(mask.ravel()).tobytes()).decode()


def segment(rgba: np.ndarray):
    a = rgba.astype(int)
    body = (rgba[..., 3] >= 128) & ~F.is_dither(rgba)
    disc = np.hypot(*np.mgrid[-OPEN:OPEN + 1, -OPEN:OPEN + 1]) <= OPEN
    lab, n = ndimage.label(ndimage.binary_opening(body, structure=disc))
    cm = [ndimage.center_of_mass(lab == i)[0] for i in range(1, n + 1)]
    roof = lab == 1 + int(np.argmin(cm))
    base = lab == 1 + int(np.argmax(cm))
    warm = body & ((a[..., 0] - a[..., 2]) > WARM)
    runs = ndimage.binary_opening(warm & ~roof, structure=np.ones((POST_RUN, 1), bool))
    lab, n = ndimage.label(runs)
    posts = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(ys) < 3 * POST_RUN:
            continue  # a rope or a chain: a pixel wide
        posts.append({'x0': int(xs.min()) - DARK, 'x1': int(xs.max()) + 1 + DARK, 'foot': int(ys.max()) + 1, 'top': int(ys.min())})
    return body, roof, base, posts, warm


def roof_fit(roof: np.ndarray, k: float, thick: float):
    """The slab's top parallelogram: (cx, cz, w, d, yaw) of its top face's centre (sprite px), by overlap with the silhouette."""
    from scipy.optimize import differential_evolution
    rows, left, right, cols, top, bot = P.H.edges(roof)
    x0, x1, y0, y1 = left.min(), right.max(), rows.min(), rows.max() + 1

    def corners(p):
        cx, cz, w, d, al = p
        c, s = np.cos(al), np.sin(al)
        return [(cx + sx * w / 2 * c - sz * d / 2 * s, cz + k * (sx * w / 2 * s + sz * d / 2 * c)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    def cost(p):
        m = P.hull_mask(corners(p), roof.shape)
        return 1.0 - (m & roof).sum() / max(1, (m | roof).sum())
    wd = x1 - x0
    r = differential_evolution(cost, [(x0, x1), (y0, y1), (8, 1.5 * wd), (8, 1.5 * wd), (-np.pi / 2, np.pi / 2)], seed=1, popsize=24,
                               maxiter=200, tol=1e-7, polish=False)
    return [float(v) for v in r.x], 1.0 - float(r.fun)


def _line(xs, ys):
    return np.polyfit(np.asarray(xs, float), np.asarray(ys, float), 1)


def roof_edges(roof: np.ndarray, k: float | None = None) -> dict:
    """The roof's three clean edges (EDGE_FIT), as lines in sprite px: the ridge (top boundary, y = a x + b), the eave (bottom
    boundary) and the right rake (right boundary, x = c y + d). The ridge and the eave are horizontal and parallel; the rake joins the
    ridge's end B to the eave's end C. Everything below follows from them under the sprite's camera, screen = (X, k Z - Y):
      * the roof is aligned with the scene's axes (psi: 45 degrees when k is the ridge's slope), so the ridge's slope is
        k cot(psi) and k is read from the edges (k=None) or given (the project's 0.4878: then psi follows from the slope);
      * the rake BC = w (cos psi, k sin psi) + (0, rise): w (the half-run, ground px) and the rise (apparent px) are its two
        components; a flat slab would put the rake at slope k tan psi;
      * the far rake's corner A' = D - BC (D: where the eave's bottom boundary leaves its line) must land on the ridge line: the
        prism check, independent of k and psi."""
    cols = [x for x in range(roof.shape[1]) if roof[:, x].any()]
    top = {x: int(np.nonzero(roof[:, x])[0].min()) for x in cols}
    bot = {x: int(np.nonzero(roof[:, x])[0].max()) + 1 for x in cols}
    rows = [y for y in range(roof.shape[0]) if roof[y].any()]
    right = {y: int(np.nonzero(roof[y])[0].max()) + 1 for y in rows}
    r0, r1 = EDGE_FIT['ridge']
    e0, e1 = EDGE_FIT['eave']
    k0, k1 = EDGE_FIT['rake']
    ridge = _line(range(r0, r1), [top[x] for x in range(r0, r1)])
    eave = _line(range(e0, e1), [bot[x] for x in range(e0, e1)])
    c, d = _line(range(k0, k1), [right[y] for y in range(k0, k1)])

    def meet(L):  # a long edge's line with the rake's
        y = (L[0] * d + L[1]) / (1 - L[0] * c)
        return np.array([c * y + d, y])
    B, C = meet(ridge), meet(eave)
    bc = C - B
    slope = (abs(ridge[0]) + abs(eave[0])) / 2
    kk = slope if k is None else k  # the aligned roof's ridge slope is k
    psi = float(np.arctan2(kk, slope))
    w = bc[0] / np.cos(psi)
    rise = bc[1] - kk * np.sin(psi) * w
    xd = next(x for x in range((e0 + e1) // 2, 45, -1) if abs(bot[x] - np.polyval(eave, x)) > 1.5) + 1  # D: the eave's left end (walking left from its middle)
    D = np.array([xd, np.polyval(eave, xd)])
    A = D - bc
    return {'k': float(kk), 'psi': psi, 'ridge': ridge, 'eave': eave, 'rake': (float(c), float(d)), 'B': B, 'C': C, 'D': D, 'A': A,
            'w': float(w), 'rise': float(rise), 'length': float(abs(B[0] - A[0]) / np.sin(psi)),
            'prism_gap': float(abs(np.polyval(ridge, A[0]) - A[1])), 'slope_ridge': float(ridge[0]), 'slope_eave': float(eave[0]),
            'rake_slope': float(1 / c), 'flat_rake_slope': float(kk * np.tan(psi))}


def well_fit(rgba: np.ndarray, k: float | None) -> dict | None:
    """k=None: the well's own (roof_edges); a number: that k (the project's 0.4878 to see what changes)."""
    body, roof, base_m, posts, warm = segment(rgba)
    if len(posts) < 2:
        return None
    E = roof_edges(roof, k)
    k = E['k']
    ys = np.nonzero(base_m.any(1))[0]
    post_px = np.zeros_like(body)
    for p in posts:
        post_px[p['top']:p['foot'], p['x0']:p['x1']] = True
    base_tex = base_m & ~post_px
    sub = rgba.copy()
    sub[..., 3] = np.where(base_m, 255, 0)
    base = P.round_fit(sub, k, True)
    if base is None:
        return None
    cx, cz = base['cx'], base['cz']
    rim = float(base['nodes'][-1][0])
    base['mask'] = pack(base_tex)
    base['void_fill'] = True  # the stone's drawn gaps (pure black) take the nearest stone pixel (prop_solids.gd _texture)
    yaw = E['psi']
    c, s = abs(np.cos(yaw)), abs(np.sin(yaw))
    # The post: a square beam; drawn width = side * (|cos| + |sin|).
    boxes = []
    side = 0.0
    zs = []
    for p in posts:
        w = p['x1'] - p['x0']
        side = max(side, w / (c + s))
    for p in posts:
        w = p['x1'] - p['x0']
        z = (p['foot'] - cz + rim) / k - w / 2
        zs.append(z)
        boxes.append([round((p['x0'] + p['x1']) / 2 - cx, 2), round(z, 2)])
    zr = float(np.mean(zs))
    thick = side
    # The roof's ridge is the middle of its footprint: its midpoint M (the ridge's ends B and A') stands over the posts' middle in
    # depth, so its height follows from where it is drawn: row = cz + k Z - Y.
    M = (E['B'] + E['A']) / 2
    xr = float(M[0]) - cx
    ridge = cz + k * zr - float(M[1])
    rw, rd, rise = 2 * E['w'], E['length'], E['rise']
    iou_flat = roof_fit(roof, k, 0.0)[1]
    ex, ez = np.array([np.cos(yaw), np.sin(yaw)]), np.array([-np.sin(yaw), np.cos(yaw)])  # across the ridge, along it
    ctr = np.array([xr, zr])
    pitch = rise / E['w']
    print('roof edges: k %.4f psi %.1f deg ridge slope %.3f eave %.3f rake %.3f (flat slab: %.3f) w %.1f rise %.1f length %.1f '
          'prism gap %.2f px; apparent pitch %.3f true %.3f (%.1f deg); ridge %.1f; flat-slab IoU %.4f'
          % (k, np.degrees(yaw), E['slope_ridge'], E['slope_eave'], E['rake_slope'], E['flat_rake_slope'], E['w'], rise, rd, E['prism_gap'],
             pitch, pitch / np.sqrt(1 - k * k), np.degrees(np.arctan(pitch / np.sqrt(1 - k * k))), ridge, iou_flat))
    for b in boxes:
        b.append(round(rim, 2))
        # The post ends in the roof's underside, at the ridge side of its top (it is yawed like the roof, so its faces are the roof's axes).
        u = float((np.array([b[0], b[1]]) - ctr) @ ex)
        u_near = max(0.0, abs(u) - side / 2)
        b.append(round(ridge - thick - rise * u_near / (rw / 2) - rim, 2))
    # The drawn post is DARK columns of black outline, then its wood (the lit run: four columns, the shaded half of it the left two). The outline is
    # a drawing convention, not material: the faces take the wood's columns only, at their drawn width (prop_solids.gd _texture, fit.flat).
    wp = posts[0]['x1'] - posts[0]['x0']
    assert all(p['x1'] - p['x0'] == wp for p in posts), 'the two posts are drawn as wide as each other'
    ww = wp - 2 * DARK  # the wood's columns
    faces = {'dark': [-wp / 2 + DARK, -wp / 2 + DARK + ww / 2], 'lit': [-wp / 2 + DARK + ww / 2, wp / 2 - DARK]}
    flat = [{'dark': [p['x0'] + DARK, p['x0'] + DARK + ww // 2], 'lit': [p['x0'] + DARK + ww // 2, p['x1'] - DARK], 'rows': [p['top'], p['foot']]} for p in posts]
    out_posts = {'class': 'box', 'faces': faces, 'flat': flat, 'size': base['size'], 'cx': cx, 'cz': cz, 'k': k, 'w': round(side, 2), 'd': round(side, 2),
                 'yaw': round(float(yaw), 4), 'h': round(ridge - thick - rise - rim, 2), 'boxes': boxes, 'mask': pack(post_px)}  # no void_fill: the post's outline is not a gap to fill but a convention to leave out (fit.flat)
    out_roof = {'class': 'gable', 'size': base['size'], 'cx': cx, 'cz': cz, 'k': k, 'w': round(rw, 2), 'd': round(rd, 2),
                'yaw': round(float(yaw), 4), 'h': round(thick, 2), 'boxes': [[round(xr, 2), round(zr, 2), round(ridge - rise - thick, 2)]],
                'pitch': round(pitch, 3), 'rise': round(rise, 2), 'ridge': round(ridge, 2), 'rake_slope': round(E['rake_slope'], 3),
                'flat_rake_slope': round(E['flat_rake_slope'], 3), 'prism_gap': round(E['prism_gap'], 2),
                'iou_flat': round(iou_flat, 4), 'mask': pack(roof & warm)}
    return {'class': 'compound', 'size': base['size'], 'cx': cx, 'cz': cz, 'k': round(k, 4), 'base': base, 'parts': [out_posts, out_roof],
            'rim': round(rim, 2)}


WALL_T = 0.4    # the ring's thickness as a share of its outer radius (the one tuned number of the ring: the outline shows the top's outer edge only)


def ring_fit(rgba: np.ndarray, k: float) -> dict | None:
    """A ring open to the camera (the save machine, inter/Save): a grating floor and, on its far half, a wall the camera sees
    the inside of. From the outline only:
      * the floor's circle: the silhouette's lowest row per column is the near arc cz + k sqrt(a^2 - (x - cx)^2) (the beams
        poking past it are outliers: a robust fit); a is the floor's radius, cz its centre row.
      * the wall's top: the silhouette's highest row per column is the far arc A - k sqrt(Rw^2 - (x - cx)^2) of the wall's outer
        top edge (columns well inside the ring; the arches' dips are outliers), A = cz - H: its radius Rw and height H.
      * the wall is the far half (the half whose inside is drawn), its thickness WALL_T * Rw."""
    from scipy.optimize import least_squares
    sil = F.silhouette(rgba)
    rows, left, right, cols, top, bot = P.H.edges(sil)
    w = rgba.shape[1]
    cx = float(np.median(((left + right) / 2)[(right - left) >= 0.9 * (right - left).max()]))
    B = np.full(w, np.nan)
    B[cols] = bot
    T = np.full(w, np.nan)
    T[cols] = top
    xs = cols[(cols >= 2) & (cols < w - 2)].astype(float)

    def near(p):
        cz, a = p
        return B[xs.astype(int)] - (cz + k * a * np.sqrt(np.clip(1 - ((xs - cx) / a) ** 2, 0, None)))
    r = least_squares(near, [bot.max() - k * (right - left).max() / 2, (right - left).max() / 2 * 0.9],
                      bounds=([10, 20], [bot.max(), (right - left).max() / 2]), loss='soft_l1', f_scale=1.0)
    cz, a = [float(v) for v in r.x]
    inner = xs[np.abs(xs - cx) <= 0.75 * a]

    def far(p):
        A, rw = p
        return T[inner.astype(int)] - (A - k * np.sqrt(np.clip(rw ** 2 - (inner - cx) ** 2, 0, None)))
    r = least_squares(far, [float(top.min()) + k * a, 0.8 * a], bounds=([0, 0.5 * a], [cz, a]), loss='soft_l1', f_scale=1.0)
    A, rw = [float(v) for v in r.x]
    return {'class': 'ring', 'size': [w, rgba.shape[0]], 'cx': round(cx, 2), 'cz': round(cz, 2), 'k': round(k, 4), 'rf': round(a, 2),
            'rw': round(rw, 2), 'ri': round(rw * (1 - WALL_T), 2), 'h': round(cz - A, 2), 'a0': round(float(np.pi), 4),
            'a1': round(float(2 * np.pi), 4), 'sil_px': int(sil.sum())}


def ring_overlay(rgba: np.ndarray, e: dict) -> Image.Image:
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    S = 6
    bg = bg.resize((bg.width * S, bg.height * S), Image.NEAREST)
    dr = ImageDraw.Draw(bg)
    cx, cz, k = e['cx'], e['cz'], e['k']
    for r, h, col in ((e['rf'], 0, (255, 255, 0, 255)), (e['rw'], 0, (0, 255, 255, 255)), (e['rw'], e['h'], (0, 255, 255, 255)),
                      (e['ri'], 0, (255, 128, 0, 255)), (e['ri'], e['h'], (255, 128, 0, 255))):
        dr.ellipse(((cx - r) * S, (cz - h - k * r) * S, (cx + r) * S, (cz - h + k * r) * S), outline=col)
    return bg


def overlay(rgba: np.ndarray, e: dict) -> Image.Image:
    img = P.round_overlay(rgba, e['base'])
    dr = ImageDraw.Draw(img)
    S = 6
    for part in e['parts']:
        if part['class'] == 'gable':  # ridge and eaves of the top, in the sprite's own camera
            X, Z, Y0 = part['boxes'][0]
            c, sn = np.cos(part['yaw']), np.sin(part['yaw'])
            def pt(u, v, y):
                return ((part['cx'] + X + u * c - v * sn) * S, (part['cz'] + part['k'] * (Z + u * sn + v * c) - y) * S)
            w2, d2, ye = part['w'] / 2, part['d'] / 2, part['ridge'] - part['rise']
            for a, b in (((0, -d2, part['ridge']), (0, d2, part['ridge'])), ((-w2, -d2, ye), (-w2, d2, ye)), ((w2, -d2, ye), (w2, d2, ye)),
                         ((0, -d2, part['ridge']), (-w2, -d2, ye)), ((0, -d2, part['ridge']), (w2, -d2, ye)),
                         ((0, d2, part['ridge']), (-w2, d2, ye)), ((0, d2, part['ridge']), (w2, d2, ye))):
                dr.line([pt(*a), pt(*b)], fill=(255, 0, 255, 255), width=2)
            continue
        for X, Z, Y0, *hb in part['boxes']:
            g, px = P.box_corners((part['cx'] + X, part['cz'] + part['k'] * Z - Y0, part['w'], part['d'], part['yaw'], hb[0] if hb else part['h']), part['k'])
            for i in range(4):
                j = (i + 1) % 4
                dr.line([(px[i][0] * S, px[i][1] * S), (px[j][0] * S, px[j][1] * S)], fill=(255, 255, 0, 255), width=2)
                dr.line([(px[4 + i][0] * S, px[4 + i][1] * S), (px[4 + j][0] * S, px[4 + j][1] * S)], fill=(0, 255, 255, 255), width=2)
                dr.line([(px[i][0] * S, px[i][1] * S), (px[4 + i][0] * S, px[4 + i][1] * S)], fill=(255, 255, 255, 255), width=1)
    return img


SAVES = ['assets/graphics/inter/save/save-0%d.png' % i for i in (1, 2, 3, 4, 5)]  # five frames of one silhouette (the ring's glow)
LANDMARKS = ['assets/graphics/struct/Landmark/landm-0%d.png' % i for i in (1, 2, 3)]  # three frames of one silhouette (the glow differs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/prototype/landmarks.json'))
    ap.add_argument('--sheet', default=str(ROOT / 'tmp/landmarks'))
    ap.add_argument('--well-k', default='measured', help="'measured' (the roof's own edges) or a number (0.4878: the project's)")
    args = ap.parse_args()
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    k, _ = F.plain_arc(4)
    out = {}
    for group, fit_one, over in ((LANDMARKS, lambda r, kk: well_fit(r, None if args.well_k == 'measured' else float(args.well_k)), overlay), (SAVES, lambda r, kk: ring_fit(r, kk), ring_overlay)):
        first = None
        for path in group:
            rgba = P.load(path)
            if first is not None and np.array_equal(rgba[..., 3] >= 128, first[0][..., 3] >= 128):
                e = first[1]  # the same silhouette: the same solid, textured by this frame
            else:
                e = fit_one(rgba, k)
                first = (rgba, e)
            if e is None:
                print('not fitted', path)
                continue
            out[path] = e
            over(rgba, e).save(Path(args.sheet) / (Path(path).stem + '.png'))
            print(path, json.dumps({q: v for q, v in e.items() if q not in ('base', 'parts')}), flush=True)
    Path(args.out).write_text(json.dumps(out, separators=(',', ':')))


if __name__ == '__main__':
    main()
