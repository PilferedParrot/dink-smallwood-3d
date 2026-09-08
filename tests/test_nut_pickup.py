import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_original_runtime_nut_touch_trigger(tmp_path):
    env = os.environ.copy()
    for kind in ("DATA", "CONFIG", "CACHE"):
        env[f"XDG_{kind}_HOME"] = str(tmp_path / kind.lower())
    result = subprocess.run(
        [find_godot(), "--headless", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/nut_pickup_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=25,
    )
    assert result.returncode == 0 and "NUT PICKUP PASS" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
