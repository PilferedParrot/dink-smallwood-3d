"""force_vision kills the old screen's non-1000 scripts and keeps its caller (FreeDink draw_screen_game)."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
LOCK = Path.home() / ".local/state/dink-godot.lock"


def run_fixture(script: str, marker: str, *user_args: str) -> None:
    result = subprocess.run(["flock", str(LOCK), "timeout", "90s", "nice", "-n", "10", "xvfb-run", "-a", GODOT,
                             "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / script), *(["--", *user_args] if user_args else [])],
                            cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True)
    assert result.returncode == 0 and marker in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr


def test_force_vision_cancels_other_screen_scripts_and_keeps_caller():
    run_fixture("tests/force_vision_cancel_test.gd", "FORCE VISION CANCEL PASS")


def test_original_troll_force_vision_kills_other_screen_scripts_and_finishes():
    run_fixture("tests/force_vision_troll_test.gd", "FORCE VISION TROLL PASS")


def test_spawned_script_is_sprite_1000_and_survives_force_vision():
    run_fixture("tests/force_vision_spawn_test.gd", "FORCE VISION CANCEL PASS")


def test_sprite_1000_callback_survives_force_vision_and_victim_callback_dies():
    run_fixture("tests/force_vision_callback_test.gd", "FORCE VISION CALLBACK PASS")


def test_callback_control_without_rebuild_fires_every_callback():
    run_fixture("tests/force_vision_callback_test.gd", "FORCE VISION CALLBACK PASS", "--control")
