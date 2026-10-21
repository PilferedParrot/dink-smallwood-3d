#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Audit emitted overhead textures, room domain, native scale and repeat edges.

This rejects a flat material, a stretched native donor, exterior look-alikes,
and an unreflected crop with a colour jump at its repeat boundary. It cannot
judge the aesthetic visibility of mirror symmetry or the suitability of a
physically inferred ceiling; inspect the packed sheets for those.
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import numpy as np
from PIL import Image
try:
    from .ceiling_donors import ROOT, reflected, validate_donor, tile_arrangement, mirror_score
except ImportError:
    from ceiling_donors import ROOT, reflected, validate_donor, tile_arrangement, mirror_score


def audit_face(face, room, screen, sequences, fits, folder, image_override=None):
    failures=[]
    if not face['textured']:
        return ['untextured']
    role=face['role'];donor=face['donor']
    if donor != room.get(role) or not validate_donor(donor,screen,sequences,fits):
        failures.append('source-domain')
    if abs(float(face['metres_per_pixel'])-0.025)>1e-8:
        failures.append('density')
    x,y,w,h=map(int,donor['rect'])
    tiled=donor.get('mode')=='authored-tiles'
    if face['tile_pixels'] != ([w,h] if tiled else [2*w,2*h]):failures.append('tile-density')
    if face.get('world_origin',[0,0,0]) != donor.get('world_origin',[0,0,0]):failures.append('projection-origin')
    shader=face['shader']
    for term in ('world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;',
                 'world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);',
                 'vec3 p = world_position - world_origin;',
                 'vec2 uv = metres / (metres_per_pixel * tile_pixels);',
                 'texture(source_texture, uv).rgb',
                 'p.zx : p.xz',
                 'metres = p.zy', 'metres = p.xy'):
        if term not in shader:failures.append('projection');break
    expected_filter='filter_linear_mipmap' if donor['filter']=='wall-plaster' else 'filter_nearest_mipmap'
    if expected_filter not in shader:failures.append('wall-filter')
    if tiled:
        expected=tile_arrangement(donor['tiles'])
    else:
        source=Image.open(folder/face['filtered_source'] if donor['filter']=='wall-plaster' else ROOT/'game'/donor['path']).convert('RGBA')
        crop=np.asarray(source)[y:y+h,x:x+w]
        expected=reflected(crop)
    actual=np.asarray(Image.open(folder/face['texture']).convert('RGBA')) if image_override is None else image_override
    if actual.shape != expected.shape or not np.array_equal(actual,expected):failures.append('texel-provenance')
    if tiled and actual.shape==expected.shape:
        if mirror_score(actual)>mirror_score(expected)+1e-8:failures.append('synthetic-mirror')
    if not tiled and actual.shape==expected.shape:
        joins=[np.max(np.abs(actual[:,0].astype(int)-actual[:,-1].astype(int))),
               np.max(np.abs(actual[0].astype(int)-actual[-1].astype(int))),
               np.max(np.abs(actual[:,w-1].astype(int)-actual[:,w].astype(int))),
               np.max(np.abs(actual[h-1].astype(int)-actual[h].astype(int)))]
        if max(joins)>0:failures.append('repeat-seam')
    return sorted(set(failures))


def audit(folder):
    data=json.loads((ROOT/'game/data/ceilings.json').read_text())
    world=json.loads((ROOT/'game/data/world.json').read_text())['screens']
    sequences=json.loads((ROOT/'game/data/sequences.json').read_text())['sequences']
    fits=json.loads((ROOT/'game/data/interior.json').read_text())
    records=json.loads((folder/'overheads.json').read_text())
    assert {r['screen'] for r in records}=={int(n) for n in data['rooms']}
    failures=[];faces=0;filtered=0
    for r in records:
        n=str(r['screen']);room=data['rooms'][n]
        assert r['hidden']+r['removed_beams']==r['baseline_expected']
        if not room['room']:
            assert all(not f['textured'] for f in r['faces'])
            continue
        expected_roles=['ceiling']+(['beam']*(r['baseline_expected']-1) if room.get('beam') else [])
        assert [f['role'] for f in r['faces']]==expected_roles
        for f in r['faces']:
            errors=audit_face(f,room,world[n],sequences,fits,folder)
            if errors:failures.append({'screen':int(n),'role':f['role'],'errors':errors})
            faces+=6;filtered+=f['donor']['filter']=='wall-plaster'
    return dict(rooms=len(records),box_faces=faces,filtered_material_instances=filtered,failures=failures)


def controls(folder):
    data=json.loads((ROOT/'game/data/ceilings.json').read_text());world=json.loads((ROOT/'game/data/world.json').read_text())['screens'];seq=json.loads((ROOT/'game/data/sequences.json').read_text())['sequences'];fits=json.loads((ROOT/'game/data/interior.json').read_text())
    records=json.loads((folder/'overheads.json').read_text())
    r=next(r for r in records if r['screen']==1);face=next(f for f in r['faces'] if f['role']=='beam');room=data['rooms']['1']
    def check(f,image=None):return audit_face(f,room,world['1'],seq,fits,folder,image)
    assert check(face)==[]
    flat=copy.deepcopy(face);flat['textured']=False
    stretched=copy.deepcopy(face);stretched['metres_per_pixel']*=2
    exterior=copy.deepcopy(face);exterior['donor']['path']='assets/graphics/outside/home/home-01.png'
    exterior['donor']['filter']='authored'
    # Domain validation fails before a source file is read; use a real exterior
    # tile image and valid rectangle so a bogus path is never the discriminant.
    exterior['donor']['path']='assets/tiles/ts02.png';exterior['donor']['rect']=[0,0,50,50]
    exterior['texture']=face['texture']
    # Look-alike control: the SAME valid authored pixels, at native density,
    # tiled directly rather than reflected. No invented seam colour.
    x,y,w,h=map(int,face['donor']['rect'])
    crop=np.asarray(Image.open(ROOT/'game'/face['donor']['path']).convert('RGBA'))[y:y+h,x:x+w]
    seam=np.tile(crop,(2,2,1))
    # A tiled natural donor has valid native source pixels and native scale,
    # but must not acquire reflected 50px kaleidoscope structure.
    rock_record=next(r for r in records if r['screen']==69)
    rock=rock_record['faces'][0]
    authored=tile_arrangement(rock['donor']['tiles'])
    # Choose an actually placed, nonconstant rock-field cell from the map.
    cell=authored[50:100,100:150]
    kaleidoscope=np.tile(reflected(cell),(4,6,1))
    natural=audit_face(rock,data['rooms']['69'],world['69'],seq,fits,folder,kaleidoscope)
    result={
        'flat':check(flat), 'stretched-source':check(stretched),
        'exterior-source':check(exterior), 'repeat-edge':check(face,seam),
        'mirrored-natural-tile':natural,
    }
    assert 'untextured' in result['flat']
    assert 'density' in result['stretched-source']
    assert 'source-domain' in result['exterior-source']
    assert 'repeat-seam' in result['repeat-edge']
    assert 'synthetic-mirror' in result['mirrored-natural-tile']
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('folder',type=Path);p.add_argument('--controls',action='store_true');a=p.parse_args()
    result=controls(a.folder) if a.controls else audit(a.folder)
    print(json.dumps(result,indent=2));return int(not a.controls and bool(result['failures']))

if __name__=='__main__':raise SystemExit(main())
