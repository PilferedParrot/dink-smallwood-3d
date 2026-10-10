"""Source doorway rows map to live first-person player coordinates only."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


@pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")
def test_live_foyer_mapping_and_inactive_leaf(tmp_path):
    env = {key: value for key, value in os.environ.items() if key != "WAYLAND_DISPLAY"}
    env.update({
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "XDG_DATA_HOME": str(tmp_path / "data"),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "LP_NUM_THREADS": "6",
    })
    cmd = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
           "--script", str(ROOT / "tests/fps_foyer_mapping_test.gd")]
    result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "FPS FOYER MAPPING PASS" in output and "SCRIPT ERROR" not in output, output[-5000:]
