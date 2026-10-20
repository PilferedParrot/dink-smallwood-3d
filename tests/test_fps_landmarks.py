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


def _dump_well(tmp_path, name, fits=None):
    """tests/fps_well_dump.gd: the well's built meshes and textures (headless), read by tools/well_materials.py."""
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    out = tmp_path / name
    args = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/fps_well_dump.gd"), "--",
            f"--out={out}"] + ([f"--fits={fits}"] if fits else [])
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600, check=False)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert (out / "surfaces.json").is_file(), result.stdout[-2000:] + result.stderr[-2000:]
    return out


def _materials(out):
    import json
    import sys

    sys.path.insert(0, str(ROOT / "tools"))
    import numpy as np
    import well_materials as M
    from PIL import Image
    import prop_fit as P

    dump = json.loads((out / "surfaces.json").read_text())
    rgba = P.load("assets/graphics/struct/Landmark/landm-01.png")
    size = (rgba.shape[1], rgba.shape[0])
    tex = np.array(Image.open(out / dump["parts"][1]["texture"]).convert("RGBA"))
    built = M.stats(M.sample_faces(dump["parts"][1], tex, size, np.random.default_rng(1)))
    ref = M.stats(M.sprite_posts())
    tsize = Image.open(out / dump["parts"][2]["texture"]).size
    jac = M.face_jacobians(dump["parts"][2], tsize)
    return built, ref, jac


def test_the_wells_posts_are_wood_not_outline_and_a_black_face_fails_it(tmp_path):
    # P4d fix round W1 (restated after the lead's view of 58866c4: the sprite's black is its OUTLINE, a drawing convention, so a measure
    # that kept it passed flat black faces for the wrong reason). Every side face of the posts, sampled by area, against the sprite's WOOD
    # pixels (outline excluded): mean luminance within 15 %, darkest quartile within 10 levels either way, no texel at or below the
    # outline's luminance; and each post column the faces read is one colour down the whole post. Controls, run by the same test: the
    # build before this fix (black shaded face, no flat) fails all of the first three.
    import json
    import sys

    import numpy as np
    from PIL import Image

    sys.path.insert(0, str(ROOT / "tools"))
    import well_materials as M

    built, ref, _ = _materials(_dump_well(tmp_path, "now"))
    ref = M.stats(M.sprite_posts())
    assert abs(built["mean_lum"] / ref["mean_lum"] - 1) <= 0.15, (built, ref)
    assert abs(built["dark_quartile_lum"] - ref["dark_quartile_lum"]) <= 10.0, (built, ref)
    assert built["min_lum"] > M.OUTLINE_LUM, built
    path = "assets/graphics/struct/Landmark/landm-01.png"
    fits = json.loads((ROOT / "game/prototype/landmarks.json").read_text())
    posts = fits[path]["parts"][0]
    tex = np.array(Image.open(tmp_path / "now" / "part1.png").convert("RGB")).astype(int)
    for post in posts["flat"]:
        for x in range(post["dark"][0], post["lit"][1]):
            assert (tex[:, x] == tex[0, x]).all(), (x, "a post column is one material down its height")
    posts.pop("flat")
    posts["faces"] = {"dark": [-4.0, -2.0], "lit": [-2.0, 2.0]}  # 58866c4: the outline columns were the shaded face
    (tmp_path / "old.json").write_text(json.dumps({path: fits[path]}))
    old, _, _ = _materials(_dump_well(tmp_path, "old", str(tmp_path / "old.json")))
    assert abs(old["mean_lum"] / ref["mean_lum"] - 1) > 0.15 and abs(old["dark_quartile_lum"] - ref["dark_quartile_lum"]) > 10.0 and old["min_lum"] <= M.OUTLINE_LUM, (old, ref)


def test_every_face_of_the_wells_roof_keeps_the_straws_density(tmp_path):
    # P4d fix round W2: the straw is one rectified patch; each face of the roof (a slope's top, underside, eave edge, two ends) has the
    # top slope's texel density along both its axes within 35 % (the old mapping stretched the ends 4.6 to 1: sigma 1.47 and 0.32).
    _, _, jac = _materials(_dump_well(tmp_path, "now"))
    top = jac[0]
    for j in jac:
        assert abs(j["sigma_max"] / top["sigma_max"] - 1) <= 0.35 and abs(j["sigma_min"] / top["sigma_min"] - 1) <= 0.35, (j, top)


def _wood_columns(rgba, top, foot, x_from, x_to):
    """Independent of landmark_fit.segment: the columns of a post's drawn silhouette that hold wood (warm, above the outline's
    luminance) in at least half of the post's rows."""
    import numpy as np

    a = rgba.astype(int)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    warm = (a[..., 3] >= 128) & (a[..., 0] - a[..., 2] > 8) & (lum > 24)
    return [x for x in range(x_from, x_to) if warm[top:foot, x].mean() >= 0.5]


def test_the_wells_post_side_and_roof_thickness_are_the_drawn_woods_width_not_a_padded_run():
    # P4d fix round 2, F4. The drawn post is two columns of black outline and four of wood (landm-01: x78,79 outline, x80..83 wood, x84 is
    # background; the pad of DARK = 2 columns each side the fit used made it eight, one third too wide, and the roof's thickness with it).
    # The beam's drawn width is side * (|cos| + |sin|) at the fitted yaw: the side is the wood's width over that. Re-measured here from the
    # sprite by an independent column count; both posts, all three frames (one fit, three silhouettes).
    import json

    import numpy as np
    import sys

    sys.path.insert(0, str(ROOT / "tools"))
    import prop_fit as P

    fits = json.loads((ROOT / "game/prototype/landmarks.json").read_text())
    for n in (1, 2, 3):
        path = f"assets/graphics/struct/Landmark/landm-0{n}.png"
        posts, roof = fits[path]["parts"]
        rgba = P.load(path)
        for x_from, top, foot in ((76, 44, 84), (48, 61, 86)) if n < 3 else ():  # the right post, the left post: rows well inside each
            # (frame 3's glow lights the outline's pixels, so its columns cannot be counted; it shares the fit of the other two)
            cols = _wood_columns(rgba, top, foot, x_from, x_from + 10)
            assert len(cols) == 4 and cols == list(range(cols[0], cols[0] + 4)), (path, x_from, cols)
        yaw = posts["yaw"]
        side = 4.0 / (abs(np.cos(yaw)) + abs(np.sin(yaw)))
        assert posts["w"] == pytest.approx(side, abs=0.02) and posts["d"] == pytest.approx(side, abs=0.02), (path, posts["w"], side)
        assert roof["h"] == pytest.approx(side, abs=0.02), (path, roof["h"], side)  # the roof is a beam's thickness
        assert [f["lit"][1] - f["dark"][0] for f in posts["flat"]] == [4, 4], posts["flat"]
        assert posts["faces"]["lit"][1] - posts["faces"]["dark"][0] == pytest.approx(4.0), posts["faces"]
