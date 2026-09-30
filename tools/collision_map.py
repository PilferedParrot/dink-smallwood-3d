#!/usr/bin/env python3
"""Where the game's collision comes from, per screen (docs/DIRECTION.md, seventh pass).

Collision has one source, the original data. `game.gd` `_blocked` reads it at a point in
source screen coordinates (x 20..620, y 0..400):
  * tile hardness (hard.dat masks, per tile or the tile's default);
  * the hardbox of every hard sprite (`hard == 0`), grown 4 px;
  * for a building the prototype rebuilds in 3D (tools/facade_fit.py), its fitted
    FOOTPRINT, derived from the same original pixels, replaces the hardness the original
    drew for its picture: the hardboxes of the building and the details drawn on it, the
    hardness of a kit building's own tiles, the ring of custom tile masks round the
    picture, and invisible blockers standing on it (screen_record).

Why the footprint: a building sprite is a picture from a raised 3/4 camera, and the map
makers drew its hardness for that picture, mostly as a ring of custom tile masks round the
drawn building (most house sprites are not hard themselves: home-01's hardbox, ~90 px behind
its drawn front wall, is unused on 439). Walked into in first person (--profile, 2026-09-30),
that ring stopped the player a median 5-18 px in front of the drawn front walls (from 7 px
inside to 33 px in front), 45-80 px out in the open ground behind the houses, and the inn
(kit-537) had none on its back: 111 of 115 approaches on 505 walked more than 80 px in. On
the prototype's 1:1 ground the wall-base lines are the footprint itself, so the fitted
footprint is where the drawn walls stand.

This tool writes `game/data/footprints.json` (what the game loads) and renders overlays:

    /usr/bin/python3 tools/collision_map.py                      # -> game/data/footprints.json
    /usr/bin/python3 tools/collision_map.py --sheet tmp/collision 439 409 440
    /usr/bin/python3 tools/collision_map.py --profile 439 409   # walk into every wall

Overlays: left, the original hardness the game used before (red); right, what changes:
kept (grey), dropped (red), added (green). Cyan: the footprints. Yellow: warp (door)
trigger rects, grown 7 px as game.gd tests them.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
COLS = 32
GROW = 4  # game.gd grows every hardbox by 4 px: the player's radius in source pixels
REACH = 50  # one tile: see screen_record


def origin(n: int):
    return ((n - 1) % COLS) * 600, ((n - 1) // COLS) * 400


def frame(seqs, seq, fr):
    fs = seqs.get(str(seq), {}).get('frames', [])
    return fs[fr - 1] if 0 < fr <= len(fs) else None


def hull(pts):
    """Convex hull (monotone chain), counter-clockwise in screen axes."""
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in pts))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def ground_polys(faces):
    """One convex polygon per block: the hull of the block's points on the ground (Y = 0).

    Walls stand on the ground; roofs and upper storeys don't. A jettied upper storey
    (kit buildings) and a tower on a ridge (the church) have no ground points, so only
    what stands on the ground blocks: walls, the apse, buttresses, a standing chimney."""
    blocks = {}
    for f in faces:
        for p in f['pts']:
            if abs(float(p[1])) < 0.5:
                blocks.setdefault(int(f['block']), []).append((float(p[0]), float(p[2])))
    return [hull(v) for _, v in sorted(blocks.items()) if len(v) >= 3]


def building_sprites(world, seqs, facades, n, vision=0):
    """The sprites of screen n the prototype builds as houses or parts buildings, and the
    standing chimneys beside them (home-13), with their footprints in screen coordinates."""
    out = []
    pieces = facades.get('_roof_pieces', {})
    for i, e in enumerate(world['screens'][str(n)]['sprites']):
        if int(e.get('vision', 0)) not in (0, vision) or int(e['type']) == 2:
            continue
        fr = frame(seqs, e['seq'], e['frame'])
        if fr is None:
            continue
        tl = (e['x'] - fr['dx'], e['y'] - fr['dy'])
        if fr['path'] in facades:
            polys = ground_polys(facades[fr['path']]['faces'])
        elif 'base' in pieces.get(fr['path'], {}):
            polys = [hull([tuple(q) for q in pieces[fr['path']]['base']])]
        else:
            continue
        out.append({'sprite': i, 'index': int(e['index']), 'path': fr['path'],
                    'polys': [[(tl[0] + x, tl[1] + z) for x, z in p] for p in polys]})
    return out


def kit_buildings(facades, n):
    """Kit buildings (the inn and its kin) with a piece on screen n: footprint in screen n's
    coordinates, and the tiles and sprites of n that belong to the building."""
    out = []
    ox, oy = origin(n)
    for b in facades.get('_kit_buildings', []):
        if n not in [int(s) for s in b['screens']]:
            continue
        wx, wy = b['rect'][0], b['rect'][1]
        polys = [[(wx + x - ox + 20, wy + z - oy) for x, z in p] for p in ground_polys(b['faces'])]
        tiles = [int(m[2]) for m in b['members'] if int(m[0]) == n and m[1] == 't']
        sprites = [int(m[2]) for m in b['members'] if int(m[0]) == n and m[1] == 's']
        out.append({'name': b['name'], 'polys': polys, 'tiles': tiles, 'sprites': sprites})
    return out


def tile_mask(world, n, revert=(), clear=()):
    """Tile hardness of screen n as a 400 x 640 raster (screen x 20..620), as game.gd reads it:
    a tile's custom mask (tile['hard']) or else its default. Tiles in `revert` read their
    default mask, tiles in `clear` none. Also returns the tile index of every pixel."""
    hard = world['hardness']
    masks, defaults = hard['masks_rle'], hard['tile_defaults']
    cache = {}
    out = np.zeros((400, 640), bool)
    per_tile = np.zeros((400, 640), np.int16) - 1
    for i, t in enumerate(world['screens'][str(n)]['tiles'][:96]):
        default = int(defaults[t['tile']]) if 0 <= t['tile'] < len(defaults) else 0
        m = 0 if i in clear else default if i in revert else (int(t.get('hard', 0)) or default)
        tx, ty = 20 + (i % 12) * 50, (i // 12) * 50
        per_tile[ty:ty + 50, tx:tx + 50] = i
        if m <= 0 or m >= len(masks):
            continue
        if m not in cache:
            flat = np.concatenate([np.full(int(c), int(v), np.uint8) for v, c in masks[m]])
            flat = np.pad(flat, (0, max(0, 51 * 51 - flat.size)))[:51 * 51]
            cache[m] = flat.reshape(51, 51)[:50, :50].T != 0  # x-major: [x, y] -> [y, x]
        out[ty:ty + 50, tx:tx + 50] = cache[m]
    return out, per_tile


def hardbox(seqs, e):
    hb = e.get('hardbox') or []
    if len(hb) != 4 or not any(hb):
        fr = frame(seqs, e['seq'], e['frame'])
        hb = (fr or {}).get('hardbox', [-10, -6, 10, 6])
    k = float(e.get('size', 100) or 100) / 100
    return (e['x'] + hb[0] * k, e['y'] + hb[1] * k, e['x'] + hb[2] * k, e['y'] + hb[3] * k)


def rect_mask(rects, grow):
    out = np.zeros((400, 640), bool)
    ys, xs = np.mgrid[0:400, 0:640]
    for x0, y0, x1, y1 in rects:
        # Rect2.grow(g).has_point: start inclusive, end exclusive
        out |= (xs >= x0 - grow) & (xs < x1 + grow) & (ys >= y0 - grow) & (ys < y1 + grow)
    return out


def poly_mask(polys, grow=0):
    im = Image.new('L', (640, 400), 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        if len(p) >= 3:
            d.polygon([tuple(q) for q in p], fill=255)
    m = np.array(im) > 0
    if grow:
        from scipy import ndimage
        yy, xx = np.mgrid[-grow:grow + 1, -grow:grow + 1]
        m = ndimage.binary_dilation(m, structure=(xx * xx + yy * yy) <= grow * grow)
    return m


def silhouette(world, seqs, facades, n, rec):
    """The buildings of screen n as the original camera drew them: the building sprites'
    and kit sprites' opaque pixels, and the kit buildings' fitted faces (their tiles'
    squares also hold grass and water, so the faces stand for them; silhouette IoU 0.96)."""
    im = Image.new('L', (640, 400), 0)
    sprites = world['screens'][str(n)]['sprites']
    owned = {int(e['index']): e for e in sprites}
    for idx in rec['sprites']:
        e = owned[idx]
        fr = frame(seqs, e['seq'], e['frame'])
        a = Image.open(ROOT / 'game' / fr['path']).convert('RGBA').getchannel('A').point(lambda v: 255 if v else 0)
        im.paste(255, (int(e['x'] - fr['dx']), int(e['y'] - fr['dy'])), a)
    d = ImageDraw.Draw(im)
    ox, oy = origin(n)
    for b in facades.get('_kit_buildings', []):
        if n in [int(q) for q in b['screens']]:
            for f in b['faces']:
                d.polygon([(b['rect'][0] + p[0] - ox + 20, b['rect'][1] + p[2] - p[1] - oy) for p in f['pts']], fill=255)
    return np.array(im) > 0


def ring_tiles(world, n, sil, clear):
    """Custom-mask tiles that carry a building's 2D ring (see screen_record)."""
    from scipy import ndimage
    near = ndimage.distance_transform_edt(~sil) <= REACH
    def cells(i):
        return slice(i // 12 * 50, i // 12 * 50 + 50), slice(20 + i % 12 * 50, 70 + i % 12 * 50)
    custom = [i for i, t in enumerate(world['screens'][str(n)]['tiles'][:96]) if int(t.get('hard', 0)) and i not in clear]
    before, per = tile_mask(world, n)
    # The core: custom masks drawn on the building's picture, inside its outline. A mask
    # that only meets the outline (one pixel on 385 and 388: the courtyard wall beside
    # kit-417) is judged as the band is.
    inner = ndimage.binary_erosion(sil)
    core = {i for i in custom if (before[cells(i)] & inner[cells(i)]).any()}
    band = {i for i in custom if i not in core and near[cells(i)].any()}
    # Past the outline a ring piece hangs off the core and ends within reach. A custom mask
    # that joins hardness beyond the reach or runs off the screen (a courtyard wall, a
    # forest edge, a fence) is its own structure and stays, even beside a building.
    rest, _ = tile_mask(world, n, core, clear)
    lab, _ = ndimage.label(rest, structure=np.ones((3, 3)))
    core_px = before & np.isin(per, list(core))
    in_band = np.isin(per, list(band))
    edge = np.zeros_like(rest)
    edge[[0, -1], 20:620] = True
    edge[:, [20, 619]] = True
    ring = set(core)
    for i in band:
        comps = set(np.unique(lab[cells(i)][rest[cells(i)]])) - {0}
        if all((in_band | (lab != c))[lab == c].all() and not (edge & (lab == c)).any()
               and (ndimage.binary_dilation(lab == c) & core_px).any() for c in comps):
            ring.add(i)
    return sorted(ring)


def screen_record(world, seqs, facades, n):
    """What footprints.json holds for screen n (and what the game does with it):
    polys    footprints in screen coordinates; `owner` is the editor index of the building
             sprite (0 for a kit building, which is tiles and many sprites);
    sprites  editor indices of hard sprites whose own hardbox stops blocking: the buildings,
             the kit pieces, and the details the prototype draws onto a building's walls
             (its doors, windows: /struct/ sprites inside the building sprite's rectangle);
    clear    tile indices whose tile hardness stops blocking: the kit buildings' tiles,
             whose art is the building;
    revert   tile indices whose custom hardness mask gives way to the tile art's own
             (default) mask: every custom tile within REACH of the buildings' drawn
             silhouette. The map makers drew a house's hardness as a ring of custom tile
             masks round its picture, and up to ~45 px outside it (274): every custom tile
             the silhouette touches, and custom hardness within REACH that hangs off
             those and ends there (ring_tiles). Other custom masks draw fences, courtyard
             walls, forest edges and gates, which stay.
    Invisible (type 2) hard sprites standing on the drawn building are the same 2D
    hardness (465: a hidden table under the kit building's roof), so they stop blocking."""
    rec = {'polys': [], 'sprites': [], 'clear': [], 'revert': []}
    sprites = world['screens'][str(n)]['sprites']
    seen, rects = set(), []
    for b in building_sprites(world, seqs, facades, n):
        rec['sprites'].append(b['index'])
        e = sprites[b['sprite']]
        fr = frame(seqs, e['seq'], e['frame'])
        w, h = Image.open(ROOT / 'game' / fr['path']).size
        rects.append((e['x'] - fr['dx'], e['y'] - fr['dy'], e['x'] - fr['dx'] + w, e['y'] - fr['dy'] + h))
        key = (b['path'], tuple(b['polys'][0][0]))
        if key in seen:  # a house drawn twice on one screen (type 0 foot + type 1 top)
            continue
        seen.add(key)
        for p in b['polys']:
            rec['polys'].append({'owner': b['index'], 'name': b['path'].split('/')[-1][:-4],
                                 'pts': [[round(x, 1), round(y, 1)] for x, y in p]})
    for k in kit_buildings(facades, n):
        rec['clear'] += k['tiles']
        rec['sprites'] += [int(sprites[i]['index']) for i in k['sprites']]
        for p in k['polys']:
            rec['polys'].append({'owner': 0, 'name': k['name'], 'pts': [[round(x, 1), round(y, 1)] for x, y in p]})
    for e in sprites:
        fr = frame(seqs, e['seq'], e['frame'])
        if fr is None or '/struct/' not in fr['path'] or int(e['index']) in rec['sprites']:
            continue
        w, h = Image.open(ROOT / 'game' / fr['path']).size
        r = (e['x'] - fr['dx'], e['y'] - fr['dy'], e['x'] - fr['dx'] + w, e['y'] - fr['dy'] + h)
        if any(R[0] <= r[0] and R[1] <= r[1] and R[2] >= r[2] and R[3] >= r[3] for R in rects):
            rec['sprites'].append(int(e['index']))
    rec['clear'] = sorted(set(rec['clear']))
    if rec['polys']:
        sil = silhouette(world, seqs, facades, n, rec)
        for e in sprites:
            if int(e['type']) == 2 and int(e.get('hard', 1)) == 0 and not e.get('warp'):
                x0, y0, x1, y1 = hardbox(seqs, e)
                if sil[int(np.clip((y0 + y1) / 2, 0, 399)), int(np.clip((x0 + x1) / 2, 0, 639))]:
                    rec['sprites'].append(int(e['index']))
        rec['revert'] = ring_tiles(world, n, sil, rec['clear'])
    rec['sprites'] = sorted(set(rec['sprites']))
    return rec


def masks(world, seqs, facades, n, rec, vision=0):
    """(before, after, warps): blocked rasters as the game computed them before and after."""
    tiles, _ = tile_mask(world, n)
    tiles_now, _ = tile_mask(world, n, set(rec['revert']), set(rec['clear']))
    live = [e for e in world['screens'][str(n)]['sprites'] if int(e.get('vision', 0)) in (0, vision)]
    hard = [e for e in live if int(e.get('hard', 1)) == 0 and not e.get('warp')]
    before = tiles | rect_mask([hardbox(seqs, e) for e in hard], GROW)
    keep = [e for e in hard if int(e['index']) not in rec['sprites']]
    after = tiles_now | rect_mask([hardbox(seqs, e) for e in keep], GROW) | poly_mask([p['pts'] for p in rec['polys']], GROW)
    warps = [hardbox(seqs, e) for e in live if e.get('warp')]
    return before, after, warps


def overlay(world, seqs, facades, n, rec, which):
    """`before`: the original hardness in red. `after`: what the footprints change; kept in
    grey, dropped (the buildings' 2D hardness) in red, added (the footprints) in green."""
    from facade_contact_sheet import reference
    base = Image.new('RGB', (640, 400))
    base.paste(reference(world, seqs, n), (20, 0))
    before, after, warps = masks(world, seqs, facades, n, rec)
    im = np.array(base).astype(float)
    if which == 'before':
        paint = [(before, [255, 40, 40])]
    else:
        paint = [(before & after, [200, 200, 200]), (before & ~after, [255, 40, 40]), (after & ~before, [40, 230, 60])]
    for m, col in paint:
        im[m] = im[m] * 0.45 + np.array(col, float) * 0.55
    out = Image.fromarray(im.astype(np.uint8))
    d = ImageDraw.Draw(out)
    for p in rec['polys']:
        d.polygon([tuple(q) for q in p['pts']], outline=(0, 255, 255))
    for x0, y0, x1, y1 in warps:
        d.rectangle((x0 - 7, y0 - 7, x1 + 7, y1 + 7), outline=(255, 230, 0))
    d.rectangle((20, 0, 28 + 7 * 12, 16), fill=(0, 0, 0))
    d.text((24, 3), f'{n} {which}', fill=(255, 255, 255))
    return out.crop((20, 0, 620, 400))


def wall_profile(world, seqs, facades, n, rec):
    """Walk into every wall of every footprint on screen n, before and after: for points 5 px
    apart along each edge, from 80 px outside inward along its normal, the signed distance
    from the drawn wall of the last free position (positive: in front of the wall; negative:
    inside it; None: walked more than 80 px in). A sample whose approach meets other hardness
    (a fence, a barrel) first, or starts blocked, says nothing about the building and is
    left out. Returns {name: {'front'|'back': [(before, after)]}}."""
    before, after, _ = masks(world, seqs, facades, n, rec)
    other = after & ~poly_mask([p['pts'] for p in rec['polys']], GROW)
    out = {}
    for p in rec['polys']:
        pts = [tuple(q) for q in p['pts']]
        cx = sum(q[0] for q in pts) / len(pts); cy = sum(q[1] for q in pts) / len(pts)
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            L = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
            if L < 10:
                continue
            nx, ny = -(by - ay) / L, (bx - ax) / L
            if nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0:
                nx, ny = -nx, -ny
            side = 'front' if ny > 0 else 'back'
            for t in np.arange(5 / L, 1 - 5 / L, 5 / L):
                wx, wy = ax + (bx - ax) * t, ay + (by - ay) * t
                path = [(int(round(wx + nx * k)), int(round(wy + ny * k)), k) for k in range(80, -81, -1)]
                if any(not (20 <= x < 620 and 0 <= y < 400) for x, y, _ in path):
                    continue
                if any(other[y, x] for x, y, k in path if k > 6):
                    continue
                res = []
                for m in (before, after):
                    hit = next((k + 1 for x, y, k in path if m[y, x]), None)
                    res.append(hit)
                if res[0] == 81:
                    continue
                out.setdefault(p['name'], {}).setdefault(side, []).append(tuple(res))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('screens', nargs='*', type=int)
    ap.add_argument('--out', default=str(ROOT / 'game/data/footprints.json'))
    ap.add_argument('--sheet', default='')
    ap.add_argument('--profile', action='store_true', help='walk into every wall, before and after')
    args = ap.parse_args()
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    facades = json.loads((ROOT / 'game/prototype/facades.json').read_text())
    recs = {}
    for n in sorted(int(k) for k in world['screens']):
        rec = screen_record(world, seqs, facades, n)
        if rec['polys']:
            recs[str(n)] = rec
    if not args.sheet and not args.profile:
        Path(args.out).write_text(json.dumps({'grow': GROW, 'screens': recs}, indent=None, separators=(',', ':')) + '\n')
        print(len(recs), 'screens with building footprints ->', args.out)
    for n in args.screens:
        rec = recs.get(str(n), {'polys': [], 'sprites': [], 'clear': [], 'revert': []})
        if args.sheet:
            Path(args.sheet).mkdir(parents=True, exist_ok=True)
            row = [overlay(world, seqs, facades, n, rec, w) for w in ('before', 'after')]
            sheet = Image.new('RGB', (1210, 400), (20, 20, 20))
            sheet.paste(row[0], (0, 0)); sheet.paste(row[1], (610, 0))
            sheet.save(Path(args.sheet) / f'collision-{n}.png')
        if args.profile:
            for name, sides in wall_profile(world, seqs, facades, n, rec).items():
                for side, pairs in sides.items():
                    b = [x[0] for x in pairs if x[0] is not None]
                    a = [x[1] for x in pairs if x[1] is not None]
                    thru = sum(1 for x in pairs if x[0] is None)
                    print('%d %-8s %-5s n=%3d  before: stops %s px from the wall (median %s), %d walked >80 px in   after: %s px' % (
                        n, name, side, len(pairs), '%d..%d' % (min(b), max(b)) if b else '-', int(np.median(b)) if b else '-',
                        thru, '%d..%d' % (min(a), max(a)) if a else '-'))
            continue
        before, after, _ = masks(world, seqs, facades, n, rec)
        print(n, 'blocked px before %d after %d' % (before.sum(), after.sum()),
              'footprints', [p['name'] for p in rec['polys']], 'clear', len(rec['clear']), 'revert', len(rec['revert']), 'sprites', rec['sprites'])


if __name__ == '__main__':
    main()
