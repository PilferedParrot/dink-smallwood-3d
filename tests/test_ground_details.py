"""All 41 source Details frames and real grass controls; see the source-art inventory.

FreeDink109.6 src/game_engine.cpp:483-512 treats type as background/live
ownership and hardness independently. Neither determines surface orientation.
"""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home()/".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_details_source_art_orientation_and_single_owner(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/"data"),
               XDG_CONFIG_HOME=str(tmp_path/"config"), XDG_CACHE_HOME=str(tmp_path/"cache"))
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT/"tests/ground_details_test.gd")],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0 and "GROUND DETAILS PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout+result.stderr
