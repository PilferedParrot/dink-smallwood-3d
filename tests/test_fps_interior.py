"""The house interior stands solid (docs/DIRECTION.md, "The interior stands solid").

0.3.0 drew Dink's house as plaster boxes and Blender furniture, and its corridor opened onto an empty sky and plain: the sky of
the outdoor screen the game came from stayed in the (shared) environment, and Godot draws a sky that is set past a doorway even with
a flat background colour. Now the environment keeps no sky inside, the corridor ends in a door of Dink's own door art, the walls are
their sprites' stone, the table a top of revolution on legs, the beds boxes turned on their axes, the hearth a block with a recess and
a chimney, and the pie stands on the table top. Two parts: tools/interior_fit.py's fits (pure Python: what is read from which pixels)
and tests/fps_interior_test.gd (Dink's house as the game loads it, headless).
Blind to: how it looks (that is for the contact sheets, tmp/ of the work), and to screens other than 1.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
SCALE = 0.025


def test_fits_read_each_shape_from_its_own_pixels(tmp_path):
    from tool_python import python_with
    out = tmp_path / "interior.json"
    py = python_with("numpy, scipy, PIL", "interior_fit.py")
    result = subprocess.run([py, str(ROOT / "tools/interior_fit.py"), "--out", str(out)], capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, result.stderr[-2000:]
    fits = json.loads(out.read_text())
    g = "assets/graphics/"
    wall = fits[g + "inside/innwalls/Walls/inn-30.png"]
    assert wall["cap"] == 6 and wall["height"] == 94 and wall["base"] == 100 and wall["stone"][0] == 7
    assert fits[g + "inside/innwalls/Walls/inn-23.png"]["cap"] == 0  # the pier: a top seen end-on, no face
    door = fits[g + "struct/Details/Door/odor1-01.png"]
    assert abs(door["slope"] + 0.486) < 0.01 and 52 < door["height"] < 54 and door["rms"] < 0.5
    table = fits[g + "inside/details/table-09.png"]
    assert 0.5 < table["k"] < 0.65 and 31 < table["top"]["r"] < 33 and table["rms_top"] < 0.5 and table["rms_under"] < 1.0
    assert 3 < table["top"]["height"] - table["under"]["height"] < 6          # the plate's thickness
    assert len(table["legs"]) == 4 and sum(1 for leg in table["legs"] if leg["seen"]) == 3  # three seen, one its reflection
    bed = fits[g + "inside/details/inacc-03.png"]
    assert bed["top_back_error"] < 1.0 and bed["consistency"] < 1.0 and 29 < bed["height"] < 33  # the hull is a box
    hearth = fits[g + "inside/details/inacc-05.png"]
    assert len(hearth["above"]) == 1 and hearth["body"]["split"] == 58 and "opening" in hearth
    shelf = fits[g + "inside/details/inacc-01.png"]
    assert shelf["body"]["split"] == shelf["body"]["rows"][0] and not shelf["above"] and not shelf["legs"]  # a plain face
    post = fits[g + "inside/details/table-10.png"]
    assert post["kind"] == "post" and post["shaft"] == 8 and post["footing"] == 17 and post["runs"][-1][1] == 106  # not a chair
    committed = json.loads((ROOT / "game/data/interior.json").read_text())
    assert committed == fits  # the file is the tool's output


@pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")
def test_dinks_house_stands_solid_with_no_sky_and_a_door(tmp_path):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    project = os.environ.get("FPS_INTERIOR_GAME") or str(ROOT / "game")
    cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", project, "--script", str(ROOT / "tests/fps_interior_test.gd")]
    result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=900, check=False)
    assert "SCRIPT ERROR" not in result.stderr + result.stdout, (result.stdout + result.stderr)[-3000:]
    lines = {}
    for line in result.stdout.splitlines():
        if line.startswith("INT "):
            parts = line.split()
            lines.setdefault(parts[1], []).append(parts[2:])
    assert "FPS INTERIOR DONE" in result.stdout, result.stdout[-3000:]
    # no sky inside, and a flat background
    assert lines["sky"][0][0] == "true", lines["sky"]
    # every wall piece is built from its sprite, stands as high as the room, and the type 2 hardness is shown as well
    assert len(lines["wall"]) >= 17, lines["wall"]
    room = float(lines["room"][0][0])
    assert abs(room - 94 * SCALE) < 0.01
    for wid, solid, height, visible in lines["wall"]:
        assert solid == "true" and abs(float(height) - room) < 0.01 and visible == "true", (wid, solid, height, visible)
    # the plaster is the tone the original shows, not its dither magnified: bilinear (Godot 3 = LINEAR_WITH_MIPMAPS; 0.3.0 drew the
    # art with nearest filtering, 2), the mean step between neighbouring texels of the stone under 4 of 255 (the art's own: 9.4)
    filt, step, rowstep = lines["plaster"][0]
    assert int(filt) == 3 and float(step) < 4.0, lines["plaster"]
    # no stripe per pixel row: restoring each row's own mean put the dither's row noise back (2.55 levels between
    # neighbouring rows' means in rc2 eb739f9, drawn as streaks across the walls; 0.41 with the smoothed trend)
    assert float(rowstep) < 1.0, lines["plaster"]
    # the exit: a door as wide as the corridor between the jambs (308 to 339), Dink's door art (24 x 52.8 px) kept in proportion
    # at that width (68.2 px = 1.70 m, above the 1.65 m eye; the art's own 52.8 px read as a slot), at the screen's edge
    door = lines["door"][0]
    assert door[0] != "none", lines["door"]
    assert abs(float(door[0]) - 31 * SCALE) < 0.01 and abs(float(door[1]) - 31 * 52.79 / 24 * SCALE) < 0.02
    assert abs(float(door[2]) - (400 - 200) * SCALE) < 0.01
    # the table: a top of the sprite's radius (32 px), on legs, 0.8 m high; the pie stands on it
    solid, wx, wy, wz = lines["table"][0]
    assert solid == "true" and abs(float(wx) - 64.3 * SCALE) < 0.05 and 0.75 < float(wy) < 0.85
    assert abs(float(wz) - float(wx)) < 0.05, (wx, wz)  # a round table is as deep as it is wide (0.3.0: its depth was the picture's, x0.57)
    top = float(lines["tabletop"][0][0])
    assert abs(float(lines["pie"][0][0]) - top) < 0.005 and top > 0.7, (lines["pie"], top)
    # two beds, each a box of the sprite's size (121 px wide, 31 px high)
    assert len(lines["bed"]) == 2
    for solid, bx, by, bz in lines["bed"]:
        assert solid == "true" and abs(float(bx) - 121 * SCALE) < 0.06 and abs(float(by) - 31 * SCALE) < 0.03, (bx, by)
    # the hearth reaches the ceiling with its chimney
    # its back (where the chimney's face stands) is in front of the wall's face, not in its plane: coplanar, the plaster drew
    # over the chimney (rc2 before the lead's fix)
    back, wall = (float(v) for v in lines["hearthback"][0])
    assert wall > 0 and back >= wall + 0.99, lines["hearthback"]
    solid, hy, hx, hz = lines["hearth"][0]
    assert solid == "true" and abs(float(hy) - room) < 0.15, lines["hearth"]
    # the fire stands inside the firebox, at its back (the hearth's front plane is 1 px south of its hotspot; the recess is
    # deep as the wall behind it allows, 20 px), a fixed card there: 0.3.0 left it a camera-facing card 7 px behind the hearth's front, proud of the recess
    fire_z, fire_fixed = lines["fire"][0]
    depth_in = float(lines["hearthz"][0][0]) + SCALE - float(fire_z)
    assert fire_fixed == "true" and depth_in > 0.45, (lines["fire"], lines["hearthz"])
