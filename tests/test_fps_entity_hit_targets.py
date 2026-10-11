"""Physics-shape targets and the actual FPS savebot talk path."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


def run_godot(tmp_path: Path, script: str) -> str:
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "LP_NUM_THREADS": "4", "XDG_DATA_HOME": str(tmp_path / "profile"),
                "XDG_CONFIG_HOME": str(tmp_path / "config"), "XDG_CACHE_HOME": str(tmp_path / "cache")})
    command = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
               "--path", str(ROOT / "game"), "--script", script]
    done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    output = done.stdout + done.stderr
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    return output


def test_collision_shapes_supply_hit_targets(tmp_path: Path):
    output = run_godot(tmp_path, "res://../tests/fps_entity_hit_targets_test.gd")
    assert "ENTITY HIT TARGETS PASS" in output


def test_real_fps_south_talk_occlusion_melee_and_barrel_persistence(tmp_path: Path):
    output = run_godot(tmp_path, "res://../tests/fps_entity_hit_targets_live_test.gd")
    assert "ENTITY HIT TARGETS LIVE PASS" in output


def test_native_worldwide_ray_census_has_no_new_loss():
    """Review the bounded native run when the topology evidence is present."""
    path = ROOT / "tmp/rc5-pocket-audit/ray-census-integrated.json"
    integrated = path.exists()
    if not integrated:
        path = ROOT / "tmp/rc5-pocket-audit/ray-census-ownbody.json"
    if not path.exists():
        path = ROOT / "tmp/rc5-pocket-audit/ray-census.json"
    if not path.exists():
        pytest.skip("Generate native ray census from final reach masks first")
    report = json.loads(path.read_text())
    assert report["schema"] == "rc5-native-entity-ray-census-1"
    assert report["source_eligible_records"] == 817
    assert report["ray_target_records"] == 579
    assert len(report["nonstanding_ray_ineligible"]) == 129
    assert sum(report["trigger_only_excluded"].values()) == 109
    assert not [r for r in report["records"] if r["status"] == "POTENTIAL_LOST_AFTER_RAY"]
    assert report["counts_by_status"] == ({
        "RAY_RETAINED_FROM_BEFORE_AND_AFTER_CELLS": 579,
    } if integrated else {
        "RAY_RETAINED_FROM_BEFORE_AND_AFTER_CELLS": 562,
        "NO_SAMPLED_OWN_RAY_UNVERIFIED": 17,
    })
    if integrated:
        posters = {(r["screen"], r["editor_index"]): r for r in report["records"]
                   if r["screen"] in (33, 35, 195, 225, 226)}
        for key in ((33, 30), (35, 27), (195, 30), (225, 30), (226, 30)):
            assert posters[key]["after"]["ray_reaches"]
            assert posters[key]["after"]["witness_xy"]
        assert sum(r["script"] == "thorn" and r["after"]["ray_reaches"]
                   for r in report["records"]) == 12
    baseline_path = ROOT / "tmp/rc5-pocket-audit/ray-census-legacy.json"
    if baseline_path.exists():
        baseline = json.loads(baseline_path.read_text())
        assert baseline["counts_by_status"] == {
            "BASELINE_OLD_FORMULA_RAY": 500,
            "BASELINE_OLD_FORMULA_NO_SAMPLED_RAY": 79,
        }
        current = {(r["screen"], r["list_index"], r["mode"]): r for r in report["records"]}
        paired = [(r["before"]["ray_reaches"],
                   current[r["screen"], r["list_index"], r["mode"]]["after"]["ray_reaches"])
                  for r in baseline["records"]]
        assert paired.count((True, True)) == 500
        assert paired.count((False, True)) == (79 if integrated else 62)
        assert paired.count((False, False)) == (0 if integrated else 17)
        assert paired.count((True, False)) == 0
