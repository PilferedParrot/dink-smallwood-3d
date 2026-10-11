#!/usr/bin/env python3
"""Raster reachable source-range cells for bounded native FPS dispatch probes.

These masks prefilter exact static reachability and authored talk/melee range.
The native probe may stop at a dispatch witness; exhaustive negatives visit all
eligible cells. FPS facing, own physics ray, and target selection remain native.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import rect_mask, tile_mask  # noqa: E402


def candidate_mask(record: dict, reachable: np.ndarray) -> tuple[tuple[int, int, int, int], np.ndarray]:
    x, y = map(float, record["source_xy"])
    if record["mode"] == "talk_nearest_any_facing_90px":
        radius = 90
        xa, xb = max(20, int(np.floor(x-radius))), min(620, int(np.ceil(x+radius)))
        ya, yb = max(0, int(np.floor(y-radius))), min(400, int(np.ceil(y+radius)))
        if xa >= xb or ya >= yb:
            return (0, 0, 0, 0), np.zeros((0, 0), bool)
        yy, xx = np.mgrid[ya:yb, xa:xb]
        d2 = (xx-x)**2 + (yy-y)**2
        eligible = d2 < radius * radius
    else:
        rectangles = {direction: melee_rect(record["source_hard_rect_xyxy"] if "source_hard_rect_xyxy" in record
                                            else record["hard_rect"], direction)
                      for direction in (4, 6, 8, 2)}
        xa = max(20, int(np.floor(min(r[0] for r in rectangles.values()))))
        xb = min(620, int(np.ceil(max(r[2] for r in rectangles.values()))))
        ya = max(0, int(np.floor(min(r[1] for r in rectangles.values()))))
        yb = min(400, int(np.ceil(max(r[3] for r in rectangles.values()))))
        if xa >= xb or ya >= yb:
            return (0, 0, 0, 0), np.zeros((0, 0), bool)
        yy, xx = np.mgrid[ya:yb, xa:xb]
        d2 = (xx - x) ** 2 + (yy - y) ** 2
        eligible = np.zeros_like(d2, bool)
        for direction, (fx, fy) in ((4, (-1, 0)), (6, (1, 0)), (8, (0, -1)), (2, (0, 1))):
            x0, y0, x1, y1 = rectangles[direction]
            dot = (x - xx) * fx + (y - yy) * fy
            eligible |= (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1) & (d2 > 0.0001) & (dot >= 0.60 * np.sqrt(d2))
    eligible &= reachable[ya:yb, xa - 20:xb - 20]
    return (xa, xb, ya, yb), eligible


def melee_rect(hb: list[float], direction: int) -> tuple[float, float, float, float]:
    """Default-range target rectangle from fps_game.gd's _fps_melee_hit_rect."""
    left, top, right, bottom = map(float, hb)
    left -= 5.0; right += 5.0; top -= 5.0; bottom += 10.0
    if direction == 6:
        left -= 28; top -= 10; bottom += 10
    elif direction == 4:
        right += 28; top -= 10; bottom += 10
    elif direction == 2:
        top -= 36; left -= 10; right += 10
    elif direction == 8:
        bottom += 36; left -= 10; right += 10
    return left, top, right, bottom


def local(mask: np.ndarray, screen: int) -> np.ndarray:
    row, col = divmod(screen - 1, 32)
    return mask[row*400:row*400+400, col*600:col*600+600]


def trigger_hits(reachable: np.ndarray, rect: list[float]) -> bool:
    x0,y0,x1,y1=map(float,rect)
    xa,xb=max(20,int(np.ceil(x0))),min(620,int(np.ceil(x1)))
    ya,yb=max(0,int(np.ceil(y0))),min(400,int(np.ceil(y1)))
    return xa<xb and ya<yb and bool(reachable[ya:yb,xa-20:xb-20].any())


def indoor_reach(world: dict, native: dict, footprints: dict,
                 before_outdoor: np.ndarray, after_outdoor: np.ndarray) -> tuple[dict, dict]:
    """Propagate outdoor reachability through native static warp destinations."""
    labels={}
    for key,record in native["indoor_collision"].items():
        fp=footprints.get(key,{})
        hard,_=tile_mask(world,int(key),fp.get("revert",()),fp.get("clear",()))
        hard |= rect_mask(record["hard_rects"],4)
        for y,a,b in record["footprint_runs"]: hard[int(y),int(a):int(b)]=True
        free=~hard; free[:,:20]=False; free[:,620:]=False
        labels[key]=ndimage.label(free[:,20:620])[0]
    trigger_tags={}
    for i,w in enumerate(native["static_warps"]):
        key=str(w["screen"])
        if key not in labels: continue
        x0,y0,x1,y1=w["trigger"]
        xa,xb=max(20,int(np.ceil(x0))),min(620,int(np.ceil(x1)))
        ya,yb=max(0,int(np.ceil(y0))),min(400,int(np.ceil(y1)))
        tags=set(map(int,np.unique(labels[key][ya:yb,xa-20:xb-20]))) if xa<xb and ya<yb else set()
        tags.discard(0); trigger_tags[i]={(key,t) for t in tags}
    outputs=[]
    for outdoor in (before_outdoor,after_outdoor):
        reached=set(); changed=True
        while changed:
            changed=False
            for i,w in enumerate(native["static_warps"]):
                key=str(w["target"]); x,y=w["destination"]
                if key not in labels or not (20<=x<620 and 0<=y<400): continue
                tag=int(labels[key][int(y),int(x)-20])
                if not tag or (key,tag) in reached: continue
                source=str(w["screen"])
                ready=bool(trigger_tags.get(i,set()) & reached) if source in labels else trigger_hits(local(outdoor,int(source)),w["trigger"])
                if ready: reached.add((key,tag)); changed=True
        outputs.append({key:np.isin(label,[tag for sn,tag in reached if sn==key]) for key,label in labels.items()})
    return outputs[0],outputs[1]


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",type=Path,required=True,help="ray-candidates.json")
    parser.add_argument("--rays",type=Path,required=True,help="integrated ray census JSON")
    parser.add_argument("--broad",type=Path,required=True,help="interactions.json with source hardboxes")
    parser.add_argument("--masks",type=Path,required=True,help="reach-masks.npz")
    parser.add_argument("--world",type=Path,required=True,help="world.json")
    parser.add_argument("--native",type=Path,required=True,help="native inventory JSON")
    parser.add_argument("--footprints",type=Path,required=True,help="footprints.json")
    parser.add_argument("--out",type=Path,required=True,help="candidate output directory")
    parser.add_argument("--screen",type=int,help="Benchmark only one scene before a full run")
    args=parser.parse_args()
    source=json.loads(args.source.read_text())
    if source.get("schema")!="rc5-native-entity-ray-candidates-1" or source.get("ray_target_records")!=579:
        raise ValueError("unexpected ray candidate source/schema/count")
    rays=json.loads(args.rays.read_text())
    broad_doc=json.loads(args.broad.read_text())
    world=json.loads(args.world.read_text())
    native=json.loads(args.native.read_text())
    fpdoc=json.loads(args.footprints.read_text()); footprints=fpdoc.get("screens",fpdoc)
    priority={(int(r["screen"]),int(r["list_index"]),r["mode"]):r for r in rays["records"]}
    broad={(int(r["screen"]),int(r["list_index"]),r["mode"]):r for r in broad_doc["records"]
           if r["mode"] in ("talk_nearest_any_facing_90px","hit_default_fist_48px")}
    selected=[r for r in source["records"] if args.screen is None or int(r["screen"])==args.screen]
    if not selected: raise ValueError("no candidate records selected")
    args.out.mkdir(parents=True,exist_ok=True)
    with np.load(args.masks,allow_pickle=False) as masks:
        before,after=masks["before_reachable"],masks["after_reachable"]
        indoor_before,indoor_after=indoor_reach(world,native,footprints,before,after)
        result=[]
        for index,record in enumerate(selected):
            screen=int(record["screen"]); key=str(screen)
            if world["screens"][key].get("indoor"):
                reach=(indoor_before[key],indoor_after[key])
            else:
                reach=(local(before,screen),local(after,screen))
            if record["mode"]=="hit_default_fist_48px":
                broad_record=broad[(screen,int(record["list_index"]),record["mode"])]
                record["source_hard_rect_xyxy"]=broad_record["source_hard_rect_xyxy"]
            images={}
            for when,reachable in zip(("before","after"),reach,strict=True):
                rect,eligible=candidate_mask(record,reachable); count=int(eligible.sum())
                assert count==int(record[f"{when}_inventory"]["reachable_range_cells"]),(screen,index,when,count)
                name=f"{screen}-{record['list_index']}-{record['mode']}-{when}.png"
                Image.fromarray(eligible.astype(np.uint8)*255,"L").save(args.out/name)
                images[when]={"rect_xyxy":list(rect),"image":str(args.out/name),"eligible_cells":count}
            ray=priority[(screen,int(record["list_index"]),record["mode"])]
            ordered={}
            for when in ("before","after"):
                seen=set();ordered[when]=[]
                for xy in [ray[when]["witness_xy"],*record[f"{when}_points"]]:
                    if len(xy)!=2 or tuple(xy) in seen:continue
                    seen.add(tuple(xy));ordered[when].append(xy)
            result.append({"screen":screen,"list_index":int(record["list_index"]),
                           "editor_index":int(record["editor_index"]),"script":record["script"],
                           "mode":record["mode"],"source_xy":record["source_xy"],"images":images,
                           "priority_xy":ordered})
    out={"schema":"rc5-all-reachable-dispatch-candidates-1","records":result,
         "counts":{"records":len(result),"before_cells":sum(r["images"]["before"]["eligible_cells"] for r in result),
                   "after_cells":sum(r["images"]["after"]["eligible_cells"] for r in result)},
         "basis":"exact before/after static-warp-reachable integer cells intersected with source talk<90 or four-cardinal default-fist range/cone; positive native probes stop at a dispatch witness, while exhaustive negatives visit every eligible white pixel"}
    output=args.out/(f"index-{args.screen}.json" if args.screen else "index.json")
    output.write_text(json.dumps(out,separators=(",",":"))+"\n")
    print("DISPATCH CANDIDATES",out["counts"])


if __name__=="__main__": main()
