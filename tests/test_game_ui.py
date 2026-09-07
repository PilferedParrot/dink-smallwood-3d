import subprocess
import os
import shutil
import pytest
from pathlib import Path


ROOT = Path(__file__).parents[1]
UI_SCRIPT = ROOT / "game" / "scripts" / "game_ui.gd"
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable; set GODOT")


def test_game_ui_parses_with_supported_godot():
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--check-only", "--script", "scripts/game_ui.gd"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_controller_can_navigate_and_activate_menu():
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", "game", "--script", str(ROOT / "tests" / "ui_controller_test.gd")],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0 and "SCRIPT ERROR" not in result.stderr, result.stdout + result.stderr


def test_modal_ui_consumes_pointer_events_and_has_focusable_controls():
    source = UI_SCRIPT.read_text()
    assert "root.mouse_filter = Control.MOUSE_FILTER_STOP" in source
    assert "overlay.mouse_filter = Control.MOUSE_FILTER_STOP" in source
    assert "button.focus_mode = Control.FOCUS_ALL" in source
    assert "child.call_deferred(\"grab_focus\")" in source


def test_controller_callbacks_bind_each_choice_and_setting_key():
    source = UI_SCRIPT.read_text()
    assert "_choose_dialogue.bind(i + 1)" in source
    assert "_setting_changed.bind(key)" in source
    assert "func():" not in source


def test_public_support_link_remains_in_credits():
    assert "Support PilferedParrot on Patreon ↗" in UI_SCRIPT.read_text()
