"""make_entity routes ground_detail before solids.handles; the order is only safe if no entity is claimed by both."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))


def test_no_source_entity_is_claimed_by_both_ground_detail_and_solids(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    result = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", "game",
                             "--script", str(ROOT / "tests/ground_detail_solids_census_test.gd")],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in out, out
    assert "GROUND DETAIL SOLIDS CENSUS PASS" in out and "both=0" in out, out
