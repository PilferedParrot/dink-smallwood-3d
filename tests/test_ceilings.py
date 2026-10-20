"""Local donors and native density; shadow-off source-camera cutaway cannot excuse a wall change.

Packed eye-level sheets remain the visual gate. This audit verifies all six
box faces through the actual shader's orthogonal world-coordinate projection,
actual emitted texture bytes and scale uniforms, not screenshots or labels alone.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from PIL import Image
from tools.ceiling_donors import ROOT, NOT_ROOMS, derive, validate_donor
from tools.audit_ceilings import audit, controls

FIXTURES=ROOT/'tests/fixtures/ceilings'


def _native(folder, *arguments, deadline=600):
    godot=os.environ.get('GODOT') or shutil.which('godot') or str(Path.home()/'.local/bin/Godot_v4.6.1-stable_linux.x86_64')
    env={k:v for k,v in os.environ.items() if k!='WAYLAND_DISPLAY'}
    env.update(XDG_DATA_HOME=str(folder/'profile/data'),XDG_CONFIG_HOME=str(folder/'profile/config'),XDG_CACHE_HOME=str(folder/'profile/cache'))
    source=['--path',str(ROOT/'game')]
    if os.environ.get('DINK_CEILING_PACK'):source+=['--main-pack',os.environ['DINK_CEILING_PACK']]
    command=['nice','-n','10','xvfb-run','-a','-s','-screen 0 1280x800x24',godot,'--audio-driver','Dummy','--resolution','1280x800',*source,'--script',str(ROOT/'tests/ceiling_capture.gd'),'--','--out-dir='+str(folder),*arguments]
    result=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=deadline)
    output=result.stdout+result.stderr
    assert result.returncode==0 and 'SCRIPT ERROR' not in output and 'Assertion failed' not in output and 'CEILING CAPTURE DONE' in output,output[-8000:]


def test_all_indoor_screens_have_room_evidence_and_local_donors():
    w=json.loads((ROOT/'game/data/world.json').read_text());s=json.loads((ROOT/'game/data/sequences.json').read_text())['sequences'];f=json.loads((ROOT/'game/data/interior.json').read_text())
    expected=derive(w,s,f);actual=json.loads((ROOT/'game/data/ceilings.json').read_text())
    assert actual==expected
    assert set(actual['rooms'])=={n for n,r in w['screens'].items() if r['indoor']}
    assert len(actual['rooms'])==74
    assert {int(n) for n,r in actual['rooms'].items() if not r['room']}==set(NOT_ROOMS)
    for n,r in actual['rooms'].items():
        for role in ('ceiling','beam'):
            if r.get(role):
                assert validate_donor(r[role],w['screens'][n],s,f)
                # Integral numeric arrays survive Godot JSON as floats.
                numeric=json.loads(json.dumps(r[role]),parse_int=float)
                assert validate_donor(numeric,w['screens'][n],s,f)
        if r['kind'] in ('cave','masonry'):assert r['beam'] is None
        if not r['room']:assert r['follow_up']=='house ceiling over a screen with no room'


def test_emitted_overhead_provenance_scale_and_adversarial_controls(tmp_path):
    _native(tmp_path,'--audit-only')
    result=audit(tmp_path)
    assert result['rooms']==74 and result['box_faces']>0 and not result['failures'],result
    assert controls(tmp_path)
    base=json.loads((FIXTURES/'manifest.json').read_text())['baseline_overhead_counts']
    for r in json.loads((tmp_path/'overheads.json').read_text()):
        assert r['hidden']+r['removed_beams']==base[str(r['screen'])]


def test_original_camera_cutaway_is_byte_unchanged_and_can_fail(tmp_path):
    manifest=json.loads((FIXTURES/'manifest.json').read_text())
    actual=tmp_path/'actual';_native(actual,'--originals',deadline=600)
    for name,expected in manifest['frames'].items():
        after=Image.open(actual/name).convert('RGB')
        assert list(after.size)==expected['size']
        assert hashlib.sha256(after.tobytes()).hexdigest()==expected['rgb_sha256'],name
    # Physical look-alike red: change a wall in the real rendered scene. The
    # overhead cutaway must neither hide it nor grant it an allowed mask.
    control=tmp_path/'wall-control';_native(control,'--originals','--screens=1','--wall-control',deadline=600)
    assert hashlib.sha256(Image.open(control/'1.png').convert('RGB').tobytes()).hexdigest()!=manifest['frames']['1.png']['rgb_sha256']
