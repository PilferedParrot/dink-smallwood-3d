"""One object per seam, and stacked art stands at its parts' feet (docs/DIRECTION.md, M3; fp_world.seam_parts).

The original draws each screen alone, clipped to its playfield, so the map stitches an object across a seam with a copy
in each screen, and tree-09/10 draw two half-trees one above the other (the upper one standing further north). The game
drew every copy whole and stood each strip as one card: the far tree floated, seam trees stood twice.

Two tests, through tests/fps_seams_test.gd, headless:
  - classification: every billboard part of every outdoor screen is built exactly when the independent reading
    (tools/seam_objects.py, written from the art's pixels and the map, not from the game) says it is.
  - scenes: on 376 and 251, loaded as the game loads them, no tree part floats or sinks (its lowest drawn pixel is on
    the ground within 2 px), no two drawn parts of one art have their feet within 3 px, and a seam
    copy at the 5x5 block's edge whose partner screen is not built still stands (251: 314's tree-09).
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest
from tool_python import python_with

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")


def _godot(args, tmp_path, timeout=900):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    r = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--script",
                        str(ROOT / "tests/fps_seams_test.gd"), "--"] + args, cwd=ROOT, env=env, capture_output=True, text=True,
                       timeout=timeout, check=False)
    assert "SCRIPT ERROR" not in r.stderr and "FPS SEAMS DONE" in r.stdout, (r.stdout[-2000:], r.stderr[-3000:])
    return r.stdout


def _reader(tmp_path):
    out = tmp_path / "seams.json"
    r = subprocess.run([python_with("numpy, PIL", "tools/seam_objects.py"), str(ROOT / "tools/seam_objects.py"), "--json", str(out)],
                       capture_output=True, text=True, timeout=600, check=False)
    assert r.returncode == 0, r.stderr[-3000:]
    return {(h[0], h[1], h[2]) for h in json.loads(out.read_text())["hidden"]}


def test_every_billboard_part_is_built_as_the_independent_reading_says(tmp_path):
    hidden = _reader(tmp_path)
    lines = [l.split() for l in _godot(["--classify"], tmp_path).splitlines() if l.startswith("SEAM ")]
    parts = {(int(p[1]), int(p[2]), int(p[3])): (p[4] == "1", p[5]) for p in lines}
    assert len(parts) > 2500, len(parts)
    wrong = [(k, v[1]) for k, v in parts.items() if v[0] == (k in hidden)]
    assert not wrong, "%d of %d parts disagree with the reading, e.g. %s" % (len(wrong), len(parts), wrong[:8])
    # The instrument saw what the pre-registration names: stacked parts, seam copies, never-drawn placements.
    assert sum(1 for k, v in parts.items() if k[2] == 1) >= 100  # second parts of tree-09/10
    assert sum(1 for k in parts if k in hidden) >= 300
    assert parts[(376, 3, 0)][0] is False and parts[(376, 3, 1)][0] is True  # 376's tree-09: the far tree is 344's
    assert parts[(251, 2, 0)][0] is False and parts[(283, 5, 1)][0] is True  # 251's strip over its edge: 283's tree


@pytest.mark.parametrize("screen", [376, 251, 319, 451])
def test_trees_stand_on_the_ground_once(tmp_path, screen):
    drawn = [l.split() for l in _godot(["--scene=%d" % screen], tmp_path).splitlines() if l.startswith("DRAWN ")]
    assert len(drawn) >= (1 if screen == 451 else 6), len(drawn)  # 451 sees one tree: its tree-04 (419 places a copy 2 px off)
    floating = [d for d in drawn if abs(float(d[4])) > 2.0 and ("tree-09" in d[5] or "tree-10" in d[5])]
    assert not floating, "%d tree-09/10 parts off the ground: %s" % (len(floating), floating[:6])
    # One object per world point: no two drawn parts of one art with their feet within 3 px on both axes (two such
    # copies z-fight, the winner following the draw order: 451's tree-04 and 419's, 2 px apart; amendment 2).
    doubled = [(a, b) for i, a in enumerate(drawn) for b in drawn[i + 1:]
               if a[5] == b[5] and abs(float(a[2]) - float(b[2])) <= 3 and abs(float(a[3]) - float(b[3])) <= 3]
    assert not doubled, "%d pairs of one art within 3 px: %s" % (len(doubled), doubled[:4])
    # At the block's edge a copy whose partner screen is not built stays: 314's lower tree-09 (its foot in 346, outside
    # 251's 5x5 block) stands where 346's copy will stand when the player walks south.
    # 319's tree-02 is placed on 319 (x 662) and on 320 (x 62), one world point; 320 places it twice, type 0 (painted
    # into the ground) and type 1 (standing). 319's copy is dropped, so from 319 the tree is 320's standing copy.
    if screen == 319:
        assert any(d[5].endswith("tree-02.png") and abs(float(d[2]) - 18642) <= 2 and abs(float(d[3]) - 3910) <= 2
                   for d in drawn), "320's tree-02 does not stand in 319's scene"
    if screen == 251:
        assert any(d[5].endswith("tree-09.png#200-377") and abs(float(d[2]) - 15234) <= 2 and abs(float(d[3]) - 4093) <= 2
                   for d in drawn), "314's tree-09 at the block's edge is missing"
