import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_speaker_floor_and_top_remain_above_actual_dialogue_card(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    load = ["--main-pack", env["SPEAKER_CONTRACT_PACK"]] if env.get("SPEAKER_CONTRACT_PACK") else ["--path", "game"]
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", *load,
                             "--script", str(ROOT / "tests/speaker_occlusion_contract_test.gd"), "--quit-after", "1200"],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0 and "SPEAKER OCCLUSION CONTRACT PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
