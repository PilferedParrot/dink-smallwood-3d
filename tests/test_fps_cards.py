"""Upright sprites are billboards, structures are fixed cards (docs/DIRECTION.md, tenth pass).

A card keeps the orientation it was drawn in only if it is a structure: a fence, a wall or a sign. Fitted castle
pieces, the two castle doors and island huts have 3D models and are outside the card sweep. A tree, bush, rock,
well, statue, prop or actor is a Y-axis billboard whatever its width: the art's
width includes its shadow dither, so every tree is over 100 px, and every tree was an edge-on sliver from the side.
A billboard casts its silhouette from a shadow-only twin turned to the sun.

Three tests, all through tests/fps_cards_test.gd:
  - classification: every sprite of every outdoor screen, built as a scene builds it, is a fixed card exactly when
    its art is a structure, as an independent reading of the art's path says (written here, from the art's
    folders and file names, not from the game's model keys). Headless. The wide-art rule it replaces (a card over
    100 px keeps its orientation: every tree) fails it, and so does the plausible wrong fix of that rule, the
    width of the art without its dither (tree-02, 03 and 04 are still over 100 px wide without it).
  - loaded scenes: the same, for scenes loaded as the game loads them, and every billboard's shadow twin is a
    plain shadow-only card whose face is on the sun.
  - pixels: a tree-04 seen from the east, west and north is as wide as seen from the south, and a tree still
    casts a shadow on the ground. Rendered under xvfb with the Dummy audio driver and no Wayland: it never opens
    a window on the desktop.
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

# Scenes loaded for the second test: trees and bushes (376, 251), the pigpen's yard (439, 409, 441, 469: their fences are solid
# now, tests/test_fps_fences.py, so the cards left are barrels, crates and grass), castle walls (402), the well and the save
# machine (408 has the machine), a signpost (376), the island's huts and spears (764, 731).
SCENES = [376, 251, 439, 402, 408, 764, 731, 409, 441, 469]


def is_structure(path: str) -> bool:
    """The independent rule, read from the art's own folders and file names."""
    p = path.lower()
    name = p.rsplit("/", 1)[-1]
    if "/struct/castle/" in p:  # the lands' rail fences and the island's (isle-07, 08) are solid posts and rails: no card
        return True
    if "innwalls" in p or "stnwalls" in p:  # walls
        return True
    if "/struct/island/" in p:  # isle-01..06 round huts, 07..12 rail fences; 13..18 spears and the torches stand up
        m = re.match(r"isle-(\d+)", name)
        # isle-07 and isle-08 are solid posts and rails, never a card (fence_solid.gd); isle-09..12 (rail fences the map places
        # nowhere) would keep a fixed card, as would the huts
        return bool(m) and (1 <= int(m.group(1)) <= 6 or 9 <= int(m.group(1)) <= 12)
    if "/struct/bridge/" in p:  # brdge-04, 07, 09, 11 the rope railings stand as cards; the rest are decks, painted into the ground
        return int(re.search(r"(\d+)", name).group(1)) in (4, 7, 9, 11)
    if "/struct/landmark/" in p:  # landm-01..03 the well, 04..06 the stone bridge (a deck, painted), 07..12 signs
        return int(re.search(r"(\d+)", name).group(1)) >= 7
    if "/paper/" in p or "/inner/" in p:  # signs
        return True
    return False


def _run_godot(args, rendered, tmp_path, timeout, project=None):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    project = Path(project) if project else ROOT
    command = [GODOT, "--audio-driver", "Dummy", "--path", str(project / "game"), "--script", str(ROOT / "tests/fps_cards_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def _cards(stdout):
    cards = []
    for line in stdout.splitlines():
        if line.startswith("CARD "):
            parts = line.split()
            cards.append({"screen": int(parts[1]), "x": int(parts[2]), "y": int(parts[3]), "key": parts[4], "mode": parts[5],
                          "path": parts[6], "twin": parts[7] if len(parts) > 7 else None})
    return cards


def _wrong(cards):
    return [c for c in cards if (c["mode"] == "fixed") != is_structure(c["path"])]


@pytest.fixture(scope="module")
def swept(tmp_path_factory):
    result = _run_godot(["--classify"], False, tmp_path_factory.mktemp("classify"), 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    return _cards(result.stdout)


def test_every_card_of_the_map_is_a_billboard_unless_its_art_is_a_structure(swept):
    wrong = _wrong(swept)
    summary = {}
    for c in wrong:
        k = (c["key"], c["mode"], c["path"].rsplit("/", 2)[-2])
        summary[k] = summary.get(k, 0) + 1
    assert not wrong, "%d of %d cards are misclassified: %s" % (len(wrong), len(swept), summary)
    # The instrument could see both kinds, and the cases the lead measured: every oak and pine, the shrubs, the well.
    keys = {(c["key"], c["mode"]) for c in swept}
    for kind in [("oak_tree", "billboard"), ("pine_tree", "billboard"), ("dead_tree", "billboard"), ("bush", "billboard"),
                 ("rock", "billboard"), ("well", "billboard"), ("save", "billboard"), ("knight", "billboard"), ("dragon", "billboard"),
                 ("wall", "fixed"), ("sign", "fixed")]:
        assert kind in keys, kind
    # The island's huts are no cards any more: all 16 stand in 3D (tests/test_fps_huts.py), so no ("hut", "fixed") is swept.
    assert ("hut", "fixed") not in keys
    assert sum(1 for c in swept if c["key"] == "oak_tree") > 500
    # The statues (struct/Stone/mdink: key "tower") stand upright; the fitted castle walls are no cards.
    assert any("/stone/mdink/" in c["path"].lower() and c["mode"] == "billboard" for c in swept)
    # Both placed castle doors are fitted surfaces now (tests/test_fps_doors.py), so neither is a card.
    assert not any(c["path"].lower().endswith(("cdoor-01.png", "cdoor-06.png")) for c in swept)
    # The island: spears and torches standing up (the huts, isle-01..06, are 3D pieces: no cards at all; the rail fences, isle-07
    # and isle-08, are solid posts and rails: tests/test_fps_fences.py).
    island = {(c["path"].rsplit("/", 1)[-1].lower(), c["mode"]) for c in swept if "/island/" in c["path"].lower()}
    assert ("isle-18.png", "billboard") in island
    assert not any(name in ("isle-%02d.png" % n for n in range(1, 7)) for name, mode in island)
    assert not any(name in ("isle-07.png", "isle-08.png") for name, mode in island)
    # The lands' rail fences are solid too: no card of any of them.
    assert not any("/lands/fence/" in c["path"].lower() for c in swept)
    assert ("torch-01.png", "billboard") in island


# What the original draws without a shadow (fp_world.gd SHADOWLESS: fire, effects, coins, grass, seeds, holes) casts none.
SHADOWLESS = {"flame", "effect", "feed_grains", "burn_scar", "hole", "coin", "grass"}


def test_loaded_scenes_agree_and_every_billboard_has_a_twin_on_the_sun(tmp_path):
    result = _run_godot(["--dump=" + ",".join(str(n) for n in SCENES)], False, tmp_path, 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    cards = _cards(result.stdout)
    assert len(cards) > 60, result.stdout[-2000:]
    wrong = _wrong(cards)
    assert not wrong, wrong[:10]
    billboards = [c for c in cards if c["mode"] == "billboard"]
    fixed = [c for c in cards if c["mode"] == "fixed"]
    assert billboards and fixed
    shadowless = [c for c in billboards if c["key"] in SHADOWLESS]
    assert shadowless, "the scenes hold no shadowless sprite: the check below could not fail"
    assert all(c["twin"] == "twin=none" for c in shadowless), [c for c in shadowless if c["twin"] != "twin=none"][:5]
    for c in billboards:
        if c["key"] in SHADOWLESS: continue
        angle, _, state = c["twin"].replace("twin=", "").partition(",")
        assert state == "ok", c
        assert abs(float(angle)) < 0.01, c  # the twin's face is on the sun (degrees, horizontally)
    # A fixed card casts its own shadow: it has no twin unless the depth rule shifted it.
    assert all(c["twin"] in ("twin=none",) or c["key"] in ("wall", "tower") for c in fixed), [c for c in fixed if c["twin"] != "twin=none"][:5]


def test_a_tree_stands_whole_from_every_side_and_still_casts_a_shadow(tmp_path):
    result = _run_godot(["--render"], True, tmp_path, 900)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "FPS CARDS PASS" in result.stdout, out[-6000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert not list(tmp_path.glob("*.png"))
