"""Fallback model placement and real-input Talk regression."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")


def test_wizard_talk_past_fallback_bookshelf(tmp_path):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    done = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_fallback_hitbody_wizard_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
    output = done.stdout + done.stderr
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    assert "FALLBACK WIZARD PASS" in output


def test_authored_fallback_reconstruction_and_unchanged_controls(tmp_path):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"),
               HITBODY_CLASS_REPORT=str(tmp_path / "class.json"))
    done = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_fallback_hitbody_class_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
    output = done.stdout + done.stderr
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    assert "FALLBACK CLASS PASS" in output
