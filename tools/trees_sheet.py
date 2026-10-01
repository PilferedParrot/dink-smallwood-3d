#!/usr/bin/env python3
"""Evidence for sprites against buildings in the game (docs/DIRECTION.md, "Trees against buildings in
the game"): before/after pairs at eye level on the screens where a canopy or a prop overlaps a house,
the game seen through the original's camera, and the original's own picture of the screen.

    /usr/bin/python3 tools/trees_sheet.py <checkout before> [--out docs/images/trees-buildings-oct1.jpg]
                                          [--work tmp/trees-sheet] [--scan]

Each row is one camera: eye level in the checkout before (the rule's parent) | eye level now | the game
now through the original's camera (orthographic, 45 degrees down, fog off; tests/fps_capture.gd
--batch) | the source reconstruction of that screen (tools/facade_contact_sheet.py reference(): the
original tiles and sprites in the original's draw order). The label of the third cell carries the
mean |RGB| difference from the reconstruction before and now, and a table at the end gives it for the
flagged screens and for screens where nothing is flagged (which must not change). The number is blind
to eye level: look at the pictures. `--scan` renders eight cameras round each case's sprite in both
checkouts and prints how many pixels the rule changed in each, to pick cameras.

Renders under xvfb (no Wayland, Dummy audio, llvmpipe: no GPU, never the desktop). Both checkouts need
their Godot import done. Needs numpy and PIL: run it with /usr/bin/python3.
Verdict (2026-10-01, Sonnet 5.5 subagent): used for docs/images/trees-buildings-oct1.jpg.
"""
from __future__ import annotations
import argparse, json, math, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from facade_contact_sheet import reference  # noqa: E402

GODOT = os.environ.get('GODOT', str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
CELL_H = 250
# screen, what it shows, the sprite [x, y] in the screen's pixels, and eye cameras (x, y, yaw, pitch, note), in
# the screen's source pixels; picked with --scan (the pixels the rule changes), plus one from behind a house.
CASES = [
    dict(screen=251, what='tree-08 over the cabin', sprite=(153, 374), cams=[(61, 466, -0.79, -0.05, 'from the south-west'), (153, 504, 0.0, -0.05, 'from the south, as the original'), (153, 74, 3.14, -0.05, 'from behind the cabin')]),
    dict(screen=528, what='tree-04 over home-07', sprite=(752, 40), cams=[(700, 330, -0.3, -0.05, 'from the south')]),
    dict(screen=497, what='tree-04 under home-07', sprite=(8, 235), cams=[(60, 430, -0.1, -0.05, 'from the south')]),
    dict(screen=530, what='tree-04 under home-01', sprite=(152, 40), cams=[(60, -52, -2.36, -0.05, 'from the north-east')]),
    dict(screen=440, what='barrels and tools on home-04', sprite=(372, 315), cams=[(372, 405, 0.0, -0.05, 'from the south')]),
    dict(screen=734, what='box and tool on home-10', sprite=(249, 327), cams=[(157, 419, -0.79, -0.05, 'from the south-west')]),
]
RAILS = [407, 408, 470, 505, 586]  # no sprite flagged on them: the rule must change nothing here


def run(checkout: Path, screen: int, views: list[dict], out: Path):
    """One Godot run: every view of `screen` through tests/fps_capture.gd --batch."""
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as home:
        batch = Path(home) / 'views.json'
        batch.write_text(json.dumps(views))
        env = {k: v for k, v in os.environ.items() if k != 'WAYLAND_DISPLAY'}
        env.update(XDG_DATA_HOME=home + '/data', XDG_CONFIG_HOME=home + '/config', XDG_CACHE_HOME=home + '/cache')
        r = subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1280x720x24', GODOT, '--audio-driver', 'Dummy', '--resolution', '960x540',
                            '--path', str(checkout / 'game'), '--script', str(ROOT / 'tests/fps_capture.gd'), '--',
                            f'--screen={screen}', '--scripts=0', f'--batch={batch}', f'--out-dir={out}'],
                           env=env, capture_output=True, text=True, timeout=300)
    for v in views:
        if not (out / f"{v['name']}.png").exists():
            raise SystemExit(r.stdout[-3000:] + r.stderr[-3000:])


def eye_name(i: int) -> str:
    return f'eye{i}'


def views_of(case: dict) -> list[dict]:
    return [dict(name='orig', original=True)] + [dict(name=eye_name(i), x=c[0], y=c[1], yaw=c[2], pitch=c[3]) for i, c in enumerate(case['cams'])]


def cell(path: Path, label: str, w: int, h: int = CELL_H) -> Image.Image:
    im = Image.open(path).convert('RGB').resize((w, h), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, w, 13), fill=(0, 0, 0))
    dr.text((4, 1), label, fill=(255, 255, 255))
    return im


def error(world, seqs, screen: int, png: Path) -> float:
    ref = np.asarray(reference(world, seqs, screen), float)
    return float(np.abs(ref - np.asarray(Image.open(png).convert('RGB').resize((600, 400)), float)).mean())


def scan(before: Path, work: Path, dists: list[int] | None = None):
    """Eight cameras round each case's sprite, at each distance in px (7 m, or 4 m for props, by default):
    the pixels the rule changed."""
    def one(case):
        sx, sy = case['sprite']
        ds = dists or [180 if case['screen'] in (440, 734) else 300]
        views = []
        for j, dist in enumerate(ds):
            for k in range(8):
                a = k * math.pi / 4
                cx, cy = sx + dist * math.cos(a), sy + dist * math.sin(a)
                views.append(dict(name=f'scan{j}-{k}', x=cx, y=cy, yaw=math.atan2(-(sx - cx), -(sy - cy)), pitch=-0.05))
        d = work / f"scan-{case['screen']}"
        run(before, case['screen'], views, d / 'before')
        run(ROOT, case['screen'], views, d / 'after')
        out = []
        for v in views:
            a = np.asarray(Image.open(d / 'before' / f"{v['name']}.png").convert('RGB'), int)
            b = np.asarray(Image.open(d / 'after' / f"{v['name']}.png").convert('RGB'), int)
            out.append((int((np.abs(a - b).max(axis=2) > 8).sum()), v))
        return case, out
    with ThreadPoolExecutor(4) as pool:
        for case, out in pool.map(one, CASES):
            print(case['screen'], case['what'])
            for n, v in sorted(out, key=lambda t: -t[0])[:6]:
                print('   %6d px  camera (%.0f, %.0f) yaw %.2f pitch -0.05' % (n, v['x'], v['y'], v['yaw']))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('before', type=Path, help='the checkout before the rule (its game/ with Godot import done)')
    ap.add_argument('--out', default=str(ROOT / 'docs/images/trees-buildings-oct1.jpg'))
    ap.add_argument('--work', default=str(ROOT / 'tmp/trees-sheet'))
    ap.add_argument('--scan', action='store_true')
    ap.add_argument('--dists', default='', help='with --scan: the distances in px, comma separated')
    args = ap.parse_args()
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    if args.scan:
        scan(args.before, work, [int(v) for v in args.dists.split(',')] if args.dists else None)
        return
    jobs = [(c['screen'], views_of(c)) for c in CASES] + [(n, [dict(name='orig', original=True)]) for n in RAILS]
    with ThreadPoolExecutor(4) as pool:
        futures = []
        for n, views in jobs:
            for tag, checkout in (('before', args.before), ('after', ROOT)):
                futures.append(pool.submit(run, checkout, n, views, work / f'{n}' / tag))
        for f in futures:
            f.result()
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    rows = []
    for c in CASES:
        n = c['screen']
        e0 = error(world, seqs, n, work / f'{n}/before/orig.png')
        e1 = error(world, seqs, n, work / f'{n}/after/orig.png')
        for i, cam in enumerate(c['cams']):
            ew, ow = 424, 393
            row = Image.new('RGB', (2 * ew + 2 * ow + 24, CELL_H), (20, 20, 20))
            x = 0
            a = np.asarray(Image.open(work / f'{n}/before/{eye_name(i)}.png').convert('RGB'), int)
            b = np.asarray(Image.open(work / f'{n}/after/{eye_name(i)}.png').convert('RGB'), int)
            changed = int((np.abs(a - b).max(axis=2) > 8).sum())
            for tag, label in (('before', 'before'), ('after', f'now ({changed} px changed)')):
                row.paste(cell(work / f'{n}/{tag}/{eye_name(i)}.png', f"{n} {c['what']}, {cam[4]}: {label}", ew), (x, 0))
                x += ew + 8
            row.paste(cell(work / f'{n}/after/orig.png', f'original camera, now: error {e1:.2f} (before {e0:.2f})', ow), (x, 0))
            x += ow + 8
            reference(world, seqs, n).save(work / f'{n}/reference.png')
            row.paste(cell(work / f'{n}/reference.png', f'{n} the original\'s picture (source)', ow), (x, 0))
            rows.append(row)
    sheet = Image.new('RGB', (rows[0].width, sum(r.height + 6 for r in rows)), (20, 20, 20))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + 6
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out, quality=88)
    print('->', args.out, sheet.size)
    print('\nOriginal camera, mean |RGB| difference from the source reconstruction (screen: before, now, delta):')
    for n in [c['screen'] for c in CASES] + RAILS:
        e0 = error(world, seqs, n, work / f'{n}/before/orig.png')
        e1 = error(world, seqs, n, work / f'{n}/after/orig.png')
        a = np.asarray(Image.open(work / f'{n}/before/orig.png').convert('RGB'), int)
        b = np.asarray(Image.open(work / f'{n}/after/orig.png').convert('RGB'), int)
        kind = 'flagged' if n in [c['screen'] for c in CASES] else 'rail'
        print(f'  {n:4d} {kind:8s} {e0:7.3f} {e1:7.3f} {e1 - e0:+.3f}   pixels changed {int((np.abs(a - b).max(axis=2) > 8).sum())}')


if __name__ == '__main__':
    main()
