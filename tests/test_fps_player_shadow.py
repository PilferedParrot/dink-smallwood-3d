"""Dink's current original animation casts a sun-facing shadow without entering the color pass."""
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_player_shadow_tracks_source_frame_sun_position_and_size(tmp_path):
    env = os.environ.copy()
    env.pop("WAYLAND_DISPLAY", None)
    env.update({
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "LP_NUM_THREADS": "6",
    })
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
         "--script", str(ROOT / "tests" / "fps_player_shadow_test.gd")],
        cwd=ROOT, env=env, text=True, capture_output=True, timeout=60, check=False,
    )
    assert result.returncode == 0 and "FPS PLAYER SHADOW PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
