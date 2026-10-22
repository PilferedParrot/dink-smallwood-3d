"""Exercise actual F9 input and renderer in an isolated profile."""
import os
import re
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
GODOT=os.environ.get('GODOT',str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64'))
def project_version(text=None):
    # game/project.godot is the version's source of truth (config/version), never a copy in a test.
    text=text if text is not None else (ROOT/'game/project.godot').read_text()
    return re.search(r'^config/version="([^"]+)"',text,re.M).group(1)
def run_report(tmp_path,expected):
    env=dict(os.environ,XDG_DATA_HOME=str(tmp_path/'data'),XDG_CONFIG_HOME=str(tmp_path/'config'),XDG_CACHE_HOME=str(tmp_path/'cache'),LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='6',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
    env.pop('WAYLAND_DISPLAY',None)
    source=['--main-pack',env['BUG_REPORT_PACK']] if env.get('BUG_REPORT_PACK') else ['--path','game']
    return subprocess.run(['nice','-n','10','xvfb-run','-a','-s','-screen 0 1280x720x24',GODOT,'--audio-driver','Dummy','--resolution','960x540',*source,'--script',str(ROOT/'tests/fps_bug_report_test.gd'),'--','--expect-version='+expected],cwd=ROOT,env=env,text=True,capture_output=True,timeout=90)
def test_version_is_parsed_from_project_godot():
    assert project_version('[application]\nconfig/version="9.8.7"\n')=='9.8.7'
    assert project_version()!='0.3.2'
def test_report_rejects_a_mutated_version(tmp_path):
    # Must-fail control: the same report run against a wrong version string is red.
    run=run_report(tmp_path,project_version()+'-mutant')
    assert run.returncode!=0 and 'FPS BUG REPORT PASS' not in run.stdout and 'carries the shipped version' in run.stdout+run.stderr and 'SCRIPT ERROR' not in run.stderr,run.stdout+run.stderr
def test_f9_saves_rendered_local_report_and_actual_input(tmp_path):
    run=run_report(tmp_path,project_version())
    source=['--main-pack',os.environ['BUG_REPORT_PACK']] if os.environ.get('BUG_REPORT_PACK') else ['--path','game']
    env=dict(os.environ,XDG_DATA_HOME=str(tmp_path/'data'),XDG_CONFIG_HOME=str(tmp_path/'config'),XDG_CACHE_HOME=str(tmp_path/'cache'),LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='6',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
    assert run.returncode==0 and 'FPS BUG REPORT PASS' in run.stdout and 'SCRIPT ERROR' not in run.stderr,run.stdout+run.stderr
    path=Path(next(line.split('=',1)[1] for line in run.stdout.splitlines() if line.startswith('REPORT_PATH=')))
    for mode in ['snapshot','inputs']:
        replay=subprocess.run(['nice','-n','10',GODOT,'--headless','--audio-driver','Dummy',*source,'--script',str(ROOT/'tools/bug_report_replay.gd'),'--','--report='+str(path),'--mode='+mode],cwd=ROOT,env=env,text=True,capture_output=True,timeout=90)
        assert replay.returncode==0 and 'BUG REPORT REPLAY' in replay.stdout and 'SCRIPT ERROR' not in replay.stderr,replay.stdout+replay.stderr
