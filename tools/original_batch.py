#!/usr/bin/python3
"""Original-camera renders of many screens, and the mean |RGB| table against the original's picture (Dink M3).

    /usr/bin/python3 tools/original_batch.py render <tag> <screens: 1,2,3 | file.json> [--procs 3] [--out tmp/orig] [--shadows=0]
    /usr/bin/python3 tools/original_batch.py table <before_tag> <now_tag> <screens> [--out tmp/orig] [--noise <tag>] [--json f]

render: THIS worktree's game, through tools/original_batch.gd, into <out>/<tag>/<n>.png (existing files kept), split
across --procs Godot runs, each on its own fixed Xvfb display (no `xvfb-run -a` race), private XDG roots, the Dummy audio
driver, WAYLAND_DISPLAY unset, a process-group timeout. Run it inside `bwrap --dev-bind / / --tmpfs /dev/input
--unshare-net`. For a "before", render a checkout's game with the same tag scheme (or swap a file and render again).
table: per screen, the mean |RGB| of each render against tools/facade_contact_sheet.py reference() (the original's
picture), whole screen and over the pixels the two renders differ on; sorted by the change; a summary line.
Verdict (2026-10-02, Opus 5.5, Dink M3 lead): written for U7 (stacked trees, seam copies); see docs/DIRECTION.md, M3.
"""
from __future__ import annotations
import argparse, json, os, signal, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))


def screens_of(arg: str) -> list[int]:
    return json.load(open(arg)) if arg.endswith('.json') else [int(s) for s in arg.split(',')]


def render(tag, screens, procs, out_root: Path, extra):
    out = out_root / tag
    out.mkdir(parents=True, exist_ok=True)
    todo = [n for n in screens if not (out / f'{n}.png').exists()]

    def job(k):
        part = todo[k::procs]
        if not part:
            return k, 'nothing to do'
        with tempfile.TemporaryDirectory() as home:
            env = {kk: v for kk, v in os.environ.items() if kk != 'WAYLAND_DISPLAY'}
            env.update(XDG_DATA_HOME=home + '/d', XDG_CONFIG_HOME=home + '/c', XDG_CACHE_HOME=home + '/k')
            cmd = ['xvfb-run', '-n', str(171 + k), '-s', '-screen 0 1280x720x24', GODOT, '--audio-driver', 'Dummy',
                   '--resolution', '960x540', '--path', str(ROOT / 'game'), '--script', str(ROOT / 'tools/original_batch.gd'),
                   '--', '--screens=' + ','.join(map(str, part)), '--out-dir=' + str(out.resolve())] + extra
            t0 = time.time()
            p = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
            try:
                log, _ = p.communicate(timeout=60 + 30 * len(part))
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                log, _ = p.communicate()
                return k, 'TIMEOUT after %.0fs, %d/%d shots' % (time.time() - t0, log.count('SHOT '), len(part))
            return k, 'rc %d, %.0fs, %d/%d shots%s' % (p.returncode, time.time() - t0, log.count('SHOT '), len(part),
                                                       ', SCRIPT ERROR' if 'SCRIPT ERROR' in log else '')

    with ThreadPoolExecutor(max_workers=procs) as ex:
        for k, s in ex.map(job, range(procs)):
            print(tag, 'run', k, s, flush=True)


def table(before, now, screens, out_root: Path, noise, json_out):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, str(ROOT / 'tools'))
    import facade_contact_sheet as F
    world = json.loads((ROOT / 'game/data/world.json').read_text())
    seqs = json.loads((ROOT / 'game/data/sequences.json').read_text())['sequences']

    def img(tag, n):
        p = out_root / tag / f'{n}.png'
        return np.array(Image.open(p).convert('RGB')).astype(float) if p.exists() else None
    rows = []
    for n in screens:
        b, a = img(before, n), img(now, n)
        if b is None or a is None:
            print(n, 'missing')
            continue
        ref = np.array(F.reference(world, seqs, n)).astype(float)
        db, da = np.abs(b - ref).mean(2), np.abs(a - ref).mean(2)
        ch = np.abs(b - a).max(2) > 0
        r = dict(n=n, before=float(db.mean()), now=float(da.mean()), changed=int(ch.sum()),
                 before_ch=float(db[ch].mean()) if ch.any() else 0.0, now_ch=float(da[ch].mean()) if ch.any() else 0.0)
        a2 = img(noise, n) if noise else None
        if a2 is not None:
            r['noise_px'] = int((np.abs(a - a2).max(2) > 0).sum())
        rows.append(r)
    rows.sort(key=lambda r: r['now'] - r['before'])
    for r in rows:
        print('%4d %s %6.2f %s %6.2f d %+6.3f | changed %6d px: %6.2f -> %6.2f%s' % (
            r['n'], before, r['before'], now, r['now'], r['now'] - r['before'], r['changed'], r['before_ch'], r['now_ch'],
            ' | noise %d px' % r['noise_px'] if 'noise_px' in r else ''))
    d = np.array([r['now'] - r['before'] for r in rows])
    print('screens %d: nearer %d, further %d, unchanged %d; sum %.2f; worst %+.3f; best %+.3f' % (
        len(rows), (d < 0).sum(), (d > 0).sum(), (d == 0).sum(), d.sum(), d.max(), d.min()))
    if json_out:
        Path(json_out).write_text(json.dumps(rows, indent=0))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('render'); r.add_argument('tag'); r.add_argument('screens')
    r.add_argument('--procs', type=int, default=3); r.add_argument('--out', default=str(ROOT / 'tmp/orig'))
    r.add_argument('--shadows', default='1')
    t = sub.add_parser('table'); t.add_argument('before'); t.add_argument('now'); t.add_argument('screens')
    t.add_argument('--out', default=str(ROOT / 'tmp/orig')); t.add_argument('--noise'); t.add_argument('--json')
    a = ap.parse_args()
    if a.cmd == 'render':
        render(a.tag, screens_of(a.screens), a.procs, Path(a.out), ['--shadows=0'] if a.shadows == '0' else [])
    else:
        table(a.before, a.now, screens_of(a.screens), Path(a.out), a.noise, a.json)


if __name__ == '__main__':
    main()
