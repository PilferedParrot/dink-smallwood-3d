"""The landmarks stand solid (docs/DIRECTION.md, "The landmarks are solid").

Review round 1 on RC1 (finding 1): the well and the save machine were camera-facing billboards, the same picture from all four sides.
tools/landmark_fit.py fits them from their own sprites (the well: a stone base, two posts, a roof; the save machine: a grating floor
and an arched wall on its far half) into game/prototype/landmarks.json; scripts/prop_solids.gd builds them. Through
tests/fps_landmarks_test.gd (headless, screen 408):
  - both stand as meshes (the model is no Sprite3D) of the fitted classes, with a ray body (the save machine's on layer 2: it has a
    script, so talking to it and touching it still reach it);
  - neither is a card: its depth is at least 0.6 of its width (a billboard has none), and it has height;
  - the save machine's silhouette is not the same from the south and from the east (a ring open to the south: seen from the east it
    covers about half as much), the well's base and roof are not one slab.
Fails on the old code: both were Sprite3D billboards ("billboard" kind, no class).
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
def landmarks(tmp_path_factory):
    tmp_path = tmp_path_factory.mktemp("landmarks")
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--script",
                             str(ROOT / "tests/fps_landmarks_test.gd")], cwd=ROOT, env=env, capture_output=True, text=True, timeout=900, check=False)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert "FPS LANDMARKS PASS" in result.stdout, result.stdout[-3000:] + result.stderr[-2000:]
    out = {}
    for line in result.stdout.splitlines():
        p = line.split()
        if line.startswith("WELLROOF "):
            out["roof"] = dict(spread=float(p[1]), verts=int(p[4]))
        if line.startswith("LANDMARK "):
            name = "well" if "landm-" in p[2] else "save"
            out[name] = dict(path=p[2], kind=p[3], cls=p[4], w=float(p[5]), d=float(p[6]), h=float(p[7]), ns=float(p[8]), ew=float(p[9]),
                             layer=int(p[10]), script=p[11] == "true")
    return out


def test_both_landmarks_are_on_the_screen(landmarks):
    assert {"well", "save"} <= set(landmarks), landmarks


@pytest.mark.parametrize("name,cls", [("save", "ring"), ("well", "compound")])
def test_a_landmark_is_a_solid_not_a_card(landmarks, name, cls):
    m = landmarks[name]
    assert m["kind"] == "solid" and m["cls"] == cls, m
    assert m["d"] >= 0.6 * m["w"], m
    assert m["h"] > 0.5, m


def test_the_save_machine_is_not_the_same_from_two_sides_and_keeps_its_script(landmarks):
    m = landmarks["save"]
    assert m["ew"] <= 0.75 * m["ns"], m  # a ring open to the south: from the east it covers about half as much
    assert m["script"] and m["layer"] == 2, m  # the talk/touch script still reaches its ray body


def test_the_well_has_a_body_the_rays_hit(landmarks):
    assert landmarks["well"]["layer"] >= 1, landmarks["well"]


def test_the_wells_roof_is_a_gable_not_a_flat_slab(landmarks):
    # The roof mesh the compound builds (whether or not the well stands as a solid): the ridge is higher than the eaves by the
    # pitch. The flat slab it replaced was one thickness (0.14 m) from end to end; a gable at the cottages' pitch is about 0.7 m.
    r = landmarks["roof"]
    assert r["spread"] >= 0.45, r
    assert r["verts"] >= 40, r  # two slopes, their undersides, eave edges and four end bands, not one box


def test_the_wells_pitch_is_measured_from_its_own_edges_and_a_flat_slab_fails_it():
    # P4d: the roof shows one slope, so only its clean edges give the pitch (tools/landmark_fit.py roof_edges): the right rake joins the
    # ridge's end to the eave's end. A flat slab's rake has slope k tan(psi) (about 0.56); the picture's is 1.44. The far rake's corner
    # lands on the ridge line (a prism). The fit stores what it measured; this re-measures it from the sprite (source of truth).
    import json
    import sys

    sys.path.insert(0, str(ROOT / "tools"))
    import landmark_fit as L
    import prop_fit as P

    path = "assets/graphics/struct/Landmark/landm-01.png"
    E = L.roof_edges(L.segment(P.load(path))[1], None)
    assert E["rake_slope"] == pytest.approx(1.44, abs=0.05), E["rake_slope"]
    assert E["flat_rake_slope"] < 0.7 and E["rake_slope"] - E["flat_rake_slope"] > 0.6, (E["rake_slope"], E["flat_rake_slope"])  # the control fails
    assert E["prism_gap"] <= 3.0, E["prism_gap"]
    fit = json.loads((ROOT / "game/prototype/landmarks.json").read_text())[path]
    posts, roof = fit["parts"]
    assert roof["class"] == "gable" and fit["k"] == pytest.approx(E["k"], abs=1e-3)
    assert roof["pitch"] == pytest.approx(E["rise"] / E["w"], abs=2e-3), roof["pitch"]
    assert 0.55 <= roof["pitch"] <= 0.70, roof["pitch"]  # apparent rise / run: 0.62 (0.80 true); the borrowed cottages' 1.1 is far outside
    assert roof["ridge"] - roof["rise"] > roof["boxes"][0][2] - 1e-6  # the eaves stand above the underside's lowest edge
    for X, Z, y0, h in posts["boxes"]:  # a post's top is in the roof's underside, below its top
        assert y0 + h <= roof["ridge"] - roof["h"] + 0.6 and y0 + h > roof["ridge"] - roof["rise"] - roof["h"] - 1, (X, Z, y0, h)
