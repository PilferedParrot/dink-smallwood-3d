"""Native layout/focus census plus real-input settings persistence."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
LOCK = Path.home()/'.local/state/dink-godot.lock'


def launch(profile, script, *args, deadline=300, rendered=False):
    env = dict(os.environ, XDG_DATA_HOME=str(profile/'data'), XDG_CONFIG_HOME=str(profile/'config'),
               XDG_CACHE_HOME=str(profile/'cache'), LIBGL_ALWAYS_SOFTWARE='1', GALLIUM_DRIVER='llvmpipe', LP_NUM_THREADS='2')
    return subprocess.run(['flock', str(LOCK), 'timeout', '--kill-after=5s', str(deadline),
        'nice', '-n', '10', 'xvfb-run', '-a', GODOT, *([] if rendered else ['--headless']), '--audio-driver', 'Dummy',
        '--fixed-fps', '1000', '--path', str(ROOT/'game'), '--script', str(ROOT/'tests'/script), '--', *args],
        cwd=ROOT, env=env, text=True, capture_output=True)


def test_every_text_surface_at_each_size_and_font(tmp_path):
    result = launch(tmp_path, 'text_accessibility_test.gd')
    assert result.returncode == 0 and 'TEXT ACCESSIBILITY PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_text_options_persist_across_process_restart(tmp_path):
    for phase in ['write','read']:
        result = launch(tmp_path, 'text_settings_test.gd', phase, deadline=90)
        assert result.returncode == 0 and 'TEXT SETTINGS PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_held_text_and_readable_marks_clear_hud_at_each_size_and_font(tmp_path):
    result = launch(tmp_path, 'viewmodel_text_test.gd', deadline=180)
    assert result.returncode == 0 and 'VIEWMODEL TEXT PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_competing_focus_reflow_and_canceled_layout_waits(tmp_path):
    result = launch(tmp_path, 'focus_reflow_test.gd', deadline=90)
    assert result.returncode == 0 and 'FOCUS REFLOW PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_focused_actions_are_whole_from_first_drawn_frame(tmp_path):
    result = launch(tmp_path, 'focus_draw_test.gd', deadline=300, rendered=True)
    assert result.returncode == 0 and 'FOCUS DRAW PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
