import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_actors_turn_with_the_camera_and_a_speaker_faces_you(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    result = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests" / "fps_facing_test.gd")],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=180,
        check=False,
    )
    assert result.returncode == 0 and "FPS FACING PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
