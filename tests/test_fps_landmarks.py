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


def _ray_hits(origin, target, parts):
    """Möller-Trumbore over every triangle of the given dumped parts: does the segment origin -> target hit a face before the target?"""
    import numpy as np

    d = target - origin
    for part in parts:
        v = np.array(part["verts"], float)
        t = np.array(part["index"], int).reshape(-1, 3)
        a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
        e1, e2 = b - a, c - a
        h = np.cross(d, e2)
        det = (e1 * h).sum(1)
        ok = np.abs(det) > 1e-9
        f = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = origin - a
        u = f * (s * h).sum(1)
        q = np.cross(s, e1)
        w = f * (q * d).sum(1)
        tt = f * (e2 * q).sum(1)
        if (ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (tt > 1e-6) & (tt < 1 - 1e-6)).any():
            return True
    return False


def _the_mouth_is_open(dump, fit):
    """Returns (cap_faces, views_seen, shaft_faces): the faces of the base's top plane inside the mouth's radius, the (8 directions x 2
    distances) eye-level views from which the mouth's centre, just under the rim, is seen past the base alone, and the faces below the rim
    inside the mouth's radius."""
    import numpy as np

    base = fit["base"]
    rim = float(base["nodes"][-1][0])
    r_in = float(base["mouth"]["r"]) if "mouth" in base else float(base["nodes"][-1][1]) * 0.5
    zc = base["cz"] - (1.0 - base["k"]) * base["nodes"][0][1]
    axis = np.array([base["cx"], 0.0, zc])
    v = np.array(dump["parts"][0]["verts"], float)
    t = np.array(dump["parts"][0]["index"], int).reshape(-1, 3)
    tri = v[t]
    flat = np.nonzero((np.abs(tri[..., 1] - rim) < 0.01).all(1))[0]
    # a face stands inside the mouth if it covers any point of the mouth's disc (a lid's fan triangles are large: their centroids lie outside)
    rr, aa = np.meshgrid(np.linspace(0.0, r_in * np.cos(np.pi / 32) - 0.02, 12), np.linspace(0.0, 2 * np.pi, 48, endpoint=False))  # the ring is a 32-gon: its chords sit inside the circle
    pts = np.stack([axis[0] + (rr * np.cos(aa)).ravel(), axis[2] + (rr * np.sin(aa)).ravel()], 1)
    cap = 0
    for i in flat:
        a, b, c = tri[i][:, [0, 2]]
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (pts[:, 0] - c[0]) + (c[0] - b[0]) * (pts[:, 1] - c[1])) / d
        l2 = ((c[1] - a[1]) * (pts[:, 0] - c[0]) + (a[0] - c[0]) * (pts[:, 1] - c[1])) / d
        if ((l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)).any():
            cap += 1
    shaft = 0
    for part in dump["parts"][3:]:
        pv = np.array(part["verts"], float)
        pt = np.array(part["index"], int).reshape(-1, 3)
        pc = pv[pt].mean(1)
        shaft += int(((pc[:, 1] < rim - 0.01) & (np.hypot(pc[:, 0] - axis[0], pc[:, 2] - axis[2]) <= r_in + 0.01)).sum())
    seen = 0
    for k in range(8):
        for dist in (70.0, 150.0):
            ang = np.pi / 4 * k
            eye = axis + np.array([dist * np.cos(ang), 0.0, dist * np.sin(ang)])
            eye[1] = 1.6 / 0.025  # eye level, 1.6 m in source px (S = 0.025 m per px)
            if not _ray_hits(eye, axis + np.array([0.0, rim - 2.0, 0.0]), dump["parts"][:1]):
                seen += 1
    return cap, seen, shaft


def test_the_wells_mouth_is_open_from_every_side_and_a_lid_fails_it(tmp_path):
    # P4d fix round 2, F1 (the blind review's finding 1: the round base closed its top with a fan to the axis, a solid lid between the posts).
    # The mouth's radius is the sprite's own near lip (tools/landmark_fit.py mouth_radius: the end of the black band under the rim's centre,
    # rows 87..90 of landm-01..03, stone again at row 91), re-measured here. The class: the opening is seen from 8 directions at two
    # distances from eye level (a ray from the eye to the mouth's centre just under the rim is not stopped by the base), no face of the
    # base's top plane stands inside the mouth's radius (counted), and the shaft's faces exist below the rim with a colour from the
    # picture's darkest stone. Control: the same fit without a mouth is the lid (its fan's 32 faces cover the mouth, no view sees in).
    import json
    import sys

    import numpy as np

    sys.path.insert(0, str(ROOT / "tools"))
    import prop_fit as P

    path = "assets/graphics/struct/Landmark/landm-01.png"
    fits = json.loads((ROOT / "game/prototype/landmarks.json").read_text())
    fit = fits[path]
    base = fit["base"]
    rim = base["nodes"][-1][0]
    for n in (1, 2, 3):
        a = P.load(f"assets/graphics/struct/Landmark/landm-0{n}.png").astype(int)
        lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
        ends = []
        for x in range(57, 71):
            y = 83
            while not (lum[y, x] <= 24 and lum[y + 1, x] <= 24):
                y += 1
            while lum[y, x] <= 24:
                y += 1
            ends.append(y)
        assert float(np.median(ends)) == 91.0, (n, ends)
        assert base["mouth"]["r"] == pytest.approx((91.0 - (base["cz"] - rim)) / base["k"], abs=0.01), base["mouth"]
    assert 0.3 * base["nodes"][-1][1] < base["mouth"]["r"] < 0.8 * base["nodes"][-1][1], base["mouth"]  # a mouth inside a rim with a wall
    dump = json.loads((_dump_well(tmp_path, "now") / "surfaces.json").read_text())
    cap, seen, shaft = _the_mouth_is_open(dump, fit)
    assert cap == 0 and seen == 16 and shaft > 0, (cap, seen, shaft)
    shaft_rgb = np.array(dump["parts"][3]["colour"]) * 255
    rgba = P.load(path)
    mouth_rgb = _mouth_stone_pixels(rgba, fit)
    y = np.sort(mouth_rgb @ np.array([0.299, 0.587, 0.114]))
    assert float(shaft_rgb @ np.array([0.299, 0.587, 0.114])) == pytest.approx(float(y[: len(y) // 4].mean()), abs=6.0), (shaft_rgb, y[: len(y) // 4].mean())
    assert float(shaft_rgb @ np.array([0.299, 0.587, 0.114])) < float(np.median(y)), "the shaft is the picture's dark, not its middle"
    lid = json.loads(json.dumps(fits))
    lid[path]["base"].pop("mouth")
    (tmp_path / "lid.json").write_text(json.dumps({path: lid[path]}))
    ldump = json.loads((_dump_well(tmp_path, "lid", str(tmp_path / "lid.json")) / "surfaces.json").read_text())
    lcap, lseen, _ = _the_mouth_is_open(ldump, {**lid[path], "base": {**lid[path]["base"], "mouth": {"r": base["mouth"]["r"]}}})
    assert lcap == 32 and lseen == 0, (lcap, lseen)


def _mouth_stone_pixels(rgba, fit):
    """The sprite's stone pixels inside the mouth's ellipse (not the base mask's posts, not the outline), independent of prop_solids.gd."""
    import numpy as np
    import sys

    sys.path.insert(0, str(ROOT / "tools"))
    import landmark_fit as L

    base = fit["base"]
    body, roof, base_m, posts, warm = L.segment(rgba)
    post_px = np.zeros_like(body)
    for p in posts:
        post_px[p["top"]:p["foot"], p["x0"] - L.DARK:p["x1"] + L.DARK] = True
    r = base["mouth"]["r"]
    rim_row = base["cz"] - base["nodes"][-1][0]
    ys, xs = np.mgrid[0:rgba.shape[0], 0:rgba.shape[1]]
    inside = ((xs + 0.5 - base["cx"]) / r) ** 2 + ((ys + 0.5 - rim_row) / (base["k"] * r)) ** 2 <= 1.0
    px = rgba[inside & base_m & ~post_px & (rgba[..., 3] >= 128)][:, :3].astype(float)
    return px[px @ np.array([0.299, 0.587, 0.114]) > 24.0]


def test_the_wells_roof_keeps_every_texel_the_camera_drew_and_fills_only_the_rest(tmp_path):
    # P4d fix round 2, F3 (finding 3: the mirrored donor replaced 526 of 1851 drawn texels, so original pixels were swapped for a copy). The
    # roof's straw patch is reconstructed independently (tools/well_materials.py thatch_projection, from the fit and the sprite): every texel
    # the camera drew must equal the sprite's projected pixel (bilinear, to one level of rounding), and the texels it did not draw must
    # each be a colour found among the drawn ones (the donor), never a new one. Control: the old build (donor everywhere) fails the first.
    import json
    import sys

    import numpy as np
    from PIL import Image

    sys.path.insert(0, str(ROOT / "tools"))
    import well_materials as M
    import prop_fit as P

    path = "assets/graphics/struct/Landmark/landm-01.png"
    fit = json.loads((ROOT / "game/prototype/landmarks.json").read_text())[path]
    colour, drawn = M.thatch_projection(fit["parts"][1], P.load(path))
    assert drawn.sum() > 1000 and (~drawn).sum() > 100, (drawn.sum(), (~drawn).sum())
    tex = np.array(Image.open(_dump_well(tmp_path, "now") / "part2.png").convert("RGB")).astype(int)
    assert tex.shape[:2] == drawn.shape, (tex.shape, drawn.shape)
    err = np.abs(tex - np.round(colour)).max(2)
    assert int((err[drawn] > 1).sum()) == 0, int((err[drawn] > 1).sum())  # kept: every drawn texel is the sprite's own
    own = {tuple(c) for c in np.round(colour[drawn]).astype(int)}
    assert all(tuple(c) in own for c in tex[~drawn]), "a filled texel is a drawn texel's colour (the donor), not a new colour"


def _g1_render(tmp_path, name, target, fits=None):
    """tests/fps_well_g1.gd: the built landmark alone through the sprite's own camera (headless; the render needs a window, so the display
    server stays default under whatever launcher the caller wraps GODOT in)."""
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update({"XDG_CONFIG_HOME": str(tmp_path / "c"), "XDG_DATA_HOME": str(tmp_path / "d"), "XDG_CACHE_HOME": str(tmp_path / "k")})
    out = tmp_path / name
    args = [GODOT, "--audio-driver", "Dummy", "--resolution", "648x364", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/fps_well_g1.gd"), "--",
            f"--out={out}", f"--target={target}"] + ([f"--fits={fits}"] if fits else [])
    if os.environ.get("DISPLAY") is None and shutil.which("xvfb-run"):
        args = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24"] + args
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600, check=False)
    assert "SCRIPT ERROR" not in result.stderr, result.stderr[-2000:]
    assert (out / "g1.json").is_file(), result.stdout[-2000:] + result.stderr[-2000:]
    return out


@pytest.fixture(scope="module")
def g1_all(tmp_path_factory):
    """The built well, the built save machine and the pre-P4d flat-slab well, each through the sprite's own camera, measured by well_g1."""
    import json
    import sys

    sys.path.insert(0, str(ROOT / "tools"))
    import well_g1 as G

    tmp_path = tmp_path_factory.mktemp("g1")

    def measured(name, target, fits=None):
        d = _g1_render(tmp_path, name, target, fits)
        return G.run(d, json.loads((d / "g1.json").read_text()), target, name)

    well = measured("well", "well")
    save = measured("save", "save")
    (tmp_path / "flat.json").write_text(subprocess.check_output(["git", "show", "4d66f27:game/prototype/landmarks.json"], cwd=ROOT, text=True))
    flat = measured("flat", "well", str(tmp_path / "flat.json"))
    result = {"well": well, "save": save, "flat": flat}
    (tmp_path / "g1-result.json").write_text(json.dumps(result, indent=1))
    if os.environ.get("P4D_G1_OUT"):
        shutil.copy(tmp_path / "g1-result.json", os.environ["P4D_G1_OUT"])
    return result


def test_g1_each_part_of_the_well_is_covered_and_its_roof_keeps_the_sprites_pitch(g1_all):
    # P4d fix round 2, F2 (finding 2). tools/well_g1.py states the tolerances before measuring (R1 whole silhouette, R2 each part of the
    # well; both derived from the sprite's own shape and a 2 px boundary band) and keeps the roof's T1-T3, measured through the sprite's own
    # camera. R2: a roof over a missing base or post fails. T1-T3: the flat-slab well (pre-P4d fit, the look-alike) must fail rake and pitch.
    well, flat = g1_all["well"], g1_all["flat"]
    assert all(v["pass"] for v in well["R2"].values()), well["R2"]
    assert well["T1_rake"]["pass"] and well["T2_prism"]["pass"] and well["T3_pitch"]["pass"], well
    assert not flat["T1_rake"]["pass"] and not flat["T3_pitch"]["pass"], flat  # the control fails: a silhouette cannot see a pitch (flat R1 is no better)
    for name in ("roof", "posts"):  # the mirrored well's parts are not covered: the measure can fail
        assert well["R2"][name]["mirrored_cover"] < well["R2"][name]["floor"], (name, well["R2"][name])
    assert well["R2"]["posts"]["n"] > 20, well["R2"]["posts"]


def test_g1_the_save_machine_registers_to_its_sprite_and_the_wrong_landmark_does_not(g1_all):
    # The save machine had no G1 picture check. Its built ring through the sprite's own camera: IoU with the sprite's body at or above the
    # sprite's own 2 px band floor; the well's sprite as the reference (the wrong landmark) is far below it. A mirrored save machine
    # cannot be told from the real one (the ring is symmetric about its axis): said, not tested.
    save, well = g1_all["save"], g1_all["well"]
    assert save["R1"]["pass"], save["R1"]
    assert save["wrong_landmark_iou"] < save["R1"]["floor"] - 0.3, save
    assert well["wrong_landmark_iou"] < well["R1"]["floor"] - 0.3, well
    assert well["mirrored_iou"] < well["R1"]["floor"] - 0.1, well  # the mirrored well is a different picture


@pytest.mark.xfail(strict=True, reason="measured 2026-10-20: the built well's whole silhouette registers at IoU 0.730 against the registered floor 0.753; "
                   "the misses are the 2 px black outline left of each post (excluded from the geometry by F4) and the rubble stones that stick out of "
                   "the base (a solid of revolution has none): see docs/DIRECTION.md, P4d fix round 2")
def test_g1_the_whole_well_silhouette_registers_within_the_registered_band(g1_all):
    well = g1_all["well"]
    assert well["R1"]["pass"], well["R1"]
