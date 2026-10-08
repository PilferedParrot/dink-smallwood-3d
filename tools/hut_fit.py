#!/usr/bin/env python3
"""The island's round huts (struct/Island isle-01..06) as solids of revolution (docs/DIRECTION.md, M3).

A hut sprite is a picture of a round hut taken by the same camera as the castle (tools/facade_fit.py castle_fit): a
ground circle is drawn as an ellipse of one aspect k, the horizontal circle at height h as the same ellipse
shifted up by h (screen = (X, Z - Y), the ground 1:1 in source px). A hut is a solid of revolution about a vertical
axis, so its silhouette is the union of the ellipses of its profile r(h) centred on rows cz - h:
    half(y) = max over h of  r(h) sqrt(1 - ((y - (cz - h)) / (k r(h)))^2)
and the fit recovers (cx, cz, r(h)) from the silhouette's edges:
  * cx: the dome's silhouette centre (rows 12-35% down: the bone arches of the door stand outside the wall lower down);
  * k: the castle's (facade_fit.plain_arc(4)), one camera. The huts' own base arcs agree with it (see arc_fit): on the
    plain half (away from the door) the arc through the lowest drawn pixel of each column fits k = 0.4878 to 0.4-0.5 px
    rms (huts 1, 3, 4, 6); a FREE k fitted to a half arc is not identifiable (it wanders 0.5-1.0);
  * cz and the base radius a: from that base arc (the silhouette alone cannot tell a drum from a cone with the same
    outline; the arc is the wall's own contact line). Huts 2 and 5, whose door stands at the front centre and spoils the
    arc, take the base radius of the hut drawn the same size (1 and 3; 4 and 6) and fit only cz;
  * r(h): piecewise linear, nodes every D px of height, least squares against the silhouette's four edges (left and
    right per row, top and bottom per column) with a robust loss (the bone arches and the thatch tips are outliers) and
    a small second-difference penalty: where the thatch hides the wall the silhouette cannot see r(h) and it is
    interpolated.
Each node also carries which of its 48 ring points the original camera sees (`vis`): the game textures a visible
point by projecting the sprite (UV = (x, z - y), exact), a hidden one from the front point across the plane through the
axis (the unseen half of a hut is its front's reflection) or else from the visible ring just below.

Measured on 2026-10-02 (Sonnet 5.5 subagent): the huts' base arcs agree with the castle's aspect 0.4878 (a free aspect
fitted to a half arc wanders 0.5-1.0, so it is kept); the fitted silhouette differs from the sprite's by 4.8-6.0% of its
pixels analytically (arches, thatch tufts and the pole), 6.3-8.1% through the game's original camera (the render grows the
silhouette by about a pixel). Pinning the base ring exactly to the arc's radius lost hut 1's cone (4.8 to 7.5%): the
silhouette pulls the lowest ring 1-2 px wider than the arc says, so the arc is a stiff prior, not a constraint.

Usage: /usr/bin/python3 tools/hut_fit.py [--out game/prototype/facades.json] [--sheet tmp/huts]
  writes "_huts" into the existing --out file (every other key stays byte-identical) and overlays into --sheet.
  Afterwards re-run the bakes (headless Godot: tools/bake_houses.gd bakes the huts' filled sprites too, and
  tools/bake_kit_canvases.gd): both manifests hold facades.json's hash.
Verdict (2026-10-02, Sonnet 5.5 subagent): works; deterministic (two runs write the same bytes); ~17 s.
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
HUT = 'assets/graphics/struct/Island/isle-%02d.png'
FRAMES = [1, 2, 3, 4, 5, 6]
APEX_ROW = 19.0  # the sprite row where the pole's stub meets the thatch (rows 18-20 in every hut: the stub is blue-grey, rows 8-18)
POLE_R = 6.0     # the stub's half-width: the silhouette's top row is 12 px wide
D = 6.0          # node spacing along the height, source px
RING = 48        # ring points per node: the game builds the same rings
# The side of the base arc not spoiled by the door's arch and step (read from the sprites), or both for the huts whose
# door stands at the front centre; and for those two the hut they share their size with.
PLAIN_SIDE = {1: 'R', 2: 'LR', 3: 'L', 4: 'R', 5: 'LR', 6: 'L'}
SIBLINGS = {2: (1, 3), 5: (4, 6)}


def hut_rgba(frame: int) -> np.ndarray:
    return np.array(Image.open(ROOT / 'game' / (HUT % frame)).convert('RGBA'))


def edges(sil):
    rows = np.nonzero(sil.any(1))[0]
    left = np.array([np.nonzero(sil[y])[0].min() for y in rows], float)
    right = np.array([np.nonzero(sil[y])[0].max() + 1 for y in rows], float)
    cols = np.nonzero(sil.any(0))[0]
    top = np.array([np.nonzero(sil[:, x])[0].min() for x in cols], float)
    bot = np.array([np.nonzero(sil[:, x])[0].max() + 1 for x in cols], float)
    return rows, left, right, cols, top, bot


def dome_centre(sil) -> float:
    rows, left, right, *_ = edges(sil)
    sel = (rows >= 0.12 * len(rows)) & (rows <= 0.35 * len(rows))
    return float(np.median(((left + right) / 2)[sel]))


def arc_fit(bot_by_col, w, cx, side, k, a_fixed=None, dmin=15, trim=(-3.0, 1.5)):
    """The base arc: cz + k sqrt(a^2 - (x - cx)^2) through the lowest drawn pixel of the columns on `side`, ends
    within dmin of the axis left out, fitted by least squares with the outliers beyond `trim` (px, below / above the
    arc: the bones' feet stand below it) dropped until stable. Returns (cz, a, inliers, columns, rms)."""
    xs = np.nonzero(~np.isnan(bot_by_col))[0]
    xs = xs[(xs >= 2) & (xs < w - 2)]
    dx = xs - cx
    m = np.zeros(len(xs), bool)
    if 'L' in side:
        m |= dx <= -dmin
    if 'R' in side:
        m |= dx >= dmin
    xs = xs[m]
    keep = np.ones(len(xs), bool)
    for _ in range(10):
        amin = np.abs(xs[keep] - cx).max() + 0.5
        best = None
        for a0 in ((92, 100, 108, 116) if a_fixed is None else (a_fixed,)):
            def res(p):
                a = p[1] if a_fixed is None else a_fixed
                return bot_by_col[xs[keep]] - (p[0] + k * a * np.sqrt(np.clip(1 - ((xs[keep] - cx) / a) ** 2, 0, None)))
            lo = [50.0] + ([amin] if a_fixed is None else [])
            hi = [320.0] + ([200.0] if a_fixed is None else [])
            p0 = [np.nanmax(bot_by_col[xs]) - k * a0] + ([max(a0, amin + 1)] if a_fixed is None else [])
            r = least_squares(res, p0, bounds=(lo, hi))
            if best is None or r.cost < best.cost:
                best = r
        cz = float(best.x[0])
        a = float(best.x[1]) if a_fixed is None else float(a_fixed)
        rr = bot_by_col[xs] - (cz + k * a * np.sqrt(np.clip(1 - ((xs - cx) / a) ** 2, 0, None)))
        keep = (rr <= trim[1]) & (rr >= trim[0])
    return cz, a, int(keep.sum()), len(xs), float(np.sqrt(np.mean(rr[keep] ** 2)))


def radius_at(R, hs, d=D):
    return np.maximum(np.interp(hs, np.arange(len(R)) * d, R, right=1e-6), 1e-6)


def predict(R, cx, cz, k, rows, cols, d=D):
    """The silhouette's edges a profile predicts: half-width per row, top and bottom per column (+-1e9: not covered)."""
    hs = np.arange(0.0, cz + 1e-9, 1.0)
    r = radius_at(R, hs, d)
    t = 1 - ((rows[:, None] - (cz - hs)[None, :]) / (k * r[None, :])) ** 2
    half = (r[None, :] * np.sqrt(np.clip(t, 0, None))).max(1)
    u = 1 - ((cols[:, None] - cx) / r[None, :]) ** 2
    s = k * r[None, :] * np.sqrt(np.clip(u, 0, None))
    bot = np.where(u > 0, (cz - hs)[None, :] + s, -1e9).max(1)
    top = np.where(u > 0, (cz - hs)[None, :] - s, 1e9).min(1)
    return half, top, bot


def profile_fit(sil, cx, cz, k, a, reg=0.3, d=D, apex=True, full=False, stand=0.0, slope=None, init=None, nodes=None):
    """The radius profile at nodes every `d` px of height. apex=False drops the thatch priors (a cone above the eave and the
    pole's stub: a hut's, tools/prop_fit.py's round props have none); full=True returns the optimiser's result, not just x;
    stand weights a prior that a thing stands on its base, the wall leaving the ground straight (R[1] = R[0]); slope=(limit,
    weight) penalises a profile steeper than limit px of radius per px of height (a pedestal neck under a belly); init is a starting profile; nodes is the number of nodes (a flat cap closes the profile at its last: nothing stands above)."""
    rows, left, right, cols, top, bot = edges(sil)
    nn = int(np.ceil(cz / d)) + 1 if nodes is None else nodes
    hw = (right - left) / 2
    R0 = np.interp(cz - np.arange(nn) * d, rows, hw) if init is None else np.resize(init, nn)

    def resid(R):
        half, tp, bt = predict(R, cx, cz, k, rows, cols, d)
        q = [(cx - half) - left, (cx + half) - right, np.where(np.abs(tp) < 1e8, tp - top, 0), np.where(np.abs(bt) < 1e8, bt - bot, 0)]
        # Above the eave (the widest node) a thatch dome only narrows, in a straight cone to the pole's base, and the pole
        # (a stub POLE_R wide) stands on it. Without this the fit puts a neck of 30 px radius under the pole: the top of
        # the silhouette is the BACK of the eave's rim (the cone's apex lies inside the outline, below the rim's back arc),
        # so the outline cannot place the cone's height; the art does, where the pole's stub ends (APEX_ROW).
        hs = np.arange(len(R)) * d
        if not apex:
            extra = [slope[1] * np.maximum(np.abs(np.diff(R)) / d - slope[0], 0.0)] if slope else []
            return np.concatenate(q + [reg * np.diff(R, 2), [30.0 * (R[0] - a)], [stand * (R[1] - R[0])]] + extra)
        peak = int(np.argmax(R))
        up = np.maximum(np.diff(R), 0.0) * (np.arange(len(R) - 1) >= peak)
        cone = np.diff(R, 2) * (np.arange(len(R) - 2) >= peak)
        pole = [np.interp(cz - APEX_ROW, hs, R) - POLE_R, np.interp(cz - 1.0, hs, R) - POLE_R]
        # The base ring is the arc's (the wall's contact line with the ground), as a stiff prior: pinned exactly, the fit of hut 1
        # lost its cone's cap (proxy xor 0.054 to 0.075, 2026-10-02); the silhouette pulls the lowest ring 1-2 px wider.
        return np.concatenate(q + [reg * np.diff(R, 2), [30.0 * (R[0] - a)], 6.0 * up, 2.0 * cone, 3.0 * np.array(pole)])
    r = least_squares(resid, R0, loss='soft_l1', f_scale=2.0, bounds=(np.zeros(nn), np.full(nn, 140.0)), x_scale=10.0, max_nfev=300)
    return r if full else r.x


def ring_visibility(R, cx, cz, k, nodes_h, d=D, ring=RING):
    """Per node a string of RING 0/1: whether the original camera (looking along (0,-1,-1), a ray from the point
    toward it is (0,1,1)) sees the ring point at angle 2 pi j / RING (x = cx + r cos, z = cz + k r sin: sin > 0 faces it)."""
    out = []
    ts = np.arange(0.25, cz + 40.0, 0.5)
    th = 2 * np.pi * np.arange(ring) / ring
    for h in nodes_h:
        r = float(radius_at(R, np.array([h]), d)[0])
        x = cx + r * np.cos(th)
        z = cz + k * r * np.sin(th)
        seen = np.ones(ring, bool)
        for t in ts:
            hh = h + t
            if hh > cz + 2.0:
                break
            rr = float(radius_at(R, np.array([hh]), d)[0]) if hh <= (len(R) - 1) * d else 0.0
            if rr <= 0.01:
                continue
            inside = ((x - cx) / rr) ** 2 + ((z + t - cz) / (k * rr)) ** 2 < 0.999
            seen &= ~inside
        out.append(''.join('1' if s else '0' for s in seen))
    return out


def hut_fit(sheet: Path) -> dict:
    k, _ = F.plain_arc(4)
    fits = {}
    for frame in FRAMES:
        rgba = hut_rgba(frame)
        sil = F.silhouette(rgba)
        h, w = sil.shape
        rows, left, right, cols, top, bot = edges(sil)
        B = np.full(w, np.nan)
        for x, b in zip(cols, bot):
            B[x] = b
        cx = dome_centre(sil)
        fits[frame] = dict(rgba=rgba, sil=sil, B=B, cx=cx, size=(w, h))
        if frame not in SIBLINGS:
            cz, a, kept, tot, rms = arc_fit(B, w, cx, PLAIN_SIDE[frame], k)
            fits[frame].update(cz=cz, a=a, arc=(kept, tot, rms))
    for frame, sib in SIBLINGS.items():
        f = fits[frame]
        a = float(np.mean([fits[s]['a'] for s in sib]))
        cz, a, kept, tot, rms = arc_fit(f['B'], f['size'][0], f['cx'], PLAIN_SIDE[frame], k, a_fixed=a, dmin=30)
        f.update(cz=cz, a=a, arc=(kept, tot, rms))
    out = {}
    for frame in FRAMES:
        f = fits[frame]
        R = profile_fit(f['sil'], f['cx'], f['cz'], k, f['a'])
        nodes_h = np.arange(len(R)) * D
        vis = ring_visibility(R, f['cx'], f['cz'], k, nodes_h)
        rows, left, right, cols, top, bot = edges(f['sil'])
        half, _, _ = predict(R, f['cx'], f['cz'], k, rows, cols)
        res = np.concatenate([(f['cx'] - half) - left, (f['cx'] + half) - right])
        entry = {'size': list(f['size']), 'cx': round(f['cx'], 2), 'cz': round(f['cz'], 2), 'k': round(k, 4), 'a': round(f['a'], 2),
                 'nodes': [[round(float(hh), 1), round(float(rr), 2), v] for hh, rr, v in zip(nodes_h, R, vis)],
                 'edge_med': round(float(np.median(np.abs(res))), 2), 'arc': list(f['arc'][:2]) + [round(f['arc'][2], 2)]}
        out[HUT % frame] = entry
        hut_overlay(frame, f, entry).save(sheet / f'hut-{frame:02d}.png')
        print(HUT % frame, json.dumps({k_: v for k_, v in entry.items() if k_ != 'nodes'}), flush=True)
    return out


def hut_overlay(frame, f, entry) -> Image.Image:
    """The fit over the sprite (x3): cyan the profile's ellipses every 12 px of height (base brighter), yellow the lowest
    pixel of each column, white the silhouette predicted from the profile (its edges), magenta ground."""
    rgba = f['rgba']
    bg = Image.new('RGBA', (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    bg.alpha_composite(Image.fromarray(rgba))
    S = 3
    bg = bg.resize((bg.width * S, bg.height * S), Image.NEAREST)
    d = ImageDraw.Draw(bg)
    cx, cz, k = entry['cx'], entry['cz'], entry['k']
    nodes = entry['nodes']
    R = np.array([n[1] for n in nodes])
    for i, (h, r, _) in enumerate(nodes):
        if i % 2 == 0 and r > 0.5:
            col = (255, 255, 0, 255) if i == 0 else (0, 255, 255, 255)
            d.ellipse(((cx - r) * S, (cz - h - k * r) * S, (cx + r) * S, (cz - h + k * r) * S), outline=col)
    sil_rows = np.arange(rgba.shape[0], dtype=float)
    cols = np.arange(rgba.shape[1], dtype=float)
    half, top, bot = predict(R, cx, cz, k, sil_rows, cols)
    for y in range(len(sil_rows)):
        if half[y] > 0:
            for xx in (cx - half[y], cx + half[y]):
                d.rectangle((xx * S - 1, y * S, xx * S + 1, y * S + 1), fill=(255, 255, 255, 255))
    return bg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(ROOT / 'game/prototype/facades.json'))
    ap.add_argument('--sheet', default=str(ROOT / 'tmp/huts'))
    args = ap.parse_args()
    Path(args.sheet).mkdir(parents=True, exist_ok=True)
    existing = json.loads(Path(args.out).read_text())
    huts = hut_fit(Path(args.sheet))
    # "_huts" goes in before "_kit_buildings", away from the castle's "_walls" at the end (another unit rewrites that).
    merged = {}
    for key, value in existing.items():
        if key == '_huts':
            continue
        if key == '_kit_buildings':
            merged['_huts'] = huts
        merged[key] = value
    if '_huts' not in merged:
        merged['_huts'] = huts
    Path(args.out).write_text(json.dumps(merged, indent=1))


if __name__ == '__main__':
    main()
