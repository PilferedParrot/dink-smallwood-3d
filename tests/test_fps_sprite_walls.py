"""Source ownership and movement evidence for structural stone spans."""
import json
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
TARGETS = {385, 386, 387, 388, 417, 420, 449, 450, 451, 452, 680, 681, 712, 713}
LEGACY_WALL_SCREENS = TARGETS | {238, 244, 536, 625}
FRAMES = set(range(1, 11)) | {15}


def mask(rows):
    out = np.zeros((400, 640), bool)
    for y, x0, x1 in rows:
        out[y, x0:x1] = True
    return out


def paste(target, alpha, x, y, y0=0):
    x0, x1 = max(0, x), min(640, x + alpha.shape[1])
    z0, z1 = max(0, y - y0), min(target.shape[0], y - y0 + alpha.shape[0])
    if x0 < x1 and z0 < z1:
        target[z0:z1, x0:x1] |= alpha[z0 - (y - y0):z1 - (y - y0), x0 - x:x1 - x]


def selected(e, frame):
    return (e["seq"] == 80 and e["frame"] in FRAMES
            and frame["path"].startswith("assets/graphics/inside/stnwalls/stonw-")
            and e.get("vision", 0) == 0 and e["type"] == 1
            and e.get("size", 100) == 100 and e.get("active", 1) != 0
            and not e.get("nodraw") and not e.get("disabled")
            and e.get("brain", 0) == 0 and not e.get("script"))


def neighbors(world, n):
    row, col = divmod(n - 1, 32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if not 0 <= col + dx < 32 or row + dy < 0:
                continue
            m = n + dx + 32 * dy
            screen = world["screens"].get(str(m))
            if screen and not screen.get("indoor"):
                yield m, dx * 600, dy * 400


def test_art_ownership_height_geometry_and_tile_subtraction():
    from sys import path
    path.insert(0, str(ROOT / "tools"))
    from collision_map import tile_mask

    fit = json.loads((ROOT / "game/prototype/rc5_walls.json").read_text())
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    footprints = json.loads((ROOT / "game/data/footprints.json").read_text())["screens"]
    assert set(map(int, fit["screens"])) == TARGETS
    assert set(fit["selection"]["legacy_wall_screens"]) == LEGACY_WALL_SCREENS
    assert fit["shared_height_px"] == 74
    assert {m["face_height_px"] for m in fit["height_evidence"]["flat_front_measurements"]} == {74}
    assert any(o["frame"] == 6 and o["size"][1] == 50
               for screen in fit["screens"].values() for o in screen["owners"])
    assert all(screen["shared_height_px"] == 74 for screen in fit["screens"].values())

    # Every legacy wall-key screen is accounted for: only body frames build
    # these spans; ivy, snake cage, freestanding piers and arch stay deferred.
    discovered_legacy = set()
    for key, screen in world["screens"].items():
        if screen.get("indoor"):
            continue
        if any(seqs[str(e["seq"])]["frames"][e["frame"] - 1]["path"].startswith(
                "assets/graphics/inside/stnwalls/") for e in screen["sprites"]):
            discovered_legacy.add(int(key))
    assert discovered_legacy == LEGACY_WALL_SCREENS
    assert not (LEGACY_WALL_SCREENS - TARGETS) & set(map(int, fit["screens"]))
    for number in LEGACY_WALL_SCREENS:
        source_wall = {e["index"] for e in world["screens"][str(number)]["sprites"]
                       if seqs[str(e["seq"])]["frames"][e["frame"] - 1]["path"].startswith(
                           "assets/graphics/inside/stnwalls/")}
        built = set(fit["screens"].get(str(number), {}).get("owner_indexes", []))
        deferred = {o["index"] for o in fit["selection"]["deferred_legacy_owners"][str(number)]}
        assert source_wall == built | deferred and built.isdisjoint(deferred), number
    assert {o["reason"] for o in fit["selection"]["deferred_legacy_owners"]["625"]} == {
        "open_arch", "snake_cage"}
    # The renderer considers a 5x5 backdrop. At this source revision, no
    # visible sprite in its outer ring reaches a structural screen's playable
    # pixels; this guards the fitter's bounded 3x3 projection search.
    for number in TARGETS:
        row, col = divmod(number - 1, 32)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if max(abs(dx), abs(dy)) != 2 or not 0 <= col + dx < 32 or row + dy < 0:
                    continue
                neighbor = world["screens"].get(str(number + dx + dy * 32))
                if not neighbor or neighbor.get("indoor"):
                    continue
                for e in neighbor["sprites"]:
                    if (e.get("vision", 0) != 0 or e["type"] == 2 or e.get("active", 1) == 0
                            or e.get("nodraw") or e.get("disabled")):
                        continue
                    f = seqs[str(e["seq"])]["frames"][e["frame"] - 1]
                    if not f.get("path"):
                        continue
                    width, height = Image.open(ROOT / "game" / f["path"]).size
                    k = (e.get("size", 100) or 100) / 100
                    x = round(e["x"] - f["dx"] * k) + dx * 600
                    y = round(e["y"] - f["dy"] * k) + dy * 400
                    assert not (x < 620 and x + round(width * k) > 20
                                and y < 400 and y + round(height * k) > 0), (number, e["index"])

    unique_world_floor = set()
    seam_gains = {}
    neighbor_protection = 0
    for number in sorted(TARGETS):
        screen = fit["screens"][str(number)]
        source = world["screens"][str(number)]["sprites"]
        selected_ids = {e["index"] for e in source if selected(e, seqs[str(e["seq"])]["frames"][e["frame"] - 1])}
        assert selected_ids == set(screen["owner_indexes"])
        assert {o["index"] for o in screen["owners"]} == selected_ids
        assert all(not o["path"].endswith(("-16.png", "-27.png", "-28.png"))
                   for o in screen["owners"])

        # Independent world-coordinate composition across the selected family.
        # This is deliberately assembled from world.json and PNGs, not the
        # fitter's owner records or its composition helper.
        atlas = np.zeros((600, 640), bool)
        local_atlas = np.zeros_like(atlas)
        other = np.zeros((400, 640), bool)
        neighbor_other = np.zeros_like(other)
        expected_atlas_owners = set()
        for neighbor, offset_x, offset_y in neighbors(world, number):
            for e in world["screens"][str(neighbor)]["sprites"]:
                f = seqs[str(e["seq"])]["frames"][e["frame"] - 1]
                if not f.get("path"):
                    continue
                alpha = Image.open(ROOT / "game" / f["path"]).convert("RGBA").getchannel("A")
                k = (e.get("size", 100) or 100) / 100
                if k != 1:
                    alpha = alpha.resize((max(1, round(alpha.width * k)), max(1, round(alpha.height * k))), Image.Resampling.NEAREST)
                x = round(e["x"] - f["dx"] * k) + offset_x
                y = round(e["y"] - f["dy"] * k) + offset_y
                opaque = np.asarray(alpha) >= 128
                if selected(e, f):
                    paste(atlas, opaque, x, y, -200)
                    if neighbor == number:
                        paste(local_atlas, opaque, x, y, -200)
                    if x < 640 and x + alpha.width > 0 and y < 400 and y + alpha.height > -200:
                        expected_atlas_owners.add((neighbor, e["index"], x, y))
                elif (e.get("vision", 0) == 0 and e["type"] != 2 and e.get("active", 1) != 0
                      and not e.get("nodraw") and not e.get("disabled")):
                    paste(other, opaque, x, y)
                    if neighbor != number:
                        paste(neighbor_other, opaque, x, y)
        assert {(o["screen"], o["index"], o["at"][0], o["at"][1])
                for o in screen["atlas_owners"]} == expected_atlas_owners
        floor = atlas[200:600] & atlas[126:526]
        floor[:, :20] = False
        floor[:, 620:] = False
        assert np.array_equal(mask(screen["floor_runs"]), floor), number
        assert floor.any(), number
        local_floor = local_atlas[200:600] & local_atlas[126:526]
        gain = floor & ~local_floor
        seam_gains[number] = int(gain[:, 20:620].sum())
        for y, x0, x1 in screen["floor_runs"]:
            wy = (number - 1) // 32 * 400 + y
            wx0 = (number - 1) % 32 * 600 + x0 - 20
            for wx in range(wx0, wx0 + x1 - x0):
                assert (wx, wy) not in unique_world_floor, (number, wx, wy)
                unique_world_floor.add((wx, wy))

        effective, per_tile = tile_mask(world, number,
                                        set(footprints.get(str(number), {}).get("revert", [])),
                                        set(footprints.get(str(number), {}).get("clear", [])))
        projected = atlas[200:600].copy()
        projected[:, :20] = False
        projected[:, 620:] = False
        expected_clear = effective & projected & ~other
        actual_clear = mask(screen["clear_tile_runs"])
        assert np.array_equal(actual_clear, expected_clear), number
        assert not np.any(actual_clear & other), number
        protected_by_neighbor = int((effective & projected & neighbor_other).sum())
        assert screen["source_counts"]["foreign_neighbor_protected_hard_px"] == protected_by_neighbor
        neighbor_protection += protected_by_neighbor
        # A touched tile may be wholly wall-owned. Where it is mixed, its
        # non-wall hardness must remain; the exact-array check above guards
        # the full rule on every selected screen.
        touched = set(per_tile[actual_clear])
        for tile in touched:
            outside_wall = effective & ~projected & (per_tile == tile)
            assert not np.any(outside_wall & actual_clear), (number, tile)
        assert screen["source_counts"]["selected_old_hardbox_counts"] == sum(
            e.get("hard", 1) == 0 for e in source if e["index"] in selected_ids)
        remaining = {e["index"] for e in source if e["index"] not in selected_ids
                     and e.get("vision", 0) == 0 and e.get("active", 1) != 0
                     and e.get("hard", 1) == 0 and not e.get("warp")
                     and e["index"] not in footprints.get(str(number), {}).get("sprites", [])}
        assert set(screen["retained_unowned_hardbox_indexes"]) == remaining, number

    assert {o["frame"] for o in fit["screens"]["451"]["deferred"]} == {16}
    assert {o["frame"] for o in fit["screens"]["712"]["deferred"]} == {27, 28}
    assert seam_gains[417] > 0 and seam_gains[449] > 0
    assert neighbor_protection > 0
    # Old per-screen alpha left a phantom corridor through the continuous
    # 417/449 end-on wall. This fails if the fitter regresses to local owners.
    cut = mask(fit["screens"]["449"]["floor_runs"])[5:27, 320:345]
    assert int(cut.sum()) >= 547


def test_native_wall_runtime(tmp_path):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path / "data"),
           "XDG_CONFIG_HOME": str(tmp_path / "config"), "OMP_NUM_THREADS": "1",
           "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "LP_NUM_THREADS": "1"}
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
         "--path", "game", "--script", str(ROOT / "tests/fps_sprite_walls_test.gd")],
        cwd=ROOT, env=env, text=True, capture_output=True, timeout=240, check=False,
    )
    assert result.returncode == 0 and "FPS SPRITE WALLS PASS" in result.stdout \
        and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
