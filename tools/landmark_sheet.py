#!/usr/bin/env python3
"""A contact sheet of a landmark's eye-level views (tests/fps_capture.gd --batch: <prefix>-dDDD-rRR.png, 8 directions x 2 distances),
stamped with what it was made from, so a sheet cannot outlive its build (P4d fix round 2, F5).

    python tools/landmark_sheet.py <capture dir> <prefix> <out.jpg> --sha <git sha> --export-sha256 <hash> [--legend]

--legend adds the provenance key (prop_solids.gd PROV_*): green projected (the sprite's own pixel), orange filled (not in the sprite: its
neighbours, or a donor patch of the same cloth), blue derived (a colour computed from drawn pixels). The views are the engine's lit render
of the provenance textures, so a hue is read, not a brightness."""
from __future__ import annotations
import argparse
from PIL import Image, ImageDraw

KEY = [('green: the sprite\'s own pixel, projected or kept', (40, 200, 60)), ('orange: not in the sprite: filled from neighbours or a donor patch', (255, 150, 0)),
       ('blue: derived from drawn pixels (a wood column\'s mean, the shaft\'s darkest stone)', (60, 120, 255))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('prefix')
    ap.add_argument('out')
    ap.add_argument('--sha', required=True)
    ap.add_argument('--export-sha256', required=True)
    ap.add_argument('--legend', action='store_true')
    a = ap.parse_args()
    W, H = 480, 270
    names = [f'{a.prefix}-d{d:03d}-r{r}' for r in (70, 150) for d in range(0, 360, 45)]
    head = 40 + (3 * 14 if a.legend else 0)
    sheet = Image.new('RGB', (W * 4, H * 4 + head), 'black')
    dr = ImageDraw.Draw(sheet)
    dr.text((6, 6), f'{a.prefix}  packed export sha256 {a.export_sha256}', fill=(255, 255, 255))
    dr.text((6, 22), f'built from git {a.sha}', fill=(255, 255, 255))
    if a.legend:
        for i, (t, c) in enumerate(KEY):
            dr.rectangle((6, 40 + i * 14, 16, 50 + i * 14), fill=c)
            dr.text((22, 40 + i * 14), t, fill=(255, 255, 255))
    for i, n in enumerate(names):
        im = Image.open(f'{a.dir}/{n}.png').convert('RGB').resize((W, H), Image.LANCZOS)
        ImageDraw.Draw(im).text((4, 4), n, fill=(255, 255, 0))
        sheet.paste(im, ((i % 4) * W, head + (i // 4) * H))
    sheet.save(a.out, quality=88)


if __name__ == '__main__':
    main()
