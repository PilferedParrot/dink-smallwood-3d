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


def test_first_person_campaign_integration():
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--script", str(ROOT / "tests/fps_test.gd")],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_first_person_controller_regressions():
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--script", str(ROOT / "tests" / "fps_controller_test.gd")],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
