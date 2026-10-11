#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Classify current terrain-attributed hard pixels by source atlas pixels.

This is a static source-art audit. It separates obvious atlas water from flat
non-water surface (rock/cliff or shore) and keeps other source pixels uncertain.
It does not label these pixels as raised geometry.
"""
from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(ROOT / "tools"))
from rc5_hardness_census import CLIFF_SHEETS, WATER_SHEETS, image
from collision_map import tile_mask, rect_mask


def load_json(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as f:
        return json.load(f)


def run_mask(record: dict, category: int | None = None) -> np.ndarray:
    out = np.zeros((400, 640), dtype=bool)
    for y, x0, x1, label in record.get("classification_runs", []):
        if category is None or int(label) == category:
            out[int(y), int(x0):int(x1)] = True
    return out


def reachable_outdoor(world: dict, records: dict, native: dict, footprints: dict) -> dict[int, np.ndarray]:
    """Rebuild exact current static-warp reachability and its one-pixel boundary."""
    rows = (max(map(int, world["screens"])) + 31) // 32
    free = np.zeros((rows * 400, 32 * 600), dtype=bool)
    for key, fixture in records.items():
        n = int(key); oy = ((n - 1) // 32) * 400; ox = ((n - 1) % 32) * 600
        view = free[oy:oy+400, ox:ox+600]
        view[:] = True
        for y, a, b, label in fixture[0]["classification_runs"]:
            view[int(y), int(a)-20:int(b)-20] = False
    labels, count = ndimage.label(free)
    seed = labels[((439-1)//32)*400+390, ((439-1)%32)*600+323-20]
    if seed == 0:
        raise ValueError("static reachability seed is blocked")
    indoor_labels = {}
    next_tag = int(labels.max()) + 1
    for key, rec in native.get("indoor_collision", {}).items():
        n = int(key)
        fp = footprints.get(key, {})
        hard, _ = tile_mask(world, n, fp.get("revert", ()), fp.get("clear", ()))
        hard |= rect_mask(rec["hard_rects"], 4)
        for y, a, b in rec["footprint_runs"]:
            hard[int(y), int(a):int(b)] = True
        local, num = ndimage.label(~hard)
        local[local != 0] += next_tag - 1
        next_tag += num
        indoor_labels[key] = local

    def label_at(n, x, y):
        if not (20 <= x < 620 and 0 <= y < 400): return 0
        if str(n) in indoor_labels: return int(indoor_labels[str(n)][int(y), int(x)])
        if str(n) not in records: return 0
        return int(labels[((n-1)//32)*400+int(y), ((n-1)%32)*600+int(x)-20])

    edges = []
    for warp in native.get("static_warps", []):
        n = int(warp["screen"]); a, b, c, d = warp["trigger"]
        x0=max(20,int(np.ceil(a))); x1=min(620,int(np.ceil(c)))
        y0=max(0,int(np.ceil(b))); y1=min(400,int(np.ceil(d)))
        if x1 <= x0 or y1 <= y0: continue
        if str(n) in indoor_labels:
            sources=set(map(int,np.unique(indoor_labels[str(n)][y0:y1,x0:x1])))
        elif str(n) in records:
            oy=((n-1)//32)*400; ox=((n-1)%32)*600-20
            sources=set(map(int,np.unique(labels[oy+y0:oy+y1,ox+x0:ox+x1])))
        else: sources=set()
        sources.discard(0)
        target=label_at(int(warp["target"]),*warp["destination"])
        if target: edges.append((sources,target))
    reached={int(seed)}
    changed=True
    while changed:
        changed=False
        for sources,target in edges:
            if reached.intersection(sources) and target not in reached:
                reached.add(target); changed=True
    reachable=np.isin(labels,list(reached))
    result={}
    neighbor=ndimage.binary_dilation(reachable)
    for key in records:
        n=int(key); oy=((n-1)//32)*400; ox=((n-1)%32)*600
        boundary=np.zeros((400,640),bool)
        boundary[:,20:620]=neighbor[oy:oy+400,ox:ox+600]
        # Census boundaries include only classified effective-hard pixels.
        boundary &= run_mask(records[key][0])
        result[n]=boundary
    return result


def pixel_classes(tile_id: int, sheet: int, source_rgb: np.ndarray) -> np.ndarray:
    """Return water, shore_ground, flat_relief, or uncertain source-art labels."""
    r,g,b=(source_rgb[...,i].astype(float) for i in range(3))
    grass=(g>r*1.12)&(g>b*1.12)
    sea=(b>r*1.1)&(b>g*.85)
    labels=np.full(source_rgb.shape[:2],3,dtype=np.uint8) # uncertain
    if sheet in WATER_SHEETS:
        labels[sea]=0
        labels[~sea]=1 # non-blue shore/ground pixels in water source family
    elif sheet in CLIFF_SHEETS:
        labels[~grass]=2
    return labels


def classify(world: dict, census: dict, native: dict, footprints: dict) -> dict:
    if census.get("schema") != "rc5-hardness-census-1": raise ValueError("unexpected census schema")
    if census.get("phase") != "RC5": raise ValueError(f"expected RC5 current phase, got {census.get('phase')!r}")
    categories=census.get("categories", [])
    if "water_cliff_edge" not in categories: raise ValueError("census lacks water_cliff_edge category")
    cat = categories.index("water_cliff_edge")
    screens=census["screens"]
    reachable=reachable_outdoor(world,screens,native,footprints)
    total=collections.Counter(); by_sheet=collections.defaultdict(collections.Counter)
    by_tile=collections.defaultdict(collections.Counter); by_screen=collections.defaultdict(collections.Counter)
    reachable_counts=collections.Counter(); reachable_sheet=collections.defaultdict(collections.Counter)
    reachable_tile=collections.defaultdict(collections.Counter)
    source_kind=collections.defaultdict(collections.Counter)
    reachable_source_kind=collections.defaultdict(collections.Counter)
    for key,fixture in screens.items():
        n=int(key); tiles=world["screens"][key]["tiles"]
        full=run_mask(fixture[0],cat); near=full & reachable[n]
        total["full_hard_px"]+=int(full.sum()); total["reachable_boundary_px"]+=int(near.sum())
        screen_c=collections.Counter()
        for ti,t in enumerate(tiles[:96]):
            y0=(ti//12)*50; x0=20+(ti%12)*50
            tile_mask_px=full[y0:y0+50,x0:x0+50]
            if not tile_mask_px.any(): continue
            tile_id=int(t["tile"]); sheet=tile_id//128+1; cell=tile_id%128
            fp=footprints.get(key,{})
            is_custom=int(t.get("hard",0)) != 0 and ti not in set(map(int,fp.get("clear",()))) and ti not in set(map(int,fp.get("revert",())))
            owner="custom_hard" if is_custom else "default_hard"
            atlas=image(f"assets/tiles/ts{sheet:02d}.png")
            art=atlas[cell//12*50:cell//12*50+50,cell%12*50:cell%12*50+50,:3]
            labels=pixel_classes(tile_id,sheet,art)
            local=tile_mask_px
            localnear=near[y0:y0+50,x0:x0+50]
            family=f"ts{sheet:02d}"
            for name,idx in (("water",0),("shore_ground",1),("flat_relief",2),("uncertain",3)):
                cnt=int((local & (labels==idx)).sum())
                nearcnt=int((localnear & (labels==idx)).sum())
                if cnt:
                    total[name+"_full_hard_px"]+=cnt
                    source_kind[owner][name+"_full_hard_px"]+=cnt
                    by_sheet[family][name+"_full_hard_px"]+=cnt
                    by_tile[str(tile_id)][name+"_full_hard_px"]+=cnt
                    screen_c[name+"_full_hard_px"]+=cnt
                if nearcnt:
                    reachable_counts[name+"_boundary_px"]+=nearcnt
                    reachable_source_kind[owner][name+"_boundary_px"]+=nearcnt
                    reachable_sheet[family][name+"_boundary_px"]+=nearcnt
                    reachable_tile[str(tile_id)][name+"_boundary_px"]+=nearcnt
                    by_sheet[family][name+"_boundary_px"]+=nearcnt
                    by_tile[str(tile_id)][name+"_boundary_px"]+=nearcnt
        by_screen[str(n)].update(screen_c)
    expected_full=sum(int(f[0]["categories_px"]["water_cliff_edge"]) for f in screens.values())
    expected_boundary=int(census["walking_reachability"]["boundary_categories_px"]["water_cliff_edge"])
    for cls in ("water", "shore_ground", "flat_relief", "uncertain"):
        total.setdefault(cls+"_full_hard_px", 0)
        reachable_counts.setdefault(cls+"_boundary_px", 0)
    if total["full_hard_px"] != expected_full: raise ValueError(f"full class mismatch {total['full_hard_px']} != {expected_full}")
    if total["reachable_boundary_px"] != expected_boundary: raise ValueError(f"boundary class mismatch {total['reachable_boundary_px']} != {expected_boundary}")
    return {
        "schema":"rc5-terrain-report-1",
        "basis":{"phase":"RC5","census_basis":census["basis"],"method":"exact census category-5 classification runs; pixel atlas lookup; exact static warp reachability graph","no_render_or_gameplay_run":True},
        "category":"water_cliff_edge",
        "denominators":{"full_hard_category_px":expected_full,"reachable_boundary_category_px":expected_boundary,"historical_880441_note":"Historical figure has no phase/artifact provenance in this report. It is not substituted for either current denominator."},
        "classification":{"water":"pixel belongs to inspected water atlas family ts08/14/15/16 and matches blue/sea threshold b>1.1r and b>0.85g","shore_ground":"non-blue pixels in the inspected water atlas families, kept distinct from rock/cliff","flat_relief":"recognized cliff/rock atlas family ts02/03/04/05/06/07/24/25/26/29/30/31/32 and not green-grass","uncertain":"all remaining source atlas pixels; preserved as a separate class","geometry_limit":"All category-5 terrain contributions are rendered on the outdoor ground plane in the current renderer. This labels source texture, not raised geometry."},
        "totals":{**{k:int(v) for k,v in total.items()},**{k:int(v) for k,v in reachable_counts.items()}},
        "by_atlas_family":{k:{a:int(b) for a,b in sorted(v.items())} for k,v in sorted(by_sheet.items())},
        "reachable_boundary_by_atlas_family":{k:{a:int(b) for a,b in sorted(v.items()) if a.endswith("_boundary_px")} for k,v in sorted(reachable_sheet.items())},
        "by_tile_id":{k:{a:int(b) for a,b in sorted(v.items())} for k,v in sorted(by_tile.items(),key=lambda kv:int(kv[0]))},
        "reachable_boundary_by_tile_id":{k:{a:int(b) for a,b in sorted(v.items()) if a.endswith("_boundary_px")} for k,v in sorted(reachable_tile.items(),key=lambda kv:int(kv[0]))},
        "by_default_custom_tile_source":{k:{a:int(b) for a,b in sorted(v.items())} for k,v in sorted(source_kind.items())},
        "reachable_boundary_by_default_custom_tile_source":{k:{a:int(b) for a,b in sorted(v.items())} for k,v in sorted(reachable_source_kind.items())},
        "full_hard_by_screen":{k:{a:int(b) for a,b in sorted(v.items())} for k,v in sorted(by_screen.items(),key=lambda kv:int(kv[0]))},
    }


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--world",type=Path,required=True);p.add_argument("--census",type=Path,required=True)
    p.add_argument("--inventory",type=Path,required=True);p.add_argument("--out",type=Path,required=True)
    p.add_argument("--footprints",type=Path,required=True)
    a=p.parse_args(); world=load_json(a.world); census=load_json(a.census); native=load_json(a.inventory)
    footprints=load_json(a.footprints)["screens"]
    report=classify(world,census,native,footprints)
    report["input_sha256"]={str(q):hashlib.sha256(q.read_bytes()).hexdigest() for q in (a.world,a.footprints,a.census,a.inventory)}
    a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report["totals"],sort_keys=True))

if __name__=="__main__": main()
