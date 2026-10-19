"""Binding class gates use physical events, independent process restarts and isolated profiles."""
from pathlib import Path
import os
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
LOCK = Path.home()/'.local/state/dink-godot.lock'
LOCK.parent.mkdir(parents=True, exist_ok=True)


def run(tmp_path, phase, *extra):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    result = subprocess.run(['flock',str(LOCK),'timeout','60s','nice','-n','10','xvfb-run','-a',GODOT,'--headless','--audio-driver','Dummy',
        '--path',str(ROOT/'game'),'--script',str(ROOT/'tests/input_bindings_test.gd'),
        '--','--phase='+phase,*extra], env=env, capture_output=True, text=True)
    return result


def test_every_action_rebinds_persists_restarts_and_rejects_old_input(tmp_path):
    for phase in ['write','read']:
        result = run(tmp_path,phase)
        assert result.returncode == 0 and 'BINDINGS PASS '+phase in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
    assert 'TABLE_ROWS=' in result.stdout


def test_binding_robustness_and_transactional_conflicts(tmp_path):
    result = run(tmp_path,'robustness')
    assert result.returncode == 0 and 'BINDINGS PASS robustness' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_inventory_has_one_binding_owner():
    """Broad static census; serialization/pointer handling is not binding lookup."""
    for path in (ROOT/'game/scripts').glob('*.gd'):
        if path.name == 'input_bindings.gd':
            continue
        source = path.read_text()
        assert not re.search(r'InputMap\.(action_add_event|add_action|action_erase_event)',source), path
        assert not re.search(r'\b(KEY_|JOY_BUTTON_|MOUSE_BUTTON_)\w+',source), path
        if path.name != 'bug_report_recorder.gd':
            assert not re.search(r'\.(?:physical_keycode|keycode|button_index)\b',source), path
    ui = (ROOT/'game/scripts/game_ui.gd').read_text()
    assert 'event.axis ==' not in ui
    for stale in ['WASD  Move','WASD move','Talk: E','Continue   ·   Enter','Arrows  Choose']:
        assert stale not in ui


def test_attack_dispatch_survives_process_restart(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    for phase in ['write','read']:
        result = subprocess.run(['flock',str(LOCK),'timeout','30s','nice','-n','10','xvfb-run','-a',GODOT,'--headless','--audio-driver','Dummy',
            '--path',str(ROOT/'game'),'--script',str(ROOT/'tests/input_attack_restart_test.gd'),
            '--',phase],env=env,capture_output=True,text=True)
        assert result.returncode == 0 and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
    assert 'ATTACK RESTART PASS' in result.stdout


def test_fps_consumers_follow_persisted_bindings(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    for phase in ['write','read']:
        result = subprocess.run(['flock',str(LOCK),'timeout','90s','nice','-n','10',
            'xvfb-run','-a',GODOT,'--headless','--audio-driver','Dummy',
            '--path',str(ROOT/'game'),'--script',str(ROOT/'tests/input_gameplay_test.gd'),
            '--',phase],env=env,capture_output=True,text=True)
        assert result.returncode == 0 and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
    assert 'FPS REMAP PASS' in result.stdout
