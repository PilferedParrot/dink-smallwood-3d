"""Unit 3: movers are points; no solid is grown (G2, G4), and the live passages equal the raw ones (G1)."""
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
sys.path.insert(0, str(ROOT / "tools"))
import clearance_passages as cp  # noqa: E402


def _godot(tmp_path, script, *args, timeout=900):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"), XDG_CONFIG_HOME=str(tmp_path / "config"),
               XDG_CACHE_HOME=str(tmp_path / "cache"))
    return subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script",
                           str(ROOT / "tests" / script), *(["--", *args] if args else [])],
                          cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)


def test_no_solid_is_grown_for_any_mover_class(tmp_path):
    run = _godot(tmp_path, "clearance_class_test.gd")
    assert run.returncode == 0 and "CLEARANCE CLASS PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr


def test_the_441_duck_and_every_actor_leave_a_raw_hardbox(tmp_path):
    run = _godot(tmp_path, "clearance_duck_test.gd")
    assert run.returncode == 0 and "CLEARANCE DUCK PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr


def _corridor(wall_grow: int) -> tuple[np.ndarray, np.ndarray]:
    raw = np.ones((60, 80), bool)
    raw[:, 20:40] = False  # a 20 px vertical corridor open at the top and the bottom
    live = raw.copy()
    if wall_grow:
        from scipy import ndimage
        live = ndimage.binary_dilation(raw, np.ones((2 * wall_grow + 1, 2 * wall_grow + 1), bool))
    return raw, live


def test_passage_instrument_sees_a_four_pixel_band_and_an_identical_map():
    raw, grown = _corridor(4)
    narrowed = cp.compare(raw, grown)
    assert narrowed["narrower"] >= 1 and 3.5 <= narrowed["max_lost_px"] <= 4.5  # the instrument can move
    same = cp.compare(raw, raw.copy())
    assert same["narrower"] == 0 and same["same"] >= 1 and same["max_lost_px"] == 0.0


@pytest.mark.parametrize("screens", [(2, 3, 408, 409, 439)])
def test_live_passages_are_the_raw_passages(tmp_path, screens):
    out = tmp_path / "live"
    out.mkdir()
    run = _godot(tmp_path, "clearance_mask_dump.gd", "--screens=" + ",".join(map(str, screens)), f"--out={out}", timeout=1200)
    assert run.returncode == 0 and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
    world = json.loads((ROOT / "game/data/world.json").read_text())
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    for n in screens:
        live = np.frombuffer((out / f"live-{n}.bin").read_bytes(), np.uint8).reshape(400, 600).astype(bool)
        r = cp.compare(cp.raw_blocked(world, sequences, n), live)
        assert r["connected_pairs"] > 0
        assert r["narrower"] == 0 and r["closed"] == 0, (n, [p for p in r["pairs"] if p["kind"] in ("narrower", "closed")])
        assert r["min_median_live"][0] >= r["min_median_raw"][0] and r["min_median_live"][1] >= r["min_median_raw"][1]
        if n in (2, 3, 408):  # no fitted structure on these maps: the live field IS the raw hitmap
            assert r["raw_blocked_live_free_px"] == 0 and r["raw_free_live_blocked_px"] == 0, n


def test_the_distance_field_is_the_blocked_set_and_is_cheap(tmp_path):
    report = tmp_path / "field.json"
    run = _godot(tmp_path, "clearance_field_test.gd", f"--report={report}")
    assert run.returncode == 0 and "CLEARANCE FIELD PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert data["failures"] == 0 and data["counts"]["distance_checked"] >= 800
