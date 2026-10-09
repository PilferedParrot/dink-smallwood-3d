"""Castle doors occupy their fitted wall, and the lowered drawbridge lies on the ground.

The instrument reads source map placements and facades.json independently of the game. Its GDScript probe reports
the actual mesh vertices built by a loaded scene. It rejects the old Sprite3D, a door moved off the wall, a leaf stood
upright, and (analytically) a south-facing card whose apparent width does not track the diagonal wall's width.
"""
import json
import hashlib
import math
import os
import shutil
import subprocess
from copy import deepcopy
from pathlib import Path

import pytest
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from tools.fit_chain_geometry import compare_masks, projected_mask, rasterize_actual_triangles, source_mask

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")
SCALE = 0.025


def _run(tmp_path, control=""):
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env.update(XDG_DATA_HOME=str(tmp_path / "data"), XDG_CONFIG_HOME=str(tmp_path / "config"),
               XDG_CACHE_HOME=str(tmp_path / "cache"))
    game = os.environ.get("FPS_DOORS_GAME") or str(ROOT / "game")
    cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", game,
           "--script", str(ROOT / "tests/fps_doors_test.gd")]
    if control:
        cmd += ["--", f"--control={control}"]
    result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, (result.stdout + result.stderr)[-3000:]
    rows = [json.loads(line.removeprefix("DOORJSON ")) for line in result.stdout.splitlines()
            if line.startswith("DOORJSON ")]
    assert len(rows) == 2, result.stdout[-3000:]
    return {row["screen"]: row for row in rows}


def _source(screen, filename):
    world = json.loads((ROOT / "game/data/world.json").read_text())
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    for sprite in world["screens"][str(screen)]["sprites"]:
        frame = sequences[str(sprite["seq"])]["frames"][sprite["frame"] - 1]
        if frame["path"].endswith(filename):
            origin = (((screen - 1) % 32) * 600 - 20, ((screen - 1) // 32) * 400)
            top_left = (origin[0] + sprite["x"] - frame["dx"], origin[1] + sprite["y"] - frame["dy"])
            return sprite, top_left
    raise AssertionError((screen, filename))


def _expected_face(screen):
    fits = json.loads((ROOT / "game/prototype/facades.json").read_text())["_walls"]
    if screen == 402:
        wall, at = _source(402, "castl-07.png")
        q = fits["assets/graphics/struct/Castle/castl-07.png"]["parts"][0]
        a = (at[0] + q["x0"], at[1] + q["s"] * q["x0"] + q["c"])
        b = (at[0] + q["x1"], at[1] + q["s"] * q["x1"] + q["c"])
    else:
        gate, at = _source(80, "castl-05.png")
        door, door_at = _source(80, "cdoor-06.png")
        anchor_x = door_at[0] + 50  # lower stone at the edge of the source arch, before the leaf
        q = fits["assets/graphics/struct/Castle/castl-05.png"]["parts"][0]
        poly = q["poly"]
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1]
                   - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
        faces = []
        for i, p in enumerate(poly):
            r = poly[(i + 1) % len(poly)]
            dx = r[0] - p[0]
            if dx == 0 or not min(p[0], r[0]) <= anchor_x - at[0] <= max(p[0], r[0]):
                continue
            normal_z = -dx * (1 if area > 0 else -1)
            if normal_z > 0:
                faces.append(((at[0] + p[0], at[1] + p[1]), (at[0] + r[0], at[1] + r[1])))
        assert len(faces) == 1, faces
        a, b = faces[0]
    length = math.dist(a, b)
    normal = (-(b[1] - a[1]) / length, (b[0] - a[0]) / length)
    return a, b, normal


def _corners(row, part):
    assert row["kind"] == "mesh", row
    vertices = row["parts"][part]
    assert len(vertices) == 6
    return [vertices[i] for i in (0, 1, 2, 5)]


def _plane_distance(corners, face):
    a, b, n = face
    return max(abs((v[0] - a[0]) * n[0] + (v[2] - a[1]) * n[1]) * SCALE for v in corners)


def _width_ratio(edge, wall_edge, direction):
    right = (direction[1], -direction[0])
    return abs(edge[0] * right[0] + edge[1] * right[1]) / abs(
        wall_edge[0] * right[0] + wall_edge[1] * right[1])


def _turn(vec, degrees):
    angle = math.radians(degrees)
    return (vec[0] * math.cos(angle) - vec[1] * math.sin(angle),
            vec[0] * math.sin(angle) + vec[1] * math.cos(angle))


def _leaf_ratio(corners, from_east):
    # Orthographic eye-level projection: horizontal screen axis is north/south from an east/west view.
    right = (0, 1 if from_east else -1)
    horizontal = [v[0] * right[0] + v[2] * right[1] for v in corners]
    length = max(horizontal) - min(horizontal)
    height = max(v[1] for v in corners) - min(v[1] for v in corners)
    return height / max(length, 1e-6)


def _chain_attached(row, face, top_left):
    a, b, _ = face
    for name, start, end in (("ChainLeft", (0, 60), (76, 177)),
                             ("ChainRight", (48, 19), (124, 147))):
        centers = row["chain_centers"][name]
        assert len(centers) >= 12
        x = top_left[0] + start[0]
        wall_z = a[1] + (x - a[0]) * (b[1] - a[1]) / (b[0] - a[0])
        top = (x, wall_z - (top_left[1] + start[1]) + 0.4, wall_z)
        bottom = (top_left[0] + end[0], 0.4, top_left[1] + end[1])
        if math.dist(centers[0], top) > 2.0 or math.dist(centers[-1], bottom) > 2.0:
            return False
        line = tuple(bottom[i] - top[i] for i in range(3))
        line_sq = sum(t * t for t in line)
        for p in centers:
            t = sum((p[i] - top[i]) * line[i] for i in range(3)) / line_sq
            closest = tuple(top[i] + t * line[i] for i in range(3))
            if math.dist(p, closest) > 2.0:
                return False
    return True


def _source_chain_palette():
    """Opaque suspended right-chain pixels, away from arch/wood and the leaf overlap."""
    path = ROOT / "game/assets/graphics/struct/Castle/cdoor-06.png"
    image = Image.open(path).convert("RGBA")
    channels = [[], [], []]
    count = 0
    for y in range(image.height):
        for x in range(65, image.width):
            leaf_top = 111 + .45 * (x - 60)
            color = image.getpixel((x, y))
            if y >= leaf_top - 3 or color[3] <= 127:
                continue
            count += 1
            for channel, value in zip(channels, color[:3]):
                channel.append(value)
    assert count == 633  # protects the mask from silently including a different surface
    for channel in channels:
        channel.sort()
    return [tuple(channel[round((count - 1) * q)] for channel in channels)
            for q in (.25, .5, .75, .90)]


def _chain_fidelity(row):
    palette = _source_chain_palette()
    document = json.loads((ROOT / "game/prototype/cdoor_chain_profile.json").read_text())
    assert document["source_sha256"] == hashlib.sha256(
        (ROOT / "game/assets/graphics/struct/Castle/cdoor-06.png").read_bytes()).hexdigest()
    profile = document["profile"]
    assert palette[1] == (49, 49, 57)
    for name, start, end in (("ChainLeft", (0, 60), (76, 177)),
                             ("ChainRight", (48, 19), (124, 147))):
        rings = row["chain_rings"][name]
        centers = row["chain_centers"][name]
        arc, tube = row["chain_segments"][name]
        assert row["chain_vertex_color"][name]
        assert {tuple(c) for c in row["chain_colors"][name]} == set(palette)
        assert arc >= 16 and tube >= 8  # enough facets for round wire in close obliques
        color_counts = {tuple(c): n for c, n in zip(row["chain_colors"][name],
                                                    row["chain_color_counts"][name])}
        total = sum(color_counts.values())
        assert .08 <= (color_counts[palette[2]] + color_counts[palette[3]]) / total <= .20
        assert .01 <= color_counts[palette[3]] / total <= .07
        assert len(rings) == len(centers) == row["chain_vertices"][name] // (arc * tube * 6)
        source_length = math.dist(start, end)
        right_length = math.dist((48, 19), (124, 147))
        expected_count = profile["right_link_count"] if name == "ChainRight" else round(
            source_length / right_length * (profile["right_link_count"] - 1)) + 1
        assert len(rings) == expected_count
        normal = (-(end[1] - start[1]) / source_length, (end[0] - start[0]) / source_length)
        for ring in rings:
            minor = ring["minor"]
            wire = ring["wire"]
            minor_size = math.dist(minor, (0, 0, 0))
            projected_half_width = abs(minor[0] * normal[0] + (minor[2] - minor[1]) * normal[1])
            width = 2 * (projected_half_width + wire)
            assert minor_size - wire > .15  # true open rings, with aperture fit by the raster check
            assert 5.5 <= width <= 8.0
            assert abs(ring["major"] - profile["major_radius_px"]) < .02
            assert abs(minor_size - profile["minor_radius_px"]) < .02
            assert abs(wire - profile["wire_radius_px"]) < .02
        for p, q in zip(rings, rings[1:]):
            a, b = p["minor"], q["minor"]
            dot = sum(x * y for x, y in zip(a, b)) / math.dist(a, (0, 0, 0)) / math.dist(b, (0, 0, 0))
            assert abs(dot - math.cos(math.radians(2 * profile["plane_tilt_deg"]))) < .03
        for p, q in zip(centers, centers[1:]):
            projected_pitch = math.dist((p[0], p[2] - p[1]), (q[0], q[2] - q[1]))
            assert 7.5 <= projected_pitch <= 9.0


def _chain_negative_controls(row):
    # Deliberately corrupt the measured mesh report; each property must be independently effective.
    uniform = deepcopy(row)
    for name in uniform["chain_colors"]:
        uniform["chain_colors"][name] = [uniform["chain_colors"][name][0]]
    with pytest.raises(AssertionError):
        _chain_fidelity(uniform)

    coplanar = deepcopy(row)
    for name, rings in coplanar["chain_rings"].items():
        for ring in rings[1:]:
            ring["minor"] = rings[0]["minor"][:]
    with pytest.raises(AssertionError):
        _chain_fidelity(coplanar)

    filled = deepcopy(row)
    for rings in filled["chain_rings"].values():
        for ring in rings:
            ring["minor"] = [v * .15 for v in ring["minor"]]
    with pytest.raises(AssertionError):
        _chain_fidelity(filled)


def _assert_chain_raster(coverage, source, domain):
    result = compare_masks(coverage, source, domain)
    mesh, art = result["mesh"], result["source"]
    assert art["pixels"] == 376 and sum(art["hole_areas"]) == 27
    assert abs(mesh["occupancy"] - art["occupancy"]) <= .08
    assert 4 <= mesh["hole_count"] <= 10
    assert .5 * sum(art["hole_areas"]) <= sum(mesh["hole_areas"]) <= 1.5 * sum(art["hole_areas"])
    assert max(mesh["hole_areas"]) <= max(art["hole_areas"]) + 4
    assert result["iou"] >= .75
    assert result["median_row_center_error_px"] <= 1.0
    return result


def _chain_raster_fidelity(row, top_left):
    source, domain = source_mask()
    triangles = row["chain_projected_vertices"]["ChainRight"]
    actual4 = rasterize_actual_triangles(triangles, top_left, scale=4)
    actual8 = rasterize_actual_triangles(triangles, top_left, scale=8)
    measured4 = _assert_chain_raster(actual4, source, domain)
    measured8 = _assert_chain_raster(actual8, source, domain)
    assert abs(measured4["mesh"]["occupancy"] - measured8["mesh"]["occupancy"]) < .04
    assert measured4["mesh"]["hole_count"] == measured8["mesh"]["hole_count"]
    assert abs(measured4["iou"] - measured8["iou"]) < .04
    y = np.indices(domain.shape)[0]
    holdout = domain & (y >= 91) & (y < 103)  # excluded from parameter fitting
    assert compare_masks(actual4, source & holdout, holdout)["iou"] >= .72

    # Geometric controls exercise the same actual-triangle raster validator.
    shifted = rasterize_actual_triangles([[x + 2, yy] for x, yy in triangles], top_left)
    filled = ndi.binary_fill_holes((actual4 >= .5) & domain).astype(float)
    old = projected_mask({"major_radius_px": 4.4, "minor_radius_px": 3.0,
                          "wire_radius_px": .56, "plane_tilt_deg": 30.0,
                          "center_offset_px": 0.0, "phase_px": 0.0,
                          "right_link_count": 20})
    thick_only = projected_mask({"major_radius_px": 4.4, "minor_radius_px": 2.1,
                                 "wire_radius_px": 1.25, "plane_tilt_deg": 30.0,
                                 "center_offset_px": 0.0, "phase_px": 0.0,
                                 "right_link_count": 20})
    for rejected in (shifted, filled, old, thick_only):
        with pytest.raises(AssertionError):
            _assert_chain_raster(rejected, source, domain)


def test_castle_doors_share_wall_plane_and_drawbridge_is_down(tmp_path):
    actual = _run(tmp_path / "actual")
    assert set(actual[402]["parts"]) == {"Panel"}
    assert set(actual[80]["parts"]) == {"Arch", "Leaf", "ChainLeft", "ChainRight"}
    assert all(n > 100 for n in actual[80]["chain_vertices"].values())
    for row in actual.values():
        hx, hz, hw, hd = row["hardbox"]
        bx, bz, bw, bd = row["ray_body"]
        assert abs(bx - hx) < 0.01 and abs(bz - hz) < 0.01
        assert abs(bw - max(8.0, hw)) < 0.01 and abs(bd - max(8.0, hd)) < 0.01
    wall = _expected_face(402)
    gate = _expected_face(80)
    panel = _corners(actual[402], "Panel")
    arch = _corners(actual[80], "Arch")
    leaf = _corners(actual[80], "Leaf")
    assert _plane_distance(panel, wall) < 0.02
    assert _plane_distance(arch, gate) < 0.02
    assert max(abs(v[1]) for v in leaf) * SCALE < 0.02
    assert all(_leaf_ratio(leaf, east) < 0.25 for east in (True, False))
    _, bridge_top_left = _source(80, "cdoor-06.png")
    assert _chain_attached(actual[80], gate, bridge_top_left)
    _chain_fidelity(actual[80])
    _chain_negative_controls(actual[80])
    _chain_raster_fidelity(actual[80], bridge_top_left)

    a, b, normal = wall
    wall_edge = (b[0] - a[0], b[1] - a[1])
    panel_edge = (panel[1][0] - panel[0][0], panel[1][2] - panel[0][2])
    front = _width_ratio(panel_edge, wall_edge, normal)
    assert front > 0.1
    for side in (-75, 75):
        ratio = _width_ratio(panel_edge, wall_edge, _turn(normal, side))
        assert abs(ratio / front - 1) <= 0.05, (side, front, ratio)
    # A south-facing card retains its full image width while the diagonal wall foreshortens.
    south_card_edge = (panel_edge[0], 0.0)
    wrong_front = _width_ratio(south_card_edge, wall_edge, normal)
    assert any(abs(_width_ratio(south_card_edge, wall_edge, _turn(normal, side)) / wrong_front - 1) > 0.05
               for side in (-75, 75))

    moved = _run(tmp_path / "wrong-face", "wrong-face")
    assert _plane_distance(_corners(moved[402], "Panel"), wall) > 0.02
    assert _plane_distance(_corners(moved[80], "Arch"), gate) > 0.02
    upright = _run(tmp_path / "standing-leaf", "standing-leaf")
    assert all(_leaf_ratio(_corners(upright[80], "Leaf"), east) > 0.25 for east in (True, False))
    gap = _run(tmp_path / "chain-gap", "chain-gap")
    assert not _chain_attached(gap[80], gate, bridge_top_left)
