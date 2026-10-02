import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_duck_preview_survives_real_w_key_boundary_crossing(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    result = subprocess.run(
        [find_godot(), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_neighbor_crossing.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=90,
    )
    assert result.returncode == 0 and "NEIGHBOR CROSSING PASS" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
