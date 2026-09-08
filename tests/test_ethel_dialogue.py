import os
import subprocess

from tools.playtest import ROOT, find_godot


def test_both_ethel_agreements_release_player_and_npc(tmp_path):
    env = {**os.environ, "XDG_DATA_HOME": str(tmp_path / "data"),
           "XDG_CONFIG_HOME": str(tmp_path / "config")}
    result = subprocess.run(
        [find_godot(), "--headless", "--path", str(ROOT / "game"),
         "--script", str(ROOT / "tests/ethel_dialogue_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=30,
    )
    assert result.returncode == 0 and "ETHEL DIALOGUE PASS" in result.stdout, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
