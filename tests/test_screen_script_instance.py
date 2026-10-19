"""A rebuilt screen constructs a new script; it does not re-enter the caller."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_screen_rebuild_preserves_force_vision_caller_and_private_locals(tmp_path):
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT / "tests/screen_script_instance_test.gd")],
                            cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=60)
    assert result.returncode == 0 and "SCREEN SCRIPT INSTANCE PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
