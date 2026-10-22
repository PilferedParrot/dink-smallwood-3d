"""Independent source-art and native geometry checks for indoor terrain columns."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from terrain_columns import (_effective_hard, check_report, expected_cells, expected_coverage,
                             rasterize_rects, raised_tiles, runs)

SCREENS = (99, 100, 101, 258, 260)
CHANGING = (99, 100, 101, 258, 260)
SAMPLES = {99: (25, 215), 100: (305, 35), 101: (105, 85), 258: (25, 85), 260: (25, 355)}


@pytest.fixture(scope="module")
def source():
    world = json.loads((ROOT / "game/data/world.json").read_text())
    footprints = json.loads((ROOT / "game/data/footprints.json").read_text())["screens"]
    return world, footprints


def _report_for(source, number, phase="B"):
    world, footprints = source
    cover = expected_coverage(world, footprints, number, phase)
    return {"schema": "terrain-columns-1", "failures": [], "screens": [{
        "screen": number, "indoor": True,
        "cells": [list(c) for c in expected_cells(world, number, footprints)],
        "rects": [[x0, y, x1 - x0, 1] for y, x0, x1 in runs(cover)],
        "sprite_perturbation_equal": True,
    }]}


def test_source_candidates_and_hardness_clipping(source):
    world, footprints = source
    for number in SCREENS:
        cells = expected_cells(world, number, footprints)
        assert SAMPLES[number] in cells, number
        full = expected_coverage(world, footprints, number, "A")
        clipped = expected_coverage(world, footprints, number, "B")
        assert full.sum() == 100 * len(cells), number
        assert np.all(clipped <= full), number
        assert bool(np.any(full != clipped)) == (number in CHANGING), number


def test_every_interior_tile_is_classed():
    from terrain_tile_classes import check
    world = json.loads((ROOT / "game/data/world.json").read_text())
    assert check(world) == []


def test_every_raised_hard_pixel_has_a_column_and_nothing_else_does(source):
    """G1's census: on all 74 interior screens the oracle's columns are exactly the hard pixels of raised art."""
    world, footprints = source
    raised = raised_tiles()
    for key, screen in world["screens"].items():
        if not screen.get("indoor"):
            continue
        number = int(key)
        hard = _effective_hard(world, footprints, number)
        cover = expected_coverage(world, footprints, number, "B")
        tile_of = np.repeat(np.repeat(np.array([int(t["tile"]) for t in screen["tiles"][:96]]).reshape(8, 12),
                                      50, axis=0), 50, axis=1)
        is_raised = np.isin(tile_of, list(raised))
        assert not (cover & ~hard).any(), number
        assert not (cover & ~is_raised).any(), number
        assert not (hard & is_raised & ~cover).any(), number


def test_enclosed_fill_is_unreachable_raised_and_not_collided(source):
    """C: the drawn bodies behind a rim. Independent flood fill (written here, not imported from the tool): every fill
    pixel is non-hard, raised-class art, and unreachable from any floor-class pixel without crossing a hard pixel."""
    from collections import deque
    from terrain_fill import build
    world, footprints = source
    raised = raised_tiles()
    data = build(world, footprints)
    assert "99" in data and "100" in data
    for key, rects_ in data.items():
        number = int(key)
        screen = world["screens"][key]
        hard = _effective_hard(world, footprints, number)
        tile_of = np.repeat(np.repeat(np.array([int(t["tile"]) for t in screen["tiles"][:96]]).reshape(8, 12),
                                      50, axis=0), 50, axis=1)
        is_raised = np.isin(tile_of, list(raised))
        fill = rasterize_rects(rects_)
        assert not (fill & hard).any(), number
        assert (fill <= is_raised).all(), number
        seen = ~hard & ~is_raised  # the floor-class seeds
        queue = deque(map(tuple, np.argwhere(seen)))
        while queue:
            y, x = queue.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < 400 and 0 <= nx < 600 and not hard[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        assert not (fill & seen).any(), number  # nothing the walkable floor reaches is ever filled
    # the plausible-but-wrong fill (no enclosure test: every non-hard raised pixel) must trip this check
    wrong = np.zeros((400, 600), bool)
    screen = world["screens"]["99"]
    tile_of = np.repeat(np.repeat(np.array([int(t["tile"]) for t in screen["tiles"][:96]]).reshape(8, 12), 50, 0), 50, 1)
    wrong = np.isin(tile_of, list(raised)) & ~_effective_hard(world, footprints, 99)
    hard99 = _effective_hard(world, footprints, 99)
    seen = ~hard99 & ~np.isin(tile_of, list(raised))
    queue = deque(map(tuple, np.argwhere(seen)))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < 400 and 0 <= nx < 600 and not hard99[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    assert (wrong & seen).any()


def test_the_screen_102_control_stays_wall_free(source):
    """102's hard bridge-edge cells sit on blue cobble paving, the very tiles of 74's corridors: floor-class art, no
    column, as in the original (lead trade 10-21, 102-BRIDGE-EDGE-WITNESSES.md)."""
    world, footprints = source
    assert _effective_hard(world, footprints, 102).sum() > 0
    assert expected_cells(world, 102, footprints) == []
    assert not expected_coverage(world, footprints, 102, "B").any()
    shared = {int(t["tile"]) for t in world["screens"]["102"]["tiles"]} & {int(t["tile"]) for t in world["screens"]["74"]["tiles"]}
    assert 4632 in shared


def test_screen_74_pin_follows_the_art_not_the_colour(source):
    """(145,235) on 74 is tile 4632, blue cobble paving (RGB 74,41,90 is a crack in it): floor-class, so no column. The
    pin first came from the colour rule's 'water' guess; the class table gives the same answer by what the tile depicts."""
    world, footprints = source
    assert int(world["screens"]["74"]["tiles"][50]["tile"]) == 4632
    assert (145, 235) not in expected_cells(world, 74, footprints)
    assert expected_cells(world, 74, footprints) == []


def test_look_alike_controls(source):
    """S13: rock that wears the old colour rule's blue or green must still stand; paving the old rule kept as 'not
    blue/green' must not."""
    world, footprints = source
    atlas = {}

    def rgb(tile, x, y):
        from PIL import Image
        sheet, cell = divmod(tile, 128)
        if sheet + 1 not in atlas:
            atlas[sheet + 1] = np.asarray(Image.open(ROOT / f"game/assets/tiles/ts{sheet + 1:02d}.png").convert("RGB"))
        r, g, b = (int(v) for v in atlas[sheet + 1][(cell // 12) * 50 + y % 50, (cell % 12) * 50 + (x - 20) % 50])
        return r, g, b

    def old_colour_rule_drops(r, g, b):
        return (b > 1.1 * r and b > .85 * g) or g > 1.12 * r

    raised = raised_tiles()
    rock_dropped, paving_kept = [], []
    for number in (99, 100, 101, 258, 260, 74, 169, 202):
        cells = set(expected_cells(world, number, footprints))
        hard = _effective_hard(world, footprints, number)
        screen = world["screens"][str(number)]
        for y in range(5, 400, 10):
            for x in range(25, 620, 10):
                if not hard[y, x - 20]:
                    continue
                tile = int(screen["tiles"][(y // 50) * 12 + (x - 20) // 50]["tile"])
                dropped = old_colour_rule_drops(*rgb(tile, x, y))
                if tile in raised and dropped:
                    rock_dropped.append((number, x, y))
                    assert (x, y) in cells
                if tile not in raised and not dropped:
                    paving_kept.append((number, x, y))
                    assert (x, y) not in cells
    assert rock_dropped, "no blue- or green-looking rock under a hard centre: the control is vacuous"
    assert paving_kept, "no non-blue paving under a hard centre: the control is vacuous"


def test_a_centre_sample_would_miss_the_rims_of_99(source):
    """The mechanism of 99's invisible walls: hard.dat rims are 1-3 px, so a 10 px centre sample misses most of them."""
    world, footprints = source
    hard = _effective_hard(world, footprints, 99)
    cells = expected_cells(world, 99, footprints)
    centres = [(x, y) for x, y in cells if hard[y, x - 20]]
    assert hard.sum() == 3844
    assert len(centres) < len(cells) * 0.5
    centre_cover = np.zeros_like(hard)
    for x, y in centres:
        centre_cover[y - 5:y + 5, x - 25:x - 15] = True
    assert (hard & centre_cover).sum() < hard.sum() * 0.5
    assert (hard & expected_coverage(world, footprints, 99, "B")).sum() == hard.sum()


def test_footprint_clear_and_revert_change_effective_source_mask(source):
    world, footprints = source
    assert (25, 215) in expected_cells(world, 99, footprints)
    cleared = dict(footprints)
    cleared["99"] = {"clear": [48]}
    assert (25, 215) not in expected_cells(world, 99, cleared)

    reverted = dict(footprints)
    reverted["134"] = {"revert": [61]}  # tile 527 (cliff face): custom mask 799 against default 115
    assert expected_cells(world, 134, reverted) != expected_cells(world, 134, footprints)


def test_source_oracle_rejects_missing_geometry_and_injected_rectangle(source):
    world, footprints = source
    for number in CHANGING:
        report = _report_for(source, number, "A")
        assert check_report(report, world, footprints, "A")["ok"]
        # A deliberately removed-geometry fixture must fail on each affected
        # screen; the actual earlier build is examined separately by the lead.
        report["screens"][0]["rects"] = []
        report["screens"][0]["cells"] = []
        finding = check_report(report, world, footprints, "A")["screens"][0]
        assert finding["missing_pixels"] > 0 and finding["missing_cells"], number

    number = 99

    report = _report_for(source, number)
    expected = expected_coverage(world, footprints, number, "B")
    y, local_x = np.argwhere(~expected)[0]
    x = int(local_x) + 20
    report["screens"][0]["rects"].append([x, int(y), 1, 1])
    report["screens"][0]["blocked_runs"] = runs(expected)
    finding = check_report(report, world, footprints, "B")["screens"][0]
    assert finding["extra_pixels"] == 1
    assert finding["walkable_overlap_pixels"] == 1
    assert finding["extra_runs"] == [[int(y), x, x + 1]]


def test_native_mask_change_and_missing_visible_cause_are_detected(source):
    world, footprints = source
    number = 99
    report = _report_for(source, number)
    # Change the source tile's default hard mask while keeping emitted native
    # geometry fixed. This catches an implementation with a stale or wrong mask.
    changed = dict(world)
    changed["hardness"] = dict(world["hardness"])
    defaults = list(world["hardness"]["tile_defaults"])
    defaults[4993] = 0
    changed["hardness"]["tile_defaults"] = defaults
    finding = check_report(report, changed, footprints, "B")["screens"][0]
    assert finding["extra_pixels"] > 0 or finding["extra_cells"]

    report = _report_for(source, number)
    expected = expected_coverage(world, footprints, number, "B")
    extra_blocked = expected.copy()
    y, local_x = np.argwhere(~expected)[0]
    extra_blocked[y, local_x] = True
    report["screens"][0]["blocked_runs"] = runs(extra_blocked)
    report["screens"][0]["visual_runs"] = runs(expected)
    finding = check_report(report, world, footprints, "B")["screens"][0]
    assert finding["blocked_without_visible_cause_pixels"] == 1
    assert finding["blocked_without_visible_cause_runs"] == [
        [int(y), int(local_x) + 20, int(local_x) + 21]]


def test_phase_a_records_native_walkable_overlap_without_failing(source):
    world, footprints = source
    report = _report_for(source, 99, "A")
    report["screens"][0]["native_coverage_violations"] = [[25, 215]]
    report["screens"][0]["blocked_runs"] = runs(
        expected_coverage(world, footprints, 99, "B"))
    result = check_report(report, world, footprints, "A")
    assert result["ok"]
    assert result["screens"][0]["walkable_overlap_pixels"] > 0


def test_out_of_screen_geometry_cannot_be_hidden_by_raster_clamping():
    for rect in ([19, 0, 1, 1], [619, 0, 2, 1], [20, 399, 1, 2]):
        with pytest.raises(ValueError, match="outside screen"):
            rasterize_rects([rect])


def test_cave_route_cells_preserve_their_seventy_walkable_pixels(source):
    world, footprints = source
    for screen, x, y in ((99, 435, 355), (258, 415, 315)):
        before = expected_coverage(world, footprints, screen, "A")[y-5:y+5, x-25:x-15]
        after = expected_coverage(world, footprints, screen, "B")[y-5:y+5, x-25:x-15]
        assert before.sum() == 100
        assert after.sum() == 30


def test_native_emitted_columns_match_source_oracle(source, tmp_path):
    world, footprints = source
    script = ROOT / "tests/terrain_columns_test.gd"
    assert script.is_file(), "native terrain-column recorder is missing"
    godot = (os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
             or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
    assert godot, "set GODOT to the Godot executable"
    assert shutil.which("xvfb-run"), "xvfb-run is required to read rendered MultiMesh transforms"
    scratch = Path.home() / "pilferedparrot-tools/tools/godot-scratch/godot-scratch"
    report_path = tmp_path / "terrain-columns-native.json"
    result = subprocess.run([
        str(scratch), "--", "xvfb-run", "-a", "-s", "-screen 0 1920x1080x24",
        str(godot), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility",
        "--path", str(ROOT / "game"), "--script", str(script), "--",
        f"--report={report_path}",
    ], cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, result.stdout + result.stderr
    assert report_path.is_file(), result.stdout + result.stderr
    report = json.loads(report_path.read_text())
    assert {str(r["screen"]) for r in report["screens"]} == set(world["screens"])
    control = next(r for r in report["screens"] if int(r["screen"]) == 99)
    control_geometry = rasterize_rects(control["rects"])
    assert control_geometry[132, 0] and control_geometry[134, 599], (
        "native MultiMesh transform readback collapsed to identity")
    phase = os.environ.get("DINK_TERRAIN_PHASE", "B")
    comparison = check_report(report, world, footprints, phase)
    assert comparison["ok"], json.dumps({
        "failures": comparison["failures"],
        "screens": [{k: s[k] for k in ("screen", "errors", "missing_pixels", "extra_pixels",
                                      "missing_cells", "extra_cells", "walkable_overlap_pixels")
                     if k in s} for s in comparison["screens"]]}, indent=2)
    if phase == "B":
        assert all(s.get("walkable_overlap_pixels", 0) == 0 for s in comparison["screens"])
    assert all(r.get("sprite_perturbation_equal") is True for r in report["screens"])
