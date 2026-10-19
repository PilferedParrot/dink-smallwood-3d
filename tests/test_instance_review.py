"""Weapon re-entry and choice-owned input guard from the VM review."""
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


@pytest.mark.parametrize("case", ["item", "choice"])
def test_item_refire_and_choice_input_keep_one_script_cursor(tmp_path, case):
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT / "tests/instance_review_test.gd"), "--",
                             "--case=" + case, "--report=" + str(tmp_path / (case + ".json"))],
                            cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=90)
    assert result.returncode == 0 and "INSTANCE REVIEW PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
