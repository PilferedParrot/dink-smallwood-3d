"""Physics rays use the fitted fence openings and parts on several real maps."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


def test_fitted_fences_pass_open_bay_rays_and_stop_part_rays(tmp_path):
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    result = subprocess.run(
        [GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests" / "fps_fence_ray_test.gd")],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=90,
        check=False,
    )
    assert result.returncode == 0 and "FPS FENCE RAY PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
