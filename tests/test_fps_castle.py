"""The castle's walls, towers, gatehouse and corner stand in 3D (docs/DIRECTION.md, tenth pass, castle; M3).

A castle sprite is a picture of a wall or a tower taken by the original camera. tools/facade_fit.py castle_fit
recovers each fitted frame (struct/Castle castl-01..04, 06..09, and in M3 the gatehouse 05 and the corner 12) from its
pixels, and the game builds it where it drew a fixed card facing south: a tall sliver from the side. Through
tests/fps_castle_test.gd:
  - classification: every castle sprite of every screen that has one is a fitted 3D piece exactly when its frame is
    one of those ten (an independent reading of the file name), and one placed twice at a spot is built once. Headless.
  - pixels (rendered under xvfb with the Dummy audio driver and no Wayland: never the desktop): through the original
    camera each fitted piece, alone in its scene, reproduces its sprite (mean |RGB| difference over the sprite's own
    pixels), and reads clearly worse with its geometry spoiled (the control: a wall's base line 8 px off, a tower's
    centre 10 px off); and each wall, seen from above, is as deep as the fit's walkway (a card has no depth).
"""
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

FITTED = {1, 2, 3, 4, 5, 6, 7, 8, 9, 12}


def _run_godot(args, rendered, tmp_path, timeout):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    project = os.environ.get("FPS_CASTLE_GAME") or str(ROOT / "game")  # a copy of the game to run the test against (the controls)
    command = [GODOT, "--audio-driver", "Dummy", "--path", project, "--script", str(ROOT / "tests/fps_castle_test.gd"), "--"] + args
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + command[:1] + ["--resolution", "960x540"] + command[1:]
    else:
        command.insert(1, "--headless")
    return subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)


def _frame(path: str):
    m = re.search(r"castl-(\d+)\.png$", path)
    return int(m.group(1)) if m else None


def test_every_fitted_castle_frame_is_a_3d_piece_and_nothing_else_is(tmp_path):
    result = _run_godot(["--classify"], False, tmp_path, 900)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    rows = []
    for line in result.stdout.splitlines():
        if line.startswith("CASTLE "):
            _, screen, path, kind, x, y = line.split()
            rows.append((int(screen), path, kind, int(x), int(y)))
    assert len(rows) > 60, result.stdout[-2000:]
    for screen, path, kind, x, y in rows:
        if _frame(path) in FITTED:
            assert kind in ("fitted", "dup"), (screen, path, kind)
        else:
            assert kind == "card", (screen, path, kind)
    # A piece placed twice at one spot (402 has castl-07 at (-127, 218) twice) is built once; and never zero times.
    spots = {}
    for screen, path, kind, x, y in rows:
        if kind in ("fitted", "dup"):
            spots.setdefault((screen, path, x, y), []).append(kind)
    assert all(kinds.count("fitted") == 1 for kinds in spots.values()), {k: v for k, v in spots.items() if v.count("fitted") != 1}
    assert any(len(kinds) > 1 for kinds in spots.values()), "no double placement in the sweep: the check could not fail"
    assert sum(1 for r in rows if r[2] == "fitted") > 40
    # The instrument saw both kinds: the gatehouse (05) and the corner (12) are 3D pieces now; the doors stay cards.
    assert any(r[2] == "card" for r in rows)
    for frame in (5, 12):
        assert any(r[2] in ("fitted", "dup") and _frame(r[1]) == frame for r in rows), frame


def _lines(stdout, tag):
    return [line.split() for line in stdout.splitlines() if line.startswith("CASTLE " + tag + " ")]


def test_each_fitted_piece_reproduces_its_sprite_through_the_original_camera_and_a_wall_is_deep(tmp_path):
    result = _run_godot(["--render"], True, tmp_path, 1500)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "FPS CASTLE PASS" in result.stdout, out[-6000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    fitted = {p[2]: (float(p[3]), float(p[4])) for p in _lines(result.stdout, "err")}
    spoiled = {p[2]: (float(p[3]), float(p[4])) for p in _lines(result.stdout, "err-wrong")}
    assert len(fitted) == 11 and len(spoiled) == 11, out[-3000:]
    for tag, (colour, xor) in fitted.items():
        # Through the original camera a projected picture is the sprite's whatever the depth of its face, up to the
        # render's filtering (colour, 0-255); only the silhouette, the fraction of the sprite's pixels where the
        # piece and the sprite do not agree on covered or empty, can tell a wrong geometry.
        limit = BLOCK_XOR_MAX if tag.split("@")[0].endswith(("castl-05.png", "castl-12.png")) else XOR_MAX
        assert colour < COLOUR_MAX and xor < limit, (tag, colour, xor)
        # The control: the same piece with its geometry spoiled reads clearly worse.
        assert spoiled[tag][1] > xor + MARGIN, (tag, xor, spoiled[tag])
    thick = {p[2]: (float(p[3]), float(p[4])) for p in _lines(result.stdout, "thickness")}
    assert len(thick) == 4, out[-3000:]
    for tag, (got, tv) in thick.items():
        assert got >= 0.8 * tv, (tag, got, tv)  # seen from above a card is a line: it covers about nothing
    # M3, the parapet is a solid strip pt thick on the OUTER edge: seen from above (only its alpha-cut surfaces drawn) the
    # merlons cover a good part of pt across the wall, and their middle lies at the far edge of 06/08 (the inner faces
    # draw the walkway in front of the merlons) and at the near edge of 07/09 (the outer faces draw the merlons in front).
    merlons = {p[2]: [float(v) for v in p[3:7]] for p in _lines(result.stdout, "merlon")}
    assert len(merlons) == 4, out[-3000:]
    for tag, (cover, pt, offset, depth) in merlons.items():
        assert pt > 3.0 and cover >= 0.5 * pt, (tag, cover, pt)
        if tag.split("@")[0].endswith(("castl-06.png", "castl-08.png")):
            assert offset >= depth - 1.5 * pt, (tag, offset, depth, pt)
        else:
            assert offset <= 1.5 * pt, (tag, offset, depth, pt)
    # The control: with the strip's thickness taken away (the ninth pass) it covers nothing from above.
    thin = {p[2]: float(p[3]) for p in _lines(result.stdout, "merlon-wrong")}
    assert len(thin) == 4 and all(v < 0.1 for v in thin.values()), thin
    # M3, the far side: the wall's far face is the sibling sprite's picture (2 triangles, on drawn brick), where the ninth
    # pass drew the point mirror of the front (the control: none carries the sibling's picture).
    far = {p[2]: (int(p[3]), float(p[4])) for p in _lines(result.stdout, "far")}
    assert len(far) == 4 and all(t == 2 and f >= 0.99 for t, f in far.values()), far
    far_wrong = {p[2]: int(p[3]) for p in _lines(result.stdout, "far-wrong")}
    assert len(far_wrong) == 4 and all(t == 0 for t in far_wrong.values()), far_wrong
    # M3, the gatehouse is a block: its silhouette width in px at eye level from the south, the east and the west
    # (orthographic, then the game's perspective). The card it was is a sliver from the side (about 1 px).
    gate = [int(v) for v in _lines(result.stdout, "gate")[0][2:]]
    south, east, west, p_south, p_east, p_west = gate
    assert east >= 0.4 * south and west >= 0.4 * south, gate
    assert p_east >= 0.4 * p_south and p_west >= 0.4 * p_south, gate


COLOUR_MAX = 25.0
XOR_MAX = 0.09
BLOCK_XOR_MAX = 0.074  # the lead's pre-registration for the gatehouse and the corner
MARGIN = 0.02
