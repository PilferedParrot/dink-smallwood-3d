#!/usr/bin/env python3
"""Side-by-side evidence for the sprite-world prototype (docs/DIRECTION.md).

Row per screen: the ORIGINAL source reconstruction (original tiles and vision-0 sprites
at their editor positions, drawn the way tools/render_opening_references.py from the
Sept 11 work does it) next to the prototype rendered through the original camera
(`original-view-N.png`), with the mean absolute RGB difference printed as a
regression number -- read the images first; the number is blind to form and to any
view other than the original camera. Then the prototype's eye-level shots.

Usage: /usr/bin/python3 tools/facade_contact_sheet.py <pigpen-centred dir> <village-centred dir> --out sheet.jpg
       [--screens 439,469,...] [--eye name,k:name,...]   (k:name takes the shot from the k-th dir)
Verdict (2026-09-29, Opus 5.5): used for the facade step; screens 407 439 440 469 470.
Verdict (2026-09-29, Opus 5.5, second pass): used for chimneys and the kit buildings.
Verdict (2026-09-29, Opus 5.5, third pass): used for kit discovery, dormers and backs; the same
shot from two runs (before / after) is labelled with its run directory.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
EYE = ['pen-from-south', 'pen-inside', 'cottage-front', 'cottage-yard', 'neighbour-440',
       'village-469', 'village-469-west', 'village-east']


def reference(world, seqs, n: int) -> Image.Image:
    im = Image.new('RGBA', (640, 400), (0, 0, 0, 255))
    sc = world['screens'][str(n)]
    for i, t in enumerate(sc['tiles'][:96]):
        k = t['tile']; cell = k % 128
        sheet = ROOT / f'game/assets/tiles/ts{k // 128 + 1:02}.png'
        if not sheet.exists():  # a missing sheet (36-39 until the .BMP import fix); the prototype skips it too
            continue
        tile = Image.open(sheet).convert('RGBA').crop(
            ((cell % 12) * 50, (cell // 12) * 50, (cell % 12 + 1) * 50, (cell // 12 + 1) * 50))
        im.paste(tile, (20 + i % 12 * 50, i // 12 * 50))
    for e in sorted(sc['sprites'], key=lambda e: -10000 + e['y'] if e['type'] == 0 else e['que'] or e['y']):
        if e['vision'] != 0 or e['type'] == 2:
            continue
        fs = seqs.get(str(e['seq']), {}).get('frames', [])
        if not fs or not 0 < e['frame'] <= len(fs):
            continue
        f = fs[e['frame'] - 1]; k = e['size'] / 100
        p = Image.open(ROOT / 'game' / f['path']).convert('RGBA')
        p = p.resize((max(1, int(p.width * k)), max(1, int(p.height * k))))
        im.alpha_composite(p, (int(e['x'] - f['dx'] * k), int(e['y'] - f['dy'] * k)))
    return im.crop((20, 0, 620, 400)).convert('RGB')


def label(im: Image.Image, text: str) -> Image.Image:
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 8 + 7 * len(text), 16), fill=(0, 0, 0))
    d.text((4, 3), text, fill=(255, 255, 255))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dirs', nargs='+')
    ap.add_argument('--out', required=True)
    ap.add_argument('--screens', help='comma-separated screens to show (default: every original view found)')
    ap.add_argument('--eye', help='comma-separated eye-level shots; k:name takes it from the k-th dir')
    args = ap.parse_args()
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    views, eyes = {}, {}
    for d in map(Path, args.dirs):
        for p in sorted(d.glob('original-view-*.png')):
            views.setdefault(int(p.stem.split('-')[-1]), p)
    # Each run builds only the 5x5 screens around its centre: take the pigpen shots from
    # the first run (centred on the pigpen) and the village shots from the last.
    # The same shot from two runs (before / after) is labelled with its run's directory.
    names = args.eye.split(',') if args.eye else EYE
    for item in names:
        k, _, name = item.rpartition(':')
        d = Path(args.dirs[int(k)] if k else args.dirs[0] if name.startswith('pen-') else args.dirs[-1])
        if (d / f'{name}.png').exists():
            eyes[item] = (d / f'{name}.png', f'{d.name}: {name}' if k else name)
    rows = []
    screens = [int(n) for n in args.screens.split(',')] if args.screens else sorted(views)
    for n, p in [(n, views[n]) for n in screens]:
        ref = reference(world, seqs, n)
        got = Image.open(p).convert('RGB').resize((600, 400))
        diff = np.abs(np.asarray(ref, float) - np.asarray(got, float)).mean()
        print(f'screen {n}: mean |RGB diff| {diff:.1f}')
        rows.append([label(ref, f'ORIGINAL source reconstruction, screen {n}'),
                     label(got, f'prototype, original camera, screen {n} (|d| {diff:.1f})')])
    for i in range(0, len(names), 2):
        pair = [label(Image.open(eyes[k][0]).convert('RGB').resize((600, 375)), f'prototype eye level: {eyes[k][1]}')
                for k in names[i:i + 2] if k in eyes]
        if pair:
            rows.append(pair)
    H = sum(max(im.height for im in r) + 6 for r in rows)
    sheet = Image.new('RGB', (1206, H), (24, 24, 24))
    y = 0
    for r in rows:
        for j, im in enumerate(r):
            sheet.paste(im, (j * 606, y))
        y += max(im.height for im in r) + 6
    sheet.save(args.out, quality=88)
    print(args.out, sheet.size)


if __name__ == '__main__':
    main()
