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


def test_opening_polish_fixture_headless(tmp_path):
    result = subprocess.run(
        [str(GODOT), "--headless", "--audio-driver", "Dummy", "--path", "game", "--script",
         str(ROOT / "tests/fps_opening_polish_test.gd"), "--", "--out-dir=" + str(tmp_path)],
        cwd=ROOT, capture_output=True, text=True, timeout=45, check=False,
        env={**os.environ, "XDG_CONFIG_HOME": str(tmp_path / "xdg-config"),
             "XDG_DATA_HOME": str(tmp_path / "xdg-data")},
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
    assert not list(tmp_path.glob("*.png"))


def test_opening_polish_rendered_fixture(tmp_path):
    if not shutil.which("xvfb-run"):
        pytest.skip("xvfb-run unavailable")
    result = subprocess.run(
        ["xvfb-run", "-a", str(GODOT), "--audio-driver", "Dummy", "--path", "game", "--script",
         str(ROOT / "tests/fps_opening_polish_test.gd"), "--", "--out-dir=" + str(tmp_path)],
        cwd=ROOT, capture_output=True, text=True, timeout=45, check=False,
        env={**os.environ, "XDG_CONFIG_HOME": str(tmp_path / "xdg-config"),
             "XDG_DATA_HOME": str(tmp_path / "xdg-data"), "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")},
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
    assert len(list(tmp_path.glob("*.png"))) == 3
