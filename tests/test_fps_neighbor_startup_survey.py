import json
import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_all_outdoor_neighbor_startup_fixtures(tmp_path):
    report = tmp_path / "neighbor-startup-survey.jsonl"
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    result = subprocess.run(
        [find_godot(), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/fps_neighbor_startup_survey.gd"), "--",
         "--report=" + str(report)],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=1800,
    )
    assert report.is_file(), result.stdout + result.stderr
    assert result.returncode == 0 and "NEIGHBOR STARTUP SURVEY PASS screens=570 fixtures=4" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
    records = [json.loads(line) for line in report.read_text().splitlines()]
    screens = [record for record in records if record["kind"] == "screen"]
    summaries = [record for record in records if record["kind"] == "summary"]
    assert len(screens) == 4 * 570
    assert len(summaries) == 4 and all(summary["unclassified"] == 0 for summary in summaries)
