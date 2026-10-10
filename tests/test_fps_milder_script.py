import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_actual_pig_feed_script_keeps_offscreen_spawned_milder_visible(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                          "--script", str(ROOT / "tests/fps_milder_script_test.gd")],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    assert run.returncode == 0 and "FPS MILDER SCRIPT PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
