"""Bridges are decks on the water and railings, not loose planks (docs/DIRECTION.md, tenth pass, unit E).

The game built every bridge sprite from one Blender model sized to its hardbox: a row of loose flat planks floating
over the water with water between them. The art draws two other things. A DECK (struct/Bridge brdge-01, 02, 03, 05,
06, 08, 10 and the stone bridge landm-04..06 of struct/Landmark) lies on the water: in the original's projection a deck
at water level is drawn at its own place on the ground, as a background sprite is, so it is painted into the screen's
ground. A RAILING (brdge-04, 07, 09, 11: the near rope railing of an east-west bridge is a sprite of its own, drawn
after the deck, in front of it) stands as a fixed card in the plane it was drawn in.

Two tests, both through tests/fps_bridges_test.gd:
  - classification: every sprite of the map whose art is a bridge, built as a scene builds it, in every story layer,
    is exactly what an independent reading of the art's file says (written here from world.json and sequences.json,
    not from the game's model keys): a deck is flagged painted-into-the-ground, is among its screen's background
    sprites and has no model of its own; a railing is a fixed card and is not painted. Headless. It is red on the code
    that built the Blender model (every deck "model", nothing painted), and on each plausible wrong fix tried:
    every bridge sprite painted (the railings lie flat), every bridge sprite a fixed card (the decks stand up as
    walls, as the prototype draws them), the railings painted and the decks cards (the two swapped).
  - pixels: from 448's bridge, looking along it, a strip down the middle of the picture is deck from the near edge to
    the island, with no row of water in it. Rendered under xvfb with the Dummy audio driver and no Wayland: it never
    opens a window on the desktop. Red on the Blender planks (a quarter of the strip's rows are water between the planks)
    and on the deck left out of the ground and on the decks as standing cards.
"""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")


def expected_part(path: str):
    """The independent rule, read from the art's own folder and file name: "deck", "rail", or None (not bridge art)."""
    p = path.lower()
    name = p.rsplit("/", 1)[-1]
    if "/struct/bridge/" in p:
        return "rail" if int(re.search(r"(\d+)", name).group(1)) in (4, 7, 9, 11) else "deck"
    if "/struct/landmark/" in p and int(re.search(r"(\d+)", name).group(1)) in (4, 5, 6):
        return "deck"  # the stone bridge
    return None


def map_bridges():
    """{(screen, index): (path, part)} for every bridge sprite of the map, from the map's data."""
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    out = {}
    for number, screen in world["screens"].items():
        for sprite in screen["sprites"]:
            frames = seqs.get(str(sprite["seq"]), {}).get("frames", [])
            if not 0 < sprite["frame"] <= len(frames):
                continue
            path = frames[sprite["frame"] - 1]["path"]
            part = expected_part(path)
            if part and sprite["type"] != 2:
                out[(int(number), int(sprite["index"]))] = (path, part)
    return out


def _run_godot(args, rendered, tmp_path, timeout, project=None):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    project = Path(project) if project else ROOT
    command = [GODOT, "--audio-driver", "Dummy", "--path", str(project / "game"), "--script", str(ROOT / "tests/fps_bridges_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def parse_sweep(stdout):
    rows = {}
    for line in stdout.splitlines():
        m = re.match(r"BRIDGE (\d+) (\d+) (\d+) (\S+) painted=(\d) in_ground=(\d) card=(\w+)", line)
        if m:
            screen, index, vision = int(m.group(1)), int(m.group(2)), int(m.group(3))
            rows[(screen, index, vision)] = {"path": m.group(4), "painted": m.group(5) == "1", "in_ground": m.group(6) == "1",
                                             "card": m.group(7)}
    return rows


def wrong_ones(rows):
    wrong = []
    for (screen, index, vision), r in rows.items():
        part = expected_part(r["path"])
        if part == "deck":
            ok = r["painted"] and r["in_ground"] and r["card"] == "none"
        else:
            ok = not r["painted"] and not r["in_ground"] and r["card"] == "fixed"
        if not ok:
            wrong.append((screen, index, vision, r["path"].rsplit("/", 1)[-1], part, r))
    return wrong


@pytest.fixture(scope="module")
def swept(tmp_path_factory):
    result = _run_godot(["--sweep"], False, tmp_path_factory.mktemp("sweep"), 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    return parse_sweep(result.stdout)


def test_every_bridge_deck_of_the_map_is_painted_into_the_ground_and_every_railing_is_a_fixed_card(swept):
    expected = map_bridges()
    # The instrument saw every bridge sprite of the map (by screen and index), and only those.
    seen = {(s, i) for (s, i, _v) in swept}
    assert seen == set(expected), (sorted(set(expected) - seen)[:10], sorted(seen - set(expected))[:10])
    parts = [part for _path, part in expected.values()]
    assert parts.count("deck") >= 25 and parts.count("rail") >= 6, (parts.count("deck"), parts.count("rail"))
    wrong = wrong_ones(swept)
    summary = {}
    for screen, _i, _v, name, part, r in wrong:
        key = (name, part, "painted" if r["painted"] else "not painted", r["card"])
        summary[key] = summary.get(key, 0) + 1
    assert not wrong, "%d of %d bridge sprites are not what their art is: %s" % (len(wrong), len(swept), summary)
    # The cases the lead measured: 404's, 448's and 512's bridges, both kinds.
    got = {(s, i): expected_part(r["path"]) for (s, i, _v), r in swept.items()}
    for screen in (404, 448, 512):
        assert "deck" in {p for (s, _i), p in got.items() if s == screen}, screen
    for screen in (404, 512, 693):
        assert "rail" in {p for (s, _i), p in got.items() if s == screen}, screen


def test_the_deck_of_448s_bridge_is_continuous_down_the_middle_of_the_picture(tmp_path):
    result = _run_godot(["--render"], True, tmp_path, 900)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "FPS BRIDGES PASS" in result.stdout, out[-6000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    m = re.search(r"PIXELS size (\d+)x(\d+) strip (\d+)x(\d+) water ([\d.]+) deck ([\d.]+) water_rows (\d+) of (\d+)", result.stdout)
    assert m, out[-3000:]
    water, deck, water_rows = float(m.group(5)), float(m.group(6)), int(m.group(7))
    # Measured (xvfb, llvmpipe; two renders of one build are identical): the deck painted into the ground, water 0.0003,
    # deck 0.61, no row of water; the Blender planks, water 0.28, deck 0.40, 62 of 232 rows water; the plausible wrong
    # fixes: the deck not in the ground (a deck was its own upright twin), water 0.51, deck 0.17, 117 rows; every
    # bridge sprite a fixed card (the decks stand up as walls), water 0.07, deck 0.74, 15 rows.
    assert water_rows == 0, "water shows between the planks: %d rows of the strip are mostly water (%s)" % (water_rows, m.group(0))
    assert water < 0.08, m.group(0)
    assert deck > 0.45, m.group(0)
    assert not list(tmp_path.glob("*.png"))
