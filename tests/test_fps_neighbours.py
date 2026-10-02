"""Neighbour screens draw their actors (docs/DIRECTION.md, tenth pass).

The game builds the current screen and its 5x5 block of neighbours. A neighbour's scenery was drawn but its
people and animals were skipped, so the continuous world was empty of life beyond the screen you stand on (from
Dink's yard, 439, the pigpen on 407 had no pigs). Editor actors remain where the editor put them; the screen's
startup can add actors, too. The camera redraws their facing every frame (fp_world.gd face_neighbours).

Through tests/fps_neighbours_test.gd:
  - which: the actors the editor places on neighbours of 439 and 406 remain present (the default layer:
    vision 0, upright, by the frame's folder), position for position. The real startup can add actors,
    checked separately by the all-screen survey. 407's five pigs and 374's eight vision-0 ducks remain.
    Headless.
  - which frame: a neighbour pig seen from the south, north, east and west of it shows the frame the
    original drew for its facing as seen from there (the prototype's _face_actors, redone here), so the frame
    follows the camera and is not the one it was loaded with. Headless.
  - the game redraws them: the same, with the game running (its _physics_process, no explicit call), so that
    a pig follows the camera as one walks round it. Headless.
  - pixels: in a rendered view of 439 the pigs are in the picture (hiding one changes pixels) and two renders of
    the same scene are identical (the instrument's noise is 0). Rendered under xvfb with the Dummy audio driver
    and no Wayland: it never opens a window on the desktop.
"""
import json
import math
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")

# The frame folders whose sprites the game draws as actors (fp_world.gd model_key), read from the folder.
ACTOR_FOLDERS = ("/pig/", "/duck/", "/fish/", "/pill/", "/bonca/", "/puddle/", "/dragon/", "/stonegnt/",
                 "/slayers/", "/goblin/", "/people/", "/dink/")
DIRS = {1: (-1, 1), 2: (0, 1), 3: (1, 1), 4: (-1, 0), 6: (1, 0), 7: (-1, -1), 8: (0, -1), 9: (1, -1)}


@pytest.fixture(scope="module")
def data():
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    screens = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    return seqs, screens


def _frame(seqs, seq, frame):
    frames = seqs.get(str(seq), {}).get("frames", [])
    return frames[max(0, min(len(frames) - 1, int(frame) - 1))] if frames else None


def _block(loaded, screens):
    """The neighbours the game builds round an outdoor screen: a 5x5 block, outdoor screens only."""
    column = (loaded - 1) % 32
    out = []
    for dz in range(-2, 3):
        for dx in range(-2, 3):
            n = loaded + dx + dz * 32
            if (dx, dz) == (0, 0) or column + dx < 0 or column + dx >= 32:
                continue
            if str(n) in screens and not screens[str(n)].get("indoor"):
                out.append(n)
    return out


def _expected(loaded, data):
    """{(neighbour, x, y)} the editor's actors on the neighbours of `loaded` at vision 0: upright (a type 0 sprite
    is painted into the ground, a type 2 is invisible), by the folder of the frame they show."""
    seqs, screens = data
    out = set()
    for n in _block(loaded, screens):
        for s in screens[str(n)]["sprites"]:
            d = _frame(seqs, s["seq"], max(1, s["frame"]))
            if d is None or s.get("vision", 0) != 0 or s["type"] != 1:
                continue
            if any(folder in d["path"].lower() for folder in ACTOR_FOLDERS):
                out.add((n, int(s["x"]), int(s["y"])))
    return out


def _run_godot(args, rendered, tmp_path, timeout):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    command = [GODOT, "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests/fps_neighbours_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def _lines(result, tag):
    return [line.split() for line in result.stdout.splitlines() if line.startswith(tag + " ")]


def test_the_neighbours_draw_the_actors_the_map_places_on_them(data, tmp_path):
    seqs, screens = data
    result = _run_godot(["--dump=439,406"], False, tmp_path, 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert "FPS NEIGHBOURS DONE" in result.stdout, result.stdout[-2000:] + result.stderr[-2000:]
    for loaded in (439, 406):
        drawn = [(int(n), int(x), int(y)) for _, l, n, x, y, key, path in _lines(result, "ACTOR") if int(l) == loaded]
        want = _expected(loaded, data)
        assert len(drawn) == len(set(drawn)), "an actor drawn twice on %d" % loaded
        assert want <= set(drawn), "on %d: missing editor actors %s" % (loaded, sorted(want - set(drawn)))
        assert len(want) > 10, (loaded, len(want))  # the instrument could have seen something
    # The sample cases: 407's five pigs from Dink's yard, 374's eight vision-0 ducks from 406.
    pigs = {(407, 250, 225), (407, 289, 302), (407, 397, 211), (407, 411, 269), (407, 331, 245)}
    ducks = {(374, s["x"], s["y"]) for s in screens["374"]["sprites"] if "/duck/" in _frame(seqs, s["seq"], s["frame"])["path"].lower() and s["vision"] == 0}
    assert len(ducks) == 8
    from_439 = {(int(n), int(x), int(y)) for _, l, n, x, y, key, path in _lines(result, "ACTOR") if int(l) == 439}
    from_406 = {(int(n), int(x), int(y)) for _, l, n, x, y, key, path in _lines(result, "ACTOR") if int(l) == 406}
    assert pigs <= from_439
    assert ducks <= from_406
    # These are created by their own screen startup scripts under the pinned
    # private preview seed; neither exists in the editor's actor list.
    assert (376, 78, 319) in from_439  # s1-wiz
    assert (408, 630, 180) in from_439  # s1-gate -> s1-lg
    # The story layers' actors (red and blue villagers, a duck: vision 1) stay out of the editor's layer.
    for s in screens["374"]["sprites"]:
        if s["vision"] == 1:
            assert (374, s["x"], s["y"]) not in from_406, s
    # An actor is an actor.
    assert {key for _, _, _, _, _, key, _ in _lines(result, "ACTOR")} <= {"man", "woman", "wizard", "knight", "pig", "duck", "pillbug", "bonca", "slime", "dragon"}


def _faced(seqs, base, own, camera, actor):
    """The frame path the prototype's _face_actors picks for an actor drawn facing `own` (a Dink direction) seen from `camera`."""
    to_x, to_y = actor[0] - camera[0], actor[1] - camera[1]
    length = math.hypot(to_x, to_y)
    to_x, to_y = to_x / length, to_y / length
    angle = math.atan2(to_x, -to_y)  # the signed angle from (0, -1) to the direction of the actor
    ox, oy = DIRS[own]
    norm = math.hypot(ox, oy)
    ox, oy = ox / norm, oy / norm
    c, s = math.cos(-angle), math.sin(-angle)
    rx, ry = ox * c - oy * s, ox * s + oy * c
    best, best_dot = own, -2.0
    for k, (dx, dy) in DIRS.items():
        if str(base + k) not in seqs:
            continue
        n = math.hypot(dx, dy)
        dot = (dx / n) * rx + (dy / n) * ry
        if dot > best_dot:
            best, best_dot = k, dot
    return seqs[str(base + best)]["frames"][0]["path"]


SPOT = (289.0, -98.0)  # the pig of 407 at (289, 302), in 439's pixels
AROUND = {"south": (SPOT[0], SPOT[1] + 150), "north": (SPOT[0], SPOT[1] - 150),
          "east": (SPOT[0] + 150, SPOT[1]), "west": (SPOT[0] - 150, SPOT[1])}
INSIDE = {"sw": (30.0, 40.0), "south": (289.0, 40.0), "se": (550.0, 40.0)}  # cameras on 439 itself


def _faces_expected(data, cameras):
    seqs, screens = data
    pig = next(s for s in screens["407"]["sprites"] if (s["x"], s["y"]) == (289, 302))
    base, own = pig["base_walk"], pig["seq"] - pig["base_walk"]
    assert (base, own) == (40, 7)  # drawn facing up and left
    want = {label: _faced(seqs, base, own, camera, SPOT) for label, camera in cameras.items()}
    assert len(set(want.values())) == len(cameras)  # different frames: the check can tell them apart
    if "south" in want:
        assert want["south"] == seqs["47"]["frames"][0]["path"]  # from the south: the frame it was drawn in
    return want


@pytest.mark.parametrize("mode,tag,cameras", [("--face", "FACE", AROUND), ("--live", "LIVE", INSIDE)])
def test_a_neighbour_pig_shows_the_frame_drawn_for_its_facing_as_the_camera_sees_it(data, tmp_path, mode, tag, cameras):
    want = _faces_expected(data, cameras)
    result = _run_godot([mode], False, tmp_path, 600)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    shown = {label: path for _, label, path in _lines(result, tag)}
    assert set(shown) == set(cameras), result.stdout[-2000:] + result.stderr[-2000:]
    assert shown == want


def test_the_neighbour_pigs_are_in_the_picture_and_the_instrument_is_still(tmp_path):
    result = _run_godot(["--render"], True, tmp_path, 900)
    assert result.returncode == 0 and "FPS NEIGHBOURS DONE" in result.stdout, (result.stdout + result.stderr)[-4000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert [int(n) for _, n in _lines(result, "NOISE")] == [0]  # two renders of the same scene are identical
    pigs = {(int(x), int(y)): int(changed) for _, x, y, changed in _lines(result, "PIG")}
    assert set(pigs) == {(250, 225), (289, 302), (397, 211), (411, 269), (331, 245)}, pigs
    for place, changed in pigs.items():
        assert changed > 300, (place, changed, pigs)  # hiding the pig changes the picture: it is in it, drawn
