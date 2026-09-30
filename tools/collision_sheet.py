#!/usr/bin/env python3
"""Before/after evidence for collision from one source (docs/DIRECTION.md, seventh pass).

For each shot, Dink starts 60 px outside a wall of a fitted footprint, faces it and holds W
(the real input path, tests/fps_capture.gd --walk; the screen is loaded with its scripts off, the
editor layer the overlays show). A post marks where he stopped, and the
camera steps 70 px back at eye level to show it against the wall, in two checkouts; the
collision overlay of tools/collision_map.py goes beside them (magenta: the walk).

    /usr/bin/python3 tools/collision_sheet.py <before checkout> <after checkout> --out sheet.jpg

Renders under xvfb with the Dummy audio driver (llvmpipe, no GPU). Both checkouts need their
Godot import done. The before checkout is measured against this checkout's footprints.
Verdict (2026-09-30, Opus 5.5): used for docs/images/collision-sept30.jpg.
"""
from __future__ import annotations
import argparse, json, math, os, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import collision_map as cm

GODOT = os.environ.get('GODOT', str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
# screen, footprint, side: Dink's cottage front and back, Ethel's front, a village back, the
# inn's back (the old data had no collision there), a village front.
SHOTS = [(439, 'home-01', 'front'), (439, 'home-01', 'back'), (409, 'home-06', 'front'),
         (440, 'home-04', 'back'), (505, 'kit-537', 'back'), (537, 'home-07', 'front')]


def approach(world, seqs, fac, n, name, side):
    """A wall point with a clear approach in both collision maps: (start, wall, inward)."""
    rec = json.loads((ROOT / 'game/data/footprints.json').read_text())['screens'][str(n)]
    before, after, warps = cm.masks(world, seqs, fac, n, rec)
    other = after & ~cm.poly_mask([p['pts'] for p in rec['polys']], cm.GROW)
    def near_door(x, y):  # a wall point by a door would take him in (its trigger is grown 7)
        return any(x0 - 30 <= x <= x1 + 30 and y0 - 30 <= y <= y1 + 30 for x0, y0, x1, y1 in warps)
    for p in rec['polys']:
        if p['name'] != name:
            continue
        pts = [tuple(q) for q in p['pts']]
        cx = sum(q[0] for q in pts) / len(pts); cy = sum(q[1] for q in pts) / len(pts)
        edges = []
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            L = math.hypot(bx - ax, by - ay)
            nx, ny = -(by - ay) / L, (bx - ax) / L
            if nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0:
                nx, ny = -nx, -ny
            if (ny > 0) == (side == 'front') and L > 40:
                edges.append((L, (ax, ay), (bx, by), (nx, ny)))
        for L, (ax, ay), (bx, by), (nx, ny) in sorted(edges, reverse=True):
            for t in (0.5, 0.35, 0.65, 0.25, 0.75, 0.15, 0.85):
                wx, wy = ax + (bx - ax) * t, ay + (by - ay) * t
                if near_door(wx, wy):
                    continue
                path = [(int(round(wx + nx * k)), int(round(wy + ny * k))) for k in range(60, 6, -1)]
                if all(20 <= x < 620 and 0 <= y < 400 for x, y in path) and not any(other[y, x] for x, y in path) \
                        and not before[path[0][1], path[0][0]]:
                    return (wx + nx * 60, wy + ny * 60), (wx, wy), (-nx, -ny)
    raise SystemExit(f'no clear approach to {name} {side} on {n}')


def capture(checkout: Path, n, start, inward, out: Path):
    yaw = math.atan2(-inward[0], -inward[1])
    with tempfile.TemporaryDirectory() as home:
        env = {**os.environ, 'XDG_DATA_HOME': home + '/data', 'XDG_CONFIG_HOME': home + '/config', 'XDG_CACHE_HOME': home + '/cache'}
        r = subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1280x720x24', GODOT, '--audio-driver', 'Dummy',
                            '--resolution', '960x540', '--path', str(checkout / 'game'), '--script', str(ROOT / 'tests/fps_capture.gd'), '--',
                            f'--screen={n}', f'--x={start[0]:.1f}', f'--y={start[1]:.1f}', f'--yaw={yaw:.4f}', '--pitch=-0.12',
                            '--walk=90', '--back=70', f'--out={out}'], env=env, capture_output=True, text=True, timeout=120)
    stop = None
    for line in r.stdout.splitlines():
        if line.startswith('WALKED to'):
            x, y = line.split('(')[1].split(')')[0].split(',')
            stop = (float(x), float(y))
            if int(line.split(' on ')[1]) != n:
                raise SystemExit(f'{checkout}: the walk left screen {n}: {line}')
    if not out.exists():
        raise SystemExit(r.stdout + r.stderr)
    return stop


def inside(pt, pts):
    x, y, c = pt[0], pt[1], False
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[i - 1]
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            c = not c
    return c


def distance(stop, rec, name):
    best, within = 1e9, False
    for p in rec['polys']:
        if p['name'] != name:
            continue
        pts = p['pts']
        within |= inside(stop, pts)
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            vx, vy = bx - ax, by - ay
            t = max(0, min(1, ((stop[0] - ax) * vx + (stop[1] - ay) * vy) / (vx * vx + vy * vy)))
            best = min(best, math.hypot(stop[0] - ax - t * vx, stop[1] - ay - t * vy))
    return -best if within else best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('before', type=Path)
    ap.add_argument('after', type=Path)
    ap.add_argument('--out', default=str(ROOT / 'docs/images/collision-sept30.jpg'))
    ap.add_argument('--work', default=str(ROOT / 'tmp/collision-sheet'))
    args = ap.parse_args()
    work = Path(args.work); work.mkdir(parents=True, exist_ok=True)
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    fac = json.loads((ROOT / 'game/prototype/facades.json').read_text())
    recs = json.loads((ROOT / 'game/data/footprints.json').read_text())['screens']
    rows = []
    for n, name, side in SHOTS:
        start, wall, inward = approach(world, seqs, fac, n, name, side)
        rec = recs[str(n)]
        cells = []
        for tag, checkout in (('before', args.before), ('after', args.after)):
            png = work / f'{n}-{name}-{side}-{tag}.png'
            stop = capture(checkout, n, start, inward, png)
            d = distance(stop, rec, name) if stop else float('nan')
            im = Image.open(png).convert('RGB').resize((640, 360))
            dr = ImageDraw.Draw(im)
            dr.rectangle((0, 0, 640, 18), fill=(0, 0, 0))
            dr.text((6, 4), f'{tag}: {n} {name} {side} wall; the post: where W stopped, {d:+.0f} px from the drawn wall', fill=(255, 255, 255))
            cells.append(im)
            print(n, name, side, tag, 'start', tuple(round(v, 1) for v in start), 'stop', stop, 'distance %.1f' % d)
        ov = cm.overlay(world, seqs, fac, n, rec, 'after').resize((480, 320))
        d2 = ImageDraw.Draw(ov)
        sx, sy = (start[0] - 20) * 0.8, start[1] * 0.8
        wx, wy = (wall[0] - 20) * 0.8, wall[1] * 0.8
        d2.line((sx, sy, wx, wy), fill=(255, 0, 255), width=3)
        d2.ellipse((sx - 4, sy - 4, sx + 4, sy + 4), outline=(255, 0, 255), width=2)
        row = Image.new('RGB', (640 * 2 + 480 + 20, 360), (20, 20, 20))
        row.paste(cells[0], (0, 0)); row.paste(cells[1], (650, 0)); row.paste(ov, (1300, 20))
        rows.append(row)
    sheet = Image.new('RGB', (rows[0].width, sum(r.height + 10 for r in rows)), (20, 20, 20))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height + 10
    sheet.save(args.out, quality=85)
    print('->', args.out)


if __name__ == '__main__':
    main()
