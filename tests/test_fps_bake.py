"""The house bake is what composing gives, and composing is deterministic (tests/fps_bake_test.gd)."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_baked_houses_equal_their_composition(tmp_path):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path / "data"), "XDG_CONFIG_HOME": str(tmp_path / "config")}
    result = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests" / "fps_bake_test.gd")],
        cwd=ROOT, env=env, text=True, capture_output=True, timeout=300, check=False,
    )
    assert result.returncode == 0 and "FPS BAKE PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout[-3000:] + result.stderr[-3000:]
