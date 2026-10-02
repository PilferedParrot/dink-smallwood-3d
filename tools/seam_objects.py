#!/usr/bin/env python3
"""Independent reading of the map's seam copies and stacked art (Dink M3, U7), for the game's rule to be tested against.

    /usr/bin/python3 tools/seam_objects.py [--json out.json]

The original draws each screen alone, clipped to its 600 x 400 playfield, so the map stitches an object across a seam
by placing a copy in each screen (a partner has the copy's vision). Stacked art (a fully transparent band of >= 3 rows between two drawn parts each >= 30
rows: tree-09/10) draws two objects at two depths; each part stands at its own foot (its lowest drawn row). A placement
(or part) is not built when no drawn pixel of it lies inside its own screen, or when its foot lies outside its own
screen and the screen holding the foot (across one seam or diagonally) places the same art crossing the shared seams at
the same coordinates along them (exactly) with a part whose foot lies inside its own screen (else both stay: a crossing pair). Only static scenery is considered, as copy and as partner: type 1, no script, brain 0, size 100.
Verdict (2026-10-02, Opus 5.5): written for U7; prints the counts the pre-registration names.
"""
from __future__ import annotations
import argparse, json, collections
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
_alpha = {}


def alpha(path):
    if path not in _alpha:
        _alpha[path] = np.array(Image.open(ROOT / 'game' / path).convert('RGBA'))[..., 3] >= 128
    return _alpha[path]


def parts(path):
    """[(row0, row1_exclusive, foot_row)] of the art's stacked parts, or one part for ordinary art."""
    a = alpha(path)
    rows = np.nonzero(a.any(1))[0]
    if not len(rows):
        return []
    cuts = [0]
    for j in range(1, len(rows)):
        if rows[j] - rows[j - 1] > 3 and rows[j - 1] + 1 - rows[cuts[-1]] >= 30 and rows[-1] + 1 - rows[j] >= 30:
            cuts.append(j)
    out = []
    for k, c in enumerate(cuts):
        end = cuts[k + 1] if k + 1 < len(cuts) else len(rows)
        out.append((int(rows[c]), int(rows[end - 1]) + 1, int(rows[end - 1])))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--json')
    args = ap.parse_args()
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    placed = {}
    for n, sc in world['screens'].items():
        if sc.get('indoor'):
            continue
        L = []
        for e in sc['sprites']:
            q = seqs.get(str(e['seq']))
            if not q or not 0 < int(e['frame']) <= len(q['frames']):
                continue
            f = q['frames'][int(e['frame']) - 1]
            a = alpha(f['path'])
            L.append(dict(e=e, p=f['path'], dx=f['dx'], dy=f['dy'], W=a.shape[1], H=a.shape[0],
                          static=e['type'] == 1 and not e.get('script') and int(e.get('brain', 0)) == 0 and int(e.get('size', 100)) == 100))
        placed[int(n)] = L

    def crosses(q, side):
        t, l = q['e']['y'] - q['dy'], q['e']['x'] - q['dx']
        return {'top': t < 0 < t + q['H'], 'bottom': t < 400 < t + q['H'], 'left': l < 20 < l + q['W'], 'right': l < 620 < l + q['W']}[side]

    def partner(n, q, sx, sy):
        """The screen holding the foot places the same static art of the same vision, lined up along every seam both
        cross (x along a top/bottom seam, y along a side seam, exactly), with a part whose foot lies in that screen."""
        m = n + sx + 32 * sy
        if sx and (n + sx - 1) // 32 != (n - 1) // 32:
            return False
        if sx and not crosses(q, 'left' if sx < 0 else 'right'):
            return False
        if sy and not crosses(q, 'top' if sy < 0 else 'bottom'):
            return False
        for r in placed.get(m, []):
            if r['p'] != q['p'] or not r['static'] or r['e'].get('vision', 0) != q['e'].get('vision', 0):
                continue
            if sy and abs(r['e']['x'] + 600 * sx - q['e']['x']) > 0:
                continue
            if sx and abs(r['e']['y'] + 400 * sy - q['e']['y']) > 0:
                continue
            if sx and not crosses(r, 'right' if sx < 0 else 'left'):
                continue
            if sy and not crosses(r, 'bottom' if sy < 0 else 'top'):
                continue
            if any(0 <= r['e']['y'] - r['dy'] + (foot if len(parts(r['p'])) > 1 else r['dy']) < 400 and 20 <= r['e']['x'] < 620
                   for (_, _, foot) in parts(r['p'])):
                return True  # the screen holding the foot shows an object's base here: that copy is the object
        return False

    count = collections.Counter()
    built = []  # (screen, index, part, world foot x, world foot z, path)
    hidden = []
    for n, L in placed.items():
        ox, oy = ((n - 1) % 32) * 600 - 20, (n - 1) // 32 * 400
        for q in L:
            e = q['e']
            if not q['static']:
                continue
            for k, (r0, r1, foot) in enumerate(parts(q['p'])):
                fx, fz = e['x'], e['y'] - q['dy'] + foot if len(parts(q['p'])) > 1 else e['y']
                a = alpha(q['p'])[r0:r1]
                ys, xs = np.nonzero(a)
                sy, sx = ys + r0 + e['y'] - q['dy'], xs + e['x'] - q['dx']
                inside = ((sy >= 0) & (sy < 400) & (sx >= 20) & (sx < 620)).any()
                rec = (n, int(e['index']), k, fx + ox, fz + oy, q['p'])
                if not inside:
                    hidden.append(rec + ('invisible',)); count['hidden: no drawn pixel in its screen'] += 1; continue
                sx = -1 if fx < 20 else 1 if fx >= 620 else 0
                sy = -1 if fz < 0 else 1 if fz >= 400 else 0
                if (sx or sy) and partner(n, q, sx, sy):
                    hidden.append(rec + ('seam:%d,%d' % (sx, sy),)); count['hidden: seam copy'] += 1; continue
                built.append(rec); count['built'] += 1
                if len(parts(q['p'])) > 1:
                    count['built stacked parts'] += 1
    # Safety: every hidden seam copy must have a built object of the same art within 210 px of its foot.
    lost = []
    byart = collections.defaultdict(list)
    for b in built:
        byart[b[5]].append(b)
    for h in hidden:
        if not h[6].startswith('seam'):
            continue
        sx, sy = (int(v) for v in h[6][5:].split(','))
        tol_x = 2 if sy else 210  # along a top/bottom seam x is fixed; across a side seam x is free
        tol_z = 2 if sx else 210
        near = [b for b in byart[h[5]] if abs(b[3] - h[3]) <= tol_x and abs(b[4] - h[4]) <= tol_z]
        if not near:
            lost.append(h)
    print(dict(count), 'seam copies with no built object of their art nearby:', len(lost))
    for h in lost[:20]:
        print('  lost', h)
    if args.json:
        Path(args.json).write_text(json.dumps({'hidden': [list(map(lambda v: v if not isinstance(v, np.integer) else int(v), h)) for h in hidden],
                                               'counts': dict(count)}, indent=0))


if __name__ == '__main__':
    main()
