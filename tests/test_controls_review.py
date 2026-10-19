"""Review regressions use physical input in an isolated UI-only fixture."""
import os
from pathlib import Path
import subprocess
import pytest
from test_controls_page import GODOT, LOCK, ROOT


@pytest.mark.parametrize('mode,large', [('pad',False),('keyboard',False),('layout',False),('layout',True),('dialogs',False)])
def test_controls_review_regressions(tmp_path, mode, large):
    env = dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),
               XDG_CONFIG_HOME=str(tmp_path/'config'), XDG_CACHE_HOME=str(tmp_path/'cache'))
    result = subprocess.run(['flock',str(LOCK),'timeout','30s','nice','-n','10','xvfb-run','-a',GODOT,
        '--headless','--audio-driver','Dummy','--path',str(ROOT/'game'),
        '--script',str(ROOT/'tests/controls_review_test.gd'),'--','--mode='+mode,
        *(['--1080'] if large else [])],env=env,capture_output=True,text=True)
    assert result.returncode == 0 and 'CONTROLS REVIEW PASS '+mode in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout+result.stderr
