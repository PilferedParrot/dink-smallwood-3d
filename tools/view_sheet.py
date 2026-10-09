#!/usr/bin/env python3
"""Before/after contact sheet of eye-level views, one row per camera and one column per checkout.

    /usr/bin/python3 tools/view_sheet.py views.json --col before=<checkout> --col now=<checkout> \
        [--out sheet.jpg] [--work tmp/view-sheet] [--width 1700]

views.json: [{"name", "screen", "x", "y", "yaw", "pitch"?, "note"?}, ...] in the screen's source pixels
(tests/fps_capture.gd --batch views; yaw 0 looks north, +pi/2 west), or {"name", "screen", "original": true}
for the original's camera. Each checkout renders each screen's views in one Godot run, the screen loaded
with its scripts off (the editor layer: scenario setup), frozen from the load. Renders under xvfb with
WAYLAND_DISPLAY unset and the Dummy audio driver (llvmpipe: no GPU, never the desktop); run it inside
`bwrap --dev-bind / / --tmpfs /dev/input --unshare-net` to hide the input devices. Each checkout needs
its Godot import done. The capture script is this checkout's tests/fps_capture.gd.
Verdict (2026-10-01, Opus 5.5): written for the tenth pass's sheets (docs/DIRECTION.md).
"""
from __future__ import annotations
import argparse, json, os, subprocess, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))


def run(checkout: Path, screen: int, views: list[dict], out: Path, extra: list[str]):
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out) as home:
        batch = Path(home) / 'views.json'
        batch.write_text(json.dumps(views))
        env = {k: v for k, v in os.environ.items() if k != 'WAYLAND_DISPLAY'}
        env.update(XDG_DATA_HOME=home + '/data', XDG_CONFIG_HOME=home + '/config', XDG_CACHE_HOME=home + '/cache')
        r = subprocess.run(['xvfb-run', '-a', '-s', '-screen 0 1280x720x24', GODOT, '--audio-driver', 'Dummy', '--resolution', '960x540',
                            '--path', str(checkout / 'game'), '--script', str(ROOT / 'tests/fps_capture.gd'), '--',
                            f'--screen={screen}', '--scripts=0', f'--batch={batch}', f'--out-dir={out}', *extra],
                           env=env, capture_output=True, text=True, timeout=600)
    missing = [v['name'] for v in views if not (out / f"{v['name']}.png").exists()]
    if missing:
        raise SystemExit(f'{checkout} {screen}: missing {missing}\n' + r.stdout[-3000:] + r.stderr[-3000:])


def cell(path: Path, label: str, w: int, h: int) -> Image.Image:
    im = Image.open(path).convert('RGB').resize((w, h), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, w, 13), fill=(0, 0, 0))
    dr.text((4, 1), label, fill=(255, 255, 255))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('views', type=Path)
    ap.add_argument('--col', action='append', required=True, help='label=checkout (repeat; left to right)')
    ap.add_argument('--out', default=str(ROOT / 'tmp/view-sheet.jpg'))
    ap.add_argument('--work', default=str(ROOT / 'tmp/view-sheet'))
    ap.add_argument('--width', type=int, default=1700)
    ap.add_argument('--arg', action='append', default=[], help='extra fps_capture.gd argument, e.g. --vision=1')
    ap.add_argument('--procs', type=int, choices=range(1, 7), default=4, help='simultaneous capture jobs (count llvmpipe threads too)')
    args = ap.parse_args()
    cols = [(c.split('=', 1)[0], Path(c.split('=', 1)[1]).resolve()) for c in args.col]
    views = json.loads(args.views.read_text())
    work = Path(args.work).resolve()
    by_screen: dict[int, list[dict]] = {}
    for v in views:
        by_screen.setdefault(int(v['screen']), []).append({k: v[k] for k in v if k not in ('screen', 'note')})
    jobs = [(label, co, n, vs) for label, co in cols for n, vs in by_screen.items()]
    with ThreadPoolExecutor(max_workers=min(args.procs, len(jobs))) as ex:
        list(ex.map(lambda j: run(j[1], j[2], j[3], work / j[0] / str(j[2]), args.arg), jobs))
    gap = 6
    w = (args.width - gap * (len(cols) - 1)) // len(cols)
    h = w * 9 // 16
    rows = []
    for v in views:
        r = Image.new('RGB', (args.width, h), (20, 20, 20))
        for i, (label, _) in enumerate(cols):
            note = f" {v['note']}" if v.get('note') else ''
            where = 'original camera' if v.get('original') else f"({v['x']:.0f}, {v['y']:.0f}) yaw {v['yaw']:.2f}"
            r.paste(cell(work / label / str(v['screen']) / f"{v['name']}.png", f"{label}: {v['screen']} {v['name']} {where}{note}", w, h), (i * (w + gap), 0))
        rows.append(r)
    sheet = Image.new('RGB', (args.width, sum(r.height + gap for r in rows)), (20, 20, 20))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height + gap
    sheet.save(args.out, quality=85)
    print('->', args.out, sheet.size)


if __name__ == '__main__':
    main()
