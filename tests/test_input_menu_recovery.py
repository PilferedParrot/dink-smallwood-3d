"""Menu input recovery class and native keyboard/pad navigation gates."""
from pathlib import Path
import os
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"))
LOCK = Path.home() / ".local/state/dink-godot.lock"
LOCK.parent.mkdir(parents=True, exist_ok=True)


def run_phase(profile: Path, phase: str, device: str = "keyboard") -> None:
    env = dict(os.environ, XDG_DATA_HOME=str(profile / "data"),
               XDG_CONFIG_HOME=str(profile / "config"), XDG_CACHE_HOME=str(profile / "cache"))
    extra = [f"--phase={phase}", f"--device={device}"]
    if old_registry := os.environ.get("MENU_RECOVERY_REGISTRY"):
        extra.append(f"--registry={old_registry}")
    result = subprocess.run([
        "flock", str(LOCK), "timeout", "60s", "nice", "-n", "10",
        "xvfb-run", "-a", "-s", "-screen 0 1920x1080x24", GODOT,
        "--headless", "--rendering-method", "gl_compatibility",
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
        "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/input_menu_recovery_test.gd"),
        "--", *extra,
    ], env=env, capture_output=True, text=True)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and f"MENU RECOVERY PASS {phase} {device}" in output and "SCRIPT ERROR" not in output, output


def test_essential_menu_bindings_reject_device_loss_and_heal_persisted_data(tmp_path):
    run_phase(tmp_path, "class")


@pytest.mark.parametrize("device", ["keyboard", "pad"])
def test_native_menu_can_reach_and_activate_harness_reset_after_restart(tmp_path, device):
    run_phase(tmp_path, "prepare", device)
    run_phase(tmp_path, "recover", device)
    run_phase(tmp_path, "verify", device)
