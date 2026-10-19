"""Source-instance event re-entry under held PUSH and repeated NPC events."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_held_push_and_npc_events_restart_the_existing_script_instance(tmp_path):
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT / "tests/push_reentry_test.gd"), "--",
                             "--report=" + str(tmp_path / "push-reentry.json")],
                            cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=300)
    assert result.returncode == 0 and "PUSH REENTRY PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
