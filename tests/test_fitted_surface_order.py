"""Recycled opaque material slots and duplicate dormer solids are game defects."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")


def test_fitted_surfaces_keep_their_order_and_source_panel_copies_make_one_solid(tmp_path):
    if not Path(GODOT).is_file() or not shutil.which("xvfb-run"):
        pytest.skip("Godot and xvfb-run required")
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    for key, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        env[key] = str(tmp_path / folder)
    project = os.environ.get("FITTED_ORDER_GAME", str(ROOT / "game"))
    result = subprocess.run(["nice", "-n", "10", "xvfb-run", "-a", GODOT,
        "--resolution", "96x96", "--audio-driver", "Dummy", "--path", project,
        "--script", str(ROOT / "tests/fitted_surface_order_test.gd")],
        env=env, capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "FITTED SURFACE ORDER PASS" in output, output[-6000:]
    assert "SCRIPT ERROR" not in output, output[-3000:]
