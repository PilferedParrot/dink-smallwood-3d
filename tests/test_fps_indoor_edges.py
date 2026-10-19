"""Indoor metadata eligibility and source/target hardness, independently reported."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_indoor_edges_use_links_and_collision_instead_of_the_indoor_bit(tmp_path):
    report = Path(os.environ.get("INDOOR_EDGE_REPORT", str(tmp_path / "indoor-edges.json")))
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    run = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                          "--script", str(ROOT / "tests/fps_indoor_edges_test.gd"), "--",
                          "--report=" + str(report)], cwd=ROOT, env=env, capture_output=True,
                         text=True, timeout=600, check=False)
    assert report.is_file(), run.stdout + run.stderr
    data = json.loads(report.read_text())
    assert data["counts"]["indoor_indoor"] == 230
    assert len({(e["source"], e["target"]) for e in data["edges"]}) == len(data["edges"])
    assert all(e["metadata_original_allowed"] == e["metadata_fps_allowed"] for e in data["edges"]), data["failures"]
    assert data["negative_controls"]["locked"] and data["negative_controls"]["missing_link"]
    assert data["negative_controls"]["original_fully_hard_edges"] > 0
    assert data["negative_controls"]["row_wrap"]
    assert data["negative_controls"]["hard_source_point"]
    assert all(e["original_open_fps_refused"] == e["fps_source_veto"] + e["fps_incoming_veto"] for e in data["edges"])
    assert not data["failures"] and run.returncode == 0 and "SCRIPT ERROR" not in run.stderr, run.stdout + run.stderr
