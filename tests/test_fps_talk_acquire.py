"""Talk acquisition by FreeDink's box rule, on the earned bonca-complete save."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")


def run_godot(tmp_path, **extra):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"), **extra)
    done = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_talk_acquire_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    return done, done.stdout + done.stderr


def test_talk_acquires_by_the_originals_box(tmp_path):
    done, output = run_godot(tmp_path)
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    assert "TALK ACQUIRE PASS" in output


def test_flipping_one_table_row_fails(tmp_path):
    done, output = run_godot(tmp_path, TALK_FLIP_ROW="0")
    assert done.returncode == 1 and "G3 row 0" in output, output
