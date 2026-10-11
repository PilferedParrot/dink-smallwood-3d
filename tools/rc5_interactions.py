"""Worldwide authored interaction reach before/after the RC5 solids.

Uses the topology compiler's exact static-warp-reachable integer free masks.
Scripted talk reproduces game.gd's <90px, facing and nearest-actor selection
over all eight Dink directions. Scripted hit/hostile proximity uses the native
default 48px fist reach; touch and warp use their source hardbox triggers.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import rect_mask, tile_mask  # noqa: E402

DIRS = [(-1, 1), (0, 1), (1, 1), (-1, 0), (1, 0), (-1, -1), (0, -1), (1, -1)]
DIRS = [(x / (x * x + y * y) ** 0.5, y / (x * x + y * y) ** 0.5) for x, y in DIRS]
NPC_KEYS = {"man", "woman", "wizard", "knight", "pig", "duck", "pillbug", "bonca", "slime", "dragon"}


def local(mask: np.ndarray, screen: int) -> np.ndarray:
    oy, ox = (screen - 1) // 32 * 400, (screen - 1) % 32 * 600
    return mask[oy:oy + 400, ox:ox + 600]


def indoor_reach(world_doc: dict, native: dict, footprints: dict,
                            before_outdoor: np.ndarray, after_outdoor: np.ndarray) -> tuple[dict, dict, dict]:
    labels = {}
    for key, record in native["indoor_collision"].items():
        fit = footprints.get(key, {})
        hard, _ = tile_mask(world_doc, int(key), fit.get("revert", ()), fit.get("clear", ()))
        hard |= rect_mask(record["hard_rects"], 4)
        for y, a, b in record["footprint_runs"]:
            hard[y, a:b] = True
        free = ~hard
        free[:, :20] = False
        free[:, 620:] = False
        label, _ = ndimage.label(free[:, 20:620])
        labels[key] = label

    def target_component(warp: dict) -> tuple[str, int] | None:
        key = str(warp["target"])
        if key not in labels:
            return None
        x, y = warp["destination"]
        if not (20 <= x < 620 and 0 <= y < 400):
            return None
        tag = int(labels[key][int(y), int(x) - 20])
        return (key, tag) if tag else None

    trigger_tags = {}
    for i, warp in enumerate(native["static_warps"]):
        key = str(warp["screen"])
        if key not in labels:
            continue
        x0, y0, x1, y1 = warp["trigger"]
        xa, xb = max(20, int(np.ceil(x0))), min(620, int(np.ceil(x1)))
        ya, yb = max(0, int(np.ceil(y0))), min(400, int(np.ceil(y1)))
        tags = set(map(int, np.unique(labels[key][ya:yb, xa - 20:xb - 20]))) if xa < xb and ya < yb else set()
        tags.discard(0)
        trigger_tags[i] = {(key, tag) for tag in tags}

    results = []
    for outdoor in (before_outdoor, after_outdoor):
        reached = set()
        changed = True
        while changed:
            changed = False
            for i, warp in enumerate(native["static_warps"]):
                target = target_component(warp)
                if target is None or target in reached:
                    continue
                key = str(warp["screen"])
                if key in labels:
                    source_ready = bool(trigger_tags.get(i, set()) & reached)
                else:
                    source_ready = rect_counts(local(outdoor, int(key)), local(outdoor, int(key)), warp["trigger"])[0] > 0
                if source_ready:
                    reached.add(target)
                    changed = True
        masks = {key: np.isin(label, [tag for screen, tag in reached if screen == key])
                 for key, label in labels.items()}
        results.append((masks, reached))
    diagnostics = {"indoor_screens": len(labels), "before_reached_components": len(results[0][1]),
                   "after_reached_components": len(results[1][1])}
    return results[0][0], results[1][0], diagnostics


def indoor_native_like(source: dict, sequences: dict) -> dict:
    hb = source.get("hardbox", [])
    seq = int(source.get("seq", 0))
    frame_no = int(source.get("frame", 1))
    frames = sequences.get(str(seq), {}).get("frames", [])
    frame = frames[frame_no - 1] if 1 <= frame_no <= len(frames) else {}
    if len(hb) != 4 or all(float(v) == 0 for v in hb):
        hb = frame.get("hardbox", [-10, -6, 10, 6])
    factor = float(source.get("size", 100)) / 100.0
    x, y = float(source.get("x", 0)), float(source.get("y", 0))
    path = str(frame.get("path", ""))
    key = "man" if "/people/" in path.lower() else ""
    return {"hard_rect": [x + hb[0] * factor, y + hb[1] * factor,
                          x + hb[2] * factor, y + hb[3] * factor],
            "key": key, "path": path, "frame_known": bool(frame)}


def actor_record(screen: int, list_index: int, source: dict, native: dict) -> dict:
    return {"screen": screen, "list_index": list_index, "editor_index": int(source.get("index", -1)),
            "script": source.get("script", ""), "key": native.get("key", ""),
            "type": int(source.get("type", 1)), "brain": int(source.get("brain", 0)),
            "source_xy": [float(source.get("x", 0)), float(source.get("y", 0))],
            "source_hard_rect_xyxy": native.get("hard_rect", []),
            "vision": int(source.get("vision", 0))}


def patch(anchor: tuple[float, float], radius: float) -> tuple[int, int, int, int, np.ndarray, np.ndarray, np.ndarray]:
    x, y = anchor
    xa, xb = max(20, int(np.floor(x - radius))), min(620, int(np.ceil(x + radius)))
    ya, yb = max(0, int(np.floor(y - radius))), min(400, int(np.ceil(y + radius)))
    if xa >= xb or ya >= yb:
        empty = np.empty((0, 0))
        return xa, xb, ya, yb, empty, empty, empty
    yy, xx = np.mgrid[ya:yb, xa:xb]
    dx, dy = x - xx, y - yy
    return xa, xb, ya, yb, dx, dy, dx * dx + dy * dy


def radial_counts(before: np.ndarray, after: np.ndarray, anchor: tuple[float, float], radius: float) -> tuple[int, int]:
    xa, xb, ya, yb, _, _, distance2 = patch(anchor, radius)
    if xa >= xb or ya >= yb:
        return 0, 0
    eligible = distance2 < radius * radius
    return int((eligible & before[ya:yb, xa - 20:xb - 20]).sum()), int((eligible & after[ya:yb, xa - 20:xb - 20]).sum())


def rect_counts(before: np.ndarray, after: np.ndarray, rect: list[float]) -> tuple[int, int]:
    x0, y0, x1, y1 = rect
    xa, xb = max(20, int(np.floor(x0))), min(620, int(np.ceil(x1)))
    ya, yb = max(0, int(np.floor(y0))), min(400, int(np.ceil(y1)))
    if xa >= xb or ya >= yb:
        return 0, 0
    yy, xx = np.mgrid[ya:yb, xa:xb]
    eligible = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    return int((eligible & before[ya:yb, xa - 20:xb - 20]).sum()), int((eligible & after[ya:yb, xa - 20:xb - 20]).sum())


def talk_winners(before: np.ndarray, after: np.ndarray, actors: list[dict]) -> list[tuple[int, int]]:
    """Any facing that selects this scripted actor under game._talk's nearest rule."""
    if not actors:
        return []
    eligible_any = [np.zeros((400, 600), dtype=bool) for _ in actors]
    for fx, fy in DIRS:
        best = np.full((400, 600), 90.0 ** 2, np.float32)
        winner = np.full((400, 600), -1, np.int16)
        for i, item in enumerate(actors):
            anchor = tuple(item["source_xy"])
            xa, xb, ya, yb, dx, dy, distance2 = patch(anchor, 90.0)
            if xa >= xb or ya >= yb:
                continue
            facing = ((dx * fx + dy * fy) > -0.2 * np.sqrt(distance2)) | (distance2 < 28.0 ** 2)
            view_best = best[ya:yb, xa - 20:xb - 20]
            selected = facing & (distance2 < view_best)
            view_best[selected] = distance2[selected]
            winner[ya:yb, xa - 20:xb - 20][selected] = i
        for i in range(len(actors)):
            eligible_any[i] |= winner == i
    return [(int((view & before).sum()), int((view & after).sum())) for view in eligible_any]


def status(before: int, after: int) -> str:
    if before and not after:
        return "FAIL_LOST_ALL_REACHABLE_INTERACTION_CELLS"
    if not before:
        return "PREEXISTING_NO_REACHABLE_CELLS_OR_UNMODELED"
    return "PASS_RETAINED_REACHABLE_CELLS"


def landing(screen: int, xy: list[float], world: dict,
            before: np.ndarray, after: np.ndarray,
            before_hard: np.ndarray, after_hard: np.ndarray,
            before_indoor: dict, after_indoor: dict) -> dict:
    x, y = map(float, xy)
    result = {"destination_screen": screen, "destination_xy": [x, y]}
    if str(screen) not in world or not (20 <= x < 620 and 0 <= y < 400):
        return {**result, "status": "DESTINATION_OUTSIDE_AUTHORED_PLAYFIELD_UNVERIFIED"}
    if world[str(screen)].get("indoor"):
        b, a = before_indoor[str(screen)], after_indoor[str(screen)]
        before_free_reached = bool(b[int(y), int(x) - 20])
        after_free_reached = bool(a[int(y), int(x) - 20])
        before_solid = after_solid = None
    else:
        b, a = local(before, screen), local(after, screen)
        bh, ah = local(before_hard, screen), local(after_hard, screen)
        before_free_reached = bool(b[int(y), int(x) - 20])
        after_free_reached = bool(a[int(y), int(x) - 20])
        before_solid = bool(bh[int(y), int(x) - 20])
        after_solid = bool(ah[int(y), int(x) - 20])
    if before_free_reached and not after_free_reached:
        verdict = "FAIL_PREVIOUSLY_REACHABLE_LANDING_LOST"
    elif before_solid is False and after_solid is True:
        verdict = "FAIL_NEW_SOLID_AT_LANDING"
    elif before_free_reached and after_free_reached:
        verdict = "PASS_REACHABLE_LANDING_RETAINED"
    else:
        verdict = "PREEXISTING_NOT_STATIC_REACHABLE_OR_UNKNOWN"
    return {**result, "before_static_reachable": before_free_reached,
            "after_static_reachable": after_free_reached,
            "before_solid": before_solid, "after_solid": after_solid,
            "status": verdict}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    for name,help_text in (("world","world.json"),("sequences","sequences.json"),
        ("footprints","footprints.json"),("native","native static inventory JSON"),
        ("masks","before/after topology reachability NPZ"),("story","story.json"),
        ("route-audit","story route audit JSON"),("out","output interaction census JSON")):
        parser.add_argument("--"+name,type=Path,required=True,help=help_text)
    args=parser.parse_args()
    for path in (args.world,args.sequences,args.footprints,args.native,args.masks,args.story,args.route_audit):
        if not path.is_file(): raise FileNotFoundError(path)
    data = np.load(args.masks, allow_pickle=False)
    before = data["before_reachable"]
    after = data["after_reachable"]
    before_hard = data["before_hard"]
    after_hard = data["after_hard"]
    assert before.shape == after.shape and before.dtype == bool and after.dtype == bool
    world_doc = json.loads(args.world.read_text())
    world = world_doc["screens"]
    footprints = json.loads(args.footprints.read_text())["screens"]
    sequences = json.loads(args.sequences.read_text())["sequences"]
    native = json.loads(args.native.read_text())
    story = json.loads(args.story.read_text())["scripts"]
    route_audit = json.loads(args.route_audit.read_text())["story_audit"]
    before_indoor, after_indoor, indoor_diagnostics = indoor_reach(world_doc, native, footprints, before, after)
    records = []
    screens_checked = {"outdoor": 0, "indoor": 0}
    unknown_indoor_frames = []
    excluded_authored_layers = []
    for key, source_screen in world.items():
        n = int(key)
        inside = bool(source_screen.get("indoor"))
        screens_checked["indoor" if inside else "outdoor"] += 1
        b, a = (before_indoor[key], after_indoor[key]) if inside else (local(before, n), local(after, n))
        talk = []
        others = []
        source_items = (indoor_native_like(source, sequences) for source in source_screen["sprites"]) if inside else native["screens"][key]
        for i, (source, item) in enumerate(zip(source_screen["sprites"], source_items, strict=True)):
            if inside and not item.get("frame_known"):
                unknown_indoor_frames.append({"screen": n, "list_index": i, "editor_index": source.get("index")})
            script = str(source.get("script", "")).lower()
            procedures = story.get(script, {}).get("procedures", {})
            if int(source.get("vision", 0)) != 0 or int(source.get("type", 1)) == 2:
                if source.get("warp") is not None or any(procedures.get(mode, {}).get("code") for mode in ("talk", "hit", "touch")):
                    excluded_authored_layers.append({"screen": n, "list_index": i,
                        "editor_index": source.get("index"), "vision": source.get("vision"),
                        "type": source.get("type"), "script": script,
                        "reason": "outside vision0 active-standing inventory"})
                continue
            rec = actor_record(n, i, source, item)
            if procedures.get("talk", {}).get("code") and int(source.get("type", 1)) == 1:
                talk.append(rec)
            if (procedures.get("hit", {}).get("code") or item.get("key") in NPC_KEYS
                    or int(source.get("brain", 0)) in (3, 4, 9, 10, 16)
                    or int(source.get("touch_damage", 0)) > 0):
                before_count, after_count = radial_counts(b, a, tuple(rec["source_xy"]), 48.0)
                others.append({**rec, "mode": "hit_default_fist_48px",
                               "before_reachable_cells": before_count,
                               "after_reachable_cells": after_count,
                               "status": status(before_count, after_count)})
            if procedures.get("touch", {}).get("code") or int(source.get("touch_damage", 0)) != 0:
                radius = 8 if int(source.get("touch_damage", 0)) == -1 else 4
                hb = item["hard_rect"]
                trigger = [hb[0] - radius, hb[1] - radius, hb[2] + radius, hb[3] + radius]
                before_count, after_count = rect_counts(b, a, trigger)
                actual = int(source.get("touch_damage", 0)) != 0
                others.append({**rec, "mode": "touch_hardbox",
                               "actual_source_touch_damage": int(source.get("touch_damage", 0)),
                               "script_touch_without_static_activation": not actual,
                               "trigger_rect_xyxy": trigger,
                               "before_reachable_cells": before_count,
                               "after_reachable_cells": after_count,
                               "status": status(before_count, after_count) if actual else "DYNAMIC_ACTIVATION_UNVERIFIED"})
        for rec, (before_count, after_count) in zip(talk, talk_winners(b, a, talk), strict=True):
            others.append({**rec, "mode": "talk_nearest_any_facing_90px",
                           "before_reachable_cells": before_count,
                           "after_reachable_cells": after_count,
                           "status": status(before_count, after_count)})
        records.extend(others)
        if n % 100 == 0:
            print("interaction screen", n, flush=True)
    for warp in native["static_warps"]:
        n = int(warp["screen"])
        rec = {"screen": n, "editor_index": int(warp["index"]), "mode": "native_static_warp_trigger",
               "target": warp["target"], "destination_xy": warp["destination"],
               "trigger_rect_xyxy": warp["trigger"]}
        b, a = (before_indoor[str(n)], after_indoor[str(n)]) if world[str(n)].get("indoor") else (
            local(before, n), local(after, n))
        bc, ac = rect_counts(b, a, warp["trigger"])
        rec.update({"before_reachable_cells": bc, "after_reachable_cells": ac,
                    "status": status(bc, ac)})
        records.append(rec)
    native_warp_ids = {(int(w["screen"]), int(w["index"])) for w in native["static_warps"]}
    other_world_warps = []
    for key, screen in world.items():
        for i, source in enumerate(screen["sprites"]):
            if source.get("warp") is None or (int(key), int(source.get("index", -1))) in native_warp_ids:
                continue
            other_world_warps.append({"screen": int(key), "list_index": i,
                                      "editor_index": int(source.get("index", -1)),
                                      "vision": int(source.get("vision", 0)),
                                      "destination": source["warp"],
                                      "status": "OTHER_VISION_LAYER_UNVERIFIED"})
    warp_destinations = []
    for warp in native["static_warps"]:
        result = landing(int(warp["target"]), warp["destination"], world,
                         before, after, before_hard, after_hard, before_indoor, after_indoor)
        warp_destinations.append({"source_screen": int(warp["screen"]),
                                  "source_editor_index": int(warp["index"]), **result})
    story_destinations = []
    for route in route_audit["paired_routes"]:
        xy = route["paired_player_xy_before_load"]
        if xy[0] is None or xy[1] is None:
            result = {"status": "DYNAMIC_PLAYER_XY_AT_LOAD_UNVERIFIED"}
        else:
            result = landing(int(route["destination_screen"]), xy, world,
                             before, after, before_hard, after_hard, before_indoor, after_indoor)
        story_destinations.append({"script_procedure": route["script_procedure"], **result})
    new_game_start = landing(1, [334, 161], world,
                             before, after, before_hard, after_hard, before_indoor, after_indoor)
    landing_failures = [item for item in warp_destinations + story_destinations + [new_game_start]
                        if item["status"].startswith("FAIL")]
    by_status = {}
    by_mode = {}
    for rec in records:
        by_status[rec["status"]] = by_status.get(rec["status"], 0) + 1
        by_mode[rec["mode"]] = by_mode.get(rec["mode"], 0) + 1
    losses = [rec for rec in records if rec["status"].startswith("FAIL")]
    savebot = [rec for rec in records if rec.get("screen") == 768 and rec.get("editor_index") == 4]
    output = {"schema": "rc5-worldwide-interaction-reach-1",
              "mask_source": str(args.masks),
              "basis": "integer free cells reachable from home439 with static vision0 warp graph; no startup scripts",
              "screens_checked": screens_checked, "indoor_reach": indoor_diagnostics,
              "unknown_indoor_frame_geometry": unknown_indoor_frames,
              "excluded_authored_layers_unverified": excluded_authored_layers,
              "other_vision_world_warps_unverified": other_world_warps,
              "warp_destinations": warp_destinations,
              "story_literal_destinations": story_destinations,
              "new_game_start": new_game_start,
              "lost_or_newly_solid_landings": landing_failures,
              "records": records, "counts_by_status": by_status, "counts_by_mode": by_mode,
              "lost_all_reachable_interactions": losses, "screen768_savebot": savebot,
              "limits": ["Talk uses exact nearest actor and eight possible facing directions at source static positions, but startup/editor state and actor movement are not executed.",
                         "Hit counts integer reachable cells within the default fist reach48px assuming a selectable facing; it does not execute attack input, animation, target state or a visual wall-line test. game.gd _attack uses distance and facing without a wall ray.",
                         "Indoor component access is closed under native static warps using unchanged source indoor collision; story-dependent portals and script state are not included.",
                         "Scripted touch whose touch_damage is set only at runtime is listed as dynamic/unverified.",
                         "Saved games, dynamic spawns and story changes can alter actor positions and are not certified."]}
    output["input_sha256"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in (args.world,args.sequences,args.footprints,args.native,args.masks,args.story,args.route_audit)}
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2) + "\n")
    print("INTERACTIONS", by_mode, by_status, "failures", len(losses),
          "landing_failures", len(landing_failures), flush=True)


if __name__ == "__main__":
    main()
