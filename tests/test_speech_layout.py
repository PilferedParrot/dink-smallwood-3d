"""Real M/Enter input and all DinkC speech/card owners at both player sizes."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable")


@pytest.mark.parametrize("size", ["1280x800", "1920x1080"])
def test_speech_cards_leave_drawn_status_art_clear(tmp_path, size):
    env = dict(os.environ)
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                         ("XDG_CACHE_HOME", "cache")]:
        env[name] = str(tmp_path / folder)
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    args = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
            "--resolution", size, "--path", project,
            "--script", str(ROOT / "tests/speech_layout_test.gd"), "--"]
    if size == "1920x1080":
        args.append("--1080")
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0 and "SPEECH LAYOUT PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_every_source_speech_and_choice_literal_respects_card_bounds(tmp_path):
    env = dict(os.environ)
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                         ("XDG_CACHE_HOME", "cache")]:
        env[name] = str(tmp_path / folder)
    # This UI-only census measures settled layout, not speech timing. Fixed
    # steps remove headless real-time pacing for its complete source layout matrix.
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--fixed-fps", "1000", "--path", project,
         "--script", str(ROOT / "tests/speech_text_census_test.gd")], cwd=ROOT, env=env,
        capture_output=True, text=True, timeout=900)
    assert result.returncode == 0 and "SPEECH CENSUS PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_long_choice_prompts_open_first_without_changing_input_owners(tmp_path):
    env = dict(os.environ)
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                         ("XDG_CACHE_HOME", "cache")]:
        env[name] = str(tmp_path / folder)
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--fixed-fps", "1000",
         "--path", project, "--script", str(ROOT / "tests/choice_prompt_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0 and "CHOICE PROMPT PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_timed_speech_exposes_every_line_before_natural_expiry(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--fixed-fps", "12",
         "--path", project, "--script", str(ROOT / "tests/timed_reading_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=900)
    assert result.returncode == 0 and "TIMED READING PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_unreflowed_content_size_is_not_a_fit_for_the_whole_height(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--path", project,
         "--script", str(ROOT / "tests/text_scroll_fit_whole_height_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0 and "TEXT SCROLL FIT WHOLE HEIGHT PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_named_geometries_run_and_cards_over_six_lines_show_them_all(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path / "data"),
               XDG_CONFIG_HOME=str(tmp_path / "config"), XDG_CACHE_HOME=str(tmp_path / "cache"))
    project = os.environ.get("SPEECH_LAYOUT_GAME", str(ROOT / "game"))
    result = subprocess.run(
        ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy", "--path", project,
         "--script", str(ROOT / "tests/speech_card_lines_test.gd")],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
    assert result.returncode == 0 and "SPEECH CARD LINES PASS" in result.stdout and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr
