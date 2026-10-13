"""Measure actual UI geometry and startup pixels, with keyboard menu actions.

The geometry fixture skips story progression explicitly. The capture regression
launches the game's existing --capture mode, which also skips source dialogue.
Exported normal-progression replay evidence is recorded separately.
"""
import os
import shutil
import subprocess
from pathlib import Path

import pytest
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT") or shutil.which("godot") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
pytestmark = pytest.mark.skipif(not Path(GODOT).is_file(), reason="Godot unavailable")


def run_godot(args, tmp_path, rendered=False):
    if rendered and not shutil.which("xvfb-run"):
        pytest.skip("xvfb-run unavailable")
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        env[key] = str(tmp_path / folder)
    project = os.environ.get("UI_HEIGHT_GAME", str(ROOT / "game"))
    command = [GODOT, "--audio-driver", "Dummy", "--resolution", "1280x800",
               "--path", project, *args]
    if rendered:
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24", *command]
    else:
        command.insert(1, "--headless")
    result = subprocess.run(
        ["nice", "-n", "10", *command],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, result.stderr
    return result


def test_wrapped_panels_shrink_across_text_width_and_input_transitions(tmp_path):
    result = run_godot(["--script", str(ROOT / "tests/ui_wrapped_height_test.gd")], tmp_path)
    assert "UI WRAPPED HEIGHT PASS" in result.stdout, result.stdout + result.stderr


def test_startup_capture_notification_leaves_the_world_visible(tmp_path):
    path = tmp_path / "capture.png"
    run_godot(["--", "--capture=" + str(path)], tmp_path, rendered=True)
    image = Image.open(path).convert("RGB")
    assert image.size == (1280, 800)
    # Find the plaque by its gold border, independent of its anchored position.
    gold = np.max(np.abs(np.asarray(image).astype(int) - (255, 220, 121)), axis=2) <= 2
    horizontal = []
    for y, row in enumerate(gold):
        xs = np.flatnonzero(row)
        for run in np.split(xs, np.flatnonzero(np.diff(xs) > 1) + 1):
            if len(run) >= image.width * 0.4:
                horizontal.append((int(run[0]), int(run[-1]), y))
    rectangles = []
    for i, (left, right, top) in enumerate(horizontal):
        for other_left, other_right, bottom in horizontal[i + 1:]:
            if (left, right) != (other_left, other_right) or bottom <= top:
                continue
            if gold[top:bottom + 1, left].all() and gold[top:bottom + 1, right].all():
                rectangles.append((left, top, right, bottom))
    assert len(rectangles) == 1, "The notification must have all four border edges inside the frame"
    left, top, right, bottom = rectangles[0]
    ink_rows = np.flatnonzero(gold[top + 1:bottom, left + 1:right].any(axis=1))
    assert len(ink_rows), "The plaque contains its gold notification text"
    ink_height = int(ink_rows[-1] - ink_rows[0] + 1)
    # Actual glyph ink omits font ascent/descent whitespace. Allow that
    # whitespace plus the designed 10px top/bottom margins, not a dialogue cap.
    assert bottom - top + 1 <= ink_height * 1.5 + 20 + 2, "Notification backing exceeds its own single-line content"
