"""Approximate FPS interaction reach with actual cone and structure-line rules.

Uses _fps_line_clear's 5px sampling and vision0 source structure masks. Polygon
edges are rasterized at integer samples, so this is a screening instrument;
_fps_ray_reaches needs live physics and is NOT certified here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import rc5_interactions as common  # noqa: E402
from rc5_dispatch_candidates import melee_rect  # noqa: E402
from collision_map import rect_mask, tile_mask  # noqa: E402

WORLD: dict = {}
FOOTPRINTS: dict = {}
NATIVE: dict = {}
WALLS: dict = {}
FIRS: dict = {}
FIR_RECORDS: dict = {}
WALLRAW: np.ndarray | None = None
YY, XX = np.mgrid[-5:6, -5:6]
BAND_STRUCT = (np.maximum(np.maximum(-XX, XX - 1), 0) ** 2
               + np.maximum(np.maximum(-YY, YY - 1), 0) ** 2) <= 16


def configure(world: dict, footprints: dict, native: dict, walls: dict, firs: dict) -> None:
    """Initialize source masks from explicit artifacts; no source files load at import."""
    global WORLD, FOOTPRINTS, NATIVE, WALLS, FIRS, FIR_RECORDS, WALLRAW
    WORLD, FOOTPRINTS, NATIVE, WALLS, FIRS = world, footprints, native, walls, firs
    FIR_RECORDS = {r["id"]: r for r in FIRS["rectangles"]}
    rows = (max(map(int, WORLD["screens"])) + 31) // 32
    WALLRAW = np.zeros((rows * 400, 19200), bool)
    for key, fit in WALLS["screens"].items():
        n = int(key); oy, ox = (n - 1) // 32 * 400, (n - 1) % 32 * 600
        for y, a, b in fit["floor_runs"]:
            WALLRAW[oy+y, ox+a-20:ox+b-20] = True
    structure.cache_clear()


@lru_cache(maxsize=256)
def structure(screen: int) -> tuple[np.ndarray, np.ndarray]:
    key = str(screen)
    fitted = FOOTPRINTS.get(key, {})
    source, _ = tile_mask(WORLD, screen, fitted.get("revert", ()), fitted.get("clear", ()))
    if WORLD["screens"][key].get("indoor"):
        for y, a, b in NATIVE["indoor_collision"][key]["footprint_runs"]:
            source[y, a:b] = True
        clipped = source[:, 20:620].copy()
        return clipped, clipped
    footprint = np.zeros_like(source)
    for y, a, b in NATIVE["footprint_layers"][key]["0"]:
        footprint[y, a:b] = True
    before = (source | footprint)[:, 20:620].copy()
    for y, a, b in WALLS["screens"].get(key, {}).get("clear_tile_runs", []):
        source[y, a:b] = False
    after = source | footprint
    assert WALLRAW is not None
    oy, ox = (screen - 1) // 32 * 400, (screen - 1) % 32 * 600
    y0, x0 = max(0, oy - 6), max(0, ox - 6)
    y1, x1 = min(WALLRAW.shape[0], oy + 406), min(WALLRAW.shape[1], ox + 606)
    halo = WALLRAW[y0:y1, x0:x1]
    if halo.any():
        after[:, 20:620] |= ndimage.binary_dilation(halo, structure=BAND_STRUCT)[
            oy - y0:oy - y0 + 400, ox - x0:ox - x0 + 600]
    visible_rects = [entry["rect_local_xyxy"] for entry in FIRS["by_screen"].get(key, [])
                     if screen in FIR_RECORDS[entry["id"]]["scene5x5_shown_centers"]]
    if visible_rects:
        after |= rect_mask(visible_rects, 4)
    return before, after[:, 20:620].copy()


def line_clear(xs: np.ndarray, ys: np.ndarray, target: tuple[float, float], solid: np.ndarray) -> np.ndarray:
    """Vector form of game.fps_game._fps_line_clear for integer player cells."""
    if len(xs) == 0:
        return np.zeros(0, bool)
    dx, dy = target[0] - xs, target[1] - ys
    distance = np.hypot(dx, dy)
    count = np.floor(distance / 5.0).astype(np.int16)
    clear = np.ones(len(xs), bool)
    for step in range(1, int(count.max(initial=0))):
        active = clear & (step < count) & (distance > 0)
        if not active.any():
            break
        indices = np.flatnonzero(active)
        fraction = step * 5.0 / distance[indices]
        x = xs[indices] + dx[indices] * fraction
        y = ys[indices] + dy[indices] * fraction
        valid = (x >= 20) & (x < 620) & (y >= 0) & (y < 400)
        hits = np.zeros(len(indices), bool)
        if valid.any():
            hits[valid] = solid[np.floor(y[valid]).astype(int), np.floor(x[valid]).astype(int) - 20]
        clear[indices[hits]] = False
    return clear


def talk_records(actors: list[dict], before_reach: np.ndarray, after_reach: np.ndarray,
                 before_solid: np.ndarray, after_solid: np.ndarray) -> list[dict]:
    if not actors:
        return []
    availability = [[np.zeros((400, 600), bool) for _ in actors] for _ in range(2)]
    for version, solid in enumerate((before_solid, after_solid)):
        lines = []
        patches = []
        for actor in actors:
            target = tuple(actor["source_xy"])
            xa, xb, ya, yb, dx, dy, d2 = common.patch(target, 90.0)
            if xa >= xb or ya >= yb:
                lines.append(np.zeros((0, 0), bool))
                patches.append((xa, xb, ya, yb, dx, dy, d2))
                continue
            yy, xx = np.mgrid[ya:yb, xa:xb]
            candidate = d2 < 90.0 ** 2
            clear = np.zeros_like(candidate)
            py, px = np.where(candidate)
            if len(px):
                clear[py, px] = line_clear((px + xa).astype(float), (py + ya).astype(float), target, solid)
            lines.append(clear)
            patches.append((xa, xb, ya, yb, dx, dy, d2))
        for fx, fy in common.DIRS:
            best = np.full((400, 600), 90.0 ** 2, np.float32)
            winner = np.full((400, 600), -1, np.int16)
            for i, (xa, xb, ya, yb, dx, dy, d2) in enumerate(patches):
                if xa >= xb or ya >= yb:
                    continue
                facing = (d2 < 20.0 ** 2) | ((dx * fx + dy * fy) > 0.55 * np.sqrt(d2))
                view = best[ya:yb, xa - 20:xb - 20]
                selected = lines[i] & facing & (d2 < view)
                view[selected] = d2[selected]
                winner[ya:yb, xa - 20:xb - 20][selected] = i
            for i in range(len(actors)):
                availability[version][i] |= winner == i
    out = []
    for i, actor in enumerate(actors):
        b = int((availability[0][i] & before_reach).sum())
        a = int((availability[1][i] & after_reach).sum())
        out.append({**actor, "mode": "fps_talk_static_cone_line_8facings",
                    "before_reachable_cells": b, "after_reachable_cells": a,
                    "status": common.status(b, a)})
    return out


def hit_record(actor: dict, before_reach: np.ndarray, after_reach: np.ndarray,
               before_solid: np.ndarray, after_solid: np.ndarray) -> dict:
    target = tuple(actor["source_xy"])
    hb = actor["source_hard_rect_xyxy"]
    masks = []
    for solid in (before_solid, after_solid):
        possible = np.zeros((400, 600), bool)
        for direction, (fx, fy) in ((4, (-1, 0)), (6, (1, 0)), (8, (0, -1)), (2, (0, 1))):
            x0, y0, x1, y1 = melee_rect(hb, direction)
            xa, xb = max(20, int(np.floor(x0))), min(620, int(np.ceil(x1)))
            ya, yb = max(0, int(np.floor(y0))), min(400, int(np.ceil(y1)))
            if xa >= xb or ya >= yb:
                continue
            yy, xx = np.mgrid[ya:yb, xa:xb]
            dx, dy = target[0] - xx, target[1] - yy
            distance = np.hypot(dx, dy)
            candidate = (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1) & (distance > 0.01)
            candidate &= (dx * fx + dy * fy) >= 0.60 * distance
            py, px = np.where(candidate)
            if not len(px):
                continue
            clear = line_clear((px + xa).astype(float), (py + ya).astype(float), target, solid)
            possible[py[clear] + ya, px[clear] + xa - 20] = True
        masks.append(possible)
    b = int((masks[0] & before_reach).sum())
    a = int((masks[1] & after_reach).sum())
    return {**actor, "mode": "fps_melee_static_hitbox_cone_line",
            "before_reachable_cells": b, "after_reachable_cells": a,
            "status": common.status(b, a)}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    for name,help_text in (("broad","interaction census JSON"),("masks","before/after topology masks NPZ"),
        ("world","world.json"),("native","native inventory JSON"),("footprints","footprints.json"),
        ("walls","wall source/effective mask JSON"),("firs","fir source/effective mask JSON"),
        ("out","output FPS static interaction JSON")):
        parser.add_argument("--"+name,type=Path,required=True,help=help_text)
    parser.add_argument("--screen",type=int,help="Process one screen for a bounded smoke check")
    args=parser.parse_args()
    broad=json.loads(args.broad.read_text()); world_doc=json.loads(args.world.read_text())
    world=world_doc["screens"]; fdoc=json.loads(args.footprints.read_text()); footprints=fdoc.get("screens",fdoc)
    native=json.loads(args.native.read_text()); walls=json.loads(args.walls.read_text()); firs=json.loads(args.firs.read_text())
    configure(world_doc,footprints,native,walls,firs)
    with np.load(args.masks,allow_pickle=False) as masks:
        before,after=masks["before_reachable"],masks["after_reachable"]
        before_indoor,after_indoor,indoor_diag=common.indoor_reach(world_doc,native,footprints,before,after)
        grouped={}
        for record in broad["records"]:
            if record["mode"] not in ("talk_nearest_any_facing_90px","hit_default_fist_48px"): continue
            if args.screen is not None and int(record["screen"]) != args.screen: continue
            grouped.setdefault(int(record["screen"]),{}).setdefault(record["mode"],[]).append(record)
        records=[]
        for screen,classes in grouped.items():
            key=str(screen)
            b,a=(before_indoor[key],after_indoor[key]) if world[key].get("indoor") else (common.local(before,screen),common.local(after,screen))
            bs,ass=structure(screen)
            records.extend(talk_records(classes.get("talk_nearest_any_facing_90px",[]),b,a,bs,ass))
            for actor in classes.get("hit_default_fist_48px",[]): records.append(hit_record(actor,b,a,bs,ass))
            print("fps static screen",screen,flush=True)
    failures=[r for r in records if r["status"].startswith("FAIL")]
    modes=sorted({r["mode"] for r in records})
    mode_counts={mode:sum(r["mode"]==mode for r in records) for mode in modes}
    savebot=[r for r in records if r["screen"]==768 and r["editor_index"]==4]
    output={"schema":"rc5-fps-static-interaction-1","records":records,"mode_counts":mode_counts,
        "lost_all_static_cone_line_candidates":failures,"screen768_savebot":savebot,
        "indoor_reach":{"indoor_screens":len(before_indoor),"before_reached_components":indoor_diag["before_reached_components"],
                         "after_reached_components":indoor_diag["after_reached_components"]},
        "limits":["_fps_line_clear is approximated at its 5px samples using source tile, native footprint, new wall and fir integer structure masks; fractional polygon edges may differ. Entity hardboxes are excluded as in _structure_blocked.",
                   "Eight cardinal/diagonal facing directions are tested for talk; FPS camera yaw is continuous, so counts are conservative lower bounds for facing choices.",
                   "Melee uses the actual default source hardbox extension and 0.60 facing cone, but omits actual nearest-target selection and equipped range changes.",
                   "Physics _fps_ray_reaches, visual height/geometry and live script/input are not certified; live savebot probing is a separate audit."]}
    output["input_sha256"]={str(path):hashlib.sha256(path.read_bytes()).hexdigest()
                            for path in (args.broad,args.masks,args.world,args.native,args.footprints,args.walls,args.firs)}
    args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(output,indent=2)+"\n")
    print("FPS STATIC",mode_counts,"failures",len(failures),"savebot",savebot,flush=True)


if __name__=="__main__": main()
