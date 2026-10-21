"""Sprint hold/toggle and attack repeat-while-held: real input, persisted across processes."""

from pathlib import Path
import os
import subprocess


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get(
    "GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
)
LOCK = Path.home() / ".local/state/dink-godot.lock"


def test_sprint_mode_and_attack_repeat_persist_and_behave(tmp_path):
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    env = dict(
        os.environ,
        XDG_DATA_HOME=str(tmp_path / "data"),
        XDG_CONFIG_HOME=str(tmp_path / "config"),
        XDG_CACHE_HOME=str(tmp_path / "cache"),
        LIBGL_ALWAYS_SOFTWARE="1",
    )
    for phase in ("write", "read"):
        result = subprocess.run(
            [
                "flock", str(LOCK), "timeout", "120s", "nice", "-n", "10",
                "xvfb-run", "-a", GODOT, "--headless", "--audio-driver", "Dummy",
                "--rendering-method", "gl_compatibility", "--path", str(ROOT / "game"),
                "--script", str(ROOT / "tests/input_hold_repeat_test.gd"), "--", phase,
            ],
            env=env, capture_output=True, text=True,
        )
        expected = f"HOLD REPEAT {phase.upper()} PASS"
        assert result.returncode == 0 and expected in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, (
            f"{phase} exit={result.returncode}\n{result.stdout}\n{result.stderr}"
        )
