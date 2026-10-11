#!/usr/bin/env python3
"""Audit every surviving free component cut off by an after-topology mask.

Reports source pixels/hardboxes, authored touch/script/item fields, static and
raw warp candidates, edges, and paired literal story arrivals. This is static
geometry and authored-data evidence, not a gameplay run.
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


def code_of(proc):
    if isinstance(proc, list):
        return proc
    if isinstance(proc, dict):
        return proc.get("code", proc.get("instructions", []))
    return []


def walk(code, path=""):
    """Walk nested story instruction lists with the source audit's AST paths."""
    for index, instruction in enumerate(code if isinstance(code, list) else []):
        if not isinstance(instruction, dict):
            continue
        pos = f"{path}{index}"
        yield pos, instruction
        for key in ("then", "else", "body", "code", "instructions"):
            nested = instruction.get(key)
            if isinstance(nested, list):
                yield from walk(nested, f"{pos}.{key}.")


def screen_origin(screen: int) -> tuple[int, int]:
    return ((screen - 1) % 32 * 600 - 20, (screen - 1) // 32 * 400)


def translated_xy(x: float, y: float, source_screen: int, target_screen: int) -> tuple[float, float]:
    sx, sy = screen_origin(source_screen)
    tx, ty = screen_origin(target_screen)
    return x + sx - tx, y + sy - ty


def bbox_hits(mask: np.ndarray, rect: tuple[float, float, float, float]) -> int:
    x0, y0, x1, y1 = rect
    xa, xb = max(20, int(np.floor(x0))), min(620, int(np.ceil(x1)))
    ya, yb = max(0, int(np.floor(y0))), min(400, int(np.ceil(y1)))
    if xa >= xb or ya >= yb:
        return 0
    yy, xx = np.mgrid[ya:yb, xa:xb]
    return int((mask[ya:yb, xa - 20:xb - 20]
                & (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)).sum())


def point_hit(mask: np.ndarray, xy: tuple[float, float]) -> bool:
    x, y = xy
    return 20 <= x < 620 and 0 <= y < 400 and bool(mask[int(y), int(x) - 20])


def component_runs(mask: np.ndarray) -> list[list[int]]:
    runs = []
    for y, row in enumerate(mask):
        edges = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), (1, 1))))
        runs.extend([[int(y), int(a + 20), int(b + 20)] for a, b in edges.reshape(-1, 2)])
    return runs


def mask_from_runs(runs: list[list[int]]) -> np.ndarray:
    mask = np.zeros((400, 600), dtype=bool)
    for y, x0, x1 in runs:
        mask[int(y), int(x0) - 20:int(x1) - 20] = True
    return mask


@lru_cache(maxsize=256)
def art_image(game_dir: str, path: str) -> np.ndarray:
    return np.asarray(Image.open(Path(game_dir) / path).convert("RGBA"))


@lru_cache(maxsize=512)
def art_size(game_dir: str, path: str) -> tuple[int, int]:
    with Image.open(Path(game_dir) / path) as im:
        return im.width, im.height


def draw_overlap(mask: np.ndarray, image: np.ndarray, left: float, top: float, scale: float) -> dict:
    h, w = image.shape[:2]
    bounds = (left, top, left + w * scale, top + h * scale)
    conservative = bbox_hits(mask, bounds)
    exact = scale == 1.0 and float(left).is_integer() and float(top).is_integer()
    if not conservative:
        return {"draw_bbox_xyxy": bounds, "bbox_overlap_px": 0,
                "alpha_overlap_px": 0 if exact else None,
                "nonblack_overlap_px": 0 if exact else None,
                "exact_pixel_mapping": exact}
    if not exact:
        return {"draw_bbox_xyxy": bounds, "bbox_overlap_px": conservative,
                "alpha_overlap_px": None, "nonblack_overlap_px": None,
                "exact_pixel_mapping": False}
    x0, y0 = int(left), int(top)
    xa, xb = max(20, x0), min(620, x0 + w)
    ya, yb = max(0, y0), min(400, y0 + h)
    pocket = mask[ya:yb, xa - 20:xb - 20]
    pixels = image[ya - y0:yb - y0, xa - x0:xb - x0]
    alpha = pixels[:, :, 3] > 127
    nonblack = alpha & (pixels[:, :, :3].astype(np.int16).sum(axis=2) >= 11)
    return {"draw_bbox_xyxy": bounds, "bbox_overlap_px": conservative,
            "alpha_overlap_px": int((pocket & alpha).sum()),
            "nonblack_overlap_px": int((pocket & nonblack).sum()),
            "exact_pixel_mapping": True}


def build_components(masks: dict[str, np.ndarray], world: dict) -> list[dict]:
    records = []
    for screen_text, source_screen in world.items():
        if source_screen.get("indoor"):
            continue
        screen = int(screen_text)
        row, col = divmod(screen - 1, 32)
        y0, x0 = row * 400, col * 600
        before = masks["before_reachable"][y0:y0 + 400, x0:x0 + 600]
        after = masks["after_reachable"][y0:y0 + 400, x0:x0 + 600]
        after_hard = masks["after_hard"][y0:y0 + 400, x0:x0 + 600]
        surviving_cutoff = before & ~after & ~after_hard
        labels, count = ndimage.label(surviving_cutoff)
        for label_id, bounds in enumerate(ndimage.find_objects(labels), 1):
            if bounds is None:
                continue
            local_component = labels == label_id
            pixels = int(local_component.sum())
            ys, xs = np.where(local_component)
            bbox = [int(xs.min()) + 20, int(ys.min()), int(xs.max()) + 21, int(ys.max()) + 1]
            component_id = f"{screen}:{label_id - 1}"
            mask_runs = component_runs(local_component)
            record = {"component_id": component_id, "screen": screen,
                      "pixels": pixels, "bbox_xyxy": bbox,
                      "touches_screen_edge": bool(local_component[0].any() or local_component[-1].any()
                                                   or local_component[:, 0].any() or local_component[:, -1].any()),
                      "runs": mask_runs}
            records.append(record)
    records.sort(key=lambda r: (r["screen"], r["bbox_xyxy"][1], r["bbox_xyxy"][0], r["component_id"]))
    return records


def sequence_frame(source: dict, item: dict, sequences: dict, by_path: dict) -> dict | None:
    seq = int(source.get("seq", 0)); frame_no = int(source.get("frame", 1))
    if seq == 0:
        seq = int(source.get("pseq", 0)); frame_no = int(source.get("pframe", 1))
    frames = sequences.get(str(seq), {}).get("frames", [])
    frame = frames[frame_no - 1] if 1 <= frame_no <= len(frames) else None
    if frame and frame.get("path") != item.get("path"):
        frame = by_path.get(item.get("path"))
    if not frame:
        frame = by_path.get(item.get("path"))
    return frame


def sprite_audit(world: dict, native: dict, sequences: dict, story: dict,
                 components: list[dict], game_dir: Path) -> dict:
    by_path = {}
    for seq in sequences.values():
        for frame in seq.get("frames", []):
            if frame.get("path"):
                by_path.setdefault(frame["path"], frame)
    pocket_results = {c["component_id"]: {"anchor_hits": [], "hardbox_hits": [],
        "grown4_hardbox_candidates": [], "actual_touch_or_warp_candidates": [],
        "draw_bbox_candidates": [], "draw_alpha_hits": [], "talk_reach_candidates": [],
        "script_or_item_content_candidates": []} for c in components}
    unresolved_draw = []
    sources = []
    checked = 0
    for screen_text, source_screen in world.items():
        screen = int(screen_text)
        if source_screen.get("indoor") or screen_text not in native.get("screens", {}):
            continue
        for list_index, (source, item) in enumerate(zip(source_screen.get("sprites", []), native["screens"][screen_text], strict=True)):
            checked += 1
            anchor_xy = [float(source.get("x", 0)), float(source.get("y", 0))]
            hb = list(map(float, item.get("hard_rect", [])))
            if len(hb) != 4:
                hb = [0.0, 0.0, 0.0, 0.0]
            script = str(source.get("script", "")).lower()
            procs = story.get(script, {}).get("procedures", {})
            warp = source.get("warp")
            descriptor = {"source_screen": screen, "list_index": list_index,
                "editor_index": int(source.get("index", -1)), "type": int(source.get("type", 1)),
                "vision": int(source.get("vision", 0)), "seq": int(source.get("seq", 0)),
                "frame": int(source.get("frame", 1)), "pseq": int(source.get("pseq", 0)),
                "pframe": int(source.get("pframe", 1)), "path": item.get("path", ""),
                "script": source.get("script", ""), "script_procedures_present": {
                    "talk": bool(procs.get("talk", {}).get("code", [])),
                    "hit": bool(procs.get("hit", {}).get("code", [])),
                    "touch": bool(procs.get("touch", {}).get("code", []))},
                "is_item_type": int(source.get("type", 1)) == 2,
                "hard": int(source.get("hard", 1)), "brain": int(source.get("brain", 0)),
                "touch_damage": int(source.get("touch_damage", 0)), "warp": warp,
                "gold": int(source.get("gold", 0)), "special": int(source.get("special", 0)),
                "exp": int(source.get("exp", 0)), "hitpoints": float(source.get("hitpoints", 0)),
                "source_xy": anchor_xy, "source_hardbox_xyxy": hb}
            frame = sequence_frame(source, item, sequences, by_path)
            image_path = str(item.get("path", ""))
            scale = float(source.get("size", 100)) / 100.0
            image_size = None
            if image_path and frame:
                try:
                    image_size = art_size(str(game_dir), image_path)
                except (FileNotFoundError, OSError):
                    unresolved_draw.append({**descriptor, "reason": "source image unavailable"})
            elif image_path:
                unresolved_draw.append({**descriptor, "reason": "frame geometry unavailable"})
            sources.append({"descriptor": descriptor, "screen": screen, "anchor_xy": anchor_xy,
                            "hardbox": hb, "frame": frame, "scale": scale,
                            "image_path": image_path, "image_size": image_size,
                            "warp": warp, "type": int(source.get("type", 1))})

    for component in components:
        component_id = component["component_id"]
        component_screen = int(component["screen"])
        mask = mask_from_runs(component["runs"])
        pocket_y, pocket_x = np.where(mask)
        pocket_x = pocket_x + 20
        for src in sources:
            descriptor = src["descriptor"]
            screen = src["screen"]
            anchor_xy = src["anchor_xy"]
            hb = src["hardbox"]
            anchor = translated_xy(anchor_xy[0], anchor_xy[1], screen, component_screen)
            hx0, hy0 = translated_xy(hb[0], hb[1], screen, component_screen)
            hx1, hy1 = translated_xy(hb[2], hb[3], screen, component_screen)
            hardbox = (hx0, hy0, hx1, hy1)
            desc = {**descriptor, "component_id": component_id, "component_screen": component_screen,
                    "anchor_local_xy": anchor, "hardbox_local_xyxy": hardbox}
            anchor_hit = point_hit(mask, anchor)
            if anchor_hit:
                pocket_results[component_id]["anchor_hits"].append(desc)
            strict = bbox_hits(mask, hardbox)
            if strict:
                pocket_results[component_id]["hardbox_hits"].append({**desc, "overlap_px": strict})
            grown = bbox_hits(mask, (hx0 - 4, hy0 - 4, hx1 + 4, hy1 + 4))
            if grown:
                pocket_results[component_id]["grown4_hardbox_candidates"].append({**desc, "overlap_px": grown})
            warp = src["warp"]
            damage = int(descriptor["touch_damage"])
            radius = 7 if warp is not None else (8 if damage == -1 else 4 if damage > 0 else 0)
            if radius:
                n = bbox_hits(mask, (hx0 - radius, hy0 - radius, hx1 + radius, hy1 + radius))
                if n:
                    pocket_results[component_id]["actual_touch_or_warp_candidates"].append(
                        {**desc, "overlap_px": n, "runtime_grow_px": radius,
                         "kind": "warp" if warp is not None else "touch_damage"})
            if src["image_size"] and src["frame"]:
                frame = src["frame"]; scale = src["scale"]
                left = anchor[0] - float(frame.get("dx", 0)) * scale
                top = anchor[1] - float(frame.get("dy", 0)) * scale
                iw, ih = src["image_size"]
                bounds = (left, top, left + iw * scale, top + ih * scale)
                if bbox_hits(mask, bounds):
                    try:
                        image = art_image(str(game_dir), src["image_path"])
                        hit = draw_overlap(mask, image, left, top, scale)
                    except (FileNotFoundError, OSError):
                        unresolved_draw.append({**desc, "reason": "source image unavailable during overlap"})
                        hit = {"bbox_overlap_px": 0}
                    if hit["bbox_overlap_px"]:
                        candidate = {**desc, **hit}
                        pocket_results[component_id]["draw_bbox_candidates"].append(candidate)
                        if hit.get("alpha_overlap_px") is not None and hit["alpha_overlap_px"] > 0:
                            pocket_results[component_id]["draw_alpha_hits"].append(candidate)
            if descriptor["script"] or src["type"] == 2:
                if strict or grown or anchor_hit:
                    pocket_results[component_id]["script_or_item_content_candidates"].append(
                        {**desc, "source_overlap_px": strict, "grown4_overlap_px": grown,
                         "origin_hit": anchor_hit})
            if descriptor["script_procedures_present"]["talk"] and src["type"] == 1:
                dx = pocket_x - anchor[0]; dy = pocket_y - anchor[1]
                dist2 = dx * dx + dy * dy
                near = np.flatnonzero(dist2 < 90.0 ** 2)
                if len(near):
                    i = int(near[np.argmin(dist2[near])])
                    pocket_results[component_id]["talk_reach_candidates"].append(
                        {**desc, "nearest_pocket_xy": [int(pocket_x[i]), int(pocket_y[i])],
                         "distance_px": float(np.sqrt(dist2[i])),
                         "eligible_pocket_pixels_before_facing": int(len(near))})
    return {"checked_outdoor_source_sprites": checked,
            "unresolved_draw_frames": unresolved_draw,
            "components": pocket_results}


def warp_audit(world: dict, native: dict, components: list[dict]) -> dict:
    raw = []
    for key, screen in world.items():
        for i, sprite in enumerate(screen.get("sprites", [])):
            warp = sprite.get("warp")
            if not isinstance(warp, dict):
                continue
            native_item = native.get("screens", {}).get(key, [])
            native_item = native_item[i] if i < len(native_item) else {}
            raw.append({"source_screen": int(key), "list_index": i,
                        "editor_index": int(sprite.get("index", -1)),
                        "source_xy": [sprite.get("x"), sprite.get("y")],
                        "type": int(sprite.get("type", 1)), "vision": int(sprite.get("vision", 0)),
                        "script": sprite.get("script", ""), "target": warp.get("map"),
                        "destination": [warp.get("x"), warp.get("y")],
                        "source_hardbox_xyxy": native_item.get("hard_rect"),
                        "native_static_match": False})
    static = native.get("static_warps", [])
    for record in raw:
        record["native_static_match"] = (record["source_screen"], record["editor_index"]) in {
            (int(w["screen"]), int(w["index"])) for w in static}
    by_component = {}
    for component in components:
        cid = component["component_id"]; screen = int(component["screen"])
        mask = mask_from_runs(component["runs"])
        native_triggers, native_destinations, raw_source_candidates, raw_destinations = [], [], [], []
        for warp in static:
            source_screen = int(warp["screen"])
            dx = screen_origin(source_screen)[0] - screen_origin(screen)[0]
            dy = screen_origin(source_screen)[1] - screen_origin(screen)[1]
            a, b, c, d = warp["trigger"]
            count = bbox_hits(mask, (a + dx, b + dy, c + dx, d + dy))
            if count:
                native_triggers.append({"source_screen": source_screen, "index": int(warp["index"]),
                                        "target": warp.get("target"), "overlap_px": count})
            if int(warp["target"]) == screen and point_hit(mask, tuple(map(float, warp["destination"]))):
                native_destinations.append(warp)
        for record in raw:
            source_screen = record["source_screen"]
            if record.get("source_hardbox_xyxy"):
                dx = screen_origin(source_screen)[0] - screen_origin(screen)[0]
                dy = screen_origin(source_screen)[1] - screen_origin(screen)[1]
                h = record["source_hardbox_xyxy"]
                count = bbox_hits(mask, (float(h[0]) + dx - 7, float(h[1]) + dy - 7,
                                         float(h[2]) + dx + 7, float(h[3]) + dy + 7))
                if count:
                    raw_source_candidates.append({**record, "source_trigger_candidate_px": count})
            target = record.get("target")
            dest = record.get("destination")
            if target is not None and int(target) == screen and all(v is not None for v in dest):
                if point_hit(mask, tuple(map(float, dest))):
                    raw_destinations.append(record)
        by_component[cid] = {"native_trigger_hits": native_triggers,
                              "native_destination_hits": native_destinations,
                              "raw_world_source_trigger_candidates": raw_source_candidates,
                              "raw_world_destination_hits": raw_destinations}
    return {"native_static_warp_count": len(static), "raw_world_warp_count": len(raw),
            "raw_world_warps": raw, "components": by_component}


def story_audit(routes: dict, story: dict, components: list[dict]) -> dict:
    route_records = []
    for route in routes.get("literal_player_map_routes", []):
        script, proc = route["script_procedure"].rsplit(".", 1)
        instructions = list(walk(code_of(story[script]["procedures"][proc])))
        start = next(i for i, (path, _) in enumerate(instructions) if path == route["assignment_ast_path"])
        stop = next((i for i in range(start + 1, len(instructions))
                     if instructions[i][1].get("op") == "call"
                     and instructions[i][1].get("name") == "load_screen"), len(instructions))
        writes = {"x": [], "y": []}
        for _, ins in instructions[start + 1:stop]:
            if ins.get("op") != "call" or ins.get("name") not in ("sp_x", "sp_y"):
                continue
            args = ins.get("args", [])
            if len(args) < 2 or args[0].get("kind") != "literal" or args[0].get("value") != 1:
                continue
            axis = "x" if ins["name"] == "sp_x" else "y"
            writes[axis].append({"line": ins.get("line"), "expr": args[1]})
        x = writes["x"][-1]["expr"].get("value") if writes["x"] and writes["x"][-1]["expr"].get("kind") == "literal" else None
        y = writes["y"][-1]["expr"].get("value") if writes["y"] and writes["y"][-1]["expr"].get("kind") == "literal" else None
        record = {"script_procedure": route["script_procedure"], "map_write_line": route["assignment_line"],
                  "destination_screen": route["literal_destination"], "paired_player_xy_before_load": [x, y],
                  "paired_writes": writes, "position_known_at_load": x is not None and y is not None,
                  "source_screens": route["resolved_source_screens"], "component_hits": []}
        if x is not None and y is not None:
            for component in components:
                if int(record["destination_screen"]) == int(component["screen"]):
                    if point_hit(mask_from_runs(component["runs"]), (float(x), float(y))):
                        record["component_hits"].append(component["component_id"])
        route_records.append(record)
    dynamic = {"saved_game_load": "save data.screen and player x/y are runtime state; arbitrary existing save can enter a cut-off area",
               "force_vision_reload": "reloads current screen at retained current player x/y",
               "screen_startup_and_scripts": "startup, movement, story state, and arbitrary saved editor changes were not executed; no absence proof",
               "dynamic_map_expressions": routes.get("dynamic_script_callers", [])}
    new_game = {"initial_screen": 1, "player_xy": [334, 161], "component_hits": []}
    for component in components:
        if int(component["screen"]) == 1 and point_hit(mask_from_runs(component["runs"]), (334, 161)):
            new_game["component_hits"].append(component["component_id"])
    return {"new_game_initial_state": new_game,
            "main_story_player_map_initial": 1,
            "literal_player_map_route_count": len(route_records),
            "literal_routes_arriving_in_components": [r for r in route_records if r["component_hits"]],
            "paired_routes": route_records, "dynamic_uncertainty": dynamic}


def edge_audit(components: list[dict]) -> dict:
    cells = [(x, 0) for x in range(20, 620)] + [(x, 399) for x in range(20, 620)]
    cells += [(20, y) for y in range(1, 399)] + [(619, y) for y in range(1, 399)]
    transitions = ([(32, y) for y in range(400)] + [(608, y) for y in range(400)]
                   + [(x, 10) for x in range(20, 620)] + [(x, 390) for x in range(20, 620)])
    result = {}
    for c in components:
        mask = mask_from_runs(c["runs"])
        result[c["component_id"]] = {
            "requested_playfield_edge_landing_hits": [list(p) for p in cells if point_hit(mask, p)],
            "fps_transition_arrival_hits": [list(p) for p in transitions if point_hit(mask, p)]}
    return {"checked_unique_playfield_edge_cells_per_screen": len(cells),
            "fps_transition_candidate_cells_per_screen": len(transitions), "components": result}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name, help_text in (("masks", "before/after reachability and hardness NPZ"),
                            ("world", "world.json"), ("native", "native sprite/warp inventory JSON"),
                            ("sequences", "sequences.json"), ("story", "story.json"),
                            ("routes", "literal/static story route audit JSON"),
                            ("out", "output report JSON")):
        parser.add_argument("--" + name, type=Path, required=True, help=help_text)
    args = parser.parse_args()
    for path in (args.masks, args.world, args.native, args.sequences, args.story, args.routes):
        if not path.is_file():
            raise FileNotFoundError(path)
    world_doc = json.loads(args.world.read_text())
    world = world_doc["screens"]
    native = json.loads(args.native.read_text())
    sequence_doc = json.loads(args.sequences.read_text())
    sequences = sequence_doc.get("sequences", sequence_doc)
    story_doc = json.loads(args.story.read_text())
    story = story_doc.get("scripts", story_doc)
    routes = json.loads(args.routes.read_text())
    game_dir = args.world.resolve().parent.parent
    with np.load(args.masks, allow_pickle=False) as loaded:
        masks = {key: loaded[key] for key in ("before_reachable", "after_reachable", "after_hard")}
        shapes = {value.shape for value in masks.values()}
        if len(shapes) != 1 or len(next(iter(shapes))) != 2 or next(iter(shapes))[1] % 600:
            raise ValueError(f"unexpected world mask shapes: {shapes}")
        components = build_components(masks, world)
    sprite = sprite_audit(world, native, sequences, story, components, game_dir)
    warps = warp_audit(world, native, components)
    story_result = story_audit(routes, story, components)
    edges = edge_audit(components)
    findings = {}
    for component in components:
        cid = component["component_id"]
        content = sprite["components"][cid]
        wh = warps["components"][cid]
        edge = edges["components"][cid]
        story_hits = [r for r in story_result["paired_routes"] if cid in r["component_hits"]]
        counts = {"source_alpha_hit_count": len(content["draw_alpha_hits"]),
                  "source_anchor_hit_count": len(content["anchor_hits"]),
                  "source_hardbox_hit_count": len(content["hardbox_hits"]),
                  "grown4_hardbox_candidate_count": len(content["grown4_hardbox_candidates"]),
                  "actual_touch_or_warp_candidate_count": len(content["actual_touch_or_warp_candidates"]),
                  "script_or_item_candidate_count": len(content["script_or_item_content_candidates"]),
                  "script_talk_reach_candidate_count": len(content["talk_reach_candidates"]),
                  "native_warp_trigger_hit_count": len(wh["native_trigger_hits"]),
                  "native_warp_destination_hit_count": len(wh["native_destination_hits"]),
                  "raw_warp_source_candidate_count": len(wh["raw_world_source_trigger_candidates"]),
                  "raw_warp_destination_hit_count": len(wh["raw_world_destination_hits"]),
                  "edge_landing_hit_count": len(edge["requested_playfield_edge_landing_hits"]),
                  "fps_transition_arrival_hit_count": len(edge["fps_transition_arrival_hits"]),
                  "literal_story_arrival_hit_count": len(story_hits)}
        gameplay_arrival = sum(counts[k] for k in (
            "source_anchor_hit_count", "source_hardbox_hit_count", "actual_touch_or_warp_candidate_count",
            "native_warp_trigger_hit_count", "native_warp_destination_hit_count",
            "raw_warp_source_candidate_count", "raw_warp_destination_hit_count",
            "edge_landing_hit_count", "fps_transition_arrival_hit_count", "literal_story_arrival_hit_count"))
        counts["gameplay_or_arrival_candidate_total"] = gameplay_arrival
        counts["static_origin_touch_warp_edge_and_literal_arrival_gate"] = "PASS" if gameplay_arrival == 0 else "REVIEW"
        counts["visual_alpha_only"] = "Source alpha can overlap independently; it is not by itself a gameplay hit."
        findings[cid] = counts
    output = {"schema": "rc5-cutoff-surviving-free-audit-1",
              "basis": "before-reachable and not-after-reachable and not-after-hard; 4-connected integer free cells, separated by screen with no row wrap",
              "cutoff_component_count": len(components),
              "cutoff_surviving_free_pixels": sum(c["pixels"] for c in components),
              "components": components, "findings": findings,
              "sprite_audit": sprite, "warp_audit": warps,
              "story_audit": story_result, "edge_audit": edges,
              "limits": ["Source alpha is exact only at size 100 and integer pixel placement; other scales/offsets report bounding-box candidates and leave alpha exactness null.",
                         "Source hardboxes and their growth are geometric overlap candidates, not proof that runtime collision blocks a cell. Type, hardness, touch, warp, script and item fields are kept separate.",
                         "The 90px talk disk is a broad-phase candidate only; facing, actor state and dispatch are not executed.",
                         "Static warps and literal paired story arrivals are source evidence. Startup execution, dynamic map expressions, saved position/vision and player input remain unverified.",
                         "A source image overlap can be visual while having no anchor, hardbox, touch or arrival overlap; output keeps these classifications separate."]}
    output["input_sha256"] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (args.masks, args.world, args.native, args.sequences, args.story, args.routes)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2) + "\n")
    print("CUTOFF AUDIT", output["cutoff_component_count"], output["cutoff_surviving_free_pixels"], findings)


if __name__ == "__main__":
    main()
