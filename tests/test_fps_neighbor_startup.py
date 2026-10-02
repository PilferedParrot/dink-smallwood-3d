import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_neighbour_startup_real_loads_disagree_with_editor_only_control(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    result = subprocess.run(
        [find_godot(), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_neighbor_startup_probe.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=60,
    )
    assert result.returncode == 0 and "NEIGHBOR STARTUP PASS" in result.stdout, result.stdout + result.stderr
    assert "NEIGHBOR STARTUP RESULTS" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
