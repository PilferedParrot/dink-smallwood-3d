"""The small props stand solid (docs/DIRECTION.md, "The small props are solid").

Chris, 2026-10-07, the 0.3.0 release: "the pig feed and apple pie are 2d, when i walk around them, they're flat". The sack's art
is Items/Paper/paper-12, which model_key called a sign (a fixed card, edge-on from the side); the pie is Items/Food, a camera-facing
billboard. tools/prop_fit.py fits every prop sprite of the folders (a barrel, a sack, a pie, a bottle, a vase: a solid of
revolution; a crate, a chest, a stack of crates: boxes; a bag, a ham, a loaf: an ellipsoid; a scroll, a coin pile: a quad on the
ground) into game/prototype/props.json, and scripts/prop_solids.gd builds them. Through tests/fps_props_test.gd (headless):
  - every placed sprite whose art is fitted stands as a solid (none is a billboard or a card), on nine screens that hold the
    sack, the pie, barrels, crates, a stack, a chest, cups, acorns and bags; the tools (not fitted) stay billboards.
  - the sack and the pie are as deep as they are wide (a round thing is round: depth over width at least 0.7), and a barrel,
    whose source hardbox is as deep as it is wide, stands 1.0 deep.
  - no solid prop's back stands behind the player's closest approach to its hardbox (hardbox plus the 4 px game.gd keeps): the
    camera never ends up inside it (at most 1 px of slack).
Fails on the old code: paper-12 was a fixed card and food-11 a billboard.
"""
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


@pytest.fixture(scope="module")
def classified(tmp_path_factory):
    tmp_path = tmp_path_factory.mktemp("props")
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--script",
                             str(ROOT / "tests/fps_props_test.gd")], cwd=ROOT, env=env, capture_output=True, text=True, timeout=1800, check=False)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert "FPS PROPS PASS" in result.stdout, result.stdout[-3000:] + result.stderr[-2000:]
    props, other = [], []
    for line in result.stdout.splitlines():
        p = line.split()
        if line.startswith("ANIM "):
            props.append(dict(anim=p[2:]))
            continue
        if line.startswith("PROP "):
            props.append(dict(screen=int(p[1]), index=int(p[2]), path=p[3], kind=p[4], cls=p[5], w=float(p[6]), d=float(p[7]),
                              h=float(p[8]), back=float(p[9])))
        elif line.startswith("OTHER "):
            other.append((int(p[1]), int(p[2]), p[3], p[4]))
    return props, other


def _named(props, stem, screen=None):
    return [r for r in props if "path" in r and r["path"].endswith(stem + ".png") and (screen is None or r["screen"] == screen)]


def test_every_fitted_prop_is_a_solid(classified):
    props, other = classified
    props = [r for r in props if "path" in r]
    assert len(props) > 40, len(props)
    for r in props:
        assert r["kind"] in ("solid", "hidden", "painted"), r  # painted: a type 0 sprite, part of the ground as the original draws it
    assert any(r["cls"] == "box" for r in props) and any(r["cls"] == "round" for r in props)
    assert any(r["cls"] == "pillow" for r in props)
    assert other and all(kind == "billboard" for *_, kind in other), other  # the tools, hearts: not fitted, still cards of the art


def test_the_pig_feed_sack_and_the_pie_are_solids_as_deep_as_they_are_wide(classified):
    props, _ = classified
    sack = _named(props, "paper-12", 1)
    pie = _named(props, "food-11", 1)
    assert len(sack) == 1 and len(pie) == 1, (sack, pie)
    for r in sack + pie:
        assert r["kind"] == "solid" and r["w"] > 0.3, r
        assert r["d"] >= 0.7 * r["w"], r


def test_a_barrel_stands_round(classified):
    props, _ = classified
    barrels = _named(props, "barel-01")
    assert barrels
    for r in barrels:
        assert r["kind"] == "solid" and r["d"] >= 0.9 * r["w"], r


def test_the_camera_never_stands_inside_a_solid_prop(classified):
    props, _ = classified
    for r in props:
        if r.get("kind") == "solid":
            assert r["back"] <= 1.0, r


def test_a_prop_follows_the_frame_its_sequence_shows(classified):
    props, _ = classified
    anim = [r["anim"] for r in props if "anim" in r]
    assert anim, "no animated barrel on screen 439"
    # whole (with a ray body), splintered on the ground (flat: none), whole again
    assert anim[0] == ["barel-01.png:body", "barel-03.png:nobody", "barel-01.png:body"], anim
