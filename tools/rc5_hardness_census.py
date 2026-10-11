#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Pixel inventory of source/effective hardness and source-art attribution.

Uses the game's own renderer dispatch/seam inventory, collision_map's x-major
hard.dat decoder, and the prior forest ownership extraction. Attribution is
not a claim that projected art fills a ground volume. Every mask is retained
as exact row runs, including unresolved cells. No game data is changed.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

from collision_map import frame, poly_mask, rect_mask, tile_mask
from rc4_fir_stand_fit import source_canvas, forest_hardness, FOREST_CELLS

ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = ("nothing", "built_solid", "billboard_object", "sprite_wall", "tile_forest", "water_cliff_edge", "sprite_decoration")
# Inspected default-hard tile contact sheet, tmp/default-hard-tiles.png.
# Rocky/cliff/snow and sea/beach atlas families; grass pixels are excluded.
CLIFF_SHEETS = {2, 3, 4, 5, 6, 7, 24, 25, 26, 29, 30, 31, 32}
WATER_SHEETS = {8, 14, 15, 16}


@lru_cache(maxsize=None)
def image(path):
    return np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))


def runs(mask):
    """Exact [y,x0,x1) source-coordinate runs; no smoothing or downsampling."""
    out = []
    for y, row in enumerate(mask):
        edges = np.flatnonzero(np.diff(np.pad(row.astype(np.int16), (1, 1))))
        out.extend([y, int(a), int(b)] for a, b in edges.reshape(-1, 2))
    return out


def components(mask):
    labels, count = ndimage.label(mask)
    sizes = np.bincount(labels.ravel())
    boxes = ndimage.find_objects(labels)
    return [{"pixels": int(sizes[i]),
             "bbox_xyxy": [int(b[1].start), int(b[0].start), int(b[1].stop), int(b[0].stop)],
             "runs": [[y+b[0].start,x0+b[1].start,x1+b[1].start]
                      for y,x0,x1 in runs(labels[b] == i)]} for i, b in enumerate(boxes, 1)]


def projection(seqs, e, parts=None):
    out = np.zeros((400, 640), bool)
    f = frame(seqs, e["seq"], e["frame"])
    if not f or not f.get("path"): return out
    a = image(f["path"])[..., 3] > 127
    if parts is not None:
        keep = np.zeros_like(a)
        for r0, r1, _, shown in parts:
            if shown: keep[:] |= a if r0 < 0 else np.vstack((np.zeros_like(a[:r0]), a[r0:r1], np.zeros_like(a[r1:])))
        a = keep
    k = (float(e.get("size", 100)) or 100) / 100
    if k != 1:
        a = np.asarray(Image.fromarray(a).resize((max(1, round(a.shape[1]*k)), max(1, round(a.shape[0]*k))), Image.Resampling.NEAREST))
    x, y = int(e["x"] - f["dx"]*k), int(e["y"] - f["dy"]*k)
    x0, x1 = max(20, x), min(620, x + a.shape[1])
    y0, y1 = max(0, y), min(400, y + a.shape[0])
    if x0 < x1 and y0 < y1: out[y0:y1, x0:x1] = a[y0-y:y1-y, x0-x:x1-x]
    return out


def terrain_mask(rgb, tiles):
    """Conservative painted natural surface support, not standing geometry.

    Only independently inspected atlas families qualify. Grass in their cells
    stays unresolved. This can miss dark grass/rock boundaries and is explicitly
    a semantic attribution, not a recovered collision owner or visual clearance.
    """
    sheets = np.zeros((400, 600), np.int16)
    for i, t in enumerate(tiles[:96]):
        y, x = divmod(i, 12)
        sheets[y*50:(y+1)*50, x*50:(x+1)*50] = int(t["tile"])//128+1
    r, g, b = [rgb[..., i].astype(float) for i in range(3)]
    grass = (g > r*1.12) & (g > b*1.12)
    sea = (b > r*1.1) & (b > g*.85)
    rocky = np.isin(sheets, sorted(CLIFF_SHEETS)) & ~grass
    water = np.isin(sheets, sorted(WATER_SHEETS)) & sea
    return rocky | water


def water_default_ownership(world, tiles, per_tile):
    """The shore tile owns its own default hard mask, including its sandy rim.

    Custom masks still need independent evidence. A per-pixel blue test misses
    the source's 2px shore allowance; that fringe is drawn beside visible water.
    """
    indexes=[]
    for i,t in enumerate(tiles[:96]):
        tile_id=int(t["tile"])
        if tile_id//128+1 not in WATER_SHEETS:continue
        default=int(world["hardness"]["tile_defaults"][tile_id])
        if int(t.get("hard",0)) not in (0,default):continue
        sheet=tile_id//128+1;j=tile_id%128
        a=image(f"assets/tiles/ts{sheet:02d}.png")[j//12*50:j//12*50+50,j%12*50:j%12*50+50,:3].astype(float)
        sea=(a[...,2]>a[...,0]*1.1)&(a[...,2]>a[...,1]*.85)
        if sea.any():indexes.append(i)
    return np.isin(per_tile,indexes)


def census_screen(world, seqs, footprints, inventory, n, vision, native=None, structures=None):
    sc = world["screens"][str(n)]
    rec = footprints.get(str(n), {})
    raw_tile, per = tile_mask(world, n)
    live_tile, _ = tile_mask(world, n, rec.get("revert", ()), rec.get("clear", ()))
    wall_fit = structures[0].get("screens",{}).get(str(n),{}) if structures else {}
    if structures:
        for y,a,b in wall_fit.get("clear_tile_runs",[]):live_tile[y,a:b]=False
    raw_boxes = np.zeros_like(raw_tile); live_boxes = raw_boxes.copy()
    masks = {name: raw_boxes.copy() for name in CATEGORIES[1:]}
    source_owners = []
    visible = []
    for e, inv in zip(sc["sprites"], inventory[str(n)], strict=True):
        inv = dict(inv)
        if inv["category"] == "sprite_wall" and not (int(e["seq"])==80 and int(e["frame"]) in (*range(1,11),15)):
            inv["category"] = "sprite_decoration"
        assert e["index"] == inv["index"]
        if int(e.get("vision", 0)) not in (0, vision): continue
        hard = int(e.get("hard", 1)) == 0 and e.get("warp") is None
        box = rect_mask([inv["hard_rect"]], 4) if hard else np.zeros_like(raw_tile)
        box[:, :20] = False; box[:, 620:] = False
        raw_boxes |= box
        replaced = int(e["index"]) in rec.get("sprites", []) or int(e["index"]) in wall_fit.get("owner_indexes",[])
        if not replaced: live_boxes |= box
        shown = inv["category"] not in ("nothing", "ground_picture") and any(p[3] for p in inv["parts"])
        art = projection(seqs, e, inv["parts"] if inv["category"] == "billboard_object" else None) if shown else np.zeros_like(raw_tile)
        visible.append((e, inv, art))
        category = inv["category"] if shown or inv["category"] == "ground_picture" else "nothing"
        if hard and not replaced and category in masks: masks[category] |= box
        source_owners.append({"index": int(e["index"]), "path": inv["path"], "category": category,
                              "vision": int(e.get("vision", 0)), "hard": hard,
                              "hardbox_px": int(box.sum()), "replaced_by_footprint": replaced,
                              "parts": inv["parts"]})
    # A fitted footprint is an actual floor solid, not the source-camera picture.
    fitted = poly_mask([p["pts"] for p in rec.get("polys", [])], 4)
    if native is not None:
        fitted[:] = False
        for y,x0,x1 in native["footprint_layers"][str(n)][str(vision)]: fitted[y,x0:x1] = True
    fitted[:, :20] = False; fitted[:, 620:] = False
    masks["built_solid"] |= fitted
    if native is not None and "visual_support" in native:
        support = np.zeros_like(fitted)
        for y,x0,x1 in native["visual_support"][str(n)][str(vision)]: support[y,x0:x1] = True
        masks["built_solid"] |= (live_tile | live_boxes) & support
    all_wall = np.zeros_like(raw_tile); other = all_wall.copy()
    wall_owners = []
    for e, inv, art in visible:
        if inv["category"] == "sprite_wall":
            all_wall |= art
            wall_owners.append({"index": int(e["index"]), "path": inv["path"], "projection_px": int(art.sum())})
        else: other |= art
    # Exclude overlap with every other visible sprite: no ownership by proximity.
    wall_claim = live_tile & all_wall & ~other
    if not structures:masks["sprite_wall"] |= wall_claim
    decoration = np.zeros_like(raw_tile)
    for _,inv,art in visible:
        if inv["category"] == "sprite_decoration":decoration |= art
    masks["sprite_decoration"] |= live_tile & decoration
    atlas = image("assets/tiles/ts01.png")[..., :3]
    rgb, forest_cells = source_canvas(atlas, sc["tiles"])
    forest = np.zeros((400, 640), bool)
    if forest_cells.any():
        _, forest_owned, _, _ = forest_hardness(world, n, forest_cells, 94)
        forest[:, 20:620] = forest_owned
    masks["tile_forest"] |= live_tile & forest
    terrain = np.zeros_like(raw_tile); terrain[:, 20:620] = terrain_mask(rgb, sc["tiles"])
    terrain |= water_default_ownership(world,sc["tiles"],per)
    masks["water_cliff_edge"] |= live_tile & terrain
    effective = live_tile | live_boxes | fitted
    wall_volume = np.zeros_like(effective)
    if structures:
        from rc5_structure_masks import structure_masks
        wall_volume,fir_volume = structure_masks(n,*structures)
        effective |= wall_volume | fir_volume
        masks["sprite_wall"] |= wall_volume
        masks["billboard_object"] |= fir_volume
    raw = raw_tile | raw_boxes
    # Disjoint reporting order, with all overlap/ambiguity retained separately.
    labels = np.zeros(raw.shape, np.uint8)
    overlap = np.zeros(raw.shape, np.uint8)
    for category in CATEGORIES[1:]:
        owned = effective & masks[category]
        overlap += owned
        labels[owned & (labels == 0)] = CATEGORIES.index(category)
    classified = {name: int((effective & (labels == i)).sum()) for i, name in enumerate(CATEGORIES)}
    assert sum(classified.values()) == int(effective.sum())
    unresolved = effective & (labels == 0)
    unowned_sources = {"invisible_sprite_hardbox":0,"ground_picture_hardbox":0,"tile_hardness":0,"other_hardbox":0}
    remainder = unresolved.copy()
    for group, categories in (("invisible_sprite_hardbox",{"nothing"}), ("ground_picture_hardbox",{"ground_picture"})):
        boxes = np.zeros_like(raw_boxes)
        effective_categories = {q["index"]:q["category"] for q in source_owners}
        for e,inv in zip(sc["sprites"],inventory[str(n)],strict=True):
            if int(e.get("vision",0)) not in (0,vision) or effective_categories.get(int(e["index"])) not in categories: continue
            if int(e.get("hard",1)) != 0 or e.get("warp") is not None or int(e["index"]) in rec.get("sprites",[]): continue
            boxes |= rect_mask([inv["hard_rect"]],4)
        unowned_sources[group] = int((remainder & boxes).sum())
        remainder &= ~boxes
    tile_unowned = remainder & live_tile
    unowned_sources["tile_hardness"] = int(tile_unowned.sum())
    unowned_sources["other_hardbox"] = int((remainder & ~live_tile).sum())
    tile_sources = []
    for i,t in enumerate(sc["tiles"][:96]):
        count = int((tile_unowned & (per == i)).sum())
        if not count: continue
        default = world["hardness"]["tile_defaults"][int(t["tile"])]
        mask = int(t.get("hard",0)) or default
        if i in rec.get("revert",[]): mask = default
        tile_sources.append({"tile_index":i,"tile":int(t["tile"]),"atlas":int(t["tile"])//128+1,
                             "hardness_id":mask,"custom":bool(t.get("hard",0)) and i not in rec.get("revert",[]),"pixels":count})
    mismatches = []
    probe_count = 0
    if native is not None:
        for x,y,blocked in native["collision_probes"][str(n)][str(vision)]:
            probe_count += 1
            if bool(effective[y,x]) != blocked: mismatches.append([x,y,blocked,bool(effective[y,x])])
    encoded = []
    for y, row in enumerate(np.where(effective, labels+1, 0)):
        edges = np.r_[0, np.flatnonzero(np.diff(row))+1, row.size]
        encoded.extend([y, int(a), int(b), int(row[a])-1] for a, b in zip(edges[:-1], edges[1:]) if row[a])
    return {"vision": vision, "source_hard_px": int(raw.sum()), "source_tile_px": int(raw_tile.sum()),
            "source_hardbox_px": int(raw_boxes.sum()), "effective_hard_px": int(effective.sum()),
            "source_removed_px": int((raw & ~effective).sum()), "fitted_added_px": int((effective & ~raw).sum()),
            "categories_px": classified, "ambiguous_attribution_px": int((overlap > 1).sum()),
            "wall_projected_hard_px": int(wall_claim.sum()), "wall_owners": wall_owners,
            "source_owners": source_owners, "footprint_record": rec, "classification_runs": encoded,
            "unowned_source_breakdown":unowned_sources,"unowned_tile_sources":tile_sources,
            "native_collision_probe_count":probe_count,"native_collision_mismatches":mismatches,
            "source_removed_runs": runs(raw & ~effective), "source_added_runs": runs(effective & ~raw),
            "unowned_components": components(unresolved),
            "forest_hard_without_standing_volume_px": int((effective & masks["tile_forest"]).sum()),
            "wall_hard_without_fitted_volume_px": 0 if structures else int((effective & masks["sprite_wall"]).sum()),
            "wall_projected_retained_hard_without_floor_px":int((wall_claim & ~wall_volume).sum())}


def reachable_boundaries(world, screens, native):
    """Exact four-connected integer free-space graph across outdoor seams.

    This uses the same plain-free predicate as the RC4 exhaustive walker. It
    does not claim normal campaign progression: scripts, editor persistence,
    warps and entering fractional clearance bands can change reachability.
    """
    rows = (max(map(int,world["screens"]))+31)//32
    free = np.zeros((rows*400,32*600),bool)
    for n,fixtures in screens.items():
        n = int(n); y0=((n-1)//32)*400; x0=((n-1)%32)*600
        view=free[y0:y0+400,x0:x0+600];view[:]=True
        for y,a,b,_ in fixtures[0]["classification_runs"]:view[y,a-20:b-20]=False
    labels,count=ndimage.label(free)
    seed_screen=439;seed_x=323;seed_y=390
    oy=((seed_screen-1)//32)*400;ox=((seed_screen-1)%32)*600
    tag=int(labels[oy+seed_y,ox+seed_x-20])
    assert tag, "outdoor home seed is blocked"
    walking_only=labels==tag
    indoor_labels={};next_tag=int(labels.max())+1
    for n,record in native["indoor_collision"].items():
        rec=world["screens"][n];fp=json.loads((ROOT/"game/data/footprints.json").read_text())["screens"].get(n,{})
        hard,_=tile_mask(world,int(n),fp.get("revert",()),fp.get("clear",()))
        hard |= rect_mask(record["hard_rects"],4)
        for y,a,b in record["footprint_runs"]:hard[y,a:b]=True
        mask=~hard;mask[:,:20]=False;mask[:,620:]=False
        local,num=ndimage.label(mask)
        local[local!=0]+=next_tag-1;next_tag+=num
        indoor_labels[n]=local
    def label_at(n,x,y):
        if not (20<=x<620 and 0<=y<400):return 0
        if str(n) in indoor_labels:return int(indoor_labels[str(n)][int(y),int(x)])
        if str(n) not in screens:return 0
        return int(labels[((n-1)//32)*400+int(y),((n-1)%32)*600+int(x)-20])
    edges=[];uncertain=[]
    for warp in native["static_warps"]:
        n=warp["screen"];a,b,c,d=warp["trigger"]
        x0=max(20,int(np.ceil(a)));x1=min(620,int(np.ceil(c)));y0=max(0,int(np.ceil(b)));y1=min(400,int(np.ceil(d)))
        if x1 <= x0 or y1 <= y0:
            continue
        if str(n) in indoor_labels: source_tags=set(map(int,np.unique(indoor_labels[str(n)][y0:y1,x0:x1])))
        elif str(n) in screens:
            oy=((n-1)//32)*400;ox=((n-1)%32)*600-20
            source_tags=set(map(int,np.unique(labels[oy+y0:oy+y1,ox+x0:ox+x1])))
        else:source_tags=set()
        source_tags.discard(0)
        target_tag=label_at(warp["target"],*warp["destination"])
        item=dict(warp,source_components=sorted(source_tags),target_component=target_tag)
        if target_tag:edges.append(item)
        else:uncertain.append(dict(item,status="static warp destination not plain-free; route unverified"))
    reached={tag}
    changed=True
    while changed:
        changed=False
        for edge in edges:
            if reached.intersection(edge["source_components"]) and edge["target_component"] not in reached:
                reached.add(edge["target_component"]);changed=True
    reachable=np.isin(labels,list(reached))
    del labels,free
    neighbor=ndimage.binary_dilation(reachable)
    reachable_screens=[];top=[];totals=collections.Counter()
    for n,fixtures in screens.items():
        k=int(n);y0=((k-1)//32)*400;x0=((k-1)%32)*600
        c=fixtures[0];near=neighbor[y0:y0+400,x0:x0+600]
        boundary=np.zeros((400,640),bool);boundary[:,20:620]=near
        labels_local=np.full((400,640),255,np.uint8)
        for y,a,b,label in c["classification_runs"]:labels_local[y,a:b]=label
        boundary &= labels_local!=255
        counts={name:int((boundary & (labels_local==i)).sum()) for i,name in enumerate(CATEGORIES)}
        totals.update(counts)
        local_reach=reachable[y0:y0+400,x0:x0+600]
        c["walking_reachable_free_px"]=int(walking_only[y0:y0+400,x0:x0+600].sum())
        c["static_warp_reachable_free_px"]=int(local_reach.sum())
        c["reachable_boundary_categories_px"]=counts
        c["reachable_unowned_components"]=components(boundary & (labels_local==0))
        if c["static_warp_reachable_free_px"]:reachable_screens.append(k)
        top.extend(dict(comp,screen=k) for comp in c["reachable_unowned_components"])
    top=sorted(top,key=lambda c:-c["pixels"])[:10]
    for component in top:
        n=component["screen"];oy=((n-1)//32)*400;ox=((n-1)%32)*600
        local=reachable[oy:oy+400,ox:ox+600];bbox=component["bbox_xyxy"]
        cx=(bbox[0]+bbox[2])/2;cy=(bbox[1]+bbox[3])/2
        targets=[(y,(a+b)/2) for y,a,b in component["runs"]]
        ty,tx=min(targets,key=lambda p:(p[0]-cy)**2+(p[1]-cx)**2)
        ys,xs=np.where(local);xs=xs+20
        distance=np.hypot(xs-tx,ys-ty)
        views=[]
        for name,dx,dy in (("south",0,1),("east",1,0),("north",0,-1),("west",-1,0)):
            cost=(xs-(tx+110*dx))**2+(ys-(ty+110*dy))**2
            eligible=(distance>35)&(distance<200)
            if not eligible.any():continue
            score=np.where(eligible,cost,np.inf);i=int(np.argmin(score));x=float(xs[i]);y=float(ys[i])
            views.append({"name":f"s{n}-boundary-{name}","x":x,"y":y,"yaw":float(np.arctan2(-(tx-x),-(ty-y))),"pitch":-.25})
        component["diagnostic_views"]=views
        component["aim_source_xy"]=[tx,ty]
    return {"seed":{"screen":seed_screen,"source_xy":[seed_x,seed_y]},
            "method":"4-connected native-plain-free outdoor pixels plus static vision0 warp edges and analytic indoor free components; unlocked fixture",
            "free_components":int(count),"reachable_screens":reachable_screens,
            "reachable_free_px":int(reachable.sum()),"boundary_categories_px":dict(totals),
            "top_unowned_components":top,"static_warp_edges":edges,"unverified_static_warps":uncertain,
            "screen145_walking_reachable":screens["145"][0]["walking_reachable_free_px"]>0,
            "screen145_static_warp_reachable":145 in reachable_screens,
            "not_connected_outdoor_screens":sorted(set(map(int,screens))-set(reachable_screens)),
            "limits":["This is a static walkable-space/warp graph, not execution of campaign progression or actual input/warp tests.",
                      "Indoor free components use source tile masks, native hardboxes and native fitted footprints; live portal triggers/destinations use the native adapter.",
                      "Scripts, other vision layers and saved clearance-band arrivals can reach other components; not-connected is not proof of unreachable.",
                      "Interior worlds are deliberately not joined by outdoor seam adjacency."]}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--inventory", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=ROOT/"tmp/rc5-census/census.json")
    ap.add_argument("--current",action="store_true",help="Apply compiled RC5 wall/fir collision; inventory must also be current")
    args = ap.parse_args()
    world = json.loads((ROOT/"game/data/world.json").read_text())
    seqs = json.loads((ROOT/"game/data/sequences.json").read_text())["sequences"]
    fp = json.loads((ROOT/"game/data/footprints.json").read_text())["screens"]
    native = json.loads(args.inventory.read_text())
    assert native["schema"] == "rc5-render-dispatch-2", "regenerate native footprint/probe inventory first"
    inventory = native["screens"]
    structures = tuple(json.loads((ROOT/p).read_text()) for p in ("game/prototype/rc5_walls.json","game/prototype/rc5_fir_collision.json")) if args.current else None
    screens = {}; total = collections.Counter(); stone = []; walls = []
    for key in sorted(inventory, key=int):
        n = int(key); sc = world["screens"][key]
        layers = sorted({0} | {int(e.get("vision", 0)) for e in sc["sprites"]})
        screens[key] = [census_screen(world, seqs, fp, inventory, n, v, native,structures) for v in layers]
        base = screens[key][0]; total.update(base["categories_px"])
        if any("stnwalls/stonw-" in e["path"] for e in inventory[key]): stone.append(n)
        if any("/stnwalls/" in e["path"] or "/innwalls/" in e["path"] for e in inventory[key]): walls.append(n)
        if n % 50 == 0: print("census", n, flush=True)
    result = {"schema":"rc5-hardness-census-1", "phase":"RC5" if args.current else "RC4 baseline", "basis":"static editor state; all authored vision layers, no startup scripts",
              "coordinates":"640x400 source screen; playable x20..619,y0..399; half-open runs",
              "categories":list(CATEGORIES), "stone_wall_screens":stone, "sprite_wall_screens":walls,
              "inventory_sha256":hashlib.sha256(args.inventory.read_bytes()).hexdigest(),
              "inventory_basis":native.get("basis","RC4 inventory captured before migration"),
              "source_sha256":{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in
                               ("game/data/world.json","game/data/sequences.json","game/data/footprints.json")},
              "limits":["Source-art attribution does not certify eye-level appearance, occupied volume, or movement safety.",
                        "Wall tile ownership is a conservative projected-art candidate excluding other visible sprite projections.",
                        "Forest connectivity uses the existing 94px ownership rule; remote grass hardness stays unowned.",
                        "Natural terrain is painted-ground support inferred from inspected atlas families and color; no standing cliff volume.",
                        "Built hardbox labels identify the renderer's fitted owner, not exact hardbox/mesh agreement.",
                        "Footprint raster is the game's native _in_footprint at every integer pixel; collision probes are a sampled cross-check.",
                        "Story/script/persistence and side-flip visibility are outside this static census."],
              "vision0_totals":dict(total), "screens":screens}
    assert len(screens) == 570 and len(stone) == 17 and len(walls) == 18
    if not args.current:assert screens["712"][0]["wall_projected_hard_px"] > 0
    assert screens["375"][0]["forest_hard_without_standing_volume_px"] > 0
    assert screens["375"][0]["unowned_components"]
    mismatches = [(n,c["vision"],c["native_collision_mismatches"]) for n,cs in screens.items() for c in cs if c["native_collision_mismatches"]]
    result["native_collision_probe_count"] = sum(c["native_collision_probe_count"] for cs in screens.values() for c in cs)
    result["native_collision_mismatches"] = mismatches
    result["inert_control_439"] = screens["439"][0]["categories_px"]
    result["unowned_source_totals"] = dict(sum((collections.Counter(v[0]["unowned_source_breakdown"]) for v in screens.values()),collections.Counter()))
    result["top_unowned_components"] = sorted((dict(c,screen=int(n)) for n,v in screens.items() for c in v[0]["unowned_components"]),key=lambda c:-c["pixels"])[:10]
    result["walking_reachability"] = reachable_boundaries(world,screens,native)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, separators=(",",":"))+"\n")
    summary = f"""# RC5 static hardness census — 2026-10-11 ({result['phase']})

570 outdoor screens; {sum(len(v) for v in screens.values())} authored vision-layer fixtures.
17 stone-wall screens: {stone}. Snake-only screen 238 makes 18 sprite-wall screens.
Vision0 effective-hard pixel attribution: {dict(total)}.
712: {screens['712'][0]['wall_projected_hard_px']} retained wall-projected hard pixels;
wall-associated hardness without fitted volume {screens['712'][0]['wall_hard_without_fitted_volume_px']}.
375: {screens['375'][0]['forest_hard_without_standing_volume_px']} forest-associated hard pixels;
{screens['375'][0]['categories_px']['nothing']} unresolved hard pixels in {len(screens['375'][0]['unowned_components'])} components.

The JSON preserves every effective hard pixel as classification runs, every removed/added
source cell, every original hardbox owner, wall candidates and every unresolved component.
All counts are pixel counts before movement-dependent clearance escape. Categories describe
source/renderer attribution, **not certified eye-level visibility or exclusive ground ownership**.
On RC4, wall projections and forest-connected masks lack standing volume. RC5 applies
compiled wall occupied floor and exact band, replacing only selected source hardness;
whole-fir source hardboxes use their measured feet and actual scene visibility. Billboard
hardboxes have their own category. Ambiguity is counted separately; categories partition each
fixture rather than adding overlaps twice. Natural terrain attribution excludes grass from
inspected rock/cliff/snow/water atlas families, with the rule preserved in the compiler.

Unresolved source breakdown: {result['unowned_source_totals']}.
Native collision probes: {result['native_collision_probe_count']}; mismatch fixtures: {len(mismatches)}.
Inert house control 439: {result['inert_control_439']}.
Top unresolved components (screen, area, bbox): {[(c['screen'],c['pixels'],c['bbox_xyxy']) for c in result['top_unowned_components']]}.

Static graph from outdoor home439 (323,390), including vision0 warp edges: {len(result['walking_reachability']['reachable_screens'])}
screens, {result['walking_reachability']['reachable_free_px']} plain-free pixels;145 walking connected:
{result['walking_reachability']['screen145_walking_reachable']}, static-warp connected:
{result['walking_reachability']['screen145_static_warp_reachable']}. Reachable boundary categories:
{result['walking_reachability']['boundary_categories_px']}.
Top unresolved reachable boundaries: {[(c['screen'],c['pixels'],c['bbox_xyxy']) for c in result['walking_reachability']['top_unowned_components']]}.
Startup scripts, story state and fractional arrivals are excluded; this does not establish
campaign reachability or certify every reachable boundary's visibility.

Known-case validation: baseline712 wall pixels >0, 375 forest pixels >0 and unresolved components >0;
17/18 distinction asserted. This instrument changes no gameplay state. Existing helpers:
collision_map.tile_mask/rect_mask/poly_mask; rc4_fir_stand_fit.source_canvas/forest_hardness;
native fp_world dispatch and per-part seam rules. Prior art: PyDink's tile/sprite/hardness
editing model (https://github.com/wijnen/pydink); no external depth/ownership implementation
found for Dink's source art. Footprints now use native integer-pixel point queries.
Visual ownership review remains necessary before item2's collision migration.
"""
    args.out.with_suffix(".md").write_text(summary)
    print(summary)
    assert not mismatches, f"native collision mismatch in {len(mismatches)} fixtures"
    assert result["inert_control_439"]["nothing"] == 0


if __name__ == "__main__": main()
