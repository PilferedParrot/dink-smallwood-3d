"""Controls UI gates: physical input only for navigation, capture, swaps and recovery."""
from pathlib import Path
import os
import subprocess
import pytest

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
LOCK = Path.home()/'.local/state/dink-godot.lock'


def run(profile, device, phase):
    env = dict(os.environ, XDG_DATA_HOME=str(profile/'data'),
               XDG_CONFIG_HOME=str(profile/'config'), XDG_CACHE_HOME=str(profile/'cache'))
    return subprocess.run(['flock',str(LOCK),'timeout','120s','nice','-n','10','xvfb-run','-a',GODOT,
        '--headless','--audio-driver','Dummy','--path',str(ROOT/'game'),
        '--script',str(ROOT/'tests/controls_page_test.gd'),'--','--device='+device,'--phase='+phase],
        env=env,capture_output=True,text=True)


@pytest.mark.parametrize('device',['keyboard','mouse','pad'])
def test_each_device_navigates_all_groups_captures_and_cancels(tmp_path, device):
    result = run(tmp_path,device,'navigation')
    assert result.returncode == 0 and 'CONTROLS PASS '+device+' navigation' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


@pytest.mark.parametrize('device',['keyboard','mouse','pad'])
def test_device_only_remapping_swap_cancel_reset_and_restart(tmp_path, device):
    for phase in ['write','read']:
        result = run(tmp_path,device,phase)
        assert result.returncode == 0 and 'CONTROLS PASS '+device+' '+phase in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_every_menu_row_rebinds_and_escape_pointer_recover(tmp_path):
    result = run(tmp_path,'mouse','recovery')
    assert result.returncode == 0 and 'CONTROLS PASS mouse recovery' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_add_remove_reset_reserved_device_safety_and_timeout(tmp_path):
    result = run(tmp_path,'mouse','edges')
    assert result.returncode == 0 and 'CONTROLS PASS mouse edges' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_all_registry_and_rendered_slot_labels_are_readable(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    result = subprocess.run(['flock',str(LOCK),'timeout','60s','nice','-n','10','xvfb-run','-a',GODOT,
        '--headless','--audio-driver','Dummy','--path',str(ROOT/'game'),
        '--script',str(ROOT/'tests/controls_labels_test.gd')],env=env,capture_output=True,text=True)
    assert result.returncode == 0 and 'CONTROLS LABELS PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr


def test_layout_keeps_slot_text_and_pinned_footer_inside_panel(tmp_path):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    result = subprocess.run(['flock',str(LOCK),'timeout','60s','nice','-n','10','xvfb-run','-a',GODOT,
        '--headless','--audio-driver','Dummy','--path',str(ROOT/'game'),
        '--script',str(ROOT/'tests/controls_layout_test.gd')],env=env,capture_output=True,text=True)
    assert result.returncode == 0 and 'CONTROLS LAYOUT PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
