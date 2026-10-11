"""A small inherited-environment native probe must use a disposable profile."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def test_default_native_subprocess_profile_is_disposable(tmp_path):
    # Fail before launching on the old uncontained runner, so the red check
    # cannot itself rotate a player's log. No per-child environment is supplied.
    profile_dirs = [Path(os.environ.get(key, "/")) for key in (
        "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")]
    assert all(path.is_relative_to(tmp_path.parent) for path in profile_dirs)
    godot = os.environ.get("GODOT") or shutil.which("godot") or str(
        Path.home()/".local/bin/Godot_v4.6.1-stable_linux.x86_64")
    if not Path(godot).is_file():
        pytest.skip("Godot unavailable")
    result = subprocess.run([godot, "--headless", "--audio-driver", "Dummy",
        "--path", str(ROOT/"game"), "--script", str(ROOT/"tests/native_profile_probe.gd")],
        capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    actual = next(line.removeprefix("NATIVE_PROFILE_DIR ")
                  for line in result.stdout.splitlines() if line.startswith("NATIVE_PROFILE_DIR "))
    assert Path(actual).is_relative_to(profile_dirs[0]), actual
