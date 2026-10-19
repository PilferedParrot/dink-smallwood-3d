"""Review regression gates for non-destructive editing and file recovery."""
from pathlib import Path
import os
import subprocess
ROOT=Path(__file__).resolve().parents[1]

def test_slot_mutations_collision_priority_and_backup(tmp_path):
    env=dict(os.environ, XDG_DATA_HOME=str(tmp_path/'data'),XDG_CONFIG_HOME=str(tmp_path/'config'),XDG_CACHE_HOME=str(tmp_path/'cache'))
    godot=os.environ.get('GODOT',str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
    r=subprocess.run(['flock',str(Path.home()/'.local/state/dink-godot.lock'),'timeout','60s','nice','-n','10','xvfb-run','-a',godot,'--headless','--audio-driver','Dummy','--path',str(ROOT/'game'),'--script',str(ROOT/'tests/input_binding_mutations_test.gd')],env=env,text=True,capture_output=True)
    assert r.returncode==0 and 'MUTATION REVIEW PASS' in r.stdout and 'SCRIPT ERROR' not in r.stdout+r.stderr,r.stdout+r.stderr
