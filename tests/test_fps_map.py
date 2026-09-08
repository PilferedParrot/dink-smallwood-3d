import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_original_map_ownership_and_keyboard_menu_inputs(tmp_path):
    env = {**os.environ, **{f"XDG_{key}_HOME": str(tmp_path / key.lower())
                            for key in ("DATA", "CONFIG", "CACHE")}}
    result = subprocess.run(
        [GODOT, "--headless", "--path", "game", "--script", str(ROOT / "tests/fps_map_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=35,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "FPS MAP PASS" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
