#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Compile a disabled, two-screen original-fir forest-boundary preview.

The boundary is RC4's exact full-pixel source-hard forest contour, verified by
its stored SHA. Current RC5 roots come only from native scene-visibility
inventories. New roots may stand on ANY raw source tile-hard pixel in a
4-connected hard component touching original forest tile art, including hard
grass. Deterministic greedy set cover targets the stricter 43-pixel eye-row
proxy, with minimum spacing from the source's nearest-neighbor crown apexes.
Neither this proxy nor the 47-pixel widest-crown proxy measures 3D
occlusion; the lead owns native rendered review and the picture decision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage, sparse
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import tile_mask  # noqa: E402
from rc4_fir_stand_fit import (  # noqa: E402
    ATLAS_PATH, ATLAS_APEXES, GRASS_DONORS, checked_forest_pixels,
    forest_hardness, source_canvas,
)

SCREENS = (144, 375)
CROWN_RADIUS_PX = 47.0
EYE_ROW_PROXY_RADIUS_PX = 43.0
WORLD_PATH = ROOT / "game/data/world.json"
RC4_PATH = ROOT / "game/prototype/rc4_fir_stand.json"
FIR_PATH = ROOT / "game/prototype/rc5_firs.json"
EXISTING_PATH = ROOT / "tmp/rc5-fir-eye/existing-native.json"
COMPLETED_PATH = ROOT / "tmp/fir-collision/native.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contour(world: dict, atlas: np.ndarray, number: int, expected: dict):
    tiles = world["screens"][str(number)]["tiles"][:96]
    rgb, forest_cells = source_canvas(atlas, tiles)
    owned_art = checked_forest_pixels(rgb, forest_cells)
    hard, forest_hard, _, _ = forest_hardness(world, number, forest_cells, 94)
    edge = forest_hard & ndimage.binary_dilation(~hard & ~owned_art,
                                                 structure=np.ones((3, 3), bool))
    # Continuing screen seams are not new forest front faces.
    edge[[0, -1], :] = False
    edge[:, [0, -1]] = False
    digest = hashlib.sha256(np.packbits(edge.ravel()).tobytes()).hexdigest()
    if digest != expected["hard_edge_pixel_sha256"] or int(edge.sum()) != expected["hard_boundary_full_pixels"]:
        raise ValueError(f"screen {number}: RC4 source contour changed: {digest} / {int(edge.sum())}")
    return hard, forest_cells, edge, digest


def current_roots(existing: list[dict], completed: list[dict], number: int) -> list[dict]:
    ox, oy = (number - 1) % 32 * 600, (number - 1) // 32 * 400
    roots = []
    for row in existing:
        if int(row["frame"]) != 1 or number not in row.get("scene5x5_shown_centers", []):
            continue
        roots.append({"class": "visible_existing_complete_tree01",
                      "source_screen": int(row["screen"]), "editor_index": int(row["editor_index"]),
                      "foot_local_px": [float(row["global_foot_xy"][0]) - ox,
                                        float(row["global_foot_xy"][1]) - oy],
                      "uniform_scale": 1.0})
    for row in completed:
        for part in row["parts"]:
            if number not in part.get("scene5x5_shown_centers", []):
                continue
            roots.append({"class": "visible_rc5_completed_source_part",
                          "source_screen": int(row["screen"]), "editor_index": int(row["editor_index"]),
                          "source_part": int(part["part"]),
                          "foot_local_px": [float(part["global_foot_xy"][0]) - ox,
                                            float(part["global_foot_xy"][1]) - oy],
                          "uniform_scale": float(part["uniform_scale"])})
    # Two source placements can share a point. Geometry coverage counts the
    # point once, while source provenance retains its first verified owner.
    unique = {}
    for root in roots:
        key = (*root["foot_local_px"], root["uniform_scale"])
        unique.setdefault(key, root)
    return list(unique.values())


def covered(points: np.ndarray, roots: list[dict], radius: float) -> np.ndarray:
    if not roots:
        return np.zeros(len(points), bool)
    sites = np.asarray([r["foot_local_px"] for r in roots], dtype=float)
    scales = np.asarray([r["uniform_scale"] for r in roots], dtype=float)
    distance2 = ((points[:, None, :] - sites[None, :, :]) ** 2).sum(axis=2)
    return np.any(distance2 <= (radius * scales[None, :]) ** 2, axis=1)


def hard_components_touching_forest(hard: np.ndarray, forest_cells: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    # ndimage's default cross is 4-connectivity, the same as the RC4 source
    # hardness attribution. Do not grow the mask into merely nearby grass.
    labels, _ = ndimage.label(hard)
    connected = np.unique(labels[hard & forest_cells])
    connected = connected[connected > 0]
    return hard & np.isin(labels, connected), labels


def candidate_coverage(points: np.ndarray, candidates: np.ndarray, radius: float):
    hits = cKDTree(points).query_ball_point(candidates, radius)
    lengths = np.fromiter(map(len, hits), dtype=np.int32, count=len(hits))
    rows = np.repeat(np.arange(len(hits), dtype=np.int32), lengths)
    cols = np.concatenate([np.asarray(hit, dtype=np.int32) for hit in hits])
    matrix = sparse.csr_matrix((np.ones(len(cols), dtype=np.int16), (rows, cols)),
                               shape=(len(candidates), len(points)))
    return hits, matrix


def fit_screen(world: dict, atlas: np.ndarray, rc4: dict, existing: list[dict],
               completed: list[dict], number: int, minimum_spacing: float) -> dict:
    stat = rc4["fixtures"][str(number)]["boundary"]["stats"]
    hard, forest_cells, edge, edge_sha = contour(world, atlas, number, stat)
    edge_y, edge_x = np.where(edge)
    points = np.stack((edge_x, edge_y), axis=1).astype(float)
    before_roots = current_roots(existing, completed, number)
    before43 = covered(points, before_roots, EYE_ROW_PROXY_RADIUS_PX)
    before47 = covered(points, before_roots, CROWN_RADIUS_PX)
    admissible, labels = hard_components_touching_forest(hard, forest_cells)
    if np.any(edge & ~admissible):
        raise ValueError(f"screen {number}: canonical hard edge outside admissible source component")
    candidate_y, candidate_x = np.where(admissible)
    candidates = np.stack((candidate_x, candidate_y), axis=1)
    spaced = np.ones(len(candidates), bool)
    for root in before_roots:
        spaced &= ((candidates - root["foot_local_px"]) ** 2).sum(axis=1) >= minimum_spacing**2
    hit_lists, cover_matrix = candidate_coverage(points, candidates, EYE_ROW_PROXY_RADIUS_PX)
    interior_depth = ndimage.distance_transform_edt(admissible)[candidate_y, candidate_x]
    uncovered = ~before43
    roots = []
    source_tiles = world["screens"][str(number)]["tiles"][:96]
    defaults = world["hardness"]["tile_defaults"]
    _, tile_indexes = tile_mask(world, number)
    tile_indexes = tile_indexes[:, 20:620]
    while uncovered.any():
        scores = np.asarray(cover_matrix @ uncovered.astype(np.int16)).ravel()
        scores[~spaced] = -1
        best = int(scores.max())
        if best <= 0:
            break
        ties = np.flatnonzero(scores == best)
        chosen = max(ties, key=lambda i: (int(forest_cells[candidate_y[i], candidate_x[i]]),
                                          float(interior_depth[i]), -int(candidate_y[i]),
                                          -int(candidate_x[i])))
        x, y = int(candidate_x[chosen]), int(candidate_y[chosen])
        tile_index = int(tile_indexes[y, x])
        tile = source_tiles[tile_index]
        tile_id = int(tile["tile"])
        mask_id = int(tile.get("hard", 0) or defaults[tile_id])
        forest_art = bool(forest_cells[y, x])
        if not hard[y, x] or not admissible[y, x]:
            raise ValueError(f"screen {number}: chosen source root is not connected forest-hard tile art")
        roots.append({"source_screen": number, "foot_local_px": [x, y],
                      "foot_source_screen_px": [x + 20, y],
                      "source_tile_index": tile_index, "source_tile_id": tile_id,
                      "source_hardness_mask_id": mask_id,
                      "source_hard_component": int(labels[y, x]),
                      "source_forest_art_tile": forest_art,
                      "source_hard_grass_tile": tile_id in GRASS_DONORS,
                      "newly_covered_43px_boundary_pixels": best,
                      "uniform_scale": 1.0,
                      "template_path": "assets/graphics/lands/Trees/tree-01.png"})
        uncovered[hit_lists[chosen]] = False
        spaced &= ((candidates - candidates[chosen]) ** 2).sum(axis=1) >= minimum_spacing**2
    after_roots = before_roots + roots
    after43 = covered(points, after_roots, EYE_ROW_PROXY_RADIUS_PX)
    after47 = covered(points, after_roots, CROWN_RADIUS_PX)
    # A spacing-constrained stand may retain a residual. Report it, rather
    # than hiding it or relaxing the source-derived spacing to reach zero.
    ground = rc4["fixtures"][str(number)]["ownership"]
    return {"source_screen": number,
            "ownership": {k: ground[k] for k in (
                "forest_pixel_mask_size", "forest_pixel_mask_runs",
                "grass_donor_by_tile_member", "grass_donor_provenance_by_tile_member")},
            "boundary": {"full_pixel_count": len(points),
                "source_sha256": edge_sha, "method": "RC4 source-hard forest edge; full source pixels; border continuation excluded"},
            "current_visible_roots": before_roots,
            "before": {"widest_crown_47px_gap": int((~before47).sum()),
                       "eye_row_43px_proxy_gap": int((~before43).sum()),
                       "existing_complete_tree01_roots": sum(r["class"] == "visible_existing_complete_tree01" for r in before_roots),
                       "completed_source_part_roots": sum(r["class"] == "visible_rc5_completed_source_part" for r in before_roots)},
            "eligibility": {"source_tile_hard_connected_to_forest_px": int(admissible.sum()),
                            "source_hard_grass_px": int((admissible & ~forest_cells).sum()),
                            "method": "raw tile_mask hard pixels; 4-connected component touches original forest tile art"},
            "added_roots": roots,
            "after": {"widest_crown_47px_gap": int((~after47).sum()),
                      "eye_row_43px_proxy_gap": int((~after43).sum()),
                      "added_whole_tree01_roots": len(roots),
                      "added_on_hard_grass": sum(r["source_hard_grass_tile"] for r in roots),
                      "residual_43px_edge_xy": points[~after43].astype(int).tolist(),
                      "residual_limit": "greedy stand; residual is conditional on chosen roots, not a proof of globally optimal spacing",
                      "added_collider_count": 0,
                      "source_art_or_entity_suppression_count": 0}}


def build(existing_path: Path = EXISTING_PATH, completed_path: Path = COMPLETED_PATH) -> dict:
    world = json.loads(WORLD_PATH.read_text())
    rc4 = json.loads(RC4_PATH.read_text())
    existing = json.loads(existing_path.read_text())["placements"]
    native = json.loads(completed_path.read_text())
    # Use the final all-frame native inventory, including frame8 ownership.
    # Older two-part inventories remain readable for explicit reproductions.
    completed = native.get("placements")
    if completed is None:
        completed = [{"screen": p["source_screen"], "editor_index": p["source_editor_index"],
                      "parts": [{"part": p["part"], "global_foot_xy": p["global_foot_xy"],
                                 "scene5x5_shown_centers": p["scene5x5_shown_centers"],
                                 "uniform_scale": p["uniform_scale"]}]}
                     for p in native["parts"]]
    atlas = np.asarray(Image.open(ATLAS_PATH).convert("RGB"))
    fir = json.loads(FIR_PATH.read_text())
    if fir["template"]["path"] != "assets/graphics/lands/Trees/tree-01.png" \
            or fir["template"]["crown_height_px"] != 176 \
            or fir["template"]["crown_bbox_px"][2] - fir["template"]["crown_bbox_px"][0] != 94:
        raise ValueError("RC5 whole-fir source template changed")
    apexes = [p["source_apex_px"] for p in fir["source_parts"]["assets/graphics/lands/Trees/tree-08.png"]]
    nearest = [min(math.dist(p,q) for j,q in enumerate(apexes) if i != j)
               for i,p in enumerate(apexes)]
    minimum_spacing = min(nearest)
    atlas_nearest = [min(math.dist(p,q) for j,q in enumerate(ATLAS_APEXES) if i != j)
                     for i,p in enumerate(ATLAS_APEXES)]
    # The atlas tips are hand-identified to +/-4px per axis. Even their
    # conservative pair-distance bound exceeds the exact frame8 minimum.
    atlas_lower_bound = min(atlas_nearest) - 2 * math.sqrt(2) * 4
    if atlas_lower_bound <= minimum_spacing:
        raise ValueError("atlas tip uncertainty could change minimum spacing; refine measurement")
    screens = {str(n): fit_screen(world, atlas, rc4, existing, completed, n, minimum_spacing) for n in SCREENS}
    return {"schema": "rc5-disabled-forest-preview-1", "enabled_default": False,
            "purpose": "bounded picture-cost preview, not a production collision or visibility claim",
            "screens": screens,
            "source": {"world_sha256": sha(WORLD_PATH), "forest_atlas_sha256": sha(ATLAS_PATH),
                       "rc4_boundary_artifact_sha256": sha(RC4_PATH),
                       "existing_native_inventory_sha256": sha(existing_path),
                       "completed_native_inventory_sha256": sha(completed_path),
                       "rc5_whole_fir_template_sha256": sha(FIR_PATH),
                       "template": fir["template"]},
            "rule": {"new_root": "any raw tile-hard pixel in 4-connected component touching forest tile art",
                     "minimum_root_spacing_px": minimum_spacing,
                     "spacing_scope": "each added root against all visible existing/completed roots and prior added roots; existing authored spacings are unchanged",
                     "spacing_source": {"tree08_apex_xy":apexes,"tree08_nearest_neighbor_px":nearest,
                         "atlas_foreground_apex_xy_approx":ATLAS_APEXES,"atlas_tip_uncertainty_each_axis_px":4,
                         "atlas_nearest_neighbor_px_approx":atlas_nearest,
                         "atlas_pair_distance_lower_bound_px":atlas_lower_bound,
                         "selection":"smallest source apex spacing; tree08 exact top-row/periodic-edge measurement wins; atlas lower bound cannot change it"},
                     "selection": "greedy maximum newly covered 43px edge pixels; ties favor forest art, deeper hard interior, stable y/x",
                     "widest_crown_radius_px": CROWN_RADIUS_PX,
                     "eye_row_proxy_radius_px": EYE_ROW_PROXY_RADIUS_PX,
                     "measurement_limit": "two-dimensional horizontal coverage proxies, not 3D occlusion",
                     "runtime": "disabled by default; shared SourceFir.at_foot scale 1, collision false, original shadow",
                     "source_art_entities_and_movement": "unchanged"}}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "game/prototype/rc5_forest_preview.json")
    parser.add_argument("--existing", type=Path, default=EXISTING_PATH)
    parser.add_argument("--completed", type=Path, default=COMPLETED_PATH)
    args = parser.parse_args()
    result = build(args.existing, args.completed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({n: {"before": q["before"], "after": q["after"]}
                      for n, q in result["screens"].items()}, indent=2))


if __name__ == "__main__":
    main()
