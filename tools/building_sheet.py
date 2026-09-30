#!/usr/bin/env python3
"""Evidence for the buildings in the game (docs/DIRECTION.md, eighth pass).

For each wall of tools/collision_sheet.py's shots (the camera positions of
docs/images/collision-sept30.jpg: 74 px out from the drawn wall, where the player stopped plus the
70 px step back) and a wider view 300 px out, and for one shot each of the church, the log cabin,
home-10 and two kit buildings (EXTRA), the same camera in three builds side by side: the old
game (a checkout with the Blender cottages), the game now, and the sprite-world prototype
(prototype/sprite_world_proto.gd, which the game's buildings now share code with).

    /usr/bin/python3 tools/building_sheet.py <old game checkout> --out sheet.jpg [--work DIR]

The game is captured by tests/fps_capture.gd with the screen's editor layer and its scripts off
(scenario setup that skips progression), at its shipped field of view; the prototype films the same
camera from its own shot file at its 1.6 m eye and 75 degree field of view. Each camera is placed in
source pixels, so the two game columns differ in scale (0.06 m/px then, 0.025 now) as they ship.
Renders under xvfb with the Dummy audio driver (llvmpipe, no GPU). Both checkouts need their Godot
import done.
Verdict (2026-09-30, Opus 5.5): used for docs/images/buildings-sept30.jpg.
"""
from __future__ import annotations
import argparse, json, math, os, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import collision_sheet as cs

GODOT = cs.GODOT
NEAR, WIDE = 74, 300  # px out from the drawn wall
PITCH = {NEAR: -0.12, WIDE: -0.05}
# The other building types, from the prototype's own shot files (world pixels): the church, the
# log cabin, home-10's cross wing, the zig-zag kit building, the kit buildings round the fountain.
EXTRA = [('church-219.json', 's188-4-front'), ('cabin-270.json', 's270-6-front'), ('houses-350.json', 's350-1-front'),
         ('kit-419.json', 'kit-417-back'), ('kit-586.json', 'kit-587-front')]
# kit-417's front from the walled street south of it (450), which the game took for an interior
# until the eighth pass: (tag, world camera, world look point).
INLINE = [('kit-417-street', (1100.0, 5700.0), (1100.0, 5300.0))]


def extra_views():
    """(screen, tag, local camera, yaw, pitch) for EXTRA: the screen holding the camera."""
    out = []
    views = []
    for fname, tag in EXTRA:
        shots = {s[0]: s for s in json.loads((ROOT / 'tools/shots' / fname).read_text())}
        views.append(shots[tag])
    views += [[tag, list(pos), list(look)] for tag, pos, look in INLINE]
    for tag, (wx, wy), (lx, ly) in views:
        col, row = int(wx // 600), int(wy // 400)
        n = row * 32 + col + 1
        cam = (wx - col * 600 + 20, wy - row * 400)
        hx, hy = lx - wx, ly - wy
        out.append((n, tag, cam, math.atan2(-hx, -hy), -0.05))
    return out


def game_capture(checkout: Path, n, cam, yaw, pitch, out: Path):
    with tempfile.TemporaryDirectory() as home:
        env = {**os.environ, 'XDG_DATA_HOME': home + '/data', 'XDG_CONFIG_HOME': home + '/config', 'XDG_CACHE_HOME': home + '/cache'}
        r = subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1280x720x24', GODOT, '--audio-driver', 'Dummy',
                            '--resolution', '960x540', '--path', str(checkout / 'game'), '--script', str(ROOT / 'tests/fps_capture.gd'), '--',
                            f'--screen={n}', f'--x={cam[0]:.1f}', f'--y={cam[1]:.1f}', f'--yaw={yaw:.4f}', f'--pitch={pitch:.4f}',
                            '--scripts=0', f'--out={out}'], env=env, capture_output=True, text=True, timeout=180)
    if not out.exists():
        raise SystemExit(r.stdout[-3000:] + r.stderr[-3000:])


def proto_capture(n, shots, out_dir: Path):
    """shots: [(name, cam, yaw, pitch)] in screen n's source pixels; one prototype run centred on n."""
    o = ((n - 1) % 32 * 600 - 20, (n - 1) // 32 * 400)  # world = o + (x, y)
    rows = []
    for name, cam, yaw, pitch in shots:
        # The prototype looks at a point at 0.8 of its 1.6 m eye: that distance gives the pitch.
        L = 0.32 / math.tan(-pitch) / 0.025
        look = (cam[0] - math.sin(yaw) * L, cam[1] - math.cos(yaw) * L)
        rows.append([name, [o[0] + cam[0], o[1] + cam[1]], [o[0] + look[0], o[1] + look[1]]])
    out_dir.mkdir(parents=True, exist_ok=True)
    shots_file = out_dir / 'shots.json'
    shots_file.write_text(json.dumps(rows))
    r = subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1920x1080x24', GODOT, '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'),
                        '-s', 'res://prototype/sprite_world_proto.gd', '--', str(out_dir.resolve()), str(n), str(n), str(shots_file.resolve())],
                       capture_output=True, text=True, timeout=300)
    for name, *_ in shots:
        if not (out_dir / f'{name}.png').exists():
            raise SystemExit(r.stdout[-3000:] + r.stderr[-3000:])


def cell(path: Path, label: str, w=560, h=315):
    im = Image.open(path).convert('RGB').resize((w, h), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, w, 16), fill=(0, 0, 0))
    dr.text((5, 3), label, fill=(255, 255, 255))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('old', type=Path)
    ap.add_argument('--out', default=str(ROOT / 'docs/images/buildings-sept30.jpg'))
    ap.add_argument('--work', default=str(ROOT / 'tmp/building-sheet'))
    args = ap.parse_args()
    work = Path(args.work); work.mkdir(parents=True, exist_ok=True)
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']
    fac = json.loads((ROOT / 'game/prototype/facades.json').read_text())
    plan = {}  # screen -> [(tag, cam, yaw, pitch)]
    for n, name, side in cs.SHOTS:
        start, wall, inward = cs.approach(world, seqs, fac, n, name, side)
        yaw = math.atan2(-inward[0], -inward[1])
        for d in (NEAR, WIDE):
            cam = (wall[0] - inward[0] * d, wall[1] - inward[1] * d)
            plan.setdefault(n, []).append((f'{name}-{side}-{d}', cam, yaw, PITCH[d]))
    for n, tag, cam, yaw, pitch in extra_views():
        plan.setdefault(n, []).append((tag, cam, yaw, pitch))
    rows = []
    for n, shots in plan.items():
        proto = work / f'proto-{n}'
        proto_capture(n, shots, proto)
        for tag, cam, yaw, pitch in shots:
            imgs = []
            for label, checkout in (('old game', args.old), ('game now', ROOT)):
                png = work / f'{n}-{tag}-{label.replace(" ", "-")}.png'
                game_capture(checkout, n, cam, yaw, pitch, png)
                imgs.append(cell(png, f'{label}: {n} {tag}, camera ({cam[0]:.0f}, {cam[1]:.0f})'))
            imgs.append(cell(proto / f'{tag}.png', f'prototype: {n} {tag}, same camera'))
            print(n, tag, 'camera', tuple(round(v, 1) for v in cam), 'yaw %.3f' % yaw)
            row = Image.new('RGB', (560 * 3 + 20, 315), (20, 20, 20))
            for i, im in enumerate(imgs):
                row.paste(im, (i * 570, 0))
            rows.append(row)
    sheet = Image.new('RGB', (rows[0].width, sum(r.height + 8 for r in rows)), (20, 20, 20))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height + 8
    sheet.save(args.out, quality=85)
    print('->', args.out)


if __name__ == '__main__':
    main()
