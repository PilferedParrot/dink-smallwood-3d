"""Native RC4 support selection and exact whole-fir hardbox movement rule."""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
FIT = ROOT / "game/prototype/rc5_fir_collision.json"
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


def compiler():
    spec = importlib.util.spec_from_file_location("rc5_fir_collision_fit", ROOT / "tools/rc5_fir_collision_fit.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_godot(tmp_path: Path, script: str, *args: str) -> str:
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "LP_NUM_THREADS": "4", "XDG_DATA_HOME": str(tmp_path / "profile")})
    command = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
               "--path", str(ROOT / "game"), "--script", script]
    if args:
        command.extend(("--", *args))
    done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
    output = done.stdout + done.stderr
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    return output


@pytest.fixture(scope="module")
def native_inventory(tmp_path_factory):
    tmp_path = tmp_path_factory.mktemp("fir-native")
    path = tmp_path / "native.json"
    output = run_godot(tmp_path, "res://../tools/rc5_fir_collision_inventory.gd", f"--out={path}")
    assert "placements=123 parts=246 shown=165 unsupported=92 invalid=1" in output
    return path


def test_compiled_fit_rebuilds_from_native_baseline(native_inventory):
    module = compiler()
    compiled = json.loads(FIT.read_text())
    inventory = json.loads(native_inventory.read_text())
    source_fit = json.loads((ROOT / "game/prototype/rc5_firs.json").read_text())
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    assert compiled == module.compile_fit(inventory, source_fit, world, sequences,native_inventory)
    assert compiled["counts"] == {"source_placements": 123, "source_parts": 246,
                                  "shown_union": 165, "authorized_roots": 92,
                                  "skipped_invalid": 1, "screen_entries": 104,
                                  "screens_touched": 50, "multi_screen_roots": 12}
    assert compiled["template"]["hardbox_relative_to_measured_foot_xyxy"] == [-50.5, -31, 43.5, 5]
    assert len({r["id"] for r in compiled["rectangles"]}) == 92
    assert compiled["skipped_invalid"][0]["normalized_foot"]["screen"] == 798
    assert all(r["baseline_blocked"] is False for r in compiled["rectangles"])
    assert all(r["full_world_shown"] or r["scene5x5_shown_centers"] for r in compiled["rectangles"])
    for name, digest in compiled["source_sha256"].items():
        path = native_inventory if name == "native_inventory.json" else (
            ROOT / "game/prototype/rc5_firs.json" if name == "rc5_firs.json" else
            ROOT / "game" / name if name.startswith("assets/") else ROOT / "game/data" / name
        )
        assert module.sha(path) == digest, name
    membership = Counter(entry["id"] for entries in compiled["by_screen"].values() for entry in entries)
    assert sum(membership.values()) == 104
    assert sum(count > 1 for count in membership.values()) == 12


def test_screen_index_includes_corners_without_row_wrap():
    module = compiler()
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    # Four outdoor screens meet at the lower-right corner of screen 375.
    assert module.touched_screens([13790, 4790, 13810, 4810], world) == [375, 376, 407, 408]
    # Screen 32's east edge is the world edge, not screen 33's west edge.
    assert module.touched_screens([19190, 10, 19210, 20], world) == [32]


def test_native_inventory_uses_source_collision_baseline(native_inventory):
    fresh = json.loads(native_inventory.read_text())
    assert fresh["counts"]["valid_unsupported"] == 92
    assert fresh["counts"]["source_parts"] == 246
    candidates = [p for p in fresh["parts"] if p["full_world_shown"] or p["scene5x5_shown_centers"]]
    assert sum(p["normalized_foot"]["valid_outdoor_neighbor"] and not p["baseline_blocked"] for p in candidates) == 92


def test_runtime_rectangles_and_escape_band(tmp_path: Path):
    output = run_godot(tmp_path, "res://../tests/fps_fir_collision_test.gd")
    assert "FIR COLLISION PASS roots=92 touched_screens=50 cross_screen=12" in output
