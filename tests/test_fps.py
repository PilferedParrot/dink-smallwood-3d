import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")


def _isolated_env(tmp_path):
    return {**os.environ, "XDG_DATA_HOME": str(tmp_path / "data"),
            "XDG_CONFIG_HOME": str(tmp_path / "config"), "XDG_CACHE_HOME": str(tmp_path / "cache")}


def test_first_person_campaign_integration(tmp_path):
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--script", str(ROOT / "tests/fps_test.gd")],
        cwd=ROOT,
        env=_isolated_env(tmp_path),
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_first_person_controller_regressions(tmp_path):
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--script", str(ROOT / "tests" / "fps_controller_test.gd")],
        cwd=ROOT,
        env=_isolated_env(tmp_path),
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
