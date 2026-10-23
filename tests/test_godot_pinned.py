"""tests/godot_pinned is what makes every launch of the suite silent, off unleased GPUs and out of the real profile."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

WRAPPER = Path(__file__).resolve().parent / "godot_pinned"


@pytest.fixture
def fake_engine(tmp_path):
    """A stand-in for Godot that prints its argv and environment as JSON."""
    engine = tmp_path / "godot"
    engine.write_text(f"#!{sys.executable}\nimport json, os, sys\nprint(json.dumps([sys.argv[1:], dict(os.environ)]))\n")
    engine.chmod(0o755)
    return engine


def launch(fake_engine, tmp_path, *args, **extra):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("__GLX", "__NV", "VK_", "DRI_", "ROOM_GPU"))}
    env.update(GODOT_REAL=str(fake_engine), XDG_DATA_HOME=str(tmp_path / "d"), XDG_CONFIG_HOME=str(tmp_path / "c"),
               XDG_CACHE_HOME=str(tmp_path / "k"), PULSE_SERVER="unix:/run/user/1000/pulse/native",
               VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json", DRI_PRIME="1")
    env.update(extra)
    done = subprocess.run([str(WRAPPER), *args], env=env, capture_output=True, text=True)
    out = json.loads(done.stdout) if done.returncode == 0 else [None, None]
    return done, out[0], out[1]


def test_audio_is_dummy_right_after_the_executable_and_before_any_separator(fake_engine, tmp_path):
    done, argv, env = launch(fake_engine, tmp_path, "--headless", "--path", "g", "--", "--audio-driver", "Pulse")
    assert done.returncode == 0, done.stderr
    assert argv[:2] == ["--audio-driver", "Dummy"] and argv.count("--audio-driver") == 2  # the user's one after `--` is theirs
    assert env["PULSE_SERVER"] == "unix:/nonexistent" and env["PIPEWIRE_REMOTE"] == "nonexistent"


def test_a_given_dummy_is_kept_once_and_another_driver_is_refused(fake_engine, tmp_path):
    done, argv, _ = launch(fake_engine, tmp_path, "--headless", "--audio-driver", "Dummy")
    assert argv == ["--headless", "--audio-driver", "Dummy"]
    done, argv, _ = launch(fake_engine, tmp_path, "--headless", "--audio-driver", "PulseAudio")
    assert done.returncode == 125 and argv is None and "only Dummy is silent" in done.stderr


def test_without_a_lease_vulkan_is_lavapipe_and_opengl_is_mesa_software(fake_engine, tmp_path):
    done, _, env = launch(fake_engine, tmp_path, "--headless")
    assert env["VK_ICD_FILENAMES"] == env["VK_DRIVER_FILES"] == "/usr/share/vulkan/icd.d/lvp_icd.json"
    assert env["__GLX_VENDOR_LIBRARY_NAME"] == "mesa" and env["LIBGL_ALWAYS_SOFTWARE"] == "1"
    assert "DRI_PRIME" not in env and "lavapipe" in done.stderr


def test_a_stray_lease_variable_alone_does_not_count_as_a_lease(fake_engine, tmp_path):
    _, _, env = launch(fake_engine, tmp_path, "--headless", ROOM_GPU_UUID="GPU-not-in-a-scope")
    assert env["VK_ICD_FILENAMES"].endswith("lvp_icd.json")


def test_homes_must_be_absolute_and_outside_the_real_profile(fake_engine, tmp_path):
    done, _, _ = launch(fake_engine, tmp_path, "--headless", XDG_DATA_HOME="relative/dir")
    assert done.returncode == 125 and "XDG_DATA_HOME" in done.stderr
    done, _, _ = launch(fake_engine, tmp_path, "--headless", XDG_CONFIG_HOME=str(Path.home() / ".config/godot"))
    assert done.returncode == 125 and "real Godot profile" in done.stderr


def test_every_launch_is_recorded_when_a_log_is_asked_for(fake_engine, tmp_path):
    log = tmp_path / "launches.log"
    launch(fake_engine, tmp_path, "--headless", DINK_GODOT_LAUNCH_LOG=str(log))
    assert log.read_text().startswith("godot-pinned pid=") and "audio Dummy" in log.read_text()


def test_this_run_launches_through_the_wrapper():
    assert Path(os.environ["GODOT"]) == WRAPPER and Path(os.environ["GODOT_REAL"]).name != "godot_pinned"


def test_a_windowed_launch_outside_xvfb_is_refused_and_headless_drops_the_display(fake_engine, tmp_path):
    # The class behind 2026-10-23: a suite started by systemd inherited DISPLAY=:0 and windowed tests drew on the user's screen.
    done, _, _ = launch(fake_engine, tmp_path, "--path", "g", DISPLAY=":0")
    assert done.returncode == 125 and "windowed launch" in done.stderr
    done, _, _ = launch(fake_engine, tmp_path, "--path", "g", DISPLAY=":99", XAUTHORITY="/home/u/.Xauthority")
    assert done.returncode == 125
    done, _, _ = launch(fake_engine, tmp_path, "--path", "g", DISPLAY=":0", XAUTHORITY="/tmp/xvfb-run.abc/Xauthority")
    assert done.returncode == 125  # :0 is never an xvfb of ours
    done, argv, env = launch(fake_engine, tmp_path, "--path", "g", DISPLAY=":99", XAUTHORITY="/tmp/xvfb-run.abc/Xauthority", WAYLAND_DISPLAY="wayland-0")
    assert done.returncode == 0 and env["DISPLAY"] == ":99" and "WAYLAND_DISPLAY" not in env
    done, argv, env = launch(fake_engine, tmp_path, "--headless", "--path", "g", DISPLAY=":0", WAYLAND_DISPLAY="wayland-0")
    assert done.returncode == 0 and "DISPLAY" not in env and "WAYLAND_DISPLAY" not in env
