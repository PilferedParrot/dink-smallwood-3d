"""Deterministic before/after reachable actor ray samples for native census."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import rc5_interactions as common  # noqa: E402
import rc5_fps_static as fps  # noqa: E402
from rc5_dispatch_candidates import melee_rect  # noqa: E402


def pick(points: list[tuple[int, int, float, bool, float]], limit: int = 32) -> list[list[int]]:
    """Keep near and far points in each angular sector, with clear rays first."""
    if not points:
        return []
    target = []
    for clear in (True, False):
        subset = [p for p in points if p[3] == clear]
        sectors = [[] for _ in range(8)]
        for p in subset:
            sectors[int(p[2]) % 8].append(p)
        for group in sectors:
            if not group:
                continue
            group.sort(key=lambda p: p[4])
            for sample in (group[0], group[len(group) // 2], group[-1]):
                point = [int(sample[0]), int(sample[1])]
                if point not in target:
                    target.append(point)
        if len(target) >= limit:
            break
    return target[:limit]


def points_for(record: dict, reachable: np.ndarray, solid: np.ndarray) -> tuple[list[list[int]], dict]:
    mode = record["mode"]
    actor_x, actor_y = map(float, record["source_xy"])
    if mode == "talk_nearest_any_facing_90px":
        radius = 90
        xa, xb, ya, yb, _, _, d2 = common.patch((actor_x, actor_y), radius)
        if xa >= xb or ya >= yb:
            return [], {"reachable_range_cells": 0, "native_line_approx_cells": 0}
        yy, xx = np.mgrid[ya:yb, xa:xb]
        eligible = d2 < radius ** 2
    else:
        rects = [melee_rect(record["source_hard_rect_xyxy"], direction) for direction in (4, 6, 8, 2)]
        xa = max(20, int(np.floor(min(r[0] for r in rects))))
        xb = min(620, int(np.ceil(max(r[2] for r in rects))))
        ya = max(0, int(np.floor(min(r[1] for r in rects))))
        yb = min(400, int(np.ceil(max(r[3] for r in rects))))
        if xa >= xb or ya >= yb:
            return [], {"reachable_range_cells": 0, "native_line_approx_cells": 0}
        yy, xx = np.mgrid[ya:yb, xa:xb]
        d2 = (xx - actor_x) ** 2 + (yy - actor_y) ** 2
        eligible = np.zeros_like(d2, bool)
        for direction, (fx, fy) in ((4, (-1, 0)), (6, (1, 0)), (8, (0, -1)), (2, (0, 1))):
            x0, y0, x1, y1 = melee_rect(record["source_hard_rect_xyxy"], direction)
            dot = (actor_x - xx) * fx + (actor_y - yy) * fy
            eligible |= (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1) & (d2 > 0.0001) & (dot >= 0.60 * np.sqrt(d2))
    eligible &= reachable[ya:yb, xa - 20:xb - 20]
    py, px = np.where(eligible)
    if not len(px):
        return [], {"reachable_range_cells": 0, "native_line_approx_cells": 0}
    xs = (px + xa).astype(float)
    ys = (py + ya).astype(float)
    clear = fps.line_clear(xs, ys, (actor_x, actor_y), solid)
    angles = (np.arctan2(ys - actor_y, xs - actor_x) + np.pi) * 8 / (2 * np.pi)
    distances = np.sqrt((xs - actor_x) ** 2 + (ys - actor_y) ** 2)
    rows = [(int(xs[i]), int(ys[i]), float(angles[i]), bool(clear[i]), float(distances[i])) for i in range(len(xs))]
    return pick(rows), {"reachable_range_cells": len(rows), "native_line_approx_cells": int(clear.sum())}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    for name,help_text in (("broad","source interaction census JSON"),("masks","before/after topology masks NPZ"),
        ("world","world.json"),("native","native inventory JSON"),("footprints","footprints.json"),
        ("walls","wall source/effective masks JSON"),("firs","fir source/effective masks JSON"),
        ("out","output ray candidate JSON")):
        parser.add_argument("--"+name,type=Path,required=True,help=help_text)
    args=parser.parse_args()
    broad=json.loads(args.broad.read_text()); world_doc=json.loads(args.world.read_text())
    world=world_doc["screens"]; fdoc=json.loads(args.footprints.read_text()); footprints=fdoc.get("screens",fdoc)
    native=json.loads(args.native.read_text()); walls=json.loads(args.walls.read_text()); firs=json.loads(args.firs.read_text())
    fps.configure(world_doc,footprints,native,walls,firs)
    with np.load(args.masks,allow_pickle=False) as data:
        before,after=data["before_reachable"],data["after_reachable"]
        source_eligible=sum(r["status"]=="PASS_RETAINED_REACHABLE_CELLS" for r in broad["records"])
        if source_eligible!=817: raise ValueError(f"expected 817 source-eligible ranges, got {source_eligible}")
        broad_ray_records=[r for r in broad["records"] if r["status"]=="PASS_RETAINED_REACHABLE_CELLS"
                           and r["mode"] in ("talk_nearest_any_facing_90px","hit_default_fist_48px")]
        if len(broad_ray_records)!=708: raise ValueError(f"expected 708 positive talk/hit records, got {len(broad_ray_records)}")
        nonstanding=[r for r in broad_ray_records if int(r.get("type",1))!=1]
        records=[r for r in broad_ray_records if int(r.get("type",1))==1]
        if len(nonstanding)!=129 or len(records)!=579: raise ValueError("authored type eligibility changed")
        indoor_before,indoor_after,_=common.indoor_reach(world_doc,native,footprints,before,after)
        out=[]
        for record in records:
            screen=int(record["screen"]); key=str(screen)
            before_reach,after_reach=(indoor_before[key],indoor_after[key]) if world[key].get("indoor") else (
                common.local(before,screen),common.local(after,screen))
            before_solid,after_solid=fps.structure(screen)
            old,old_info=points_for(record,before_reach,before_solid)
            new,new_info=points_for(record,after_reach,after_solid)
            out.append({"screen":screen,"list_index":record["list_index"],"editor_index":record["editor_index"],
                        "script":record["script"],"mode":record["mode"],"source_xy":record["source_xy"],
                        "before_points":old,"after_points":new,"before_inventory":old_info,"after_inventory":new_info})
        trigger_only=[r for r in broad["records"] if r["status"]=="PASS_RETAINED_REACHABLE_CELLS"
                      and r["mode"] not in ("talk_nearest_any_facing_90px","hit_default_fist_48px")]
        if len(trigger_only)!=109: raise ValueError(f"expected 109 positive trigger-only records, got {len(trigger_only)}")
    before_candidates=sum(bool(r["before_points"]) for r in out)
    after_candidates=sum(bool(r["after_points"]) for r in out)
    output={"schema":"rc5-native-entity-ray-candidates-1","source_eligible_records":source_eligible,
            "ray_target_records":len(out),"nonstanding_ray_ineligible":[
                {"screen":r["screen"],"list_index":r["list_index"],"editor_index":r["editor_index"],
                 "type":r["type"],"key":r["key"],"reason":"type0 ground-painted, no standing FPS target"}
                for r in nonstanding],"before_with_candidate_cells":before_candidates,
            "after_with_candidate_cells":after_candidates,
            "trigger_only_excluded":{mode:sum(r["mode"]==mode for r in trigger_only)
                                      for mode in sorted({r["mode"] for r in trigger_only})},"records":out}
    output["input_sha256"]={str(path):hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in (args.broad,args.masks,args.world,args.native,args.footprints,args.walls,args.firs)}
    args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(output,separators=(",",":"))+"\n")
    print("RAY CANDIDATES",len(out),"before",before_candidates,"after",after_candidates,
          "trigger only",len(trigger_only),"nonstanding",len(nonstanding),
          "line-clear-after",sum(r["after_inventory"]["native_line_approx_cells"]>0 for r in out))


if __name__=="__main__": main()
