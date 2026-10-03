"""Bridge railings stand and decks take rays (docs/DIRECTION.md, October 2, Dink M3 unit U1).

M2 painted every bridge deck into its screen's ground and stood the near railings (brdge-04, 07, 09, 11) as fixed
cards. Three defects were left: the far railing drawn INSIDE an east-west deck's own sprite (brdge-06, 08, 10) lay flat in
the ground with the planks; a near railing seen along its length was a zero-width sliver; and a deck had no body for rays.
tools/bridge_split.py splits the railing from the planks in the art (game/prototype/bridges.json); game/scripts/bridge_rails.gd
stands it. The north-south decks (brdge-01..03) are NOT split: their side ropes stay painted in the ground as at 46b68a0. The art
draws the rope over the planks' own rows, so a rope that stands at the end posts' height cannot also stay over the deck, and
02 and 03 draw no posts; the first version of this unit stood them (99af3dc) and they hung in the air along the deck, a
metre past its ends. A deck of any kind still takes its ray plate.

Tests (the three Godot parts through tests/fps_bridge_rails_test.gd, as the game builds a scene):
  - the split is reproducible and agrees with an independent reading of the art (PIL only, no tool code): the foot line of
    an east-west deck's far railing is where the planks' top edge is; no railing pixel lies under it; a near railing's posts
    stand on its line; the json holds no entry for a north-south deck.
  - sweep (headless): every bridge sprite of the map, in every story layer, built as a scene builds it. Every deck has a
    body for rays on the ray layer (collision layer 1, no mask); an east-west deck's and a near railing's card stands on
    its foot line (corners read back from the geometry against the art's line and the frame's hotspot), is as tall as the
    rope stands, with its posts as prisms; a north-south deck and the stone bridge hold NO railing (no meshes) and a plate
    that lies where the planks are (the north-south deck's, not over its end posts or the rope's tail).
  - ground (headless): the east-west decks' railing pixels are gone from the painted ground, the planks are not (an
    independent plank rule from the json's line, not from its card); the north-south decks are in the ground exactly as the
    art has them, their side ropes included.
  - render (xvfb, Dummy audio, no Wayland: never the desktop): a downward ray 0.3 m over every deck of 404, 448, 512 and
    693 hits the deck's own body and one 4 m beside it does not; from a camera exactly on a railing's axis the railing's
    own pixels (entity hidden against shown, shadows off) are counted: a zero-width card gives 0, posts that are prisms
    give hundreds, and the same railing seen from 1.5 m to the side is the control that the count counts.
Environment: BRIDGE_RAILS_GAME=<a game dir> runs the Godot parts and reads bridges.json against another build (the
controls in the report: the unmodified build, the first version that stood the north-south ropes (99af3dc), a card facing
south, dark seams taken as rope, no post prisms, the plate on another layer; each one makes a test below fail).
Verdict: written 2026-10-02 (Sonnet 5.5, unit U1 of Dink M3). The whole file takes about a minute.
"""
import json
import math
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("BRIDGE_RAILS_GAME") or ROOT / "game")
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
SCALE = 0.025
godot_needed = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")

EW = {"brdge-06.png", "brdge-08.png", "brdge-10.png"}
NS = {"brdge-01.png", "brdge-02.png", "brdge-03.png"}
NEAR = {"brdge-07.png", "brdge-09.png", "brdge-11.png"}  # brdge-04 is in no screen of the map
STONE = {"landm-04.png", "landm-05.png", "landm-06.png"}


def rails_json():
    return json.loads((GAME / "prototype/bridges.json").read_text())


def entry_of(name):
    return rails_json()["assets/graphics/struct/Bridge/" + name]


def art(name):
    return Image.open(GAME / "assets/graphics/struct/Bridge" / name).convert("RGBA")


def frames():
    """{art path (as sequences.json writes it): (dx, dy)}."""
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    out = {}
    for seq in seqs.values():
        for f in seq.get("frames", []):
            out.setdefault(f["path"], (float(f["dx"]), float(f["dy"])))
    return out


def map_bridges():
    """{(screen, index): art path} for every bridge sprite of the map, from the map's data (as test_fps_bridges)."""
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    out = {}
    for number, screen in world["screens"].items():
        for sprite in screen["sprites"]:
            fr = seqs.get(str(sprite["seq"]), {}).get("frames", [])
            if not 0 < sprite["frame"] <= len(fr) or sprite["type"] == 2:
                continue
            path = fr[sprite["frame"] - 1]["path"]
            low = path.lower()
            name = low.rsplit("/", 1)[-1]
            if "/struct/bridge/" in low or ("/struct/landmark/" in low and name in STONE):
                out[(int(number), int(sprite["index"]))] = path
    return out


# --- the split against an independent reading of the art ---------------------------------------------------------
def warm(px):
    r, g, b, a = px
    return a >= 128 and r - g >= 24 and g - b >= 10


def plank_tops(im):
    """Per column: the first row of the lowest opaque run at least 20 rows long (the planks from their top edge, dark rim
    included, to their underside; a rope or a post above them is a shorter run or, at a post, is left out by the caller)."""
    w, h = im.size
    px = im.load()
    out = []
    for x in range(w):
        top = None
        y = h - 1
        while y >= 0:
            if px[x, y][3] >= 128:
                y1 = y
                while y >= 0 and px[x, y][3] >= 128:
                    y -= 1
                if y1 - y >= 20:
                    top = y + 1
                    break
            else:
                y -= 1
        out.append(top)
    return out


@pytest.mark.parametrize("name", sorted(EW))
def test_an_east_west_decks_foot_line_is_its_planks_top_edge_and_no_railing_pixel_is_under_it(name):
    e = entry_of(name)
    im = art(name)
    tops = plank_tops(im)
    in_post = {x for x0, x1, _y0, _y1 in e["posts"] for x in range(x0 - 1, x1 + 2)}
    cols = [x for x, t in enumerate(tops) if t is not None and x not in in_post]
    assert len(cols) >= 40, "the planks were not found by the independent rule"
    ends = []
    for group in (cols[:16], cols[-16:]):
        x = sum(group) / len(group) + 0.5
        y = sorted(tops[c] for c in group)[len(group) // 2]  # the median: a rope that touches the planks is an outlier
        ends.append((x, y))
        assert abs(e["line"][0] + e["line"][1] * x - y) <= 3.5, (name, x, y, e["line"])
    slope = (ends[1][1] - ends[0][1]) / (ends[1][0] - ends[0][0])
    assert abs(slope - e["line"][1]) <= 0.04, (name, slope, e["line"][1])
    for y, x0, x1 in e["card"]:
        for x in (x0, x1, (x0 + x1) // 2):
            assert y < e["line"][0] + e["line"][1] * (x + 0.5) + 1.5, ("a railing pixel under the foot line", name, y, x)
    assert len(e["posts"]) >= 2 and all(p[3] - p[2] >= 30 for p in e["posts"])


def test_the_north_south_decks_are_not_split_and_every_other_bridge_art_is():
    data = rails_json()
    for name in sorted(NS):
        assert "assets/graphics/struct/Bridge/" + name not in data, ("a north-south deck's rope must stay in the ground", name)
    got = {k.rsplit("/", 1)[-1] for k in data if k != "_meta"}
    assert got == EW | NEAR | {"brdge-04.png"}, got


@pytest.mark.parametrize("name", sorted(NEAR))
def test_a_near_railings_posts_stand_on_its_line_and_everything_in_its_card_is_above_it(name):
    e = entry_of(name)
    im = art(name)
    w, h = im.size
    px = im.load()
    assert len(e["posts"]) >= 2
    for x0, x1, y0, y1 in e["posts"]:
        xc = (x0 + x1 + 1) / 2.0
        foot = max(y for y in range(h) for x in range(max(0, x0 - 8), min(w, x1 + 9)) if px[x, y][3] >= 128) + 1
        assert abs(foot - (e["line"][0] + e["line"][1] * xc)) <= 2.5, (name, xc, foot)
    for y, x0, x1 in e["card"]:
        for x in (x0, x1):
            assert y < e["line"][0] + e["line"][1] * (x + 0.5) + 1.5, ("a pixel under the foot line", name, y, x)


def test_the_committed_split_is_what_the_tool_makes_from_the_art(tmp_path):
    python = "/usr/bin/python3"
    probe = subprocess.run([python, "-c", "import numpy, scipy, PIL"], capture_output=True)
    if probe.returncode != 0:
        pytest.skip("numpy/scipy unavailable to /usr/bin/python3")
    out = tmp_path / "bridges.json"
    result = subprocess.run([python, str(ROOT / "tools/bridge_split.py"), "--out", str(out)], capture_output=True, text=True,
                            cwd=ROOT, timeout=120)
    assert result.returncode == 0, result.stderr[-2000:]
    assert json.loads(out.read_text()) == rails_json()


# --- the Godot parts ---------------------------------------------------------------------------------------------
def _run_godot(args, rendered, tmp_path, timeout):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    command = [GODOT, "--audio-driver", "Dummy", "--path", str(GAME), "--script", str(ROOT / "tests/fps_bridge_rails_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def _floats(text):
    return [float(v) for v in text.split(",")]


def parse_sweep(stdout):
    rails = {}
    cards = {}
    plates = {}
    for line in stdout.splitlines():
        m = re.match(r"PLATE (\d+) (\d+) (\d+) (\S+) x (\S+) to (\S+) z (\S+) to (\S+) top (\S+)", line)
        if m:
            plates[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = [float(m.group(i)) for i in range(5, 10)]
        m = re.match(r"RAIL (\d+) (\d+) (\d+) (\S+) (deck|rail) meshes=(\d+) posts=(\d+) min=(\S+) max=(\S+) body=(\S+)", line)
        if m:
            rails[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = {
                "path": m.group(4), "node": m.group(5), "meshes": int(m.group(6)), "posts": int(m.group(7)),
                "min": _floats(m.group(8)), "max": _floats(m.group(9)), "body": m.group(10)}
        m = re.match(r"CARD (\d+) (\d+) (\d+) (\S+) foot x (\S+) z (\S+) to x (\S+) z (\S+) top (\S+)", line)
        if m:
            cards[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = [float(m.group(i)) for i in range(5, 10)]
    return rails, cards, plates


@pytest.fixture(scope="module")
def swept(tmp_path_factory):
    result = _run_godot(["--sweep"], False, tmp_path_factory.mktemp("sweep"), 600)
    assert "SCRIPT ERROR" not in result.stderr and "Parse Error" not in result.stdout, (result.stderr + result.stdout)[-2500:]
    return parse_sweep(result.stdout)


@godot_needed
def test_every_bridge_sprite_of_the_map_is_built_with_its_railing_and_its_ray_body(swept):
    rails, cards, plates = swept
    expected = map_bridges()
    seen = {(s, i) for (s, i, _v) in rails}
    assert seen == set(expected), (sorted(set(expected) - seen)[:8], sorted(seen - set(expected))[:8])
    fr = frames()
    problems = []
    for (screen, index, vision), r in sorted(rails.items()):
        name = r["path"].rsplit("/", 1)[-1]
        who = (screen, index, vision, name)
        if r["node"] == "deck":
            # a deck is a thin body on the ray layer: layer 1, no mask, one shape
            if not re.fullmatch(r"1/0/[1-9]\d*", r["body"]):
                problems.append((who, "ray body", r["body"]))
        else:
            if not re.fullmatch(r"[12]/0/[1-9]\d*", r["body"]):
                problems.append((who, "the near railing keeps its body on the hardbox", r["body"]))
        if name in STONE:
            if r["meshes"] != 0:
                problems.append((who, "the stone bridge has no railing", r["meshes"]))
            continue
        dx, dy = fr[r["path"]]
        e = entry_of(name) if name not in NS else None
        w = art(name).size[0]
        if name in EW or name in NEAR:
            card = cards.get((screen, index, vision))
            if card is None or r["meshes"] < 2 or r["posts"] != 1:
                problems.append((who, "a card and its posts", r["meshes"], r["posts"], card))
                continue
            xl, zl, xr, zr, top = card
            a, s = e["line"]
            if abs(xl - (-dx * SCALE)) > 0.01 or abs(zl - (a - dy) * SCALE) > 0.02 or abs((zr - zl) - s * w * SCALE) > 0.02:
                problems.append((who, "the card is not on the foot line", (xl, zl, zr - zl), (-dx * SCALE, (a - dy) * SCALE, s * w * SCALE)))
            if abs(r["min"][1]) > 0.001 or not 0.85 <= r["max"][1] <= 1.35:
                problems.append((who, "the railing stands from the deck to the rope's height", r["min"][1], r["max"][1]))
        elif name in NS:
            if r["meshes"] != 0 or r["posts"] != 0:
                problems.append((who, "a north-south deck stands nothing: its rope stays in the ground", r["meshes"], r["posts"]))
            # Its plate is where its planks are: the wood of the plank rows of the art (the end posts above 01's planks and the
            # rope's tail past 02's are not deck), to within the dark rim and the dither (0.08 m).
            im = art(name)
            px = im.load()
            # plank rows: at least 40 percent of the sprite's width is warm brown (01's end posts are brown too, but narrow)
            rows = [y for y in range(im.size[1]) if sum(warm(px[x, y]) for x in range(im.size[0])) >= 0.4 * im.size[0]]
            wood = [(x, y) for y in rows for x in range(im.size[0]) if warm(px[x, y])]
            plate = plates.get((screen, index, vision))
            if plate is None or not wood:
                problems.append((who, "no plate", plate))
                continue
            want = [(min(x for x, _ in wood) - dx) * SCALE, (max(x for x, _ in wood) + 1 - dx) * SCALE,
                    (min(y for _, y in wood) - dy) * SCALE, (max(y for _, y in wood) + 1 - dy) * SCALE]
            have = [plate[0], plate[1], plate[2], plate[3]]
            if any(abs(a - b) > 0.08 for a, b in zip(have, want)) or abs(plate[4] - 0.05) > 0.001:
                problems.append((who, "the plate is not where the planks are", have, want))
        if name in EW:
            plate = plates.get((screen, index, vision))
            a, s_ = e["line"]
            top_z = (min(a, a + s_ * w) - dy) * SCALE
            if plate is None or plate[2] < top_z - 0.03:
                problems.append((who, "the plate reaches over the railing", plate, top_z))
    assert not problems, "%d of %d: %s" % (len(problems), len(rails), problems[:6])
    kinds = {r["path"].rsplit("/", 1)[-1] for r in rails.values()}
    assert kinds >= (EW | NS | NEAR | {"landm-04.png", "landm-05.png"}), kinds


@pytest.fixture(scope="module")
def grounded(tmp_path_factory):
    mask = GAME / "prototype/bridges.json"
    result = _run_godot(["--ground", "--mask=" + str(mask)], False, tmp_path_factory.mktemp("ground"), 600)
    assert "SCRIPT ERROR" not in result.stderr and "Parse Error" not in result.stdout, (result.stderr + result.stdout)[-2500:]
    rows = []
    for line in result.stdout.splitlines():
        m = re.match(r"GROUND (\d+) v(\d) split=(\d+) rail_pixels_in_ground=(\d+) rail_total=(\d+) planks=(\d+) planks_kept=(\d+) "
                     r"whole_decks=(\d+) whole=(\d+) whole_kept=(\d+)", line)
        if m:
            rows.append(tuple(int(m.group(i)) for i in range(1, 11)))
    return rows


@godot_needed
def test_the_east_west_railing_is_gone_from_the_painted_ground_and_the_planks_and_north_south_ropes_are_not(grounded):
    # Measured: the unmodified build holds 100 percent of the east-west decks' railing pixels in the ground (5186 of 5186);
    # the split build 0.3 percent (14: planks of the same colours as a rope pixel); every plank pixel is kept (26930 of 26930)
    # and every north-south deck's opaque pixels are in the ground as the art has them (101609 of 101609 less the stone
    # bridge's, which is not counted here).
    assert len(grounded) == 10 and {r[0] for r in grounded} == {404, 416, 448, 480, 512, 533, 544, 693, 701}, grounded
    left = sum(r[3] for r in grounded)
    total = sum(r[4] for r in grounded)
    assert total > 5000 and left <= 0.05 * total, (left, total)
    split = [r for r in grounded if r[2] > 0]
    assert {r[0] for r in split} == {404, 512, 693}, split
    for screen, vision, n_split, in_ground, rail_total, planks, kept, whole_decks, whole, whole_kept in split:
        assert rail_total > 1500 and in_ground <= 0.15 * rail_total, (screen, vision, in_ground, rail_total)
        assert planks > 7000 and kept >= 0.99 * planks, ("the planks were eaten", screen, vision, kept, planks)
    whole_rows = [r for r in grounded if r[7] > 0]
    assert {r[0] for r in whole_rows} == {416, 448, 480, 512, 533, 544, 701}, whole_rows
    for screen, vision, _s, _g, _t, _p, _k, whole_decks, whole, whole_kept in whole_rows:
        assert whole > 3000 and whole_kept >= 0.99 * whole, ("a north-south rope left the ground", screen, vision, whole_kept, whole)


@pytest.fixture(scope="module")
def rendered(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("render")
    result = _run_godot(["--render"], True, tmp, 900)
    assert result.returncode == 0 and "FPS BRIDGE RAILS PASS" in result.stdout, (result.stdout + result.stderr)[-4000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    rays = {}
    axes = []
    for line in result.stdout.splitlines():
        m = re.match(r"RAY (\d+) decks=(\d+) hit=(\d+) aside_missed=(\d+)", line)
        if m:
            rays[int(m.group(1))] = tuple(int(m.group(i)) for i in range(2, 5))
        m = re.match(r"AXIS (\d+) (\d+) (\S+) on_axis=(\d+) side=(\d+)", line)
        if m:
            axes.append((int(m.group(1)), m.group(3), int(m.group(4)), int(m.group(5))))
    assert not list(tmp.glob("*.png"))
    return rays, axes


@godot_needed
def test_a_downward_ray_onto_a_deck_hits_the_deck_and_one_beside_it_does_not(rendered):
    rays, _axes = rendered
    # Measured: the unmodified build, 0 of 16 decks (the ray goes on to the ground slab, entity 0); the split build 16 of 16.
    assert set(rays) == {404, 448, 512, 693}, rays
    for screen, (decks, hit, missed) in rays.items():
        assert decks >= 2 and hit == decks and missed == decks, (screen, decks, hit, missed)


@godot_needed
def test_a_railing_seen_from_its_own_axis_is_not_a_sliver(rendered):
    _rays, axes = rendered
    names = {a[1] for a in axes}
    assert names >= {"brdge-06.png", "brdge-08.png", "brdge-10.png", "brdge-07.png", "brdge-09.png", "brdge-11.png"}, names
    for screen, name, on_axis, side in axes:
        # Measured: the unmodified near railings 0 pixels on their axes (746 to 3897 from the side); the split build 186 to 752.
        assert side >= 400, ("the counter does not count a railing seen from the side", screen, name, side)
        assert on_axis >= 100, ("a sliver from its own axis", screen, name, on_axis)
