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
from terrain_columns import (check_report, expected_cells, expected_coverage,
                             rasterize_rects, runs)

SCREENS = (3, 74, 99, 169, 258, 260)
CHANGING = (74, 99, 169, 258)
SAMPLES = {3: (75, 105), 74: (95, 115), 99: (25, 215),
           169: (295, 25), 258: (85, 305), 260: (55, 55)}


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
    # This native-hard centre is purple in raw ts37 and meets the stated blue
    # exclusion (RGB 74,41,90); do not silently add it based on its appearance.
    assert (145, 235) not in expected_cells(world, 74, footprints)
    assert expected_cells(world, 439, footprints) == []  # outdoors stay untouched
    assert not expected_coverage(world, footprints, 439, "A").any()


def test_footprint_clear_and_revert_change_effective_source_mask(source):
    world, footprints = source
    assert (25, 215) in expected_cells(world, 99, footprints)
    cleared = dict(footprints)
    cleared["99"] = {"clear": [48]}
    assert (25, 215) not in expected_cells(world, 99, cleared)

    assert (295, 25) in expected_cells(world, 169, footprints)
    reverted = dict(footprints)
    reverted["169"] = {"revert": [5]}
    assert (295, 25) not in expected_cells(world, 169, reverted)


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
    control = next(r for r in report["screens"] if int(r["screen"]) == 3)
    control_geometry = rasterize_rects(control["rects"])
    assert control_geometry[105, 75 - 20] and control_geometry[115, 85 - 20], (
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
