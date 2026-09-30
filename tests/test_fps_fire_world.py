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


def _run(tmp_path, rendered=False):
    command = [str(GODOT), "--audio-driver", "Dummy"]  # a rendered run must not reach a speaker
    if not rendered:
        command.append("--headless")
    command += ["--path", "game", "--script", str(ROOT / "tests/fps_fire_world_test.gd"), "--",
                "--out-dir=" + str(tmp_path)]
    env = {**os.environ, "XDG_CONFIG_HOME": str(tmp_path / "xdg-config"),
           "XDG_DATA_HOME": str(tmp_path / "xdg-data"),
           "XDG_CACHE_HOME": str(tmp_path / "xdg-cache")}
    if rendered:
        if not shutil.which("xvfb-run"):
            pytest.skip("xvfb-run unavailable")
        command.insert(0, "xvfb-run")
        command.insert(1, "-a")
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60,
                          check=False, env=env)


def test_fire_and_ruin_fixture_headless(tmp_path):
    result = _run(tmp_path)
    assert result.returncode == 0 and "FPS FIRE WORLD PASS" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
    assert not list(tmp_path.glob("*.png"))


def test_fire_and_ruin_fixture_rendered(tmp_path):
    result = _run(tmp_path, rendered=True)
    assert result.returncode == 0 and "FPS FIRE WORLD PASS" in result.stdout
    assert "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
    assert {p.name for p in tmp_path.glob("*.png")} == {
        "story3-fire.png", "story5-ruin.png", "story5-ruin-door.png"
    }
