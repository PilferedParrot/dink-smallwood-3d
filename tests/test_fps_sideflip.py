"""The side flip at a wall's plane (docs/DIRECTION.md, "The side flip, walked"; the eleventh-pass unit U5).

A billboard near a fitted house's wall is drawn over the house or under it by which side of the wall's plane the camera
stands on (fp_world.gd DEPTH_SHADER). The retained source screen 496 editor 1 tree-04 at (608,235), also covered by
the trees' under-home-07 pixel test, exercises this rule after tree-08 became an indivisible complete fir. The
shader now turns it pixel by pixel over a narrow band either side of the plane (SIDE_BLEND reaches, a screen-door
cross-fade), and everywhere beyond the band the picture is the old one bit for bit. Two tests, through
tests/fps_sideflip_test.gd, rendered under xvfb with the Dummy audio driver and no Wayland:

  - the walk: the sprite's picture changes by no more than 1.5 x the walk's ordinary step at each of the two
    crossings. Controls that go red: the old code (--k=0, the side turned at the plane) shows its pop.
  - the rails: cameras on 496 at least the band away from every plane (including one 0.43
    reach from the plane that the rejected blend over the whole reach would spoil) render byte-identical to the old
    code's; a camera inside the band differs (the control that the band acts); the wide blend (--k=1) differs at the
    outside-band view (the cut comes back).
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
                "XDG_CACHE_HOME": str(tmp_path / "xdg-cache"), "OMP_NUM_THREADS": "1",
                "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "LP_NUM_THREADS": os.environ.get("LP_NUM_THREADS", "1"),
                "LIBGL_ALWAYS_SOFTWARE": "1", "GALLIUM_DRIVER": "llvmpipe"})
    command = ["nice", "-n", "10", "xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GODOT, "--resolution", "960x540", "--audio-driver", "Dummy",
               "--path", "game", "--script", str(ROOT / "tests/fps_sideflip_test.gd"), "--"] + args
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout, check=False)
    assert "SCRIPT ERROR" not in result.stderr + result.stdout, (result.stdout + result.stderr)[-3000:]
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]
    return result.stdout


def _walk(tmp_path, first, last, k=None):
    """[(angle, tree px, popped px, e in reaches)] around source 496 tree-04 at 130 px."""
    args = ["--mode=walk", f"--from={first}", f"--to={last}", "--step=0.25", "--radius=130"] + ([] if k is None else [f"--k={k}"])
    rows = []
    for line in _run(args, tmp_path).splitlines():
        if line.startswith("TREE "):
            _, angle, tree, popped, e = line.split()
            rows.append((float(angle), int(tree), int(popped), float(e)))
    assert len(rows) > 40, "the walk printed too few steps"
    return rows[1:]  # the first has no previous step


# At radius 130 the wall-plane crossings are near 10.4 and 271.8 degrees;
# both retain a measured old-k=0 pop and a bounded screen-door transition.
@pytest.mark.parametrize("first,last,pops", [(260, 284, True), (0, 21, True)])
def test_the_flip_is_spread_over_the_band_and_the_old_code_pops(tmp_path, first, last, pops):
    band = _band()
    built = _walk(tmp_path / "built", first, last)
    old = _walk(tmp_path / "old", first, last, k=0)
    assert any(r[3] < -0.01 for r in built) and any(r[3] > 0.01 for r in built), "the walk does not cross the plane"
    # The walk's ordinary step: the old code's largest step other than the flip itself (the one pop of the walk).
    steps = sorted((r[2] for r in old), reverse=True)
    flip, ordinary = steps[0], steps[1]
    bound = 1.5 * ordinary
    # The control goes red: the old code's step at the plane is far over the walk's ordinary steps ...
    if pops:
        assert flip > 2.0 * ordinary, (flip, ordinary)
    # ... and the picture's change in one step, the crossing included, stays within 1.5 x the ordinary step.
    assert max(r[2] for r in built) <= bound, (max(r[2] for r in built), bound)
    # Outside the band the built code's steps are the old code's, pixel for pixel.
    for b, o in zip(built, old):
        if abs(o[3]) > band + 0.02:
            assert b[1:3] == o[1:3], (b, o)


# Screen 496's retained tree-04 has a rendered under/over control in
# fps_trees_test.gd. The first three views map those source-497 cameras to
# screen-496 coordinates. The radial views cover both sides of its wall plane.
def _views():
    import math

    views = []
    for i, (x, y, yaw) in enumerate([(660, 430, -0.1), (720, 480, 0.3), (608, -65, 3.14)]):
        views.append({"name": f"home-496-{i}", "screen": 496, "x": x, "y": y, "yaw": yaw, "pitch": -0.05})
    for i, (x, y, yaw) in enumerate([(600, 465, -0.035), (608, 465, 0.0), (540, 455, -0.297), (382, 235, -1.571)]):
        views.append({"name": f"side-496-{i}", "screen": 496, "x": x, "y": y, "yaw": yaw, "pitch": -0.05})
    for radius in (130, 230):
        for deg in range(0, 360, 45):
            r = math.radians(deg)
            yaw = (math.pi / 2 + r + math.pi) % (2 * math.pi) - math.pi
            views.append({"name": f"ring-496-{radius}-{deg:03d}", "screen": 496, "x": 608 + radius * math.cos(r),
                          "y": 235 - radius * math.sin(r), "yaw": yaw, "pitch": -0.06})
    for deg in (252.5, 253.0):
        r = math.radians(deg)
        yaw = (math.pi / 2 + r + math.pi) % (2 * math.pi) - math.pi
        views.append({"name": f"band-496-{deg}", "screen": 496, "x": 608 + 230 * math.cos(r),
                      "y": 235 - 230 * math.sin(r), "yaw": yaw, "pitch": -0.06})
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
    _, built_again = _render(tmp_path / "built-again", views_file)
    _, old = _render(tmp_path / "old", views_file, k=0)
    _, old_again = _render(tmp_path / "old-again", views_file, k=0)
    _, wide = _render(tmp_path / "wide", views_file, k=1)
    _, wide_again = _render(tmp_path / "wide-again", views_file, k=1)
    planned = {v["name"] for v in _views()}
    assert set(near) == set(built) == set(built_again) == set(old) == set(old_again) == set(wide) == set(wide_again) == planned
    # Instability is an instrument failure, never permission to lose a camera.
    for variant, first, repeated in (("built", built, built_again), ("old", old, old_again), ("wide", wide, wide_again)):
        unstable = [n for n in planned if first[n] != repeated[n]]
        assert not unstable, (f"{variant} picture changed between processes", sorted(unstable))
    beyond = {n for n in planned if near[n] >= band + 0.01}
    inside = {n for n in planned if near[n] < band - 0.01}
    # These camera positions straddle the retained tree-04's wall plane.
    # Require each geometry case, rather than a count fitted to one run. The
    # 0.01-reach clearance also exceeds SHOT's 0.001-reach output resolution.
    expected_inside = {"side-496-2", "ring-496-130-270", "band-496-252.5", "band-496-253.0"}
    assert inside == expected_inside, (inside, expected_inside)
    assert beyond == planned - expected_inside, (beyond, planned - expected_inside)
    # Every camera beyond every flagged plane's band retains the old pixels.
    assert [n for n in beyond if built[n] != old[n]] == []
    # The south view at (600,465) stands 0.43 reach from the tree's wall plane.
    assert "side-496-0" in beyond and 0.40 < near["side-496-0"] < 0.46
    # Control: a camera inside the band is not the old picture (the cross-fade acts) ...
    assert any(built[n] != old[n] for n in inside), inside
    # ... and the rejected wide blend spoils a steady outside-band view.
    assert wide["side-496-0"] != old["side-496-0"]
