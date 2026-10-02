"""The side flip at a wall's plane (docs/DIRECTION.md, "The side flip, walked"; the eleventh-pass unit U5).

A billboard near a fitted house's wall is drawn over the house or under it by which side of the wall's plane the camera
stands on (fp_world.gd DEPTH_SHADER). Turned in one step, a patch of canopy appears over the cabin's east wall in one
frame (251's tree-08, walking round it at 230 px: 3,872 px at 206.0 -> 206.25 degrees, 2,504 at 27.0 -> 27.25). The
shader now turns it pixel by pixel over a narrow band either side of the plane (SIDE_BLEND reaches, a screen-door
cross-fade), and everywhere beyond the band the picture is the old one bit for bit. Two tests, through
tests/fps_sideflip_test.gd, rendered under xvfb with the Dummy audio driver and no Wayland:

  - the walk: the sprite's picture changes by no more than 1.5 x the walk's ordinary step at each of the two
    crossings. Controls that go red: the old code (--k=0, the side turned at the plane) shows its pop.
  - the rails: cameras on 251 at least the band away from every plane (the trees pass's sheet cameras, among them the one 0.43
    reach from the plane that the rejected blend over the whole reach would spoil) render byte-identical to the old
    code's; a camera inside the band differs (the control that the band acts); the wide blend (--k=1) differs at the
    sheet camera (the cut comes back).
"""
import hashlib
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


def _band() -> float:
    """The band's half-width in reaches, parsed from the shader's own constant (fp_world.gd SIDE_BLEND)."""
    source = (ROOT / "game/scripts/fp_world.gd").read_text()
    return float(re.search(r"^const SIDE_BLEND := ([0-9.]+)", source, re.M).group(1))


def _run(args, tmp_path, timeout=900):
    if not shutil.which("xvfb-run"):
        pytest.skip("xvfb-run unavailable")
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "xdg-config"), "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")})
    command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GODOT, "--resolution", "960x540", "--audio-driver", "Dummy",
               "--path", "game", "--script", str(ROOT / "tests/fps_sideflip_test.gd"), "--"] + args
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)
    assert "SCRIPT ERROR" not in result.stderr + result.stdout, (result.stdout + result.stderr)[-3000:]
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]
    return result.stdout


def _walk(tmp_path, first, last, k=None):
    """[(angle, tree px, popped px, e in reaches)] of a walk round 251's tree-08 at 230 px, 0.25 degree steps."""
    args = ["--mode=walk", f"--from={first}", f"--to={last}", "--step=0.25"] + ([] if k is None else [f"--k={k}"])
    rows = []
    for line in _run(args, tmp_path).splitlines():
        if line.startswith("TREE "):
            _, angle, tree, popped, e = line.split()
            rows.append((float(angle), int(tree), int(popped), float(e)))
    assert len(rows) > 40, "the walk printed too few steps"
    return rows[1:]  # the first has no previous step


# The rule's wall point and normal put 251's cabin tree on the plane at 27.2 and 206.0 degrees.
@pytest.mark.parametrize("first,last", [(198, 214), (19, 35)])
def test_the_flip_is_spread_over_the_band_and_the_old_code_pops(tmp_path, first, last):
    band = _band()
    built = _walk(tmp_path / "built", first, last)
    old = _walk(tmp_path / "old", first, last, k=0)
    assert any(r[3] < -0.01 for r in built) and any(r[3] > 0.01 for r in built), "the walk does not cross the plane"
    # The walk's ordinary step: the old code's largest step other than the flip itself (the one pop of the walk).
    steps = sorted((r[2] for r in old), reverse=True)
    flip, ordinary = steps[0], steps[1]
    bound = 1.5 * ordinary
    # The control goes red: the old code's step at the plane is far over the walk's ordinary steps ...
    assert flip > 2.0 * ordinary, (flip, ordinary)
    # ... and the picture's change in one step, the crossing included, stays within 1.5 x the ordinary step.
    assert max(r[2] for r in built) <= bound, (max(r[2] for r in built), bound)
    # Outside the band the built code's steps are the old code's, pixel for pixel.
    for b, o in zip(built, old):
        if abs(o[3]) > band + 0.02:
            assert b[1:3] == o[1:3], (b, o)


# The cameras, all on 251 (the cabin and its tree-08, the unit's case): the trees pass's three sheet cameras there
# (tools/trees_sheet.py CASES), four more round the cabin, a ring of eight round the tree at 130 and at 230 px, and "band-*"
# standing inside the band (the tree at 230 px at 206.0 and 207.0 degrees, looking at it). Other screens render a little
# differently from one run to the next (animated sprites, two states about even under load: 376, 404, 440, 734), so a
# byte-for-byte rail cannot stand on them; the unit's survey of 119 cameras on 12 screens is in tmp/U5-report.md.
def _views():
    import math

    views = []
    for i, (x, y, yaw) in enumerate([(61, 466, -0.79), (153, 504, 0.0), (153, 74, 3.14)]):
        views.append({"name": f"sheet-251-{i}", "screen": 251, "x": x, "y": y, "yaw": yaw, "pitch": -0.05})
    for i, (x, y, yaw) in enumerate([(153, 520, 0.0), (260, 500, 0.25), (153, 74, 3.14), (-59, 162, -2.36)]):
        views.append({"name": f"cabin-251-{i}", "screen": 251, "x": x, "y": y, "yaw": yaw, "pitch": -0.05})
    for radius in (130, 230):
        for deg in range(0, 360, 45):
            r = math.radians(deg)
            yaw = (math.pi / 2 + r + math.pi) % (2 * math.pi) - math.pi
            views.append({"name": f"ring-251-{radius}-{deg:03d}", "screen": 251, "x": 153 + radius * math.cos(r),
                          "y": 374 - radius * math.sin(r), "yaw": yaw, "pitch": -0.06})
    for deg in (206.0, 207.0):
        r = math.radians(deg)
        yaw = (math.pi / 2 + r + math.pi) % (2 * math.pi) - math.pi
        views.append({"name": f"band-251-{int(deg)}", "screen": 251, "x": 153 + 230 * math.cos(r),
                      "y": 374 - 230 * math.sin(r), "yaw": yaw, "pitch": -0.06})
    return views


def _render(tmp_path, views_file, k=None):
    out = tmp_path / "png"
    out.mkdir(parents=True)
    stdout = _run(["--mode=views", f"--views={views_file}", f"--out-dir={out}"] + ([] if k is None else [f"--k={k}"]), tmp_path)
    near = {m.group(1): float(m.group(2)) for m in re.finditer(r"^SHOT (\S+) (\S+)$", stdout, re.M)}
    digest = {p.stem: hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob("*.png")}
    return near, digest


def test_cameras_beyond_the_band_get_the_old_picture_and_the_controls_go_red(tmp_path):
    import json

    band = _band()
    views_file = tmp_path / "views.json"
    views_file.write_text(json.dumps(_views()))
    near, built = _render(tmp_path / "built", views_file)
    _, old = _render(tmp_path / "old", views_file, k=0)
    _, old_again = _render(tmp_path / "old-again", views_file, k=0)
    _, wide = _render(tmp_path / "wide", views_file, k=1)
    assert set(near) == set(built) == set(old) == set(old_again) == set(wide) and len(near) > 20
    # 251 renders the same twice (the unit's walks: 0 px of noise over hundreds of renders); a view that does not is dropped,
    # and the test fails below if too few remain.
    steady = [n for n in near if old[n] == old_again[n]]
    beyond = [n for n in steady if near[n] >= band + 0.01]
    inside = [n for n in steady if near[n] < band - 0.01]
    assert len(beyond) > 18 and inside, (len(steady), len(beyond), inside)
    # The rail: every steady camera at least the band from every flagged plane renders the old picture, byte for byte.
    assert [n for n in beyond if built[n] != old[n]] == []
    # The sheet's first camera on 251 stands 0.43 reach from the plane: outside the band, and a steady view.
    assert "sheet-251-0" in beyond and 0.40 < near["sheet-251-0"] < 0.46
    # Control: a camera inside the band is not the old picture (the cross-fade acts) ...
    assert any(built[n] != old[n] for n in inside), inside
    # ... and the wide blend (the one the October 1 section rejected) spoils the sheet camera: the cut returns.
    assert wide["sheet-251-0"] != old["sheet-251-0"]
