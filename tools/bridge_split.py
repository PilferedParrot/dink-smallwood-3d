#!/usr/bin/env python3
"""Split the bridges' art into what lies on the water (planks) and what stands (railings), from the pixels.

    /usr/bin/python3 tools/bridge_split.py [--out game/prototype/bridges.json] [--overlay docs/images/bridge-split-m3.jpg]

The original draws a rope railing on a bridge as part of the deck's own sprite (brdge-06, 08, 10: the far railing above
the planks; brdge-01..03: the two side rails along a north-south deck) or as a sprite of its own (brdge-04, 07, 09, 11:
the near railing). In the original's projection a point at height Y on the ground point (x, z) is drawn at (x, z - Y);
so a standing railing's pixels are exactly the art's pixels above the line its posts stand on, and the planks are
exactly the art's pixels below it. The tool finds that split in the art and writes it to game/prototype/bridges.json,
which game/scripts/bridge_rails.gd reads (fp_world.gd calls it for a deck and a near railing); tests/test_fps_bridge_rails.py
reads the art itself and checks the file against it.

The reading (all of it from the art, no per-screen value):
  plank = the biggest connected warm-brown body (r-g >= 24, g-b >= 10) after a 3x3 closing and a 5x5 opening: the rope
    and the posts are thin or not warm and fall out, the planks' dark seams close.
  "ew" (brdge-06, 08, 10), an east-west deck: t(x) is the plank body's top row in column x; the line the far railing
    stands on is the least-squares line a + s x through t over the plank columns (the deck is drawn a little turned:
    06's edge falls 8 px over 66, 08's rises 6 px over 195, and the posts' feet follow it). Card pixels are the
    opaque pixels above min(t(x), the line) in each column; everything else stays painted in the ground.
    The posts are the columns where the card holds a vertical run of at least POST_RUN pixels (a rope never runs
    straight up 16 px; a post runs 38).
  "ns" (brdge-01..03), a north-south deck: the side rails are the two columns bands where the art is mostly not
    warm-brown (rope, its dark side strip); the band's rows above the first plank row (01 only: the end posts) are posts;
    the rope runs along the deck edge at the posts' height H (the height of 01's end post: the rope ties on at its
    top, so the band's pixel at sprite row y is at height H and z = y + H; the pieces of one bridge stack, and the rope of
    01's last row meets the rope of the next piece's first). The rope is the band's pixels that are not warm-brown.
  "near" (brdge-04, 07, 09, 11): the posts are vertical runs, as above; each stands on its lowest drawn pixel, the line
    through the feet is where the railing stands (a hotspot is wherever the artist put it: 11's is 23 px above its
    feet), and everything above that line is a card on it with the posts cut out as prisms. The railings' lines
    slope as their decks' edges do (09: -0.045, 08: -0.054; 07: +0.118, 06: +0.111).
Verdict (2026-10-02, Sonnet 5.5, unit U1 of Dink M3): works; the overlay (docs/images/bridge-split-m3.jpg, looked at) shows the line along the posts' feet and the
rope above it. The line is the planks' top edge as fitted, so it is not a second measurement of the posts' feet. Needs numpy
and scipy (/usr/bin/python3).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "game/assets/graphics/struct/Bridge"
PREFIX = "assets/graphics/struct/Bridge/brdge-%s.png"
POST_RUN = 16  # a column's vertical run of rail pixels that makes it part of a post
EW = ("06", "08", "10")
NS = ("01", "02", "03")
NEAR = ("04", "07", "09", "11")


def load(number: str) -> np.ndarray:
    return np.array(Image.open(ART / ("brdge-%s.png" % number)).convert("RGBA")).astype(int)


def masks(im: np.ndarray):
    r, g, b, a = (im[..., i] for i in range(4))
    opaque = a >= 128
    warm = opaque & (r - g >= 24) & (g - b >= 10)
    return opaque, warm


def plank_body(warm: np.ndarray) -> np.ndarray:
    core = ndi.binary_opening(ndi.binary_closing(warm, np.ones((3, 3))), np.ones((5, 5)))
    lab, k = ndi.label(core)
    if k == 0:
        return core
    sizes = ndi.sum(core, lab, range(1, k + 1))
    return lab == (1 + int(np.argmax(sizes)))


def runs_of(mask: np.ndarray):
    """[[y, x0, x1], ...] the horizontal runs of a mask (x1 inclusive)."""
    out = []
    for y in range(mask.shape[0]):
        x = 0
        w = mask.shape[1]
        while x < w:
            if mask[y, x]:
                x0 = x
                while x < w and mask[y, x]:
                    x += 1
                out.append([y, x0, x - 1])
            else:
                x += 1
    return out


def long_runs(mask: np.ndarray, minimum: int):
    """For each column, [top, bottom] of its longest vertical run of `mask` if it is >= minimum, else None."""
    h, w = mask.shape
    out = []
    for x in range(w):
        best = None
        y = 0
        while y < h:
            if mask[y, x]:
                y0 = y
                while y < h and mask[y, x]:
                    y += 1
                if y - y0 >= minimum and (best is None or y - y0 > best[1] - best[0] + 1):
                    best = [y0, y - 1]
            else:
                y += 1
        out.append(best)
    return out


def posts_of(mask: np.ndarray, minimum: int = POST_RUN):
    """Posts: groups of adjacent columns holding a long vertical run of `mask`: [x0, x1, y0, y1] (inclusive)."""
    runs = long_runs(mask, minimum)
    posts = []
    x = 0
    while x < len(runs):
        if runs[x] is None:
            x += 1
            continue
        x0 = x
        y0, y1 = runs[x]
        while x < len(runs) and runs[x] is not None:
            y0 = min(y0, runs[x][0])
            y1 = max(y1, runs[x][1])
            x += 1
        posts.append([x0, x - 1, y0, y1])
    return posts


def split_ew(im: np.ndarray) -> dict:
    opaque, warm = masks(im)
    body = plank_body(warm)
    h, w = opaque.shape
    top = [int(np.argmax(body[:, x])) if body[:, x].any() else -1 for x in range(w)]
    xs = np.array([x for x in range(w) if top[x] >= 0], float) + 0.5
    ys = np.array([top[x] for x in range(w) if top[x] >= 0], float)
    s, a = np.polyfit(xs, ys, 1)
    card = np.zeros_like(opaque)
    for x in range(w):
        base = int(round(a + s * (x + 0.5)))
        limit = min(base, top[x]) if top[x] >= 0 else base
        card[:max(limit, 0), x] = opaque[:max(limit, 0), x]
    posts = posts_of(card)
    return {"kind": "ew", "line": [round(float(a), 4), round(float(s), 5)], "top": top, "posts": posts, "card": card}


def split_ns(im: np.ndarray, height: float | None) -> dict:
    opaque, warm = masks(im)
    h, w = opaque.shape
    # The band columns: where the rows that carry planks (a row with warm pixels in the middle of the sprite) are mostly
    # not warm-brown. The middle of the sprite is where the planks are for sure.
    mid = slice(w // 4, 3 * w // 4)
    plank_rows = [y for y in range(h) if warm[y, mid].mean() > 0.4]
    first = plank_rows[0] if plank_rows else 0
    # Bands, by hysteresis on the share of the column's planks-rows pixels that are not warm-brown: columns at 0.7 or more
    # are rope or its dark strip for certain; a band grows up to three columns either way over columns at 0.5 or more (a
    # plank edge inside the strip), runs within two columns of each other join, and a band lies in the outer third.
    frac = []
    for x in range(w):
        col = opaque[first:h, x]
        n = int(col.sum())
        frac.append((col & ~warm[first:h, x]).sum() / n if n >= 8 else 0.0)
    bands = []
    x = 0
    while x < w:
        if frac[x] >= 0.7:
            x0 = x
            while x < w and frac[x] >= 0.7:
                x += 1
            x1 = x - 1
            for _ in range(3):
                if x0 > 0 and frac[x0 - 1] >= 0.5:
                    x0 -= 1
            for _ in range(3):
                if x1 + 1 < w and frac[x1 + 1] >= 0.5:
                    x1 += 1
            if bands and x0 - bands[-1][1] <= 3:
                bands[-1][1] = max(bands[-1][1], x1)
            else:
                bands.append([x0, x1])
        else:
            x += 1
    bands = [b for b in bands if b[1] < w // 3 or b[0] > 2 * w // 3]
    card = np.zeros_like(opaque)
    posts = []
    for x0, x1 in bands:
        for y in range(h):
            for x in range(x0, x1 + 1):
                if opaque[y, x] and (y < first or not warm[y, x]):
                    card[y, x] = True
        if first >= POST_RUN:
            # The end post: the band widened by the post's own wood (the warm pixels beside the rope above the planks).
            xs = [x for x in range(max(0, x0 - 2), min(w, x1 + 3)) if opaque[:first, x].sum() >= first * 0.5]
            if xs:
                px0, px1 = min(xs), max(xs)
                for y in range(first):
                    for x in range(px0, px1 + 1):
                        card[y, x] = opaque[y, x]
                top_row = int(np.argmax(opaque[:first, px0:px1 + 1].any(axis=1)))
                posts.append([px0, px1, top_row, first - 1])
    post_height = None
    if posts:
        post_height = float(np.mean([p[3] - p[2] + 1 for p in posts]))
    # The rope is the band's pixels within a column of the rope's highlight (the column with most light pixels); the rest
    # of the band, the dark strip beside it, is the rope's shadow on the planks: it leaves the ground with the rope (the
    # light casts the real one now) and is filled from the planks.
    rope = np.zeros_like(card)
    r, g, b = (im[..., i] for i in range(3))
    light = opaque & ~warm & (r + g + b >= 330)
    rope_cols = []
    for x0, x1 in bands:
        counts = [int(light[:, x].sum()) for x in range(x0, x1 + 1)]
        hc = x0 + int(np.argmax(counts))
        c0, c1 = max(x0, hc - 1), min(x1, hc + 1)
        rope_cols.append([c0, c1])
        rope[:, c0:c1 + 1] = card[:, c0:c1 + 1] & ~warm[:, c0:c1 + 1]
    for p in posts:  # the post's own pixels stand with it, whatever they are
        rope[:p[3] + 1, p[0]:p[1] + 1] &= False
    return {"kind": "ns", "first": first, "bands": bands, "posts": posts, "card": card, "rope": rope, "rope_cols": rope_cols, "post_height": post_height}


def split_near(im: np.ndarray) -> dict:
    """A near railing: posts are vertical runs; each stands on its lowest drawn pixel (its foot bracket included, within
    a few columns of it); the line a + s x through the feet is where the whole railing stands, and everything above it
    is the card (the posts' own pixels stand as prisms)."""
    opaque, _ = masks(im)
    h, w = opaque.shape
    posts = posts_of(opaque)
    feet = []
    for x0, x1, y0, y1 in posts:
        lo, hi = max(0, x0 - 8), min(w, x1 + 9)
        rows = np.nonzero(opaque[:, lo:hi].any(axis=1))[0]
        feet.append(((x0 + x1 + 1) / 2.0, float(rows.max() + 1)))
    if len(feet) >= 2:
        s, a = np.polyfit([f[0] for f in feet], [f[1] for f in feet], 1)
    else:
        s, a = 0.0, feet[0][1] if feet else float(h)
    card = np.zeros_like(opaque)
    for x in range(w):
        base = int(round(a + s * (x + 0.5)))
        card[:max(min(base, h), 0), x] = opaque[:max(min(base, h), 0), x]
    return {"kind": "near", "line": [round(float(a), 4), round(float(s), 5)], "posts": posts, "card": card}


def build() -> tuple[dict, dict]:
    out = {}
    detail = {}
    for n in EW:
        d = split_ew(load(n))
        detail[n] = d
        out[PREFIX % n] = {"kind": "ew", "line": d["line"], "top": d["top"], "posts": d["posts"], "card": runs_of(d["card"])}
    heights = []
    ns = {n: split_ns(load(n), None) for n in NS}
    for n, d in ns.items():
        if d["post_height"]:
            heights.append(d["post_height"])
    ew_heights = [p[3] - p[2] + 1 for d in detail.values() for p in d["posts"]]
    height = float(np.median(heights)) if heights else float(np.median(ew_heights))
    for n, d in ns.items():
        detail[n] = d
        out[PREFIX % n] = {"kind": "ns", "first": d["first"], "bands": d["bands"], "posts": d["posts"], "height": height,
                           "card": runs_of(d["card"]), "rope": runs_of(d["rope"]), "rope_cols": d["rope_cols"]}
    for n in NEAR:
        d = split_near(load(n))
        detail[n] = d
        out[PREFIX % n] = {"kind": "near", "line": d["line"], "posts": d["posts"], "card": runs_of(d["card"])}
    out["_meta"] = {"post_run": POST_RUN, "ns_height": height, "ew_post_heights": ew_heights}
    return out, detail


def overlay(detail: dict, path: Path) -> None:
    tiles = []
    for n in EW + NS + NEAR:
        d = detail[n]
        im = load(n)
        base = Image.new("RGBA", (im.shape[1], im.shape[0]), (90, 160, 200, 255))
        base.alpha_composite(Image.fromarray(im.astype(np.uint8), "RGBA"))
        rgb = np.array(base.convert("RGB")).astype(float)
        if "card" in d:
            c = d["card"]
            rgb[c] = rgb[c] * 0.35 + np.array([255, 40, 200]) * 0.65
        scale = 3 if im.shape[1] <= 120 else 2
        pil = Image.fromarray(rgb.astype(np.uint8)).resize((im.shape[1] * scale, im.shape[0] * scale), Image.NEAREST)
        dr = ImageDraw.Draw(pil)
        if d["kind"] == "ew":
            a, s = d["line"]
            dr.line([(0, a * scale), (im.shape[1] * scale, (a + s * im.shape[1]) * scale)], fill=(255, 255, 0), width=1)
        for x0, x1, y0, y1 in d["posts"]:
            dr.rectangle([x0 * scale, y0 * scale, (x1 + 1) * scale, (y1 + 1) * scale], outline=(0, 255, 0))
        if d["kind"] == "ns":
            for x0, x1 in d["bands"]:
                dr.rectangle([x0 * scale, 0, (x1 + 1) * scale, im.shape[0] * scale - 1], outline=(255, 255, 255))
        dr.rectangle([0, 0, 60, 11], fill=(0, 0, 0))
        dr.text((2, 0), "brdge-" + n, fill=(255, 255, 255))
        tiles.append(pil)
    width = 1700
    x = y = row_h = 0
    placed = []
    for t in tiles:
        if x + t.width > width:
            x = 0
            y += row_h + 4
            row_h = 0
        placed.append((t, x, y))
        x += t.width + 4
        row_h = max(row_h, t.height)
    sheet = Image.new("RGB", (width, y + row_h), (30, 30, 30))
    for t, px, py in placed:
        sheet.paste(t, (px, py))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, quality=88)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "game/prototype/bridges.json"))
    ap.add_argument("--overlay", default="")
    args = ap.parse_args()
    data, detail = build()
    Path(args.out).write_text(json.dumps(data, separators=(",", ":")))
    print("wrote", args.out, "ns_height", data["_meta"]["ns_height"], "ew post heights", data["_meta"]["ew_post_heights"])
    for n, d in detail.items():
        print(n, d["kind"], "posts", d["posts"], d.get("line", ""), d.get("bands", ""), d.get("first", ""))
    if args.overlay:
        overlay(detail, Path(args.overlay))


if __name__ == "__main__":
    main()
