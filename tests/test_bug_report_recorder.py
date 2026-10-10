import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_bug_report_recorder_saves_local_evidence_and_bounded_input(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["OMP_NUM_THREADS"] = "1"
    env["OPENBLAS_NUM_THREADS"] = "1"
    env["MKL_NUM_THREADS"] = "1"
    env["LP_NUM_THREADS"] = "1"
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests" / "bug_report_recorder_test.gd")],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=90,
        check=False,
    )
    assert result.returncode == 0 and "BUG REPORT RECORDER PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
