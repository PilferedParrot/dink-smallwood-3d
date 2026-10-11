#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Fit outdoor structural stone spans from their composed source pixels.

The source camera maps (x, height, z) to (x, z-height). A floor pixel is
occupied only if the selected wall family is opaque both at its ground and
shared-height projections. Source art is composed in shared world coordinates
before each playable screen rectangle is clipped: a wall sprite across a map
seam can supply the top of its neighbor's footprint. Tile hardness is removed
only at opaque wall projection pixels that no other visible sprite, including
a neighboring screen's sprite, projects onto.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import GROW, hardbox, rect_mask, tile_mask  # noqa: E402
from rc4_wall_mask_fit import ATLAS_H, ATLAS_Y0, SCREEN_H, SCREEN_W, common_height, runs  # noqa: E402

SCREENS = (385, 386, 387, 388, 417, 420, 449, 450, 451, 452, 680, 681, 712, 713)
FRAMES = frozenset((*range(1, 11), 15))
FAMILY = "assets/graphics/inside/stnwalls/stonw-"
EXCLUDED = {
    "ivy": {244: (21, 22)},
    "freestanding_piers": {536: (27, 28), 712: (27, 28)},
    "open_arch": {451: (16,), 625: (16,)},
    "snake_cage": {238: ("snak",), 625: ("snak",)},
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_frame(seqs: dict, sprite: dict) -> dict:
    fs = seqs.get(str(sprite["seq"]), {}).get("frames", [])
    idx = int(sprite["frame"]) - 1
    if not 0 <= idx < len(fs):
        raise ValueError(f"invalid frame for source sprite {sprite['index']}")
    return fs[idx]


def eligible(e: dict, path: str) -> bool:
    return (int(e.get("seq", 0)) == 80 and int(e.get("frame", 0)) in FRAMES
            and path.startswith(FAMILY) and int(e.get("vision", 0)) == 0
            and int(e.get("type", 1)) == 1 and int(e.get("size", 100)) == 100
            and int(e.get("active", 1)) != 0 and int(e.get("nodraw", 0)) == 0
            and int(e.get("disabled", 0)) == 0 and int(e.get("brain",0)) == 0 and not e.get("script"))


def visible(e: dict, vision: int = 0) -> bool:
    return (int(e.get("vision", 0)) in (0, vision) and int(e.get("type", 1)) != 2
            and int(e.get("active", 1)) != 0 and int(e.get("nodraw", 0)) == 0
            and int(e.get("disabled", 0)) == 0)


def projected_alpha(sprite: dict, f: dict, image_cache: dict) -> tuple[np.ndarray, int, int]:
    path = str(f.get("path", ""))
    if path not in image_cache:
        image_cache[path] = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))[..., 3]
    alpha = image_cache[path]
    scale = float(sprite.get("size", 100) or 100) / 100.0
    if scale != 1.0:
        w, h = max(1, round(alpha.shape[1] * scale)), max(1, round(alpha.shape[0] * scale))
        alpha = np.asarray(Image.fromarray(alpha).resize((w, h), Image.Resampling.NEAREST))
    x = round(float(sprite["x"]) - float(f["dx"]) * scale)
    y = round(float(sprite["y"]) - float(f["dy"]) * scale)
    return alpha >= 128, x, y


def paste_or(target: np.ndarray, alpha: np.ndarray, x: int, y: int, y0: int) -> None:
    x0, x1 = max(0, x), min(target.shape[1], x + alpha.shape[1])
    z0, z1 = max(0, y - y0), min(target.shape[0], y - y0 + alpha.shape[0])
    if x0 < x1 and z0 < z1:
        target[z0:z1, x0:x1] |= alpha[z0 - (y - y0):z1 - (y - y0), x0 - x:x1 - x]


def owner_record(e: dict, f: dict, alpha: np.ndarray, x: int, y: int) -> dict:
    return {"index": int(e["index"]), "seq": int(e["seq"]), "frame": int(e["frame"]),
            "path": str(f["path"]), "at": [x, y],
            "hotspot": [int(e["x"]), int(e["y"])],
            "size": [int(alpha.shape[1]), int(alpha.shape[0])],
            "hard": int(e.get("hard", 1)), "source_sha256": sha(ROOT / "game" / f["path"])}


def neighbors(world: dict, number: int):
    """Outdoor source screens in the 3x3 block, with offsets in target pixels."""
    row, col = divmod(number - 1, 32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if not 0 <= col + dx < 32 or row + dy < 0:
                continue
            other = number + dx + 32 * dy
            screen = world["screens"].get(str(other))
            if screen is None or screen.get("indoor"):
                continue
            yield other, dx * 600, dy * 400


def fit_screen(world: dict, seqs: dict, footprints: dict, number: int,
               height: int, evidence: dict, images: dict) -> dict:
    screen = world["screens"][str(number)]
    sprites = screen["sprites"]
    selected = []
    deferred = []
    for e in sprites:
        f = source_frame(seqs, e)
        p = str(f.get("path", ""))
        if eligible(e, p):
            selected.append((e, f))
        elif int(e.get("seq", 0)) == 80 and int(e.get("frame", 0)) in FRAMES and p.startswith(FAMILY):
            raise ValueError(f"screen {number} structural candidate {e['index']} is not static size-100 vision-0 type-1")
        elif p.startswith(FAMILY):
            deferred.append({"index": int(e["index"]), "seq": int(e["seq"]),
                             "frame": int(e["frame"]), "path": p,
                             "reason": "outside_structural_span_frame_or_static_scope"})
    if not selected:
        raise ValueError(f"screen {number} lacks a selected structural wall")
    # Preserve source painter order where sprites overlap in the projected atlas.
    selected.sort(key=lambda pair: (int(pair[0].get("que", 0) or pair[0]["y"]), int(pair[0]["index"])))
    selected_ids = {int(e["index"]) for e, _ in selected}
    atlas = np.zeros((ATLAS_H, SCREEN_W), bool)
    owners = [owner_record(e, f, *projected_alpha(e, f, images)) for e, f in selected]
    atlas_layers = []
    other = np.zeros((SCREEN_H, SCREEN_W), bool)
    other_neighbor = np.zeros_like(other)
    selected_other_screens = set()
    for source_number, offset_x, offset_y in neighbors(world, number):
        for e in world["screens"][str(source_number)]["sprites"]:
            f = source_frame(seqs, e)
            path = str(f.get("path", ""))
            if eligible(e, path):
                alpha, local_x, local_y = projected_alpha(e, f, images)
                x, y = local_x + offset_x, local_y + offset_y
                # Only records intersecting the projected ground/top atlas
                # participate. The two tests share this one composed alpha.
                if x < SCREEN_W and x + alpha.shape[1] > 0 and y < ATLAS_Y0 + ATLAS_H and y + alpha.shape[0] > ATLAS_Y0:
                    paste_or(atlas, alpha, x, y, ATLAS_Y0)
                    record = owner_record(e, f, alpha, x, y)
                    record["screen"] = source_number
                    atlas_layers.append((offset_y + int(e.get("que", 0) or e["y"]), source_number,
                                         int(e["index"]), record))
                    if source_number != number:
                        selected_other_screens.add(source_number)
                continue
            if not visible(e) or not path:
                continue
            alpha, local_x, local_y = projected_alpha(e, f, images)
            x, y = local_x + offset_x, local_y + offset_y
            paste_or(other, alpha, x, y, 0)
            if source_number != number:
                paste_or(other_neighbor, alpha, x, y, 0)
    # Runtime's atlas blend uses these owner records in world painter order;
    # owner identity below remains local to this screen for suppression.
    atlas_owners = [record for _, _, _, record in sorted(atlas_layers, key=lambda layer: layer[:3])]
    candidate = atlas[-ATLAS_Y0:-ATLAS_Y0 + SCREEN_H] & atlas[-ATLAS_Y0-height:-ATLAS_Y0-height + SCREEN_H]
    candidate[:, :20] = False
    candidate[:, 620:] = False
    projection = atlas[-ATLAS_Y0:-ATLAS_Y0 + SCREEN_H].copy()
    projection[:, :20] = False
    projection[:, 620:] = False
    other_hard = []
    already_replaced = []
    rec = footprints.get(str(number), {})
    footprint_replaced = set(rec.get("sprites", []))
    for e in sprites:
        if int(e["index"]) in selected_ids:
            continue
        if int(e.get("vision", 0)) == 0 and int(e.get("active", 1)) != 0 and int(e.get("hard", 1)) == 0 and not e.get("warp"):
            if int(e["index"]) in footprint_replaced:
                already_replaced.append(e)
            else:
                other_hard.append(e)
    effective, per_tile = tile_mask(world, number, set(rec.get("revert", [])), set(rec.get("clear", [])))
    clear = effective & projection & ~other
    old_selected = [e for e, _ in selected if int(e.get("hard", 1)) == 0 and not e.get("warp")]
    old_selected_mask = rect_mask([hardbox(seqs, e) for e in old_selected], GROW)
    other_hard_mask = rect_mask([hardbox(seqs, e) for e in other_hard], GROW)
    # A local flat face is preferred. All-frame-5 screens use the same source
    # family's global flat-front art, expressly marked as inferred material.
    flats = [o for o in owners if o["frame"] in (2, 4)]
    if flats:
        counts = {o["path"]: sum(q["path"] == o["path"] for q in flats) for o in flats}
        donor_path = sorted(counts, key=lambda p: (-counts[p], p))[0]
        donor_owner = next(o for o in flats if o["path"] == donor_path)
        source = "same_screen_flat_wall"
    else:
        donor_frame = seqs["80"]["frames"][1]
        donor_path = str(donor_frame["path"])
        donor_owner = None
        source = "same_family_flat_wall_other_screen"
    donor_number = 2 if donor_path.endswith("-02.png") else 4
    split = next(q for q in evidence["flat_front_measurements"] if q["frame"] == donor_number)
    donor = {"source_path": donor_path, "source_sha256": sha(ROOT / "game" / donor_path),
             "source_frame": donor_number, "source_owner_index": donor_owner["index"] if donor_owner else None,
             "selection": source, "face_crop_rows": [split["cap_rows"], split["rows"]],
             "face_size_px": [100, height],
             "inference": "own stone-family flat face transferred to unseen north/end faces; hidden source history is unknown"}
    tile_counts = {}
    for i in range(96):
        claimed = int(np.count_nonzero(clear & (per_tile == i)))
        if claimed:
            tile_counts[str(i)] = claimed
    retained = effective & ~clear
    return {"owners": owners, "atlas_owners": atlas_owners,
            "owner_indexes": sorted(selected_ids), "deferred": deferred,
            "floor_runs": runs(candidate), "clear_tile_runs": runs(clear),
            "shared_height_px": height, "unseen_face_material": donor,
            "world_composition": {"selected_contributor_screens": sorted(selected_other_screens),
                                  "foreign_projection_neighbor_screens": sorted({m for m, _, _ in neighbors(world, number) if m != number}),
                                  "atlas_owner_count": len(atlas_owners),
                                  "rule": "selected alpha in shared world pixels, clipped to target playable rectangle"},
            "source_counts": {"floor_px": int(candidate.sum()), "selected_projection_px": int(projection.sum()),
                              "effective_tile_hard_px": int(effective.sum()), "clear_tile_px": int(clear.sum()),
                              "retained_tile_hard_px": int(retained.sum()),
                              "retained_under_selected_projection_px": int((retained & projection).sum()),
                              "other_sprite_projection_px": int(other.sum()),
                              "other_neighbor_projection_px": int(other_neighbor.sum()),
                              "foreign_projection_protected_hard_px": int((effective & projection & other).sum()),
                              "foreign_neighbor_protected_hard_px": int((effective & projection & other_neighbor).sum()),
                              "selected_old_hardbox_px": int(old_selected_mask.sum()),
                              "retained_other_hardbox_px": int(other_hard_mask.sum()),
                              "retained_other_hardbox_owners": len(other_hard),
                              "already_replaced_by_footprint_hardbox_owners": len(already_replaced),
                              "selected_old_hardbox_counts": len(old_selected),
                              "tile_claims": tile_counts},
            "hardbox_replaced_indexes": [int(e["index"]) for e in old_selected],
            "retained_unowned_hardbox_indexes": [int(e["index"]) for e in other_hard],
            "already_replaced_by_footprint_hardbox_indexes": [int(e["index"]) for e in already_replaced]}


def build() -> dict:
    world_path = ROOT / "game/data/world.json"
    seq_path = ROOT / "game/data/sequences.json"
    footprint_path = ROOT / "game/data/footprints.json"
    world = json.loads(world_path.read_text())
    seqs = json.loads(seq_path.read_text())["sequences"]
    footprints = json.loads(footprint_path.read_text())["screens"]
    height, evidence = common_height(seqs)
    images = {}
    numbers = sorted(int(n) for n,screen in world["screens"].items() if not screen.get("indoor")
                     and any(int(e.get("seq",0))==80 and int(e.get("frame",0)) in FRAMES
                             for e in screen["sprites"]))
    legacy = sorted(int(n) for n, screen in world["screens"].items() if not screen.get("indoor")
                    and any(str(source_frame(seqs, e).get("path", "")).startswith("assets/graphics/inside/stnwalls/")
                            for e in screen["sprites"]))
    if set(numbers) != set(SCREENS) or len(legacy) != 18:
        raise ValueError(f"structural/legacy screen scope changed: {numbers} / {legacy}")
    screens = {str(n): fit_screen(world, seqs, footprints, n, height, evidence, images) for n in numbers}
    deferred_legacy = {}
    for n in legacy:
        omitted = []
        for e in world["screens"][str(n)]["sprites"]:
            f = source_frame(seqs, e)
            path = str(f.get("path", ""))
            if not path.startswith("assets/graphics/inside/stnwalls/") or eligible(e, path):
                continue
            frame = int(e["frame"])
            reason = ("ivy_decoration" if frame in (21, 22) else
                      "freestanding_pier" if frame in (27, 28) else
                      "open_arch" if frame == 16 else
                      "snake_cage" if "/snake/" in path else "other_nonstructural_wall_art")
            omitted.append({"index": int(e["index"]), "seq": int(e["seq"]),
                            "frame": frame, "path": path, "reason": reason})
        deferred_legacy[str(n)] = omitted
    return {"schema": 1, "purpose": "source_fitted_structural_stone_spans",
            "camera": {"projection": "source=(x,z-y)", "atlas_y0": ATLAS_Y0,
                       "atlas_size": [SCREEN_W, ATLAS_H], "scale_m_per_px": 0.025,
                       "playable_rect": [20, 0, 620, 400]},
            "shared_height_px": height, "height_evidence": evidence,
            "selection": {"screens": numbers, "legacy_wall_screens": legacy,
                          "deferred_legacy_owners": deferred_legacy, "seq": 80, "frames": sorted(FRAMES),
                          "deferred": EXCLUDED,
                          "rule": "static size-100 vision-0 type-1 structural stone frames only"},
            "collision": {"floor": "world_composed_selected_alpha_ground_AND_top_then_exact_one_pixel_cells_with_4px_escape_band",
                          "tile_clear": "effective_source_tile_hardness_AND_world_composed_selected_opaque_projection_AND_NOT_any_other_visible_sprite_projection_including_neighbors",
                          "hardbox": "remove_selected_owner_hardboxes_only"},
            "source_sha256": {"world.json": sha(world_path), "sequences.json": sha(seq_path),
                              "footprints.json": sha(footprint_path)},
            "screens": screens}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "game/prototype/rc5_walls.json")
    args = parser.parse_args()
    result = build()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(json.dumps({n: {"owners": len(v["owners"]), "floor_px": v["source_counts"]["floor_px"],
                          "clear_tile_px": v["source_counts"]["clear_tile_px"]}
                      for n, v in result["screens"].items()}, indent=2))


if __name__ == "__main__":
    main()
