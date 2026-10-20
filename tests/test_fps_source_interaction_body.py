"""Original image-hardbox ray targets for scripted decorative sprites."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


def test_source_interaction_body_native(tmp_path: Path) -> None:
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "LP_NUM_THREADS": "4", "XDG_DATA_HOME": str(tmp_path / "profile"),
                "XDG_CONFIG_HOME": str(tmp_path / "config"), "XDG_CACHE_HOME": str(tmp_path / "cache")})
    command = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
               "--path", str(ROOT / "game"), "--script", "res://../tests/fps_source_interaction_body_test.gd"]
    done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
    output = done.stdout + done.stderr
    assert done.returncode == 0 and "SCRIPT ERROR" not in output, output
    assert "SOURCE INTERACTION BODY PASS thorn=138 decorative=140" in output
