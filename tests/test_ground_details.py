"""Representation consistency for all 41 frames; partial pixel cues are separate.

FreeDink109.6 src/game_engine.cpp:483-512 treats type as background/live
ownership and hardness independently. Neither determines surface orientation.
"""
import json
import sys
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home()/".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_details_representation_consistency_and_reviewed_pixel_cases(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/"data"),
               XDG_CONFIG_HOME=str(tmp_path/"config"), XDG_CACHE_HOME=str(tmp_path/"cache"))
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT/"tests/ground_details_test.gd")],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    (tmp_path / "ground-native.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0 and "GROUND DETAILS PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout+result.stderr

    # External review and the independent pixel instrument agree on these two
    # cast-shadow cases. This is not a universal classifier: weak outline-dither
    # positives and unshadowed frames remain explicitly unresolved in the report.
    sys.path.insert(0, str(ROOT / "tools"))
    from detail_pixels import inspect
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    actual = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 5 and parts[0] == "DETAIL":
            actual[int(parts[1]), int(parts[2])] = parts[4] == "true"
    (tmp_path / "ground-observed.json").write_text(json.dumps({f"{seq}/{frame}": planar for (seq, frame), planar in actual.items()}, indent=2))
    failures = []
    for seq, frame in [(92, 4), (91, 1)]:
        path = ROOT / "game" / seqs[str(seq)]["frames"][frame-1]["path"]
        pixels = inspect(path)
        assert pixels["class"] == "upright_cue", (path.name, pixels)
        if actual[seq, frame]:
            failures.append((path.name, pixels))
    assert not failures, ("reviewed cast-shadow objects rendered flat", failures)
