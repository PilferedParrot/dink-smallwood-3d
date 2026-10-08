"""The rail fences stand as solid posts and rails (docs/DIRECTION.md, "Solid fences", Dink M3 solid unit).

The 0.3.0 release drew every fence (lands/Fence fence-01..06, the island's isle-07 and isle-08) as a fixed card of the art:
edge-on from the side, the north-south column (fence-04) a side rail turned 90 degrees, corners and diagonals not joined.
Chris, 2026-10-07: "the pig fence is not drawn correctly". tools/fence_fit.py reads each art's posts and rails from its
pixels (game/prototype/fences.json) and game/scripts/fence_solid.gd builds them, textured by the original camera's
projection, a post shared by two segments as one post.

Tests:
  - the committed json is what the tool makes from the art, and agrees with an independent reading of the art (PIL only, no
    tool code): every post's foot is where its column of pixels ends, its width is what it is drawn.
  - the map's chains agree with the reading of which rows are depth: on screen 731 the island's column starts at the top
    fence's post, on 407 the column's first post stands on the corner piece's.
  - sweep (headless: screens 407, 439 and 441 loaded as the game loads them, the island's 731 at story layer 1): every
    fence entity stands as a solid fence, no card, no entity keeps a Sprite3D; the ray body is on the source's hardbox, as it
    was, and absent on the hard=1 openings; no two posts of a scene stand within 6 px (a chain's shared post is one post); every
    post is the module's size and height; the rails meet posts (the bars' ends not on a post are the free ends and clipped ends).
  - render (xvfb, Dummy audio, no Wayland: never the desktop): 407's north fence seen from its own axis is not a sliver: its own
    pixels (entity hidden against shown, shadows off) are hundreds where a fixed card gives next to none; the same fence seen from
    1.5 m to the side is the control that the count counts.
Environment: FENCES_GAME=<a game dir> runs the Godot parts and reads fences.json against another build (the controls in the
report: the unmodified build fails the sweep and the render).
Verdict: written 2026-10-07 (Sonnet 5.5, solid-fences unit).
"""
import collections
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

import pytest
from PIL import Image
from tool_python import python_with

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("FENCES_GAME") or ROOT / "game")
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
godot_needed = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")
LANDS = "assets/graphics/lands/Fence/fence-%02d.png"
ISLE = "assets/graphics/struct/Island/isle-%02d.png"


def fences():
    return json.loads((GAME / "prototype/fences.json").read_text())


def pixels(rel):
    return Image.open(GAME / rel).convert("RGBA")


def is_dither(px, x, y, w, h):
    """A black pixel with no black 4-neighbour: the shadow dither (the independent statement of the cleaning rule)."""
    def black(xx, yy):
        if not (0 <= xx < w and 0 <= yy < h):
            return False
        r, g, b, a = px[xx, yy]
        return a > 0 and r + g + b < 11
    return black(x, y) and not (black(x - 1, y) or black(x + 1, y) or black(x, y - 1) or black(x, y + 1))


def solid(px, x, y, w, h):
    return 0 <= x < w and 0 <= y < h and px[x, y][3] > 0 and not is_dither(px, x, y, w, h)


def test_every_fence_art_of_the_map_has_a_reading_and_the_reading_is_the_modules():
    data = fences()
    assert sorted(k.rsplit("/", 1)[-1] for k in data["arts"]) == ["fence-%02d.png" % n for n in range(1, 7)] + ["isle-07.png", "isle-08.png"]
    lands, island = data["modules"]["lands"], data["modules"]["island"]
    # The module: fence-01's posts are 4 wide and stand 46-47 rows above the row they end on (cap row 0-2: 42 + 4 + the cap rows)
    assert lands["w"] == 4 and lands["d"] == 4 and 40 <= lands["H"] <= 44 and 2.5 <= lands["th"] <= 3.5
    assert 1.0 <= lands["e"] <= 3.5 and 0.5 <= island["e"] <= 3.0  # the rope ties reach this far past a post (the silhouette's fit)
    assert island["w"] == 3 and 52 <= island["H"] <= 56 and 1 <= island["th"] <= 2
    # The model projected through the original camera covers the art's pixels (IoU of the silhouettes; the columns' bars are the
    # least readable, their posts being hidden behind the bars' top faces).
    for rel, art in data["arts"].items():
        floor = 0.6 if rel.endswith(("fence-04.png", "isle-08.png")) else 0.76
        assert art["iou"] >= floor, (rel, art["iou"])


@pytest.mark.parametrize("rel", sorted(fences()["arts"]) if (GAME / "prototype/fences.json").exists() else [])
def test_every_posts_foot_is_where_its_pixels_end_and_its_width_is_drawn(rel):
    data = fences()
    art = data["arts"][rel]
    module = data["modules"][art["module"]]
    im = pixels(rel)
    w, h = im.size
    px = im.load()
    assert art["size"] == [w, h]
    for i, p in enumerate(art["posts"]):
        x, f = p["x"], int(p["f"])
        if rel.endswith(("fence-04.png", "isle-08.png")):
            continue  # a column's posts are read by hand (fence_fit.COLUMNS): checked below against the map's chains
        xc = int(x)
        # Its last drawn row is the one above the foot, its post columns are drawn there, and below the foot nothing but dither.
        wide = [xx for xx in range(0, w) if any(solid(px, xx, row, w, h) for row in range(f - 4, f)) and abs(xx + 0.5 - x) <= module["w"] + 1.5]
        if p["cut"] is None:
            assert len(wide) >= module["w"] - 1.5, (rel, i, p, wide)
            assert wide and abs((min(wide) + max(wide) + 1) / 2.0 - x) <= 1.0, (rel, i, p, wide)
        else:
            assert wide, (rel, i, p)
        for xx in wide:
            for yy in range(f + 1, min(h, f + 4)):
                assert not solid(px, xx, yy, w, h), ("drawn under the foot", rel, i, xx, yy)
        # Standing: the column above the foot is drawn all the way up to the cap (a post is not a rail's tip).
        col = [yy for yy in range(0, f) if wide and solid(px, wide[len(wide) // 2], yy, w, h)]
        assert len(col) >= module["H"] * 0.8, (rel, i, len(col))


def test_the_committed_reading_is_what_the_tool_makes_from_the_art(tmp_path):
    python = python_with("numpy, PIL", "tools/fence_fit.py")
    out = tmp_path / "fences.json"
    env = {k: v for k, v in os.environ.items()}
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"})
    result = subprocess.run(["nice", "-n", "10", python, str(ROOT / "tools/fence_fit.py"), "--out", str(out)], capture_output=True,
                            text=True, cwd=ROOT, timeout=600, env=env)
    assert result.returncode == 0, result.stderr[-2000:]
    assert json.loads(out.read_text()) == fences()


def _frame(seqs, seq, frame):
    return seqs[str(seq)]["frames"][frame - 1]


def _world():
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    return world, seqs


def _post_feet(screen, index):
    """The world rows and x of a placed fence art's posts: the hotspot's place plus the post's place in the art, from the json."""
    world, seqs = _world()
    s = next(s for s in world[str(screen)]["sprites"] if s["index"] == index)
    fr = _frame(seqs, s["seq"], s["frame"])
    art = fences()["arts"][fr["path"]]
    return [(s["x"] + p["x"] - fr["dx"], s["y"] + p["f"] - fr["dy"]) for p in art["posts"]]


def test_the_maps_chains_stand_on_the_rows_the_reading_takes_for_depth():
    # Island 731: the top fence (isle-07 at 324, 182) and the column isle-08 at (207, 270) start at one post (row 181), and the
    # column's second placement (206... y 344) starts 74 below: its first two posts stand on the first column's last two.
    top = _post_feet(731, 3)
    first = _post_feet(731, 12)
    second = _post_feet(731, 11)
    assert abs(top[0][1] - first[0][1]) <= 2.5 and abs(top[0][0] - first[0][0]) <= 4.5, (top[0], first[0])
    assert abs(first[2][1] - second[0][1]) <= 3 and abs(first[3][1] - second[1][1]) <= 3, (first, second)
    # The pigpen 407: the corner piece (fence-02 at 91, 105) ends on the column's first post (fence-04 at 41, 164).
    corner = _post_feet(407, 46)
    column = _post_feet(407, 1)
    assert min(math.hypot(c[0] - column[0][0], c[1] - column[0][1]) for c in corner) <= 3.5, (corner, column)
    # The column's segments chain every 74 rows: the next one's first post within 4 px of the last one's third.
    chain = [_post_feet(407, i) for i in (1, 47, 48, 57)]
    for a, b in zip(chain, chain[1:]):
        assert abs(a[2][1] - b[0][1]) <= 4 and abs(a[2][0] - b[0][0]) <= 4, (a, b)


# --- the Godot parts ---------------------------------------------------------------------------------------------
def _run_godot(args, rendered, tmp_path, timeout):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache"), "LP_NUM_THREADS": "6", "OMP_NUM_THREADS": "1"})
    command = ["nice", "-n", "10", GODOT, "--audio-driver", "Dummy", "--path", str(GAME), "--script", str(ROOT / "tests/fps_fences_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["nice", "-n", "10", "xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GODOT, "--resolution", "960x540"] + command[4:]
    else:
        command.insert(4, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def parse(stdout):
    fence, posts, bars = [], collections.defaultdict(list), collections.defaultdict(list)
    for line in stdout.splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "FENCE":
            fence.append({"screen": int(p[1]), "index": int(p[2]), "art": p[3], **dict(q.split("=", 1) for q in p[4:])})
        elif p[0] == "POST":
            posts[int(p[1])].append(tuple(float(v) for v in p[2:]))
        elif p[0] == "BAR":
            bars[int(p[1])].append(tuple(float(v) for v in p[2:]))
    return fence, posts, bars


@pytest.fixture(scope="module")
def swept(tmp_path_factory):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    tmp = tmp_path_factory.mktemp("fences-sweep")
    results = []
    for screens, vision in (("407,439,441", 0), ("731", 1)):
        r = _run_godot(["--sweep", "--screens=" + screens, "--vision=%d" % vision], False, tmp, 1800)
        assert "SCRIPT ERROR" not in r.stderr, r.stderr[-2000:]
        assert "FPS FENCES PASS" in r.stdout, (r.stdout + r.stderr)[-3000:]
        results.append(parse(r.stdout))
    return results


@godot_needed
def test_every_fence_entity_stands_solid_with_the_source_body_and_no_card(swept):
    seen = collections.Counter()
    for fence, posts, bars in swept:
        assert fence, "the sweep saw no fence"
        for f in fence:
            seen[f["art"]] += 1
            if f["kind"] == "none":
                # Not stood at all: the map's own seam rule leaves a copy to its partner screen, or it is painted in the ground.
                assert f["why"] in ("seam", "ground"), f
                continue
            assert f["kind"] == "solid", f  # no fixed card, no billboard
            if int(f["type"]) == 2:
                continue  # the original does not draw it
            if int(f["hard"]) != 0:
                assert f["hit"] == "none", f  # a hard=1 piece is an opening: no body, as it was
            else:
                layer, size = f["hit"].split("/")
                sx, sz = (float(v) for v in size.split(","))
                bx, bz = (float(v) for v in f["box"].split(","))
                assert layer == "1" and abs(sx - bx) < 0.01 and abs(sz - bz) < 0.01, f  # on the source's hardbox
    assert {"fence-01.png", "fence-04.png", "fence-02.png", "fence-03.png", "fence-05.png", "fence-06.png", "isle-07.png", "isle-08.png"} <= set(seen), seen


@godot_needed
def test_a_post_the_map_shares_is_one_post_and_every_post_is_the_modules_size(swept):
    data = fences()
    for (fence, posts, bars), module_name in zip(swept, ("lands", "island")):
        for screen, plist in posts.items():
            assert len(plist) >= 10, (screen, len(plist))
            for i, a in enumerate(plist):
                for b in plist[i + 1:]:
                    assert math.hypot(a[0] - b[0], a[1] - b[1]) > 6.0, ("two posts one place", screen, a, b)
            module = data["modules"][module_name]
            for x, z, w, d, h in plist:
                # an upright post of the module's height; its horizontal extent is its width (a turned one's box is a little wider)
                assert abs(h - module["H"]) < 0.5, (screen, h)
                assert module["w"] - 0.2 <= w <= module["w"] * 1.5 + 0.2 and module["w"] - 0.2 <= d <= module["w"] * 1.5 + 0.2, (w, d)


@godot_needed
def test_the_rails_meet_posts_and_a_chain_is_one_line(swept):
    for fence, posts, bars in swept:
        for screen, blist in bars.items():
            plist = posts[screen]
            assert len(blist) >= 20, (screen, len(blist))
            free = 0
            for ax, az, bx, bz in blist:
                for end in ((ax, az), (bx, bz)):
                    if min(math.hypot(end[0] - p[0], end[1] - p[1]) for p in plist) > 6.5:
                        free += 1
            # The ends not on a post are the free ends (a rail runs past the end post, up to 30 px) and the clipped ones.
            assert free <= 0.5 * 2 * len(blist), (screen, free, len(blist))
    # 407's west column (x 42, y 164..387 as placed: world x 13222, rows 4964..): its posts stand every 30-45 rows, none doubled.
    fence, posts, bars = swept[0]
    column = sorted(p[1] for p in posts[407] if abs(p[0] - (13180 + 42)) <= 6 and 4800 + 100 <= p[1] <= 4800 + 345)
    assert len(column) >= 7, column
    gaps = [b - a for a, b in zip(column, column[1:])]
    assert all(28 <= g <= 46 for g in gaps), gaps


@pytest.fixture(scope="module")
def rendered(tmp_path_factory):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    r = _run_godot(["--render"], True, tmp_path_factory.mktemp("fences-render"), 1800)
    return r


@godot_needed
def test_a_fence_seen_from_its_own_axis_is_not_a_sliver(rendered):
    assert "SCRIPT ERROR" not in rendered.stderr, rendered.stderr[-2000:]
    line = next(l for l in rendered.stdout.splitlines() if l.startswith("AXIS "))
    parts = dict(p.split("=") for p in line.split()[3:])
    on_axis, side = int(parts["on_axis"]), int(parts["side"])
    assert side > 800, line  # the control: the count counts a fence that is there
    assert on_axis > 1000, line  # posts and rails with a body show from their own axis (a fixed card shows next to nothing)
