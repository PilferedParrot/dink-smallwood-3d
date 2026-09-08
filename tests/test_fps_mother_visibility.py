import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_story_two_mother_dialogue_uses_and_restores_clear_camera(tmp_path):
    # The fixture uses the actual persistence/UI path but never reads a player's
    # profile, settings, logs, or shader cache.
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    result = subprocess.run(
        [GODOT, "--headless", "--path", "game", "--script", str(ROOT / "tests/fps_mother_visibility_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "FPS MOTHER VISIBILITY PASS" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
