"""CI cannot turn native coverage into skips by losing its tools."""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_ci_rejects_a_missing_godot_before_any_test_can_skip():
    env = dict(os.environ, DINK_REQUIRE_GODOT="1", GODOT="/nonexistent/dink-test-godot")
    result = subprocess.run([sys.executable, "-m", "pytest", "--collect-only", "-q",
        str(ROOT / "tests/test_fitted_surface_order.py")], cwd=ROOT, env=env,
        capture_output=True, text=True, timeout=30)
    assert result.returncode != 0
    assert "DINK_REQUIRE_GODOT=1: executable Godot is missing" in result.stdout + result.stderr


def test_ci_rejects_missing_xvfb_before_any_test_can_skip(tmp_path):
    executable = tmp_path / "fake-godot"
    executable.write_text("#!/bin/sh\nexit 0\n")
    executable.chmod(0o700)
    env = dict(os.environ, DINK_REQUIRE_GODOT="1", GODOT=str(executable), PATH=str(tmp_path))
    result = subprocess.run([sys.executable, "-m", "pytest", "--collect-only", "-q",
        str(ROOT / "tests/test_fitted_surface_order.py")], cwd=ROOT, env=env,
        capture_output=True, text=True, timeout=30)
    assert result.returncode != 0
    assert "DINK_REQUIRE_GODOT=1: xvfb-run is missing" in result.stdout + result.stderr
