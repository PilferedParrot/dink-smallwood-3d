"""Real-input regressions for FreeDink109.6 brain_keyboard.cpp:216-241."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
LOCK = Path.home() / ".local/state/dink-godot.lock"


def run_speech(tmp_path, script, *args, timeout=90):
    env = dict(os.environ, XDG_CONFIG_HOME=str(tmp_path / "config"),
               XDG_DATA_HOME=str(tmp_path / "data"), XDG_CACHE_HOME=str(tmp_path / "cache"),
               LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="1")
    result = subprocess.run(["flock", str(LOCK), "timeout", f"{timeout}s", "nice", "-n", "10",
                           "xvfb-run", "-a", GODOT, "--headless", "--audio-driver", "Dummy",
                           "--path", os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game")),
                           "--script", str(ROOT / "tests" / script), "--", *args],
                          cwd=ROOT, env=env, capture_output=True, text=True)
    (tmp_path / (script + "-" + "-".join(args).replace("/", "_") + ".log")).write_text(result.stdout + result.stderr)
    return result


def test_speech_waits_for_caller_without_freezing_input(tmp_path):
    result = run_speech(tmp_path, "speech_input_test.gd")
    assert result.returncode == 0 and "SPEECH INPUT PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
