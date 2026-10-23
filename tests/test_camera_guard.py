"""Unit 3: the camera keeps its own distance from solids; the mover is a point (G3, G6, G7)."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_camera_guard_formula_clearance_and_cost(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"), XDG_CONFIG_HOME=str(tmp_path / "config"),
               XDG_CACHE_HOME=str(tmp_path / "cache"))
    report = tmp_path / "camera-guard.json"
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script",
                          str(ROOT / "tests/camera_guard_test.gd"), "--", f"--report={report}"],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=1500)
    assert run.returncode == 0 and "CAMERA GUARD PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert not data["failures"]
    assert all(data["cases_by_class"].get(c, 0) >= 3 for c in ("sprite", "footprint", "tile", "stone", "fir", "seam"))
