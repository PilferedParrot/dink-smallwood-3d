import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_story_three_grief_camera_and_aftermath_labels(tmp_path):
    capture = tmp_path / "grief-room-fire.png"
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    command = [
        GODOT, "--headless", "--path", "game", "--script",
        str(ROOT / "tests/fps_grief_presentation_test.gd"),
        "--",
        "--capture=" + str(capture),
    ]
    if os.environ.get("FPS_RENDERED"):
        command[1:2] = []
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "FPS GRIEF PRESENTATION PASS" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
    if os.environ.get("FPS_RENDERED"):
        assert capture.is_file()
