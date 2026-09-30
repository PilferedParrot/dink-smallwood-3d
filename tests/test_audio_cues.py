import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_every_audio_cue_resolves_or_is_a_listed_freedink_gap(tmp_path):
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    result = subprocess.run(
        [find_godot(), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/audio_cues_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0 and "AUDIO CUES PASS" in result.stdout, result.stdout[-4000:] + result.stderr[-4000:]
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
