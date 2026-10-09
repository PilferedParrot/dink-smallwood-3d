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
  * the roof's PITCH is not in the outline (the two slope edges fitted 7 to 17 degrees). It is the thatched houses': the median of the
    rise/run that facade_fit.HOUSES reads from the art of the six cottages (PITCH below), applied to the roof across its ridge,
    which runs along the roof's long axis. The ridge's height is the one thing left to fit: the height whose projected gable
    overlaps the roof silhouette best. A gable roof (class 'gable'): two planes ridge to eaves, a thatch thickness, gable ends
    closed; the posts end at its underside.
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
PITCH = float(np.median([p for h in F.HOUSES for p in h[3]]))  # rise/run of the thatched cottages' roofs (facade_fit.HOUSES: 1.1)
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


def well_fit(rgba: np.ndarray, k: float) -> dict | None:
    body, roof, base_m, posts, warm = segment(rgba)
    if len(posts) < 2:
        return None
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
    (rcx, rcz, rw, rd, yaw), iou = roof_fit(roof, k, 0.0)
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
    # The roof's flat-slab fit puts its top face centre at (rcx, rcz) = (cx + X, cz + k Z - (y0 + thick)); its footprint is w x d,
    # yawed, the ridge along the long axis d (local z), the pitch across it (local x).
    y0 = cz + k * zr - rcz - thick
    xr = rcx - cx
    assert rd >= rw, 'the ridge runs along the long axis: the fit put it across'
    ex, ez = np.array([np.cos(yaw), np.sin(yaw)]), np.array([-np.sin(yaw), np.cos(yaw)])  # across the ridge, along it

    def gable_pts(xc, w, d, ridge):
        """The gable's vertices (sprite px): ridge ends, eave corners, and the eave corners a thatch thickness down."""
        eave = ridge - PITCH * w / 2
        out = []
        for u, v, y in ((0, -d / 2, ridge), (0, d / 2, ridge)) + tuple((su * w / 2, sv * d / 2, eave - dy) for su in (-1, 1) for sv in (-1, 1) for dy in (0, thick)):
            q = np.array([xc, zr]) + u * ex + v * ez
            out.append((cx + q[0], cz + k * q[1] - y))
        return out

    def gable_cost(p):
        if p[2] < p[1]:
            return 2.0  # the ridge runs along the long axis
        m = P.hull_mask(gable_pts(*p[:1], p[1], p[2], p[3]), roof.shape)
        return 1.0 - (m & roof).sum() / max(1, (m | roof).sum())
    from scipy.optimize import differential_evolution
    wd = float(np.ptp(np.nonzero(roof.any(0))[0]))
    r = differential_evolution(gable_cost, [(xr - wd, xr + wd), (8, 1.5 * wd), (D_MIN, 1.5 * wd), (y0, y0 + thick + 60)], seed=1, popsize=24,
                               maxiter=200, tol=1e-7, polish=False)
    xr, rw, rd, ridge = [float(v) for v in r.x]
    iou_g = 1.0 - float(r.fun)
    rise = PITCH * rw / 2
    ctr = np.array([xr, zr])
    print('gable: pitch %.2f rise %.2f ridge %.1f (flat slab top %.1f) iou %.4f (flat slab %.4f)' % (PITCH, rise, ridge, y0 + thick, iou_g, iou))
    for b in boxes:
        b.append(round(rim, 2))
        # The post ends in the roof's underside, at the ridge side of its top (it is yawed like the roof, so its faces are the roof's axes).
        u = float((np.array([b[0], b[1]]) - ctr) @ ex)
        u_near = max(0.0, abs(u) - side / 2)
        b.append(round(ridge - thick - rise * u_near / (rw / 2) - rim, 2))
    out_posts = {'class': 'box', 'size': base['size'], 'cx': cx, 'cz': cz, 'k': k, 'w': round(side, 2), 'd': round(side, 2),
                 'yaw': round(float(yaw), 4), 'h': round(y0 - rim, 2), 'boxes': boxes, 'mask': pack(post_px)}
    out_roof = {'class': 'gable', 'size': base['size'], 'cx': cx, 'cz': cz, 'k': k, 'w': round(rw, 2), 'd': round(rd, 2),
                'yaw': round(float(yaw), 4), 'h': round(thick, 2), 'boxes': [[round(xr, 2), round(zr, 2), round(ridge - rise - thick, 2)]],
                'pitch': round(PITCH, 3), 'rise': round(rise, 2), 'ridge': round(ridge, 2), 'iou': round(iou_g, 4),
                'iou_flat': round(iou, 4), 'mask': pack(roof & warm)}
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
    args = ap.parse_args()
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    k, _ = F.plain_arc(4)
    out = {}
    for group, fit_one, over in ((LANDMARKS, well_fit, overlay), (SAVES, lambda r, kk: ring_fit(r, kk), ring_overlay)):
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
