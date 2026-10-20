#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Derive inferred overhead donors from each room's own authored material.

No original ceiling is claimed. Native-scale reflection tiles remove colour
jumps without blending source colours. Fitted plaster uses the runtime wall's
existing Gaussian/row-trend filter BEFORE the crop/reflection, not a new filter.
"""
from __future__ import annotations
import argparse
import collections
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NOT_ROOMS = {85: 'fire field', 86: 'fire field', 133: 'blank dark screen',
             134: 'forest', 197: 'blank dark screen'}


def source_paths(screen, sequences):
    paths = []
    for e in screen['sprites']:
        frames = sequences.get(str(e['seq']), {}).get('frames', [])
        if 0 < e['frame'] <= len(frames):
            paths.append(frames[e['frame'] - 1]['path'])
    return paths


def derive(world, sequences, fits):
    rooms = {}
    for key, screen in world['screens'].items():
        if not screen.get('indoor'):
            continue
        n = int(key)
        paths = source_paths(screen, sequences)
        record = {
            'room': n not in NOT_ROOMS, 'inferred': True,
            # Concrete census evidence, independent of the donor choice. A
            # statue in stnwalls is a sprite source, not an enclosing wall;
            # the source picture decides whether these tiles enclose a room.
            'wall_sprite_sources': sorted({p for p in paths if '/innwalls/' in p or '/stnwalls/' in p}),
            'boundary_tiles': sorted({int(t['tile']) for i,t in enumerate(screen['tiles'][:96])
                                      if i//12 in (0,7) or i%12 in (0,11)}),
        }
        if n in NOT_ROOMS:
            record.update(kind='not-room', evidence=NOT_ROOMS[n],
                          follow_up='house ceiling over a screen with no room')
        else:
            counts = collections.Counter(p for p in paths if
                fits.get(p, {}).get('kind') == 'wall' and
                fits[p].get('cap', 0) > 0 and fits[p]['size'][0] >= 100)
            if counts:
                # Same deterministic room_stone selection as interior_solids.gd.
                path = min(counts, key=lambda p: (-counts[p], p))
                f = fits[path]
                record.update(kind='plaster-house', evidence='enclosing innwalls sprites',
                    # The central half of the plaster field excludes the
                    # drawn timber/end trims on some span sprites. Dimensions
                    # remain native pixels; this crop is never resized.
                    ceiling={'path': path, 'rect': [f['size'][0]//4, f['stone'][0], f['size'][0]//2, f['stone'][1]-f['stone'][0]], 'filter': 'wall-plaster'},
                    beam={'path': path, 'rect': [0, 90, f['size'][0], 10], 'filter': 'authored'})
            else:
                sheets = collections.Counter(t['tile']//128+1 for t in screen['tiles'])
                sheet = max((k for k in sheets if k in (37,39,40)), key=lambda k:sheets[k])
                # The original authored arrangement is itself the repeat unit.
                # Small reflected natural crops invent kaleidoscope structure.
                kind='cave' if sheet==40 else 'masonry'
                record.update(kind=kind,evidence=('enclosing rock tiles' if sheet==40 else 'enclosing masonry sprites or tiles'),
                    ceiling={'mode':'authored-tiles','rect':[0,0,600,400],
                             'tiles':[int(t['tile']) for t in screen['tiles'][:96]],
                             'filter':'authored','world_origin':[-7.5,0,-5]},beam=None)
        rooms[key]=record
    return {'source_pixels_per_metre':40,'repeat':{'plaster-house':'reflected-native-crop','cave/masonry':'authored-screen-tile-arrangement'},'rooms':rooms}


def reflected(crop):
    return np.concatenate((np.concatenate((crop,crop[:,::-1]),axis=1),
                           np.concatenate((crop[::-1],crop[::-1,::-1]),axis=1)),axis=0)


def validate_donor(record, screen, sequences, fits):
    """Domain check independent of room labels and emitted material tags."""
    if record.get('mode')=='authored-tiles':
        return record['rect']==[0,0,600,400] and record['world_origin']==[-7.5,0,-5] and record['tiles']==[int(t['tile']) for t in screen['tiles'][:96]] and len(record['tiles'])==96
    path=record['path']
    if any(int(v) != v for v in record['rect']):return False
    # Godot's JSON round trip emits numeric array elements as floats.
    x,y,w,h=map(int,record['rect'])
    paths=source_paths(screen,sequences)
    if path.startswith('assets/tiles/'):
        if path not in {f'assets/tiles/ts{t["tile"]//128+1:02}.png' for t in screen['tiles']}:
            return False
        # A rectangle must lie wholly within an actually placed source tile.
        allowed=any(x>=t['tile']%128%12*50 and x+w<=(t['tile']%128%12+1)*50 and
                    y>=t['tile']%128//12*50 and y+h<=(t['tile']%128//12+1)*50
                    for t in screen['tiles'] if f'assets/tiles/ts{t["tile"]//128+1:02}.png'==path)
    else:
        allowed=path in paths and ('/innwalls/' in path or '/stnwalls/' in path)
    if not allowed or min(w,h)<=0:
        return False
    im=np.asarray(Image.open(ROOT/'game'/path).convert('RGBA'))
    return x>=0 and y>=0 and x+w<=im.shape[1] and y+h<=im.shape[0] and bool((im[y:y+h,x:x+w,3]==255).all())


def tile_arrangement(tiles):
    """Original 12x8 tile placements, no painted sprites or filter changes."""
    out=np.zeros((400,600,4),dtype=np.uint8);cache={}
    for i,k in enumerate(tiles):
        k=int(k);sheet=k//128+1;cell=k%128
        if sheet not in cache:cache[sheet]=np.asarray(Image.open(ROOT/f'game/assets/tiles/ts{sheet:02}.png').convert('RGBA'))
        x=cell%12*50;y=cell//12*50
        out[i//12*50:(i//12+1)*50,i%12*50:(i%12+1)*50]=cache[sheet][y:y+50,x:x+50]
    return out


def mirror_score(rgba):
    """Fraction of exact reflected 50px tile pairs, excluding constant pairs.

    This detects manufactured small-tile reflection. Compare to the authored
    map's own score: authored symmetry is permitted rather than called a defect.
    """
    matches=[]
    for axis in (0,1):
        a=np.swapaxes(rgba,0,axis)
        for start in range(0,a.shape[0]-99,100):
            left=a[start:start+50];right=a[start+50:start+100][::-1]
            if np.any(left[...,:3]!=left.reshape(-1,4)[0,:3]):
                matches.append(float(np.all(left[...,:3]==right[...,:3],axis=2).mean()))
    return float(np.mean(matches)) if matches else 0.0


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,default=ROOT/'game/data/ceilings.json');args=ap.parse_args()
    world=json.loads((ROOT/'game/data/world.json').read_text());seq=json.loads((ROOT/'game/data/sequences.json').read_text())['sequences'];fits=json.loads((ROOT/'game/data/interior.json').read_text())
    data=derive(world,seq,fits)
    for n,r in data['rooms'].items():
        for role in ('ceiling','beam'):
            if r.get(role):assert validate_donor(r[role],world['screens'][n],seq,fits),(n,role,r[role])
    args.out.write_text(json.dumps(data,indent=1,sort_keys=True)+'\n')
    print(dict(collections.Counter(r['kind'] for r in data['rooms'].values())))

if __name__=='__main__':main()
