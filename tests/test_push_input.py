"""Original PUSH scripts through real movement input in both controllers."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_push_scripts_through_movement_input(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT / "tests/push_input_test.gd"), "--",
                             "--report=" + str(tmp_path / "push-input.json")],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0 and "PUSH INPUT PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
