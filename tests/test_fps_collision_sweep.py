"""Native static collision survey; startup/real input are separate regressions."""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_outdoor_landings_and_walkable_grid_never_trap(tmp_path):
    report = Path(os.environ.get("COLLISION_SURVEY_REPORT", str(tmp_path / "collision-survey.json")))
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    args = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
            "--script", str(ROOT / "tests/fps_collision_sweep.gd"), "--", "--report=" + str(report)]
    if os.environ.get("COLLISION_SURVEY_HOST"):
        args.append("--host=" + os.environ["COLLISION_SURVEY_HOST"])
    run = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, timeout=3600)
    assert report.is_file(), run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert data["screens"] == 570 and data["grid_samples"] > 1000000, data
    # Count and coordinate sums certify that both physical sides of each axis
    # were scanned at every pixel, rather than mirroring one side's results.
    screens = data["screens"]
    y_sum = sum(range(400)) * screens
    x_sum = sum(range(20, 620)) * screens
    expected = {
        "west": (400 * screens, 21 * 400 * screens, y_sum),
        "east": (400 * screens, 619 * 400 * screens, y_sum),
        "north": (600 * screens, x_sum, 600 * screens),
        "south": (600 * screens, x_sum, 399 * 600 * screens),
    }
    coverage = data["edge_coverage"]
    assert set(coverage) == set(expected), coverage
    for side, (count, side_x_sum, side_y_sum) in expected.items():
        observed = coverage[side]
        assert (observed["candidates"], observed["x_sum"], observed["y_sum"]) == (
            count, side_x_sum, side_y_sum), (side, observed)
        assert 0 < observed["walkable"] <= count, (side, observed)
        assert 0 < observed["crossings"] <= observed["walkable"], (side, observed)
        assert observed["crossings"] + observed["rejected"] == observed["walkable"], (
            side, observed)
    assert data["edge_samples"] == sum(side["walkable"] for side in coverage.values()), data
    assert data["edge_samples"] > 1000000, data
    assert data["crossings"] + data["rejected"] == data["edge_samples"], data
    assert 0 <= data["indoor_landings"] <= data["crossings"], data
    assert data["indoor_landing_traps"] == 0, data
    assert run.returncode == 0 and not data["failures"] and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr + str(data["failures"][:20])


def test_survey_rejects_an_injected_indoor_landing_trap(tmp_path):
    """A bounded negative fixture, not a second whole-world walker run."""
    report = tmp_path / "indoor-trap.json"
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                          "--script", str(ROOT / "tests/fps_collision_sweep.gd"), "--",
                          "--sources=117", "--host=res://../tests/indoor_landing_trap_host.gd",
                          "--report=" + str(report)], cwd=ROOT, env=env, text=True,
                         capture_output=True, timeout=180)
    assert report.is_file() and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert data["host"].endswith("indoor_landing_trap_host.gd")
    assert data["screens"] == 1 and data["indoor_landings"] > 0, data
    assert data["indoor_landing_traps"] == data["indoor_landings"], data
    assert run.returncode == 1 and any(f["kind"] == "landing_trap" and f["target"] == 85
                                     and f["indoor"] for f in data["failures"]), data
