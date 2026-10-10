#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Negative final fir layout: source-eligible roots cannot cover all hard edges.
"""Fit the authored tile forest as a stand of whole original fir sprites.

One transferable density is read from ts01's 200x200 forest motif: four distinct
foreground fir crowns in sixteen 50x50 cells, or 0.25 fir/cell. Along source
forest-hardness boundaries, whole firs stand at most their own measured crown
width apart. Where the atlas looks closed without source hardness, its art is
cleared to walkable ground with no standing trees. No per-screen
height, density, or width is fitted. Tree-09/10 split edge trims become complete
tree-01 sprites at each shown source part's actual foot, across the outdoor map.
Tile hardness is never edited.

Run: /usr/bin/python3 tools/rc4_fir_stand_fit.py
Optional: --screens 144,176,375 --out game/prototype/rc4_fir_stand.json
This script does no Godot rendering; the lead owns original/eye-level capture.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

from collision_map import tile_mask


ROOT = Path(__file__).resolve().parents[1]
ATLAS_PATH = ROOT / "game/assets/tiles/ts01.png"
WORLD_PATH = ROOT / "game/data/world.json"
SEQ_PATH = ROOT / "game/data/sequences.json"
FOREST_CELLS = frozenset((52, 53, 54, 55, 64, 65, 66, 67,
                          72, 73, 74, 75, 76, 77, 78, 79,
                          84, 85, 86, 87, 88, 89, 90, 91))
GRASS_DONORS = frozenset((40, 41, 60, 61))
CELL = 50
MACRO = 100
CROWNS_PER_ATLAS_MOTIF = 4
ATLAS_MOTIF_CELLS = 16
CROWNS_PER_FOREST_CELL = CROWNS_PER_ATLAS_MOTIF / ATLAS_MOTIF_CELLS
# The source's four recognizable foreground apexes in ts01 (x200..400,y200..400).
# Approximate apex positions document the count; positions are not fit parameters.
ATLAS_APEXES = ((266, 209), (355, 209), (239, 312), (326, 307))
SEED = "dink-original-fir-stand-v1"
EDGE_GRID = 4  # source-pixel sampling resolution; the width rule absorbs its diagonal
SHEET_CACHE: dict[int, np.ndarray | None] = {}


def cell_image(atlas: np.ndarray, index: int) -> np.ndarray:
    k = index % 128
    return atlas[(k // 12) * CELL:(k // 12 + 1) * CELL,
                 (k % 12) * CELL:(k % 12 + 1) * CELL]


def source_canvas(atlas: np.ndarray, tiles: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    rgb = np.zeros((400, 600, 3), dtype=np.uint8)
    candidate = np.zeros((400, 600), dtype=bool)
    for i, tile in enumerate(tiles[:96]):
        k = int(tile["tile"])
        y, x = divmod(i, 12)
        sheet = k // 128 + 1
        if sheet not in SHEET_CACHE:
            path = ROOT / f"game/assets/tiles/ts{sheet:02d}.png"
            SHEET_CACHE[sheet] = np.asarray(Image.open(path).convert("RGB")) if path.exists() else None
        source = atlas if sheet == 1 else SHEET_CACHE[sheet]
        if source is not None:
            rgb[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = cell_image(source, k)
        if k in FOREST_CELLS:
            candidate[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = True
    return rgb, candidate


def checked_forest_pixels(rgb: np.ndarray, candidate: np.ndarray) -> np.ndarray:
    """Keep authored forest-cell pixels, excluding connected grass at their edge.

    The old contour prototype failed as *geometry*, not as a ground-pixel owner.
    This extraction is reused without its shell or its inferred height.
    """
    smooth = np.stack([ndimage.uniform_filter(rgb[..., c].astype(float), size=5)
                       for c in range(3)], axis=-1)
    grass_like = ((smooth[..., 0] > 62) & (smooth[..., 1] > 84)
                  & (smooth[..., 2] > 40)
                  & (smooth[..., 1] - smooth[..., 0] < 45))
    connected_grass = ndimage.binary_propagation(~candidate, mask=~candidate | grass_like)
    owned = candidate & ~connected_grass
    labels, _ = ndimage.label(owned)
    sizes = np.bincount(labels.ravel())
    owned &= sizes[labels] > 100
    assert not (owned & ~candidate).any()
    return owned


def rle(mask: np.ndarray) -> list[list[int]]:
    flat = mask.ravel().astype(np.int8)
    d = np.diff(np.pad(flat, (1, 1)))
    return [[int(a), int(b - a)] for a, b in zip(np.where(d == 1)[0], np.where(d == -1)[0])]


def hash01(*items: object) -> float:
    raw = (SEED + ":" + ":".join(map(str, items))).encode()
    return int.from_bytes(hashlib.sha256(raw).digest()[:8], "big") / 2**64


def source_foot(image: np.ndarray, row0: int, row1: int) -> tuple[float, int]:
    # fp_world.sprite_foot: bottom nonblack drawn row, mean x at pixel centers.
    for y in range(row1 - 1, row0 - 1, -1):
        a = image[y]
        xs = np.where((a[:, 3] > 127) & (a[:, :3].sum(axis=1) >= 11))[0]
        if len(xs):
            return round(float(xs.mean() + .5), 3), y + 1
    raise ValueError("sprite part has no root row")


def split_parts(image: np.ndarray) -> list[tuple[int, int]]:
    rows = np.where((image[..., 3] > 127).any(axis=1))[0]
    if not len(rows):
        return []
    cuts = [0]
    for j in range(1, len(rows)):
        if (rows[j] - rows[j - 1] > 3
                and rows[j - 1] + 1 - rows[cuts[-1]] >= 30
                and rows[-1] + 1 - rows[j] >= 30):
            cuts.append(j)
    return [(int(rows[cuts[k]]), int(rows[(cuts[k + 1] if k + 1 < len(cuts) else len(rows)) - 1] + 1))
            for k in range(len(cuts))]


def global_grass_sources(world: dict) -> dict[int, tuple[cKDTree, list[tuple[int, int, int]]]]:
    grouped: dict[int, list[tuple[int, int, int, int, int]]] = {0: [], 1: []}
    for name, screen in world["screens"].items():
        if screen.get("indoor"):
            continue
        n = int(name)
        sx, sy = (n - 1) % 32 * 12, (n - 1) // 32 * 8
        for i, t in enumerate(screen["tiles"][:96]):
            k = int(t["tile"])
            if k in GRASS_DONORS:
                row, col = divmod(i, 12)
                gx, gy = sx + col, sy + row
                grouped[gx % 2].append((gx, gy, n, i, k))
    return {parity: (cKDTree([(r[0], r[1]) for r in rows]), [(r[2], r[3], r[4]) for r in rows])
            for parity, rows in grouped.items() if rows}


def donor_for_tile(screen: int, tiles: list[dict], i: int,
                   global_donors: dict) -> tuple[int, list[int], str, float]:
    """Continue local grass phase, or use the nearest source donor across seams."""
    row, col = divmod(i, 12)
    if all(int(tiles[3 * 12 + c]["tile"]) == v for c, v in ((4, 40), (5, 41), (6, 60), (7, 61))):
        # This phase is visible in the continuous center trail on 144.
        donor = (40 if (row + col // 2) % 2 else 60) + col % 2
        source_i = next(j for j, t in enumerate(tiles) if int(t["tile"]) == donor)
        return donor, [screen, source_i], "local measured phase", 0.0
    for d in range(2, 12, 2):
        for c in (col - d, col + d):
            j = row * 12 + c
            if 0 <= c < 12 and int(tiles[j]["tile"]) in GRASS_DONORS:
                return int(tiles[j]["tile"]), [screen, j], "same-row parity", float(d)
    for d in range(1, 8):
        for r in (row - d, row + d):
            j = r * 12 + col
            if 0 <= r < 8 and int(tiles[j]["tile"]) in GRASS_DONORS:
                return int(tiles[j]["tile"]), [screen, j], "same-column", float(d)
    gx = (screen - 1) % 32 * 12 + col
    gy = (screen - 1) // 32 * 8 + row
    tree, records = global_donors[gx % 2]
    distance, near = tree.query((gx, gy))
    source_n, source_i, donor = records[int(near)]
    return donor, [source_n, source_i], "nearest outdoor grass donor", round(float(distance), 3)


def generated_firs(screen: int, tiles: list[dict], solid_owned: np.ndarray) -> list[dict]:
    # The density is measured per art-cell area, but only source forest pixels
    # that are also source-hard may stand a tree. Unhard art becomes a clearing.
    desired = round(float(solid_owned.sum()) / (CELL * CELL) * CROWNS_PER_FOREST_CELL)
    ox = ((screen - 1) % 32) * 600
    oy = ((screen - 1) // 32) * 400
    blocks = []
    for my in range(4):
        for mx in range(6):
            members = [(my * 2 + dy) * 12 + mx * 2 + dx for dy in range(2) for dx in range(2)]
            present = [i for i in members if int(tiles[i]["tile"]) in FOREST_CELLS]
            solid_patch = solid_owned[my * MACRO:(my + 1) * MACRO,
                                      mx * MACRO:(mx + 1) * MACRO]
            if present and solid_patch.any():
                gx, gy = (ox + mx * MACRO) // MACRO, (oy + my * MACRO) // MACRO
                blocks.append((int(solid_patch.sum()), hash01("rank", gx, gy), mx, my, present, gx, gy))
    blocks.sort(key=lambda b: (-b[0], -b[1], b[3], b[2]))
    distance = ndimage.distance_transform_edt(solid_owned)
    out = []
    for coverage, _, mx, my, members, gx, gy in blocks[:desired]:
        choices = []
        for attempt in range(16):
            x = int(mx * MACRO + 50 + (hash01("x", gx, gy, attempt) - .5) * 40)
            y = int(my * MACRO + 50 + (hash01("y", gx, gy, attempt) - .5) * 40)
            if 0 <= x < 600 and 0 <= y < 400 and solid_owned[y, x]:
                choices.append((float(distance[y, x]), -attempt, x, y))
        if choices:
            _, _, x, y = max(choices)
        else:
            patch = distance[my * MACRO:(my + 1) * MACRO, mx * MACRO:(mx + 1) * MACRO]
            iy, ix = np.unravel_index(int(np.argmax(patch)), patch.shape)
            x, y = mx * MACRO + int(ix), my * MACRO + int(iy)
            if not solid_owned[y, x]:
                raise ValueError(f"screen {screen} chosen forest block has no hard forest pixel")
        out.append({"class": "generated_from_tile", "foot": [float(x), float(y)],
                    "vision": 0,
                    "world_macrocell": [int(gx), int(gy)], "tile_members": members,
                    "source_solid_pixels_in_macrocell": coverage,
                    "placement": "global SHA256 cell hash, +/-20 px jitter; root on source-hard forest art"})
    if len(out) != desired:
        raise ValueError(f"screen {screen}: expected {desired} forest firs, made {len(out)}")
    return out


def forest_hardness(world: dict, screen: int, candidate: np.ndarray,
                    crown_width: int) -> tuple[np.ndarray, np.ndarray, list[dict], dict]:
    """Attribute only connected tile hardness rooted in source forest cells.

    A custom grass-tile mask can project into the path for one crown width. It
    belongs to forest only when its hard component touches a forest tile. Hard
    components on other art remain unowned and are listed for the lead.
    """
    source = world["screens"][str(screen)]
    hard, members = tile_mask(world, screen)
    hard, members = hard[:, 20:620], members[:, 20:620]
    ids = np.array([int(t["tile"]) for t in source["tiles"][:96]], dtype=np.int32)
    tile_ids = ids[members]
    labels, _ = ndimage.label(hard)
    roots = np.unique(labels[hard & candidate])
    roots = roots[roots > 0]
    near = ndimage.distance_transform_edt(~candidate) <= crown_width
    eligible = candidate | (np.isin(tile_ids, tuple(GRASS_DONORS)) & near)
    owned = hard & np.isin(labels, roots) & eligible
    mismatch = hard & near & ~owned
    components, count = ndimage.label(mismatch)
    boxes = ndimage.find_objects(components)
    sizes = np.bincount(components.ravel())
    misses = []
    for label in range(1, count + 1):
        if sizes[label] == 0:
            continue
        box = boxes[label - 1]
        misses.append({"pixels": int(sizes[label]),
                       "bbox_xyxy": [int(box[1].start), int(box[0].start),
                                     int(box[1].stop), int(box[0].stop)]})
    misses.sort(key=lambda m: -m["pixels"])
    stats = {"all_tile_hard_px": int(hard.sum()), "forest_hard_owned_px": int(owned.sum()),
             "near_forest_unowned_hard_px": int(mismatch.sum()),
             "hard_components_touching_forest": len(roots)}
    return hard, owned, misses, stats


def boundary_points(mask: np.ndarray) -> np.ndarray:
    """A representative source pixel of each 4x4 cell touched by a boundary."""
    coarse = mask.reshape(100, EDGE_GRID, 150, EDGE_GRID).any(axis=(1, 3))
    points = []
    for by, bx in np.argwhere(coarse):
        ys, xs = np.where(mask[by * EDGE_GRID:(by + 1) * EDGE_GRID,
                                    bx * EDGE_GRID:(bx + 1) * EDGE_GRID])
        points.append((int(bx * EDGE_GRID + round(float(xs.mean()))),
                       int(by * EDGE_GRID + round(float(ys.mean())))))
    return np.asarray(points, dtype=np.int16).reshape((-1, 2))


def close_boundary(screen: int, points: np.ndarray, existing: list[dict],
                   solid_owned: np.ndarray, crown_width: int,
                   kind: str) -> tuple[list[dict], float]:
    """Try to cover each sampled edge point within half a source crown width.

    Trims already converted to whole firs can cover the edge; interior density
    trees are excluded because their root may be behind the visible hard edge.
    """
    if not len(points):
        return [], 0.0
    radius = (crown_width - EDGE_GRID * 2) / 2.0
    possible_yx = np.argwhere(solid_owned)
    if not len(possible_yx):
        return [], float("inf")
    possible_xy = possible_yx[:, ::-1]
    nearest = cKDTree(possible_xy).query(points.astype(float))[1]
    candidates = np.unique(possible_xy[nearest], axis=0)
    sites = np.array([p["foot"] for p in existing], dtype=float).reshape((-1, 2))
    coords = points.astype(float)
    if len(sites):
        distances = cKDTree(sites).query(coords)[0]
    else:
        distances = np.full(len(coords), np.inf)
    ox = ((screen - 1) % 32) * 600
    oy = ((screen - 1) // 32) * 400
    ranked = np.array([hash01(kind, ox + int(p[0]), oy + int(p[1])) for p in candidates])
    nearby = cKDTree(coords).query_ball_point(candidates.astype(float), radius)
    out = []
    used = set()
    while float(distances.max()) > radius:
        uncovered = distances > radius
        scores = [int(uncovered[near].sum()) if i not in used else -1 for i, near in enumerate(nearby)]
        best = max(scores)
        if best <= 0:
            break  # remaining hard edge is farther than a crown from any source-hard forest art
        equally_good = [i for i, score in enumerate(scores) if score == best]
        chosen = max(equally_good, key=lambda i: ranked[i])
        x, y = (int(v) for v in candidates[chosen])
        used.add(chosen)
        out.append({"class": kind, "foot": [float(x), float(y)],
                    "vision": 0,
                    "source_boundary": "source-hard forest art beside forest-connected tile hardness",
                    "spacing_source": "whole seq32/frame1 crown width"})
        distances = np.minimum(distances, np.hypot(coords[:, 0] - x, coords[:, 1] - y))
    return out, round(float(distances.max()), 3)


def boundary_firs(screen: int, world: dict, candidate: np.ndarray, owned: np.ndarray,
                  trims: list[dict], crown_width: int) -> tuple[list[dict], dict, np.ndarray]:
    if not candidate.any():
        return [], {"stats": {"all_tile_hard_px": 0, "forest_hard_owned_px": 0,
                              "near_forest_unowned_hard_px": 0, "hard_edge_firs": 0,
                              "hard_boundary_sample_points": 0, "hard_boundary_full_pixels": 0,
                              "hard_edge_uncovered_sample_points": 0, "hard_edge_uncovered_full_pixels": 0,
                              "hard_edge_uncoverable_any_admissible_root_px": 0,
                              "hard_edge_avoidable_after_fit_px": 0,
                              "visual_edge_without_hard_sample_points": 0,
                              "edge_spacing_limit_px": crown_width},
                    "unowned_near_forest_hard_components": [],
                    "uncovered_hard_edge_components": []}, np.zeros_like(owned)
    hard, forest_hard, mismatches, hard_stats = forest_hardness(world, screen, candidate, crown_width)
    grass_and_free = ~hard & ~owned
    touching_free = ndimage.binary_dilation(grass_and_free, structure=np.ones((3, 3), bool))
    hard_edge = forest_hard & touching_free
    # The source sometimes paints a closed forest where hardness has a gap
    # (144 north center). It stays a clearing under the lead's solidity rule.
    distance_to_hard = (ndimage.distance_transform_edt(~hard_edge) if hard_edge.any()
                        else np.full(owned.shape, np.inf))
    visual_edge = owned & touching_free & (distance_to_hard > crown_width / 2.0)
    # Screen seams are continuations, not new forest fronts.
    for edge in (hard_edge, visual_edge):
        edge[0, :] = False
        edge[-1, :] = False
        edge[:, 0] = False
        edge[:, -1] = False
    hard_points, visual_points = boundary_points(hard_edge), boundary_points(visual_edge)
    current_trims = [p for p in trims if int(p.get("vision", 0)) == 0]
    hard_firs, hard_radius = close_boundary(screen, hard_points, current_trims,
                                            owned & forest_hard, crown_width, "forest_hard_edge")
    # The 4 px grid chooses economical sites. Complete the same rule on actual
    # source pixels so grid resolution cannot be blamed for a remaining gap.
    full_y, full_x = np.where(hard_edge)
    full_xy = np.stack((full_x, full_y), axis=1).astype(float)
    allowed_y, allowed_x = np.where(owned & forest_hard)
    allowed_xy = np.stack((allowed_x, allowed_y), axis=1).astype(float)
    if len(full_xy) and len(allowed_xy):
        allowed_tree = cKDTree(allowed_xy)
        best_possible, nearest_allowed = allowed_tree.query(full_xy)
        root_sites = np.array([p["foot"] for p in current_trims + hard_firs], float).reshape((-1, 2))
        actual = cKDTree(root_sites).query(full_xy)[0] if len(root_sites) else np.full(len(full_xy), np.inf)
        while True:
            fixable = np.where((actual > crown_width / 2.0) & (best_possible <= crown_width / 2.0))[0]
            if not len(fixable):
                break
            chosen = max(fixable, key=lambda i: (actual[i], hash01("full-edge", screen, int(full_x[i]), int(full_y[i]))))
            x, y = (int(v) for v in allowed_xy[int(nearest_allowed[chosen])])
            hard_firs.append({"class": "forest_hard_edge", "foot": [float(x), float(y)], "vision": 0,
                              "source_boundary": "full-resolution source-hard forest art edge",
                              "spacing_source": "whole seq32/frame1 crown width"})
            actual = np.minimum(actual, np.hypot(full_xy[:, 0] - x, full_xy[:, 1] - y))
        if len(hard_points):
            roots = np.array([p["foot"] for p in current_trims + hard_firs], float)
            hard_radius = round(float(cKDTree(roots).query(hard_points.astype(float))[0].max()), 3)
    sites = [p["foot"] for p in current_trims + hard_firs]
    uncovered = (int((cKDTree(sites).query(hard_points.astype(float))[0] > crown_width / 2.0).sum())
                 if len(sites) and len(hard_points) else len(hard_points))
    edge_y, edge_x = np.where(hard_edge)
    full_points = np.stack((edge_x, edge_y), axis=1).astype(float)
    full_distance = (cKDTree(sites).query(full_points)[0] if len(sites) and len(full_points)
                     else np.full(len(full_points), np.inf))
    full_missing = np.zeros_like(hard_edge)
    full_missing[edge_y[full_distance > crown_width / 2.0],
                 edge_x[full_distance > crown_width / 2.0]] = True
    admissible = np.array([p["foot"] for p in current_trims], float).reshape((-1, 2))
    if len(allowed_xy):
        admissible = np.concatenate((admissible, allowed_xy))
    lower_bound = (cKDTree(admissible).query(full_points)[0] if len(admissible) and len(full_points)
                   else np.full(len(full_points), np.inf))
    impossible = lower_bound > crown_width / 2.0
    avoidable_after_fit = int(((full_distance > crown_width / 2.0) & ~impossible).sum())
    if avoidable_after_fit:
        raise ValueError(f"screen {screen}: {avoidable_after_fit} coverable hard-edge pixels left open")
    missing_labels, missing_count = ndimage.label(full_missing)
    missing_sizes = np.bincount(missing_labels.ravel())
    missing_boxes = ndimage.find_objects(missing_labels)
    missing_components = []
    for i in range(1, missing_count + 1):
        if missing_sizes[i] == 0:
            continue
        box = missing_boxes[i - 1]
        missing_components.append({"pixels": int(missing_sizes[i]),
                                   "bbox_xyxy": [int(box[1].start), int(box[0].start),
                                                 int(box[1].stop), int(box[0].stop)]})
    missing_components.sort(key=lambda c: -c["pixels"])
    stats = hard_stats | {
        "hard_boundary_sample_points": len(hard_points),
        "hard_boundary_full_pixels": len(full_points),
        "visual_edge_without_hard_sample_points": len(visual_points),
        "hard_edge_firs": len(hard_firs),
        "hard_edge_max_sample_to_fir_px": hard_radius if np.isfinite(hard_radius) else None,
        "hard_edge_uncovered_sample_points": uncovered,
        "hard_edge_max_full_pixel_to_fir_px": round(float(full_distance.max()), 3) if len(full_distance) and np.isfinite(full_distance).any() else None,
        "hard_edge_uncovered_full_pixels": int(full_missing.sum()),
        "hard_edge_uncoverable_any_admissible_root_px": int(impossible.sum()),
        "hard_edge_avoidable_after_fit_px": avoidable_after_fit,
        "hard_edge_pixel_sha256": hashlib.sha256(np.packbits(hard_edge.ravel()).tobytes()).hexdigest(),
        "edge_spacing_limit_px": crown_width,
    }
    return hard_firs, {"stats": stats, "unowned_near_forest_hard_components": mismatches,
                       "uncovered_hard_edge_components": missing_components}, forest_hard


def static_trim(e: dict) -> bool:
    return (int(e.get("seq", 0)) == 32 and int(e.get("frame", 0)) in (9, 10)
            and int(e.get("type", -1)) in (0, 1)
            and not str(e.get("script", "")) and int(e.get("brain", 0)) == 0
            and abs(float(e.get("size", 100)) - 100.0) < .5)


def collect_trim_owners(world: dict, seqs: dict) -> dict[int, tuple[list[dict], list[dict], list[dict]]]:
    """Port fp_world's drawn/seam/coincident rules for all static tree-09/10.

    Type-1 parts use the engine's seam rule; type-0 art was background paint, so
    its visible parts are inventoried separately and keep their source type.
    A source placement is suppressed only if its precise member/type/vision
    matches. A shown part with an outside foot remains assigned to its source
    screen and is placed at that outside world foot, as the original draws it.
    """
    images = {frame: np.asarray(Image.open(ROOT / "game" / seqs["32"]["frames"][frame - 1]["path"]).convert("RGBA"))
              for frame in (9, 10)}
    by_screen: dict[int, list[dict]] = {}
    suppress: dict[int, list[dict]] = {}
    for name, sc in world["screens"].items():
        if sc.get("indoor"):
            continue
        n = int(name)
        for i, e in enumerate(sc["sprites"]):
            if not static_trim(e):
                continue
            frame = seqs["32"]["frames"][int(e["frame"]) - 1]
            image = images[int(e["frame"])]
            parts = split_parts(image)
            q = {"screen": n, "list_index": i, "editor_index": int(e["index"]),
                 "e": e, "frame": frame, "path": frame["path"], "image": image,
                 "parts": parts, "vision": int(e.get("vision", 0)), "type": int(e["type"])}
            by_screen.setdefault(n, []).append(q)
            suppress.setdefault(n, []).append({
                "member": [n, "s", i], "editor_index": int(e["index"]),
                "seq": 32, "frame": int(e["frame"]), "type": int(e["type"]),
                "vision": int(e.get("vision", 0)), "hard": int(e.get("hard", 0)),
                "path": frame["path"], "parts": [list(p) for p in parts],
                "shown_parts": [], "source_draw": "ground paint" if int(e["type"]) == 0 else "upright"})

    def crosses(q: dict, side: str) -> bool:
        e, f, a = q["e"], q["frame"], q["image"]
        top, left = float(e["y"]) - float(f["dy"]), float(e["x"]) - float(f["dx"])
        return {"top": top < 0 < top + a.shape[0],
                "bottom": top < 400 < top + a.shape[0],
                "left": left < 20 < left + a.shape[1],
                "right": left < 620 < left + a.shape[1]}[side]

    def seam_partner(q: dict, sx: int, sy: int) -> bool:
        n, e = q["screen"], q["e"]
        m = n + sx + 32 * sy
        if sx and (n + sx - 1) // 32 != (n - 1) // 32:
            return False
        if sx and not crosses(q, "left" if sx < 0 else "right"):
            return False
        if sy and not crosses(q, "top" if sy < 0 else "bottom"):
            return False
        for r in by_screen.get(m, []):
            re = r["e"]
            if r["type"] != 1 or r["path"] != q["path"] or r["vision"] != q["vision"]:
                continue
            if sy and abs(float(re["x"]) + 600 * sx - float(e["x"])) > .5:
                continue
            if sx and abs(float(re["y"]) + 400 * sy - float(e["y"])) > .5:
                continue
            if sx and not crosses(r, "right" if sx < 0 else "left"):
                continue
            if sy and not crosses(r, "bottom" if sy < 0 else "top"):
                continue
            for _, row1 in r["parts"]:
                foot = float(re["y"]) - float(r["frame"]["dy"]) + row1 - 1
                if 0 <= foot < 400 and 20 <= float(re["x"]) < 620:
                    return True
        return False

    candidates: list[dict] = []
    hidden: dict[int, list[dict]] = {}
    for n, placements in by_screen.items():
        upright = {(int(q["e"]["seq"]), int(q["e"]["frame"]),
                    int(q["e"]["x"]), int(q["e"]["y"]), q["vision"])
                   for q in placements if q["type"] == 1}
        for q in placements:
            e, f, image = q["e"], q["frame"], q["image"]
            if q["type"] == 0 and (32, int(e["frame"]), int(e["x"]), int(e["y"]), q["vision"]) in upright:
                hidden.setdefault(n, []).append({"member": [n, "s", q["list_index"]], "reason": "upright twin owns background"})
                continue
            for part_index, (row0, row1) in enumerate(q["parts"]):
                top = int(e["y"] - f["dy"])
                left = int(e["x"] - f["dx"])
                x0, x1 = max(0, 20 - left), min(image.shape[1], 620 - left)
                y0, y1 = max(row0, -top), min(row1, 400 - top)
                if x1 <= x0 or y1 <= y0 or not (image[y0:y1, x0:x1, 3] > 127).any():
                    hidden.setdefault(n, []).append({"member": [n, "s", q["list_index"]],
                                                      "part": part_index, "reason": "no drawn pixel in source screen"})
                    continue
                hot_y = float(e["y"]) - float(f["dy"]) + row1 - 1
                hot_x = float(e["x"])
                outside = not (20 <= hot_x < 620 and 0 <= hot_y < 400)
                if q["type"] == 1 and outside:
                    sx = -1 if hot_x < 20 else (1 if hot_x >= 620 else 0)
                    sy = -1 if hot_y < 0 else (1 if hot_y >= 400 else 0)
                    if seam_partner(q, sx, sy):
                        hidden.setdefault(n, []).append({"member": [n, "s", q["list_index"]],
                                                          "part": part_index, "reason": "source seam partner"})
                        continue
                foot_x, foot_row = source_foot(image, row0, row1)
                local_x = float(e["x"]) - float(f["dx"]) + foot_x - 20.0
                local_y = float(e["y"]) - float(f["dy"]) + foot_row
                world_x = ((n - 1) % 32) * 600 + hot_x - 20
                world_y = ((n - 1) // 32) * 400 + hot_y
                candidates.append({"screen": n, "list_index": q["list_index"], "editor_index": q["editor_index"],
                                   "path": q["path"], "vision": q["vision"], "type": q["type"],
                                   "part": part_index, "rows": [row0, row1], "foot": [round(local_x, 3), round(local_y, 3)],
                                   "source_foot_in_sprite": [foot_x, foot_row], "outside": outside,
                                   "world_hotspot": (world_x, world_y)})

    # fp_world.coincident_first: inside foot first, then member order. For
    # type-0 paint, prefer the type-1 owner at a coincident source point.
    candidates.sort(key=lambda q: (q["outside"], q["type"] == 0,
                                   q["screen"], q["editor_index"], q["part"]))
    kept: list[dict] = []
    for q in candidates:
        near = next((p for p in kept if p["path"] == q["path"] and p["vision"] == q["vision"]
                     and abs(p["world_hotspot"][0] - q["world_hotspot"][0]) <= 3
                     and abs(p["world_hotspot"][1] - q["world_hotspot"][1]) <= 3), None)
        if near is not None:
            hidden.setdefault(q["screen"], []).append({"member": [q["screen"], "s", q["list_index"]],
                                                         "part": q["part"], "reason": "coincident owner",
                                                         "owner": [near["screen"], "s", near["list_index"], near["part"]]})
            continue
        kept.append(q)

    out: dict[int, tuple[list[dict], list[dict], list[dict]]] = {}
    for n in by_screen:
        out[n] = ([], suppress[n], hidden.get(n, []))
    for q in kept:
        n = q["screen"]
        placement = {"class": "replaces_trim", "foot": q["foot"],
                     "source_member": [n, "s", q["list_index"]], "source_editor_index": q["editor_index"],
                     "source_part": q["part"], "source_rows": q["rows"],
                     "source_foot_in_sprite": q["source_foot_in_sprite"], "source_path": q["path"],
                     "source_type": q["type"], "vision": q["vision"], "outside_source_screen": q["outside"]}
        out[n][0].append(placement)
        suppress[n][next(i for i, s in enumerate(suppress[n]) if s["member"][2] == q["list_index"])]["shown_parts"].append(q["part"])
    return out


def support_trim_parts(world: dict, seqs: dict, atlas: np.ndarray,
                       owners: dict[int, tuple[list[dict], list[dict], list[dict]]],
                       forest_screens: set[int], crown_width: int) -> dict[int, list[dict]]:
    """Keep whole replacements only where source collision supports their foot.

    Unsupported shown parts are suppressed as walkable clearing, with explicit
    evidence. Support is tested at the drawn root pixel, not in a clearance band.
    """
    distance_cache: dict[int, np.ndarray] = {}
    omitted: dict[int, list[dict]] = {}

    def forest_distance(n: int, x: float, y: float) -> float:
        if n not in forest_screens or not (0 <= x < 600 and 0 <= y < 400):
            return float("inf")
        if n not in distance_cache:
            sc = world["screens"][str(n)]
            _, candidate = source_canvas(atlas, sc["tiles"][:96])
            _, hard, _, _ = forest_hardness(world, n, candidate, crown_width)
            distance_cache[n] = ndimage.distance_transform_edt(~hard) if hard.any() else np.full((400, 600), np.inf)
        return float(distance_cache[n][min(399, max(0, int(y))), min(599, max(0, int(x)))])

    for n, (placements, suppress, _) in owners.items():
        kept = []
        for p in placements:
            foot_x, foot_y = (float(v) for v in p["foot"])
            world_x = ((n - 1) % 32) * 600 + foot_x
            world_y = ((n - 1) // 32) * 400 + foot_y
            col, row = int(np.floor(world_x / 600)), int(np.floor(world_y / 400))
            destination = 1 + row * 32 + col if 0 <= col < 32 and row >= 0 else -1
            dx, dy = world_x - col * 600, world_y - row * 400
            # source_foot gives the bottom edge (last drawn row + 1). The last
            # drawn root pixel is the source pixel immediately above it.
            tile_distance = forest_distance(destination, dx, dy - 1.0)
            e = world["screens"][str(n)]["sprites"][int(p["source_member"][2])]
            frame = seqs["32"]["frames"][int(e["frame"]) - 1]
            box = e.get("hardbox") or frame.get("hardbox", [-10, -6, 10, 6])
            size = float(e.get("size", 100)) / 100.0
            bx0, by0 = float(e["x"]) + float(box[0]) * size, float(e["y"]) + float(box[1]) * size
            bx1, by1 = float(e["x"]) + float(box[2]) * size, float(e["y"]) + float(box[3]) * size
            source_foot_x, source_foot_y = foot_x + 20.0, foot_y
            box_distance = float(np.hypot(max(bx0 - source_foot_x, 0.0, source_foot_x - bx1),
                                          max(by0 - source_foot_y, 0.0, source_foot_y - by1)))
            tile_support = tile_distance == 0.0
            sprite_support = (not p["outside_source_screen"] and int(e.get("hard", 1)) == 0
                              and box_distance == 0.0)
            evidence = {"foot_screen": destination, "foot_in_screen": [round(dx, 3), round(dy, 3)],
                        "forest_tile_hard_distance_px": round(tile_distance, 3) if np.isfinite(tile_distance) else None,
                        "sprite_hardbox_distance_px": round(box_distance, 3),
                        "sprite_hardbox_source_xyxy": [bx0, by0, bx1, by1],
                        "sprite_hard": int(e.get("hard", 1)), "source_type": int(e["type"]),
                        "source_vision": int(e.get("vision", 0)),
                        "support": "forest tile hardness" if tile_support else
                                   "hard sprite box" if sprite_support else "none"}
            if tile_support or sprite_support:
                p["hardness_support"] = evidence
                kept.append(p)
            else:
                omission = {"source_member": p["source_member"], "source_part": p["source_part"],
                            "source_path": p["source_path"], "foot": p["foot"],
                            "reason": "walkable clearing: no source forest tile hardness or hard sprite box at foot",
                            "hardness_evidence": evidence}
                omitted.setdefault(n, []).append(omission)
                for member in suppress:
                    if member["member"][2] == p["source_member"][2]:
                        member.setdefault("omitted_parts", []).append(p["source_part"])
                        break
        placements[:] = kept
    return omitted


def projected_whole_firs(placements: list[dict], image: np.ndarray,
                         foot: tuple[float, int]) -> np.ndarray:
    """Diagnostic source-camera cutout coverage; no pixel-exact fit claim."""
    out = np.zeros((400, 600), bool)
    drawn = (image[..., 3] > 127) & (image[..., :3].sum(axis=2) > 40)
    for p in placements:
        x = round(float(p["foot"][0]) - foot[0])
        y = round(float(p["foot"][1]) - foot[1])
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(600, x + image.shape[1]), min(400, y + image.shape[0])
        if x1 > x0 and y1 > y0:
            out[y0:y1, x0:x1] |= drawn[y0 - y:y1 - y, x0 - x:x1 - x]
    return out


def source_trim_pixels(sprites: list[dict], seqs: dict) -> np.ndarray:
    out = np.zeros((400, 600), bool)
    for e in sprites:
        if not static_trim(e) or int(e.get("vision", 0)) != 0:
            continue
        frame = seqs["32"]["frames"][int(e["frame"]) - 1]
        image = np.asarray(Image.open(ROOT / "game" / frame["path"]).convert("RGBA"))
        x = int(e["x"] - frame["dx"] - 20)
        y = int(e["y"] - frame["dy"])
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(600, x + image.shape[1]), min(400, y + image.shape[0])
        if x1 > x0 and y1 > y0:
            out[y0:y1, x0:x1] |= image[y0 - y:y1 - y, x0 - x:x1 - x, 3] > 127
    return out


def center_gap(mask: np.ndarray, y: int) -> int:
    if mask[y, 300]:
        return 0
    left = right = 300
    while left > 0 and not mask[y, left - 1]:
        left -= 1
    while right < 599 and not mask[y, right + 1]:
        right += 1
    return right - left + 1


def fit_screen(screen: int, world: dict, seqs: dict, atlas: np.ndarray,
               whole_image: np.ndarray, whole_foot: tuple[float, int],
               crown_width: int, global_donors: dict,
               trim_owners: dict[int, tuple[list[dict], list[dict], list[dict]]],
               trim_omissions: dict[int, list[dict]]) -> dict:
    source = world["screens"][str(screen)]
    tiles = source["tiles"][:96]
    rgb, candidate = source_canvas(atlas, tiles)
    owned = checked_forest_pixels(rgb, candidate)
    forest_members = [[screen, "t", i] for i, t in enumerate(tiles) if int(t["tile"]) in FOREST_CELLS]
    donor_records = {str(m[2]): donor_for_tile(screen, tiles, m[2], global_donors) for m in forest_members}
    donors = {key: value[0] for key, value in donor_records.items()}
    donor_sources = {key: {"source_member": value[1], "method": value[2], "distance_tiles": value[3]}
                     for key, value in donor_records.items()}
    trims, suppression, hidden_trims = trim_owners.get(screen, ([], [], []))
    hard_edge, boundary, forest_hard = boundary_firs(screen, world, candidate, owned, trims, crown_width)
    solid_owned = owned & forest_hard
    generated = generated_firs(screen, tiles, solid_owned)
    placements = generated + hard_edge + trims
    proposal = projected_whole_firs(placements, whole_image, whole_foot)
    source_visible = owned | source_trim_pixels(source["sprites"], seqs)
    sample_rows = (100, 150, 200, 250, 300, 350)
    # The whole source fir stands by its actual root rather than its editor anchor.
    # A caller using add_billboard can use these hotspot offsets; the isolated
    # builder instead uses sprite_foot directly.
    for placement in placements:
        placement["whole_fir_source_hotspot"] = [round(placement["foot"][0] - (whole_foot[0] - 81), 3),
                                                  round(placement["foot"][1] - (whole_foot[1] - 158), 3)]
    return {
        "screen": screen,
        "ownership": {"forest_tile_members": forest_members,
                      "forest_pixel_mask_size": [600, 400], "forest_pixel_mask_runs": rle(owned),
                      "grass_donor_by_tile_member": donors,
                      "grass_donor_provenance_by_tile_member": donor_sources,
                      "suppressed_trim_members": suppression,
                      "hardness_changed": False, "collision_added": False},
        "placements": placements,
        "boundary": boundary,
        "hidden_trim_parts": hidden_trims,
        "omitted_walkable_trim_parts": trim_omissions.get(screen, []),
        "measurement": {"forest_tile_cells": len(forest_members), "candidate_px": int(candidate.sum()),
                        "owned_forest_px": int(owned.sum()), "owned_outside_forest_cell_px": int((owned & ~candidate).sum()),
                        "source_hard_forest_art_px": int(solid_owned.sum()),
                        "walkable_art_cleared_without_tree_px": int((owned & ~forest_hard).sum()),
                        "generated_firs": len(generated), "whole_fir_trim_replacements": len(trims),
                        "walkable_trim_parts_suppressed_without_replacement": len(trim_omissions.get(screen, [])),
                        "hard_edge_firs": len(hard_edge),
                        "total_whole_firs": len(placements),
                        "expected_generated_from_density": round(float(solid_owned.sum()) / (CELL * CELL) * CROWNS_PER_FOREST_CELL),
                        "original_camera_whole_fir_drawn_px": int(proposal.sum()),
                        "source_center_clear_width_by_row_px": {str(y): center_gap(source_visible, y) for y in sample_rows},
                        "proposed_center_clear_width_by_row_px": {str(y): center_gap(proposal, y) for y in sample_rows},
                        "source_camera_gate": "semantic forest reading; no pixel-exact atlas reconstruction claim"},
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--screens", help="comma-separated subset for investigation; default: every outdoor forest/trim screen")
    ap.add_argument("--out", type=Path, default=ROOT / "game/prototype/rc4_fir_stand.json")
    args = ap.parse_args()
    world = json.loads(WORLD_PATH.read_text())
    seqs = json.loads(SEQ_PATH.read_text())["sequences"]
    atlas = np.asarray(Image.open(ATLAS_PATH).convert("RGB"))
    whole = seqs["32"]["frames"][0]
    whole_image = np.asarray(Image.open(ROOT / "game" / whole["path"]).convert("RGBA"))
    whole_foot = source_foot(whole_image, 0, whole_image.shape[0])
    crown = whole_image[:whole_foot[1]]
    crown_pixels = (crown[..., 3] > 127) & (crown[..., :3].sum(axis=2) > 40)
    crown_x = np.where(crown_pixels)[1]
    crown_width = int(crown_x.max() - crown_x.min() + 1)
    trim_owners = collect_trim_owners(world, seqs)
    forest_screens = {int(n) for n, sc in world["screens"].items()
                      if not sc.get("indoor") and any(int(t["tile"]) in FOREST_CELLS for t in sc["tiles"][:96])}
    all_screens = forest_screens | set(trim_owners)
    screens = [int(x) for x in args.screens.split(",")] if args.screens else sorted(all_screens)
    if any(n not in all_screens for n in screens):
        raise ValueError("requested screen has neither outdoor forest cells nor static tree-09/10")
    global_donors = global_grass_sources(world)
    trim_omissions = support_trim_parts(world, seqs, atlas, trim_owners, forest_screens, crown_width)
    fixtures = {str(n): fit_screen(n, world, seqs, atlas, whole_image, whole_foot,
                                  crown_width, global_donors, trim_owners, trim_omissions) for n in screens}
    result = {
        "schema": "rc4-fir-stand-prototype-1", "source": {
            "atlas": "res://assets/tiles/ts01.png", "atlas_sha256": hashlib.sha256(ATLAS_PATH.read_bytes()).hexdigest(),
            "world": "game/data/world.json", "world_sha256": hashlib.sha256(WORLD_PATH.read_bytes()).hexdigest(),
            "sequences": "game/data/sequences.json", "sequences_sha256": hashlib.sha256(SEQ_PATH.read_bytes()).hexdigest(),
            "whole_fir": whole["path"], "whole_fir_frame": [32, 1],
            "whole_fir_foot_in_sprite": list(whole_foot), "whole_fir_editor_anchor": [whole["dx"], whole["dy"]],
            "whole_fir_scale": 0.025, "shadow": "fp_world.clean_texture + shadow_twin",
            "whole_fir_crown_x_range": [int(crown_x.min()), int(crown_x.max())],
            "whole_fir_crown_width_px": crown_width,
            "crown_measure": "RGBA alpha>127, RGB sum>40, rows above measured whole-fir foot"},
        "density": {"atlas_motif": "ts01 x200..399,y200..399", "atlas_crown_apexes": [list(p) for p in ATLAS_APEXES],
                    "crowns_counted": CROWNS_PER_ATLAS_MOTIF, "atlas_motif_tile_cells": ATLAS_MOTIF_CELLS,
                    "crowns_per_forest_tile_cell": CROWNS_PER_FOREST_CELL,
                    "algorithm": "round(forest tile cells * density), highest-coverage 100px world macrocells first, global cell hash for ties and +/-20px jitter",
                    "seed": SEED},
        "fixtures": fixtures,
        "coverage": {"outdoor_forest_screens": len(forest_screens),
                     "static_trim_source_screens": len(trim_owners),
                     "union_fixtures": len(all_screens),
                     "generated_fixtures": len(fixtures),
                     "supported_trim_whole_firs": sum(f["measurement"]["whole_fir_trim_replacements"] for f in fixtures.values()),
                     "walkable_trim_parts_omitted": sum(f["measurement"]["walkable_trim_parts_suppressed_without_replacement"] for f in fixtures.values()),
                     "all_outdoor_regions_included": set(screens) == all_screens},
        "technical_cause_of_old_failure": "The contour shell projected only its edge; 150791 source foliage pixels were missing on screen144.",
        "reason_we_made_old_failure": "We treated a pre-rendered collage's boundary as enough geometry before measuring its projected interior canopy coverage; that heuristic stopped short. Its ground-pixel ownership remains useful, its inferred shell height does not.",
        "technical_cause_of_first_fir_failure": "A density-only stand left gaps along authored forest hard edges. It also opened screen144's painted north canopy, where source hardness is absent.",
        "reason_we_made_first_fir_failure": "We assumed area density would also close a boundary; random macrocell roots can project their crowns beyond the screen or behind the edge. The heuristic applies only to interior source-hard forest; the edge needs measured crown-width spacing. Walkable painted forest is deliberately cleared under the lead's collision/appearance rule, at the known cost of original-camera canopy closure.",
        "limits": ["Whole tree-01 is an original fir sprite, but the atlas collage does not contain exact separable tree-01 copies.",
                   "Original-camera and eye-level semantic forest reading need the root's rendered review.",
                   "Type-0 trim paint must be suppressed before fp_world paints ground; its whole-fir replacement has no collision.",
                   "A shown trim part without source forest tile hardness or a hard sprite box at its foot is suppressed as walkable clearing, with omission evidence.",
                   "Unowned near-forest hardness components are reported per fixture and not turned into trees."]}
    args.out.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    for n in (144, 375, 439):
        if str(n) in fixtures:
            print(n, fixtures[str(n)]["measurement"], fixtures[str(n)]["boundary"]["stats"])
    print("fixtures", len(fixtures), "whole firs", sum(len(f["placements"]) for f in fixtures.values()),
          "static trims", sum(len(f["ownership"]["suppressed_trim_members"]) for f in fixtures.values()))
    print(args.out)


if __name__ == "__main__":
    main()
