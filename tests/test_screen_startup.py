import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_original_duck_search_runs_before_sprite_vision_filter(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    result = subprocess.run(
        [find_godot(), "--headless", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/screen_startup_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0 and "SCREEN STARTUP PASS" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
