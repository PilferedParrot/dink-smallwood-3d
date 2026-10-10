#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Six-owner wall candidate matches source silhouette; gameplay integration deferred.
"""Screen 712 geometry-first wall experiment. Does not change movement hardness.

The Dink camera projects a source-pixel point (x, height, z) to (x, z-height).
An opaque pixel can belong to a wall's ground footprint only where the same
source-art family is opaque both at ground projection (x,z) and at the top
projection (x,z-H). This makes the front span thin and the end-on run long,
without drawing a generic box over the courtyard. The footprint's raster
contour is the prototype shell contour. Its measured disagreement with the
authored tile mask is a collision migration diagnostic, not a geometry fit.

The selected owner indices are one connected bend and span. The right wall,
the two piers, the isle-07 gate, huts, actors, and their masks stay separate.
The shared height comes from the existing interior cap/face rule: both flat
front frames split after row 26 of 100, leaving a 74 px upright face. The
end-on run is 30 px wide against that 26 px visible cap depth. Curved art is
not fitted independently. --height overrides the one shared height only for
diagnosis; it cannot change x-side mask mismatches.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import tile_mask  # noqa: E402
from interior_fit import CAP_RATIO, cap_split  # noqa: E402

SCREEN = 712
OWNER_INDEXES = (1, 2, 6, 7, 8, 9)
SCREEN_W, SCREEN_H = 640, 400
ATLAS_Y0 = -200
ATLAS_H = 600
ART_FAMILY = "assets/graphics/inside/stnwalls/stonw-"


def frame(sequences: dict, sprite: dict) -> dict:
    return sequences[str(sprite["seq"])]["frames"][sprite["frame"] - 1]


def compose(sequences: dict, sprites: list[dict]) -> tuple[np.ndarray, list[dict]]:
    """Source-art alpha in screen coordinates including sprites above the screen."""
    alpha = np.zeros((ATLAS_H, SCREEN_W), bool)
    owners = []
    for sprite in sprites:
        f = frame(sequences, sprite)
        path = str(f["path"])
        if not path.startswith(ART_FAMILY):
            raise ValueError(f"owner {sprite['index']} is not a stone wall: {path}")
        im = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
        x, y = int(sprite["x"] - f["dx"]), int(sprite["y"] - f["dy"] - ATLAS_Y0)
        x0, x1 = max(x, 0), min(x + im.shape[1], SCREEN_W)
        y0, y1 = max(y, 0), min(y + im.shape[0], ATLAS_H)
        if x0 < x1 and y0 < y1:
            alpha[y0:y1, x0:x1] |= im[y0 - y:y1 - y, x0 - x:x1 - x, 3] >= 128
        owners.append({"index": int(sprite["index"]), "seq": int(sprite["seq"]),
                       "frame": int(sprite["frame"]), "path": path,
                       "at": [int(sprite["x"] - f["dx"]), int(sprite["y"] - f["dy"])],
                       "size": [int(im.shape[1]), int(im.shape[0])]})
    return alpha, owners


def footprint(alpha: np.ndarray, height: int) -> np.ndarray:
    ground = -ATLAS_Y0
    return alpha[ground:ground + SCREEN_H] & alpha[ground - height:ground - height + SCREEN_H]


def runs(mask: np.ndarray) -> list[list[int]]:
    """Exact contour-preserving scanlines, [z, inclusive x0, exclusive x1]."""
    out = []
    for z, row in enumerate(mask):
        edges = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), (1, 1))))
        out.extend([z, int(a), int(b)] for a, b in edges.reshape(-1, 2))
    return out


def metrics(candidate: np.ndarray, authored: np.ndarray) -> dict:
    dist = ndimage.distance_transform_edt(~authored)[candidate]
    labels, count = ndimage.label(candidate, structure=np.ones((3, 3), bool))
    sizes = np.bincount(labels.ravel())[1:]
    missing, missing_count = ndimage.label(candidate & ~authored, structure=np.ones((3, 3), bool))
    missing_sizes = np.bincount(missing.ravel())[1:]
    largest = {}
    if missing_count:
        tag = int(np.argmax(missing_sizes) + 1)
        yy, xx = np.where(missing == tag)
        largest = {"area_px": int(missing_sizes[tag - 1]),
                   "bbox_screen_px": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1]}
    return {"candidate_px": int(candidate.sum()),
            "inside_authored_px": int((candidate & authored).sum()),
            "outside_authored_px": int((candidate & ~authored).sum()),
            "inside_authored_fraction": round(float((candidate & authored).sum() / max(candidate.sum(), 1)), 4),
            "outside_distance_px": {"median": round(float(np.median(dist)), 2),
                                    "p95": round(float(np.percentile(dist, 95)), 2),
                                    "max": round(float(dist.max()), 2)},
            "candidate_components": int(count),
            "component_areas_px": sorted((int(n) for n in sizes), reverse=True),
            "largest_unmatched_component": largest}


def preview(alpha: np.ndarray, candidate: np.ndarray, authored: np.ndarray, output: Path) -> None:
    # Red: candidate stone ground outside hardness; green: both; blue: hardness
    # near the family without candidate. The art above is its original pixels.
    im = Image.new("RGBA", (SCREEN_W, SCREEN_H), (65, 96, 62, 255))
    near = ndimage.binary_dilation(candidate, iterations=16)
    a = np.asarray(im).copy()
    a[authored & near] = (38, 77, 175, 255)
    a[candidate & authored] = (60, 195, 89, 255)
    a[candidate & ~authored] = (230, 61, 52, 255)
    im = Image.fromarray(a)
    d = ImageDraw.Draw(im)
    d.text((350, 10), "green: solid and authored hardness", fill="white")
    d.text((350, 25), "red: solid only  blue: nearby hardness only", fill="white")
    im.save(output)


def common_height(seqs: dict) -> tuple[int, dict]:
    """The existing cap split on two independent flat-front art frames."""
    evidence = []
    for number in (2, 4):
        f = seqs["80"]["frames"][number - 1]
        a = np.asarray(Image.open(ROOT / "game" / f["path"]).convert("RGBA"))
        cap, ratio = cap_split(a)
        if ratio < CAP_RATIO:
            raise ValueError(f"flat wall frame {number} has no measured cap/face split")
        evidence.append({"frame": number, "rows": int(a.shape[0]), "cap_rows": int(cap),
                         "face_height_px": int(a.shape[0] - cap), "cap_ratio": round(float(ratio), 4)})
    heights = {e["face_height_px"] for e in evidence}
    if len(heights) != 1:
        raise ValueError(f"flat fronts have no shared measured face height: {evidence}")
    side = seqs["80"]["frames"][4]
    side_width = Image.open(ROOT / "game" / side["path"]).width
    return heights.pop(), {"method": "interior_fit.cap_split on flat fronts",
                           "flat_front_measurements": evidence,
                           "end_on_frame": 5, "end_on_width_px": side_width,
                           "cap_depth_vs_end_on_width_px": side_width - evidence[0]["cap_rows"],
                           "limits": "one raised view does not uniquely determine hidden surfaces; curved cap needs visual review"}


def tile_diagnostic(world: dict, per_tile: np.ndarray, candidate: np.ndarray,
                    authored: np.ndarray) -> list[dict]:
    """Every source tile touched by the proposed solid or its nearby hardness."""
    nearby = ndimage.binary_dilation(candidate, iterations=16)
    out = []
    for i, tile in enumerate(world["screens"][str(SCREEN)]["tiles"][:96]):
        cell = per_tile == i
        if not (candidate & cell).any() and not (authored & nearby & cell).any():
            continue
        default = world["hardness"]["tile_defaults"][tile["tile"]]
        out.append({"index": i, "tile": int(tile["tile"]),
                    "hardness_mask_id": int(tile.get("hard", 0) or default),
                    "solid_px": int((candidate & cell).sum()),
                    "authored_px": int((authored & cell).sum()),
                    "overlap_px": int((candidate & authored & cell).sum()),
                    "hardness_outside_solid_px": int((authored & ~candidate & cell).sum())})
    return out


def foreign_art(seqs: dict, sprites: list[dict]) -> np.ndarray:
    """Opaque pixels of all other visible source sprites: never claim their mask cells."""
    out = np.zeros((SCREEN_H, SCREEN_W), bool)
    for sprite in sprites:
        if int(sprite["index"]) in OWNER_INDEXES or int(sprite.get("vision", 0)) != 0 or int(sprite["type"]) == 2:
            continue
        f = frame(seqs, sprite)
        if not f.get("path"):
            continue
        a = np.asarray(Image.open(ROOT / "game" / f["path"]).convert("RGBA"))[..., 3] >= 128
        x, y = int(sprite["x"] - f["dx"]), int(sprite["y"] - f["dy"])
        x0, x1 = max(x, 0), min(x + a.shape[1], SCREEN_W)
        y0, y1 = max(y, 0), min(y + a.shape[0], SCREEN_H)
        if x0 < x1 and y0 < y1:
            out[y0:y1, x0:x1] |= a[y0 - y:y1 - y, x0 - x:x1 - x]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--height", type=int, default=None)
    ap.add_argument("--out", type=Path, default=ROOT / "game/prototype/rc4_walls.json")
    ap.add_argument("--preview", type=Path, default=ROOT / "tmp/rc4-wall-prototype/fit.png")
    args = ap.parse_args()
    world = json.loads((ROOT / "game/data/world.json").read_text())
    seqs = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    derived_height, height_evidence = common_height(seqs)
    height = derived_height if args.height is None else args.height
    if not 1 <= height < 100:
        ap.error("height must leave a positive depth in the 100 px flat-front span")
    screen = world["screens"][str(SCREEN)]
    selected = [e for e in screen["sprites"] if int(e["index"]) in OWNER_INDEXES]
    if {int(e["index"]) for e in selected} != set(OWNER_INDEXES):
        raise ValueError("wall owner index missing from source screen")
    # Match the original sprite draw order for the source-art atlas at overlaps.
    selected.sort(key=lambda e: ((-10000 + e["y"]) if e["type"] == 0 else (e["que"] or e["y"]),
                                 int(e["index"])))
    alpha, owners = compose(seqs, selected)
    # Same choice as interior_solids.room_stone: most frequent full-width wall
    # picture in this owner set, lexicographic path on ties. The material
    # transfer below is expressly an inference for faces the camera did not see.
    flat = [o for o in owners if o["frame"] in (2, 4) and o["size"][0] >= 100]
    counts = {o["path"]: sum(p["path"] == o["path"] for p in flat) for o in flat}
    donor_path = sorted(counts, key=lambda p: (-counts[p], p))[0]
    donor_owner = next(o for o in flat if o["path"] == donor_path)
    donor_measurement = next(e for e in height_evidence["flat_front_measurements"] if e["frame"] == donor_owner["frame"])
    donor = {"source_path": donor_path, "source_frame": donor_owner["frame"],
             "source_owner_index": donor_owner["index"],
             "source_size_px": donor_owner["size"],
             "face_crop_rows": [donor_measurement["cap_rows"], donor_measurement["rows"]],
             "face_size_px": [donor_owner["size"][0], donor_measurement["face_height_px"]],
             "inference": "transfer the wall's own flat stone face to unseen north and end-on faces; not recovered source history"}
    candidate = footprint(alpha, height)
    authored, per_tile = tile_mask(world, SCREEN)
    result = metrics(candidate, authored)
    sweep = {}
    for h in (68, 70, 72, 74, 76, 78, 80):
        m = metrics(footprint(alpha, h), authored)
        sweep[str(h)] = {"inside_fraction": m["inside_authored_fraction"],
                         "p95_outside_px": m["outside_distance_px"]["p95"]}
    gate = next(e for e in screen["sprites"] if int(e["index"]) == 3)
    gf = frame(seqs, gate)
    gate_alpha = np.asarray(Image.open(ROOT / "game" / gf["path"]).convert("RGBA"))[..., 3] >= 128
    gate_on_screen = np.zeros_like(candidate)
    gx, gy = int(gate["x"] - gf["dx"]), int(gate["y"] - gf["dy"])
    gx0, gx1 = max(gx, 0), min(gx + gate_alpha.shape[1], SCREEN_W)
    gy0, gy1 = max(gy, 0), min(gy + gate_alpha.shape[0], SCREEN_H)
    if gx0 < gx1 and gy0 < gy1:
        gate_on_screen[gy0:gy1, gx0:gx1] = gate_alpha[gy0-gy:gy1-gy, gx0-gx:gx1-gx]
    near = ndimage.binary_dilation(candidate, iterations=16)
    wall_projection = alpha[-ATLAS_Y0:-ATLAS_Y0 + SCREEN_H]
    other_projection = foreign_art(seqs, screen["sprites"])
    proposed_clear = authored & wall_projection & ~other_projection
    retained_authored = authored & ~proposed_clear
    record = {"schema": 2, "screen": SCREEN, "purpose": "bounded geometry-first wall prototype",
              "camera": {"projection": "source=(x,z-y)", "atlas_y0": ATLAS_Y0,
                         "atlas_size": [SCREEN_W, ATLAS_H], "scale_m_per_px": 0.025},
              "shared_height_px": height,
              "height_evidence": height_evidence,
              "unseen_face_material": donor,
              "owner_indexes": list(OWNER_INDEXES), "owners": owners,
              "excluded": {"right_wall_indexes": [10, 14, 16], "pier_indexes": [4, 5],
                           "gate_index": 3, "reason": "separate source owners and masks"},
              "surface": {"method": "source_alpha_at_ground_AND_source_alpha_at_top",
                          "contour": "exact raster run boundary", "runs": runs(candidate)},
              "authored_movement_mask": "game/data/world.json screen 712 tile hardness; unchanged",
              "geometry_status": "pending_original_and_eye_camera_review",
              "collision_proposal": {"status": "diagnostic_only_no_mask_edits",
                                     "solid_footprint_runs": runs(candidate),
                                     "source_wall_projection_runs": runs(wall_projection),
                                     "other_sprite_projection_runs": runs(other_projection),
                                     "proposed_clear_wall_projection_runs": runs(proposed_clear),
                                     "proposed_clear_px": int(proposed_clear.sum()),
                                     "retained_authored_runs": runs(retained_authored),
                                     "retained_authored_px": int(retained_authored.sum()),
                                     "retained_nearby_outside_solid_px": int((retained_authored & near & ~candidate).sum()),
                                     "authored_mask_intersection_runs": runs(candidate & authored),
                                     "authored_mask_outside_solid_runs": runs(authored & ~candidate),
                                     "nearby_authored_outside_solid_px": int((authored & near & ~candidate).sum()),
                                     "tiles": tile_diagnostic(world, per_tile, candidate, authored),
                                     "rule": "candidate clear is authored hardness beneath visible wall art, excluding every other sprite projection; retained cells remain listed; solid collision equals own footprint only after review"},
              "mask_comparison": result,
              "shared_height_sweep": sweep,
              "negative_controls": {"gate_owner_excluded": 3 not in OWNER_INDEXES,
                                    "gate_art_overlap_px": int((candidate & gate_on_screen).sum()),
                                    "non_wall_owners_in_atlas": sum(not o["path"].startswith(ART_FAMILY) for o in owners),
                                    "other_wall_owners_excluded": [4, 5, 10, 14, 16]},
              "runtime_gate": "geometry preview permitted; gameplay mask integration pending ownership review"}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(record, indent=2) + "\n")
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    preview(alpha, candidate, authored, args.preview)
    print(json.dumps({"screen": SCREEN, "height": height, "owners": list(OWNER_INDEXES),
                      "mask_comparison": result, "json": str(args.out), "preview": str(args.preview)}, indent=2))


if __name__ == "__main__":
    main()
