"""An ordinary wall stays solid; the bar door redirects instead of crossing66."""
import os
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
def test_indoor_edge_change_keeps_walls_and_authored_warp_priority(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"), XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game", "--script", str(ROOT / "tests/fps_indoor_portal_input.gd")], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    assert run.returncode == 0 and "INDOOR PORTAL INPUT PASS" in run.stdout and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
