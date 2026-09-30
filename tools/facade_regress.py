#!/usr/bin/env python3
"""Render every building run of the sprite-world prototype and compare two sets of renders
(docs/DIRECTION.md). One command replaces the per-run Godot invocations of the Sept 29 passes.

  render <checkout> <out_root> [--only name,...]
      Runs sprite_world_proto.gd in <checkout>/game for each run in RUNS (headless, xvfb,
      Mesa llvmpipe: no GPU), writing <out_root>/<name>/. Shot files are read from THIS
      checkout's tools/shots, so a "before" checkout is filmed from the same cameras.
  table <before_root> <after_root>
      Per screen, the mean |RGB| difference between the source reconstruction
      (tools/facade_contact_sheet.py, this checkout's tiles) and each root's original-camera
      render. A regression check only: it is blind to every view but the original camera.
      Look at the renders first.
  sheet <before_root> <after_root> --out sheet.jpg --screens 270,251 [--eye shot,shot...]
      Contact sheet: per screen, the source reconstruction, before and after through the
      original camera; then per eye-level shot, before and after.

Verdict (2026-09-29, Opus 5.5, fourth pass): used for the church / cabin / seq 63 pass; covers
every screen the Sept 29 passes rendered, plus the new buildings.
"""
from __future__ import annotations
import argparse, json, os, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get('GODOT', Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
# (name, centre screen, shots file in tools/shots or None for the script's defaults, original-camera screens)
RUNS = [
    ('c407', 407, None, [407]),
    ('c470', 470, None, [407, 439, 440, 469, 470]),
    ('c505', 505, None, [439, 472, 473, 474, 504, 505, 506, 537, 538, 539]),
    ('c419', 419, 'kit-419.json', [385, 386, 387, 388, 417, 418, 419, 420]),
    ('c219', 219, 'kit-219.json', [186, 187, 188, 218, 219, 251]),
    ('c586', 586, 'kit-586.json', [553, 554, 555, 585, 586, 587]),
    ('c498', 498, 'kit-498.json', [465, 466, 467, 497, 498, 499, 500]),
    ('dormers', 505, 'dormers-505.json', [505]),
    ('soffit', 505, 'soffit-505.json', [505]),
    ('cottage', 470, 'cottage-439.json', [439]),
    ('church', 219, 'church-219.json', [187, 188, 251]),
    ('cabin', 270, 'cabin-270.json', [270]),
    ('h501', 501, 'houses-501.json', [500, 501]),
    ('h498', 498, 'houses-498.json', [497]),
    ('h537', 505, 'houses-537.json', [537]),
    ('h619', 619, 'houses-619.json', [617, 618, 619]),
    ('h350', 350, 'houses-350.json', [318, 349, 350]),
    ('court', 419, 'court-419.json', [418]),
]


def render(checkout: Path, out_root: Path, only=None):
    for name, centre, shots, views in RUNS:
        if only and name not in only:
            continue
        if shots and not (ROOT / 'tools/shots' / shots).exists():
            print('skip', name, '(no', shots + ')')
            continue
        out = (out_root / name).resolve()
        cmd = ['xvfb-run', '-a', '-s', '-screen 0 1920x1080x24', str(GODOT), '--path', str(checkout / 'game'),
               '-s', 'res://prototype/sprite_world_proto.gd', '--', str(out), str(centre)] + [str(v) for v in views]
        if shots:
            cmd.append(str(ROOT / 'tools/shots' / shots))
        try:  # a script error leaves Godot running: never wait on it forever
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired:
            print(name, "TIMEOUT"); continue
        errs = [l for l in (r.stdout + r.stderr).splitlines() if 'ERROR' in l or 'SCRIPT ERROR' in l]
        print(name, 'exit', r.returncode, len(list(out.glob('*.png'))), 'images', *errs[:3], sep='  ')


def table(before: Path, after: Path):
    sys.path.insert(0, str(ROOT / 'tools'))
    from facade_contact_sheet import reference
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']

    def views(root):
        out = {}
        for name, *_ in RUNS:
            for p in sorted((root / name).glob('original-view-*.png')):
                out.setdefault(int(p.stem.split('-')[-1]), p)
        return out
    vb, va = views(before), views(after)
    print('screen  before  after  delta')
    for n in sorted(set(vb) | set(va)):
        ref = np.asarray(reference(world, seqs, n), float)
        d = [np.abs(ref - np.asarray(Image.open(v[n]).convert('RGB').resize((600, 400)), float)).mean() if n in v else None
             for v in (vb, va)]
        fmt = lambda x: '   -  ' if x is None else f'{x:6.1f}'
        flag = '  WORSE' if None not in d and d[1] > d[0] + 0.05 else ''
        print(f'{n:6d}  {fmt(d[0])}  {fmt(d[1])}  {"" if None in d else f"{d[1] - d[0]:+.1f}"}{flag}')


def find(root: Path, fname: str):
    for name, *_ in RUNS:
        if (root / name / fname).exists():
            return root / name / fname


def sheet(before: Path, after: Path, out: str, screens, eyes):
    sys.path.insert(0, str(ROOT / 'tools'))
    from facade_contact_sheet import reference, label
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    rows = []
    for n in screens:
        r = [label(reference(world, seqs, n).resize((400, 267)), f'source {n}')]
        for tag, root in (('before', before), ('after', after)):
            p = find(root, f'original-view-{n}.png')
            r.append(label(Image.open(p).convert('RGB').resize((400, 267)), f'{tag}, original camera {n}') if p
                     else Image.new('RGB', (400, 267)))
        rows.append(r)
    for e in eyes:
        r = []
        for tag, root in (('before', before), ('after', after)):
            p = find(root, e + '.png')
            r.append(label(Image.open(p).convert('RGB').resize((600, 338)), f'{tag}, eye level: {e}') if p
                     else Image.new('RGB', (600, 338)))
        rows.append(r)
    W = max(sum(im.width + 4 for im in r) for r in rows)
    H = sum(max(im.height for im in r) + 4 for r in rows)
    im_ = Image.new('RGB', (W, H), (24, 24, 24))
    y = 0
    for r in rows:
        x = 0
        for im in r:
            im_.paste(im, (x, y)); x += im.width + 4
        y += max(im.height for im in r) + 4
    im_.save(out, quality=86)
    print(out, im_.size)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render'); r.add_argument('checkout', type=Path); r.add_argument('out_root', type=Path)
    r.add_argument('--only')
    t = sub.add_parser('table'); t.add_argument('before', type=Path); t.add_argument('after', type=Path)
    h = sub.add_parser('sheet'); h.add_argument('before', type=Path); h.add_argument('after', type=Path)
    h.add_argument('--out', required=True); h.add_argument('--screens', default=''); h.add_argument('--eye', default='')
    a = ap.parse_args()
    if a.cmd == 'render':
        render(a.checkout.resolve(), a.out_root, a.only.split(',') if a.only else None)
    elif a.cmd == 'table':
        table(a.before, a.after)
    else:
        sheet(a.before, a.after, a.out, [int(v) for v in a.screens.split(',') if v], [v for v in a.eye.split(',') if v])


if __name__ == '__main__':
    main()
