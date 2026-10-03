"""Castle doors occupy their fitted wall, and the lowered drawbridge lies on the ground.

The instrument reads source map placements and facades.json independently of the game. Its GDScript probe reports
the actual mesh vertices built by a loaded scene. It rejects the old Sprite3D, a door moved off the wall, a leaf stood
upright, and (analytically) a south-facing card whose apparent width does not track the diagonal wall's width.
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
