"""Native static collision survey; startup/real input are separate regressions."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_outdoor_landings_and_walkable_grid_never_trap(tmp_path):
    report = tmp_path / "collision-survey.json"
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    args = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
            "--script", str(ROOT / "tests/fps_collision_sweep.gd"), "--", "--report=" + str(report)]
    if os.environ.get("COLLISION_SURVEY_HOST"):
        args.append("--host=" + os.environ["COLLISION_SURVEY_HOST"])
    run = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, timeout=900)
    assert report.is_file(), run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert data["screens"] == 570 and data["edge_samples"] > 100000 and data["grid_samples"] > 1000000, data
    assert run.returncode == 0 and not data["failures"] and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr + str(data["failures"][:20])
