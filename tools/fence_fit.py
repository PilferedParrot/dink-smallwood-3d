#!/usr/bin/env python3
"""Read the rail fences' posts and rails from their art's pixels: the fences stand as 3D posts and rails (M3 solid unit).

    /usr/bin/python3 tools/fence_fit.py [--out game/prototype/fences.json] [--overlay PREFIX]

The art draws a fence in the original's projection, screen = (X, Z - Y) (docs/DIRECTION.md, "Buildings"): a point at height
Y over the ground point (X, Z) is drawn Y rows above where it stands. So a fence's pixels fix a 3D fence:
  post  a column of the post's own pixels (dark in the lands fences, pale wood with a dark edge on the island): its width is
        read from the rows just above its foot, its foot F is the row after its last drawn row (the front face's bottom edge
        on the ground), and its top row is its first drawn row (the top face's far edge). The post is as deep as it is wide
        (bridge_rails.gd takes a prism so: the lit cap measures 2-3 rows, the artist's, not a second reading), so its height
        is F - top - width. A post cut by the sprite's edge is found from the columns that are drawn.
  rail  a bar between two posts, th high and td deep: a column of it is 2 visible faces, so each is (rows of its run) / 2.
        Its bottom stands at height bA over one post and bB over the next. The fit is a search: for each bay and each of K
        rails the (bA, bB) whose projected box (the convex hull of its eight corners, as the art draws it) covers the most
        art pixels not yet explained and the fewest transparent ones.
Two styles: lands/Fence (fence-01..06: 2 rails a bay) and struct/Island (isle-07: a lattice, 3 bars a bay). The front view of
each (fence-01, isle-07: the fence seen from the front, its posts in a row) gives the module: post width and height, rail
section. The turned sprites (fence-02, 03, 05, 06 diagonals; fence-04 and isle-08, the column along the depth axis) show the
same fence, so their posts and rails are the same size and only their places differ; a column's posts are one under another
and its rails end-on, so they are not readable and the column takes the front view's bays (in the direction that matches
its silhouette better), its posts placed by the cap row and the solid column's last row (COLUMNS below).
Output: game/prototype/fences.json, read by game/scripts/fence_solid.gd (which builds the posts and rails and textures them
by the original camera's projection, so from the original camera they are the art's own pixels), and tests/test_fps_fences.py,
which re-reads the art and checks every number here against it.

Which rows are depth (the question the map answers): a post's foot F is a ground row, 1:1 (the same convention the buildings
and bridges use), and the map confirms it where it chains: on screen 731 the island's top fence (isle-07 at y 182: feet at
182-59+58 = 181) and the column isle-08 at (207, 270), whose first post foot reads 270-148+59 = 181, start at one post; the
second column placement (y 344) starts 74 below, and its first two posts stand within 2 px of the first column's last two
(255/257, 293/295). The pigpen's corner piece (fence-02 at 91, 105: post foot 111) meets the column (fence-04 at 41, 164: first
post foot 113) within 2 px. A hotspot is not the ground line: fence-01's hotspot (dy 41) is 6 rows above its posts' feet.

Verdict (2026-10-07, Sonnet 5.5, solid-fences unit): see docs/DIRECTION.md, "Solid fences". Needs numpy and PIL (/usr/bin/python3).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
DARK = 0x58  # r+g+b below this is a lands post's dark front

LANDS = "assets/graphics/lands/Fence/fence-%02d.png"
ISLE = "assets/graphics/struct/Island/isle-%02d.png"
STYLES = {
    "lands": {"front": 1, "fmt": LANDS, "arts": [(LANDS % n) for n in (1, 2, 3, 5, 6)], "column": (LANDS % 4), "rails": 2,
              "any_pixel": False, "min_count": 12, "min_span": 33},
    "island": {"front": 7, "fmt": ISLE, "arts": [(ISLE % 7)], "column": (ISLE % 8), "rails": 3, "any_pixel": True,
               "min_count": 30, "min_span": 45},
}
# The column arts' posts: one under another, behind their rails' top faces, so the columns do not give them. Read from the pixel
# dumps (docs/DIRECTION.md, "Solid fences"). fence-04: the first post's cap is rows 0-2, the last post's solid column ends at row
# 117 (foot 118); the second stands between (the module's bays are equal). isle-08: the first post's foot is row 59 (the chain: 731), its
# last post's column ends at row 172 (foot 173); the world's chain says four posts: its second placement starts 74 rows below
# the first, and posts 3 and 4 of the one stand on posts 1 and 2 of the other within 2 px, which three bays of 38 rows give.
COLUMNS = {
    LANDS % 4: {"x": 18.0, "feet": [47.0, 82.5, 118.0]},
    ISLE % 8: {"x": 25.0, "feet": [59.0, 97.0, 135.0, 173.0]},
}


def load(rel: str):
    """RGBA ints and the 'clean' opaque mask: the shadow dither (a dark pixel with no dark 4-neighbour) is not art."""
    im = np.array(Image.open(GAME / rel).convert("RGBA")).astype(int)
    a = im[..., 3] > 0
    d = a & (im[..., :3].sum(-1) < 11)
    dn = np.zeros_like(d)
    dn[:, 1:] |= d[:, :-1]
    dn[:, :-1] |= d[:, 1:]
    dn[1:, :] |= d[:-1, :]
    dn[:-1, :] |= d[1:, :]
    clean = a & ~(d & ~dn)
    return im, clean


def detect_posts(im, clean, style):
    """The posts of an art: columns holding many of the post's pixels, grouped; a post's group spans most of a post's height."""
    h, w = clean.shape
    dark = clean if style["any_pixel"] else clean & (im[..., :3].sum(-1) < DARK)
    cnt = dark.sum(0)
    cols = [x for x in range(w) if cnt[x] >= style["min_count"]]
    # A sprite's edge cuts a post: its few drawn columns hold fewer of the post's pixels.
    for x in (0, 1, 2, w - 3, w - 2, w - 1):
        if 0 <= x < w and cnt[x] >= style["min_count"] // 2 and x not in cols:
            cols.append(x)
    cols.sort()
    groups: list[list[int]] = []
    for x in cols:
        if groups and x - groups[-1][-1] <= 1:
            groups[-1].append(x)
        else:
            groups.append([x])
    posts = []
    for g in groups:
        rows = np.nonzero(dark[:, g[0] : g[-1] + 1].any(1))[0]
        if rows.max() - rows.min() + 1 < style["min_span"]:
            continue
        edge = g[0] == 0 or g[-1] == w - 1
        if len(g) < (1 if style["any_pixel"] else 3) and not edge:
            continue  # a thin dark line inside the sprite is a rail's edge, not a post
        foot = int(rows.max()) + 1
        # The post's own columns, from the rows just above its foot (nothing else is drawn there).
        lo, hi = max(g[0] - 3, 0), min(g[-1] + 4, w)
        xs = np.nonzero(clean[foot - 4 : foot, lo:hi].any(0))[0] + lo
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        # The top: the first row where the post's columns draw anything, up from its first dark/post row.
        t = int(rows.min())
        while t - 1 >= 0 and clean[t - 1, x0:x1].any():
            t -= 1
        cut = "left" if x0 == 0 else ("right" if x1 >= w else None)
        posts.append({"x0": x0, "x1": x1, "foot": foot, "top": t, "cut": cut})
    return posts


def read_module(style):
    """Post w (= d) x H, rail th x td, from the front view's art."""
    rel = style["fmt"] % style["front"]
    im, clean = load(rel)
    posts = [p for p in detect_posts(im, clean, style) if p["cut"] is None]
    w = int(round(float(np.median([p["x1"] - p["x0"] for p in posts]))))
    H = int(round(float(np.median([p["foot"] - p["top"] - w for p in posts]))))
    runs = []
    for x in range(posts[0]["x1"] + 4, posts[1]["x0"] - 4):
        col = clean[:, x]
        y = 0
        while y < col.size:
            if col[y]:
                s = y
                while y < col.size and col[y]:
                    y += 1
                if 2 <= y - s <= 9:
                    runs.append(y - s)
            else:
                y += 1
    t = float(np.median(runs)) / 2.0
    return {"w": float(w), "d": float(w), "H": float(H), "th": t, "td": t, "source": rel,
            "feet": [p["foot"] for p in posts], "tops": [p["top"] for p in posts]}


def hull(points):
    pts = sorted(set(map(tuple, points)))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def unit_n(u):
    u = np.array(u, float)
    u = np.array([1.0, 0.0]) if np.linalg.norm(u) < 1e-9 else u / np.linalg.norm(u)
    n = np.array([-u[1], u[0]])
    if n[1] < 0 or (n[1] == 0 and n[0] > 0):
        n = -n
    return u, n


def rail_box(pa, pb, ha, hb, d, th):
    """The eight corners (X, Z, Y) of a bar from plan point pa (bottom at height ha) to pb (hb): d across the line, th high."""
    pa, pb = np.array(pa, float), np.array(pb, float)
    u, n = unit_n(pb - pa)
    pts = []
    for p, hgt in ((pa, ha), (pb, hb)):
        for sn in (-0.5, 0.5):
            for y in (0.0, th):
                q = p + n * (d * sn)
                pts.append((q[0], q[1], hgt + y))
    return pts


def post_box(x, z, u, w, d, H):
    """A post of plan centre (x, z), w along the line u and d across, H high: its eight corners."""
    u, n = unit_n(u)
    pts = []
    for su in (-0.5, 0.5):
        for sn in (-0.5, 0.5):
            for y in (0.0, H):
                q = np.array([x, z]) + u * (w * su) + n * (d * sn)
                pts.append((q[0], q[1], y))
    return pts


def lowest_offset(u, w, d):
    """How far below its plan centre (rows) a post's lowest drawn corner lies: the foot of its front face."""
    u, n = unit_n(u)
    return abs(u[1]) * w / 2 + abs(n[1]) * d / 2


def project(pts):
    return [(x, z - y) for x, z, y in pts]


def raster(poly_list, shape, ss=4):
    h, w = shape
    img = Image.new("L", (w * ss, h * ss), 0)
    dr = ImageDraw.Draw(img)
    for poly in poly_list:
        if len(poly) >= 3:
            dr.polygon([(x * ss, y * ss) for x, y in poly], fill=255)
    big = np.array(img).astype(float) / 255.0
    return big.reshape(h, ss, w, ss).mean((1, 3)) >= 0.5


def place_posts(posts, module):
    """Plan centre z and direction u of ordered posts [{x, f, cut}]: z = foot less the lowest corner's offset."""
    for i, p in enumerate(posts):
        j = i + 1 if i + 1 < len(posts) else i
        k = i - 1 if i > 0 else i
        u = np.array([posts[j]["x"] - posts[k]["x"], posts[j]["f"] - posts[k]["f"]]) if j != k else np.array([1.0, 0.0])
        p["u"] = [float(u[0]), float(u[1])]
        p["z"] = float(p["f"] - lowest_offset(u, module["w"], module["d"]))
    return posts


def fit_rails(posts, module, clean, n_rails):
    """Per bay, the n_rails bars (bottom heights at the two posts) that explain the most of the art."""
    h, w = clean.shape
    H, th, td = int(module["H"]), module["th"], module["td"]
    explained = np.zeros_like(clean)
    bays = []
    for i in range(len(posts) - 1):
        a, b = posts[i], posts[i + 1]
        pa, pb = (a["x"], a["z"]), (b["x"], b["z"])
        rails = []
        for _ in range(n_rails):
            best = None
            for ha in range(0, H - int(th) + 4):
                for hb in range(0, H - int(th) + 4):
                    poly = hull(project(rail_box(pa, pb, ha, hb, td, th)))
                    xs = [q[0] for q in poly]
                    ys = [q[1] for q in poly]
                    x0, x1 = max(int(min(xs)) - 1, 0), min(int(max(xs)) + 2, w)
                    y0, y1 = max(int(min(ys)) - 1, 0), min(int(max(ys)) + 2, h)
                    if x1 <= x0 or y1 <= y0:
                        continue
                    sub = raster([[(q[0] - x0, q[1] - y0) for q in poly]], (y1 - y0, x1 - x0), 2)
                    cov = int((sub & clean[y0:y1, x0:x1] & ~explained[y0:y1, x0:x1]).sum())
                    over = int((sub & ~clean[y0:y1, x0:x1]).sum())
                    score = cov - 2.5 * over
                    if best is None or score > best[0]:
                        best = (score, ha, hb, cov, over)
            score, ha, hb, cov, over = best
            rails.append({"a": ha, "b": hb, "cov": cov, "over": over})
            explained |= raster([hull(project(rail_box(pa, pb, ha, hb, td, th)))], clean.shape)
        rails.sort(key=lambda r: (-(r["a"] + r["b"]), r["a"]))
        bays.append({"a": i, "b": i + 1, "rails": rails})
    return bays


def stubs(posts, bays, module, clean, td):
    """A fence's rails run past its end posts (fence-01's poke out 12 px at both ends): for each rail of the first bay and the
    last, the length past the end post (along the line, 0-30 px) that covers the most art pixels and the fewest transparent."""
    th = module["th"]
    h, w = clean.shape
    for bi, end in ((0, "ea"), (len(bays) - 1, "eb")):
        bay = bays[bi]
        a, b = posts[bay["a"]], posts[bay["b"]]
        post = a if end == "ea" else b
        for r in bay["rails"]:
            r[end] = 0
        if post["cut"] is not None:
            continue
        pa, pb = np.array([a["x"], a["z"]]), np.array([b["x"], b["z"]])
        L = float(np.linalg.norm(pb - pa))
        u = (pb - pa) / L
        for r in bay["rails"]:
            slope = (r["b"] - r["a"]) / L
            tip = pa if end == "ea" else pb
            hgt = r["a"] if end == "ea" else r["b"]
            sign = -1.0 if end == "ea" else 1.0
            best, best_e, acc = 0.0, 0, 0.0
            for e in range(1, 31):
                q0 = tip + sign * u * (e - 1)
                q1 = tip + sign * u * e
                h0 = hgt + sign * slope * (e - 1)
                h1 = hgt + sign * slope * e
                poly = hull(project(rail_box(tuple(q0), tuple(q1), h0, h1, td, th)))
                m = raster([poly], clean.shape, 2)
                acc += int((m & clean).sum()) - 2.5 * int((m & ~clean).sum())
                if acc > best:
                    best, best_e = acc, e
            r[end] = best_e


def lashings(art, module):
    """The rope ties at the joints: [(post index, bottom height)]. One per cluster of rail ends at a post (rail ends within
    4.5 px of height are one joint: the two bays' rails meet a middle post at one tie), at the cluster's mean height."""
    out = []
    for i, p in enumerate(art["posts"]):
        hs = []
        for bay in art["bays"]:
            for r in bay["rails"]:
                if bay["a"] == i:
                    hs.append(float(r["a"]))
                if bay["b"] == i:
                    hs.append(float(r["b"]))
        hs.sort()
        cluster = []
        for hgt in hs + [None]:
            if cluster and (hgt is None or hgt - cluster[-1] > 4.5):
                out.append((i, float(np.mean(cluster))))
                cluster = []
            if hgt is not None:
                cluster.append(hgt)
    return out


def lashing_box(p, hgt, module):
    e = module.get("e", 0.0)
    pts = post_box(p["x"], p["z"], p["u"], module["w"] + 2 * e, module["d"] + 2 * e, module["th"])
    return [(x, z, y + hgt) for x, z, y in pts]


def silhouette(art, module):
    h, w = art["size"][1], art["size"][0]
    polys = [hull(project(post_box(p["x"], p["z"], p["u"], module["w"], module["d"], module["H"]))) for p in art["posts"]]
    for bay in art["bays"]:
        a, b = art["posts"][bay["a"]], art["posts"][bay["b"]]
        pa, pb = np.array([a["x"], a["z"]]), np.array([b["x"], b["z"]])
        L = float(np.linalg.norm(pb - pa))
        u = (pb - pa) / L
        for r in bay["rails"]:
            slope = (r["b"] - r["a"]) / L
            ea, eb = r.get("ea", 0), r.get("eb", 0)
            qa, qb = pa - u * ea, pb + u * eb
            polys.append(hull(project(rail_box(tuple(qa), tuple(qb), r["a"] - slope * ea, r["b"] + slope * eb, art["td"], module["th"]))))
    if module.get("e", 0.0) > 0:
        for i, hgt in lashings(art, module):
            polys.append(hull(project(lashing_box(art["posts"][i], hgt, module))))
    return raster(polys, (h, w))


def iou(art, module, clean):
    sil = silhouette(art, module)
    return float((sil & clean).sum() / max(1, (sil | clean).sum()))


def raw_posts(im, clean, module, style):
    """Ordered [{x, f, cut}]: centre x from the foot rows' extent (a cut post: from its drawn side, one width in)."""
    out = []
    w = module["w"]
    for p in detect_posts(im, clean, style):
        if p["cut"] == "left":
            xc = p["x1"] - w / 2.0
        elif p["cut"] == "right":
            xc = p["x0"] + w / 2.0
        else:
            xc = (p["x0"] + p["x1"]) / 2.0
        out.append({"x": float(xc), "f": float(p["foot"]), "cut": p["cut"]})
    if len(out) >= 2:
        d = np.array([out[-1]["x"] - out[0]["x"], out[-1]["f"] - out[0]["f"]])
        key = "x" if abs(d[0]) >= abs(d[1]) else "f"
        out.sort(key=lambda p: p[key])
    return out


def tie_extent(art, module, clean):
    """How far a rope tie reaches past a post (px each side): the e (0 to 4 in half pixels) that fits the front view's silhouette
    best (its IoU against the art's pixels; a tie is a box a little wider and deeper than its post, as high as a rail)."""
    best = (-1.0, 0.0)
    for e in np.arange(0.0, 4.01, 0.5):
        score = iou(art, dict(module, e=float(e)), clean)
        if score > best[0] + 1e-9:
            best = (score, float(e))
    return best[1]


def fit_style(style):
    module = read_module(style)
    arts, ims = {}, {}
    front = None
    for rel in style["arts"]:
        im, clean = load(rel)
        posts = place_posts(raw_posts(im, clean, module, style), module)
        bays = fit_rails(posts, module, clean, style["rails"])
        stubs(posts, bays, module, clean, module["td"])
        art = {"size": [clean.shape[1], clean.shape[0]], "posts": posts, "bays": bays, "td": module["td"]}
        arts[rel] = art
        ims[rel] = (im, clean)
        if rel.endswith("-%02d.png" % style["front"]):
            front = art
            module["e"] = round(tie_extent(art, module, clean), 2)
    for rel, art in arts.items():
        art["iou"] = round(iou(art, module, ims[rel][1]), 3)
    # The column: its posts from COLUMNS, its rails the front view's bays, in the direction that matches its silhouette better.
    rel = style["column"]
    im, clean = load(rel)
    spec = COLUMNS[rel]
    posts = place_posts([{"x": spec["x"], "f": f, "cut": None} for f in spec["feet"]], module)
    widths = [int(np.count_nonzero(clean[y])) for y in range(clean.shape[0])]
    # A column's rail has no front face to count: the art's width between its knots is its width across the line.
    td = float(np.median([x for x in widths if 5 <= x <= 8])) if not style["any_pixel"] else module["td"]
    # The rails of a column: the lands fence's two bars stand level at the heights the front view's stand at on average (a
    # bay of 36 rows cannot take the front view's 75-px sag without a kink the art does not show); the island's lattice
    # takes the front view's bays as they are (its braces cannot be level).
    if not style["any_pixel"]:
        levels = []
        for k in range(style["rails"]):
            vals = []
            for bay in front["bays"]:
                r = sorted(bay["rails"], key=lambda q: -(q["a"] + q["b"]))[k]
                vals += [r["a"], r["b"]]
            levels.append(int(round(float(np.mean(vals)))))
        bays = [{"a": i, "b": i + 1, "rails": [{"a": lv, "b": lv, "ea": 0, "eb": 0} for lv in levels]} for i in range(len(posts) - 1)]
        turned = "level"
    else:
        bays = []
        for i in range(len(posts) - 1):
            bays.append({"a": i, "b": i + 1, "rails": [dict(r, ea=0, eb=0) for r in front["bays"][i % len(front["bays"])]["rails"]]})
        turned = "front bays"
    best = {"size": [clean.shape[1], clean.shape[0]], "posts": posts, "bays": bays, "td": td, "turned": turned}
    best["iou"] = round(iou(best, module, clean), 3)
    arts[rel] = best
    ims[rel] = (im, clean)
    return module, arts, ims


def overlay(arts, ims, module, path):
    k = 4
    tiles = []
    for rel, art in arts.items():
        im, clean = ims[rel]
        h, w = clean.shape
        sil = silhouette(art, module)
        rgb = np.zeros((h, w, 3), np.uint8)
        rgb[...] = (110, 190, 110)
        rgb[clean] = im[..., :3][clean]
        big = Image.fromarray(rgb).resize((w * k, h * k), Image.NEAREST)
        dr = ImageDraw.Draw(big, "RGBA")
        for y, x in zip(*np.nonzero(clean & ~sil)):
            dr.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1], fill=(255, 0, 255, 150))
        for y, x in zip(*np.nonzero(sil & ~clean)):
            dr.rectangle([x * k, y * k, x * k + k - 1, y * k + k - 1], fill=(0, 255, 255, 150))
        tiles.append(big)
    W = max(t.width for t in tiles)
    Ht = sum(t.height + 6 for t in tiles)
    sheet = Image.new("RGB", (W, Ht), (0, 0, 0))
    y = 0
    for t in tiles:
        sheet.paste(t.convert("RGB"), (0, y))
        y += t.height + 6
    sheet.save(path)


def build() -> dict:
    out = {"modules": {}, "arts": {}}
    for name, style in STYLES.items():
        module, arts, ims = fit_style(style)
        out["modules"][name] = module
        for rel, art in arts.items():
            out["arts"][rel] = dict(art, module=name)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(GAME / "prototype/fences.json"))
    ap.add_argument("--overlay", default="", help="path prefix: <prefix>-lands.png, <prefix>-island.png (magenta: art the model misses; cyan: model over transparent)")
    args = ap.parse_args()
    out = {"modules": {}, "arts": {}}
    for name, style in STYLES.items():
        module, arts, ims = fit_style(style)
        out["modules"][name] = module
        print(name, {k: v for k, v in module.items() if k != "source"})
        for rel, art in arts.items():
            out["arts"][rel] = dict(art, module=name)
            print(" ", rel.split("/")[-1], "iou", art["iou"], art.get("turned", ""), "td", art["td"])
            print("    posts", [(p["x"], p["f"], p["cut"]) for p in art["posts"]])
            for bay in art["bays"]:
                print("    bay", bay["a"], bay["b"], [(r["a"], r["b"], r.get("ea", 0), r.get("eb", 0)) for r in bay["rails"]])
        if args.overlay:
            overlay(arts, ims, module, "%s-%s.png" % (args.overlay, name))
    Path(args.out).write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
