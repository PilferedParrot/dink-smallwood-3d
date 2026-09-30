#!/usr/bin/env python3
"""Eye-level shots of kit buildings for the sprite-world prototype (docs/DIRECTION.md).

Reads game/prototype/facades.json and writes a shots file for sprite_world_proto.gd:
[[name, [x, y], [look x, look y]], ...] in world source pixels. Per building: in front of its
lowest front corner (`-front`), close to its front wall (`-wall`), from behind (`-back`), and
with --dormers one shot per dormer (`-dormerK`). A camera stands at eye height; world =
screen origin + (x - 20, y).

A name of the form screen:index is a placed sprite (a house, the church, a cabin): four shots
round it, from the south-west (`-front`), east, north (`-back`) and west, at a distance scaled to
the sprite, and one close from the south-west (`-near`), aimed at its footprint (the lower part of the sprite, which the oblique original
camera draws below the roof).

Usage: /usr/bin/python3 tools/kit_shots.py kit-498[,kit-251,500:0...] out.json [--dormers]
Verdict (2026-09-29, Opus 5.5): used for the kit-discovery / dormer / back evidence
(docs/images/kit-buildings-sept29.jpg).
"""
import argparse, json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('names')
    ap.add_argument('out')
    ap.add_argument('--dormers', action='store_true')
    args = ap.parse_args()
    fac = json.loads((ROOT / 'game/prototype/facades.json').read_text())
    shots = []
    for name in args.names.split(','):
        if ':' not in name:
            continue
        world = json.loads((ROOT / 'game/data/world.json').read_text())
        seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
        n, i = (int(v) for v in name.split(':'))
        e = world['screens'][str(n)]['sprites'][i]
        f = seqs[str(e['seq'])]['frames'][e['frame'] - 1]
        w, h = Image.open(ROOT / 'game' / f['path']).size
        x0 = (n - 1) % 32 * 600 + e['x'] - 20 - f['dx']
        y0 = (n - 1) // 32 * 400 + e['y'] - f['dy']
        c = np.array([x0 + w / 2, y0 + 0.65 * h])
        d = 1.3 * max(w, h)
        tag = f's{n}-{i}'
        shots += [[tag + '-front', (c + (-0.3 * d, d)).tolist(), c.tolist()],
                  [tag + '-east', (c + (d, -0.1 * d)).tolist(), c.tolist()],
                  [tag + '-back', (c + (0.2 * d, -d)).tolist(), c.tolist()],
                  [tag + '-west', (c + (-d, 0)).tolist(), c.tolist()],
                  [tag + '-near', (c + (-0.35 * d, 0.45 * d)).tolist(), c.tolist()]]
    for b in fac['_kit_buildings']:
        if b['name'] not in args.names.split(','):
            continue
        wx, wy = b['rect'][:2]
        n = b['name']
        if args.dormers:
            for k, dm in enumerate(b.get('dormers', [])):
                P = np.array([p for f in dm['faces'] for p in f['pts']])
                x, z = P[:, 0].mean() + wx, P[:, 2].mean() + wy
                shots.append([f'{n}-dormer{k}', [x - 250, z + 560], [x, z]])
            continue
        front = [np.array(q) + (wx, wy) for q in b['front']]
        ground = np.array([p for f in b['faces'] if f['label'] == 1 for p in f['pts'] if abs(p[1]) < 1e-6])
        back_z, cx = wy + ground[:, 2].min(), wx + ground[:, 0].mean()
        low = max(front, key=lambda q: q[1])
        mid = (front[0] + low) / 2
        shots += [[n + '-front', (low + (-120, 520)).tolist(), (low + (0, -200)).tolist()],
                  [n + '-wall', (mid + (-60, 230)).tolist(), (mid + (60, -80)).tolist()],
                  [n + '-back', [cx + 150, back_z - 520], [cx, back_z + 100]]]
    Path(args.out).write_text(json.dumps([[s[0], [round(float(v), 1) for v in s[1]], [round(float(v), 1) for v in s[2]]] for s in shots]))
    print(len(shots), 'shots ->', args.out)


if __name__ == '__main__':
    main()
