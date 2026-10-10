import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_seam_solids_and_open_grass_through_keyboard(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                          "--script", str(ROOT / "tests/fps_collision_input.gd")],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
    assert run.returncode == 0 and "FPS COLLISION INPUT PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr


def test_diagonal_neighbor_solidity_and_continuous_coordinates(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                          "--script", str(ROOT / "tests/fps_collision_corners.gd")],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
    assert run.returncode == 0 and "FPS COLLISION CORNERS PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
