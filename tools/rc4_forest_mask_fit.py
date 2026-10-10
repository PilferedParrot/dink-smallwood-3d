#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Negative contour shell: source foliage recall is insufficient; renderer/masks unchanged.
"""Verdict: negative contour-shell reconstruction; retain only as a diagnostic.

Screen 144 forest boundary prototype from the original atlas and map.

The forest is tile art, not a set of editor tree objects. Keep tile hardness and
the four tree-09/10 trim placements in their existing owners. This fit owns only
pixels of the repeated ts01 forest motifs, and extrudes their path-facing contour
under the original camera projection (screen x=X, screen y=Z-Y).

Run: /usr/bin/python3 tools/rc4_forest_mask_fit.py
Output: game/prototype/rc4_forest.json and diagnostic PNGs under
tmp/rc4-forest-prototype/outputs. No rendered view is certified here.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from collision_map import tile_mask


ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "game/assets/tiles/ts01.png"
WORLD = ROOT / "game/data/world.json"
SEQUENCES = ROOT / "game/data/sequences.json"
OUT = ROOT / "game/prototype/rc4_forest.json"
EVIDENCE = ROOT / "tmp/rc4-forest-prototype/outputs"
SCREEN = 144
CELL = 50
GRID = 4
FOREST_CELLS = frozenset((52, 53, 54, 55, 64, 65, 66, 67,
                          72, 73, 74, 75, 76, 77, 78, 79,
                          84, 85, 86, 87, 88, 89, 90, 91))
GRASS_DONORS = frozenset((40, 41, 60, 61))


def atlas_cell(atlas: np.ndarray, k: int) -> np.ndarray:
    k %= 128
    return atlas[(k // 12) * CELL:(k // 12 + 1) * CELL,
                 (k % 12) * CELL:(k % 12 + 1) * CELL]


def canvas(atlas: np.ndarray, tiles: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    rgb = np.zeros((400, 600, 3), np.uint8)
    candidates = np.zeros((400, 600), bool)
    for i, tile in enumerate(tiles[:96]):
        k = int(tile["tile"])
        y, x = divmod(i, 12)
        rgb[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = atlas_cell(atlas, k)
        if k in FOREST_CELLS:
            candidates[y * CELL:(y + 1) * CELL, x * CELL:(x + 1) * CELL] = True
    return rgb, candidates


def owned_pixels(rgb: np.ndarray, candidate: np.ndarray) -> tuple[np.ndarray, dict]:
    """A checked color+connectivity mask; green alone cannot distinguish grass.

    The permitted cells are authored forest motifs. In them, a 5 px local RGB
    average can be grass only when it resembles the four actual grass donor cells
    *and* connects to an unowned tile. Foliage highlights inside the forest thus
    remain forest. This keeps every other source tile untouched by construction.
    """
    smooth = np.stack([ndimage.uniform_filter(rgb[..., c].astype(float), size=5)
                       for c in range(3)], axis=-1)
    grass_like = ((smooth[..., 0] > 62) & (smooth[..., 1] > 84)
                  & (smooth[..., 2] > 40)
                  & (smooth[..., 1] - smooth[..., 0] < 45))
    connected_grass = ndimage.binary_propagation(~candidate, mask=(~candidate | grass_like))
    owned = candidate & ~connected_grass
    # Remove isolated pixel noise; contour geometry is sampled on a separate 4 px grid.
    labels, _ = ndimage.label(owned)
    sizes = np.bincount(labels.ravel())
    owned &= sizes[labels] > 100
    metrics = {
        "candidate_px": int(candidate.sum()),
        "owned_px": int(owned.sum()),
        "candidate_grass_px": int((candidate & ~owned).sum()),
        "outside_candidate_owned_px": int((owned & ~candidate).sum()),
        "grass_like_nonforest_fraction": round(float(grass_like[~candidate].mean()), 6),
        "classification": "ts01 forest-cell whitelist; 5x5 RGB grass test; connectivity to nonforest; component >100px",
        "classification_thresholds": {"r_gt": 62, "g_gt": 84, "b_gt": 40, "g_minus_r_lt": 45},
    }
    return owned, metrics


def donor_for_tile(tiles: list[dict], i: int) -> int:
    """Continue the four grass cells' authored two-column/two-row phase.

    fp_world.ground_tile seeks a nearby tile of the same column parity when an
    upper-storey tile replaces grass. Here the nearest path grass explicitly shows
    the 40/41 and 60/61 two-column pair alternating by row and by pair of columns
    (rows 3-5, columns 4-7). Extend that source phase through the forest cells.
    Only the source's four grass cells are allowed; a forest motif is never a donor.
    """
    row, col = divmod(i, 12)
    donor = (40 if (row + col // 2) % 2 else 60) + col % 2
    if donor not in GRASS_DONORS or not any(int(t["tile"]) == donor for t in tiles[:96]):
        raise ValueError(f"screen {SCREEN} tile {i} has no original grass donor")
    return donor


def rle(mask: np.ndarray) -> list[list[int]]:
    flat = mask.ravel().astype(np.int8)
    changes = np.diff(np.pad(flat, (1, 1)))
    return [[int(start), int(end - start)] for start, end in
            zip(np.where(changes == 1)[0], np.where(changes == -1)[0])]


def trim_parts(image: Image.Image) -> list[list[int]]:
    rows = np.where(np.asarray(image.convert("RGBA"))[..., 3].max(axis=1) > 127)[0]
    cuts = [0]
    for j in range(1, len(rows)):
        if (rows[j] - rows[j - 1] > 3
                and rows[j - 1] + 1 - rows[cuts[-1]] >= 30
                and rows[-1] + 1 - rows[j] >= 30):
            cuts.append(j)
    return [[int(rows[cuts[k]]), int(rows[(cuts[k + 1] if k + 1 < len(cuts) else len(rows)) - 1])]
            for k in range(len(cuts))]


def boundary_segments(mask: np.ndarray, height_px: float) -> list[dict]:
    """Merge collinear exposed edges of a 4 px majority mask; no screen-edge walls."""
    coarse = mask.reshape(100, GRID, 150, GRID).sum(axis=(1, 3)) >= 8
    out = []
    # x-constant, free side +/-X
    for j in range(1, coarse.shape[1]):
        for sign in (-1, 1):
            active = ((coarse[:, j] & ~coarse[:, j - 1]) if sign == -1
                      else (coarse[:, j - 1] & ~coarse[:, j]))
            runs = rle(active)
            for start, length in runs:
                out.append({"a": [j * GRID, start * GRID],
                            "b": [j * GRID, (start + length) * GRID],
                            "outward": [sign, 0], "height_px": height_px})
    # y-constant, free side +/-Z
    for j in range(1, coarse.shape[0]):
        for sign in (-1, 1):
            active = ((coarse[j] & ~coarse[j - 1]) if sign == -1
                      else (coarse[j - 1] & ~coarse[j]))
            for start, length in rle(active):
                out.append({"a": [start * GRID, j * GRID],
                            "b": [(start + length) * GRID, j * GRID],
                            "outward": [0, sign], "height_px": height_px})
    return out


def visible_trim_mask(screen: dict, seqs: dict) -> np.ndarray:
    """Original-view opaque trim pixels for residual accounting only; no ownership."""
    out = np.zeros((400, 600), bool)
    for e in screen["sprites"]:
        if e["seq"] != 32 or e["frame"] not in (9, 10) or e["vision"] != 0:
            continue
        frame = seqs["32"]["frames"][e["frame"] - 1]
        a = np.asarray(Image.open(ROOT / "game" / frame["path"]).convert("RGBA"))
        x, y = int(e["x"] - frame["dx"] - 20), int(e["y"] - frame["dy"])
        x0, x1, y0, y1 = max(0, x), min(600, x + a.shape[1]), max(0, y), min(400, y + a.shape[0])
        if x1 > x0 and y1 > y0:
            out[y0:y1, x0:x1] |= a[y0 - y:y1 - y, x0 - x:x1 - x, 3] > 127
    return out


def projected_shell(segments: list[dict]) -> np.ndarray:
    """The original-camera pixels the proposed shell can possibly cover."""
    img = Image.new("1", (600, 400), 0)
    draw = ImageDraw.Draw(img)
    for seg in segments:
        a, b, height = seg["a"], seg["b"], seg["height_px"]
        draw.polygon(((a[0], a[1]), (b[0], b[1]),
                      (b[0], b[1] - height), (a[0], a[1] - height)), fill=1)
    return np.asarray(img, dtype=bool)


def main() -> None:
    world = json.loads(WORLD.read_text())
    screen = world["screens"][str(SCREEN)]
    seqs = json.loads(SEQUENCES.read_text())["sequences"]
    atlas = np.asarray(Image.open(ATLAS).convert("RGB"))
    facades = json.loads((ROOT / "game/prototype/facades.json").read_text())
    kit_claims = [m for b in facades.get("_kit_buildings", [])
                  for m in b.get("members", []) if int(m[0]) == SCREEN]
    footprint_claim = json.loads((ROOT / "game/data/footprints.json").read_text()).get("screens", {}).get(str(SCREEN))
    if kit_claims or footprint_claim:
        raise ValueError("screen 144 already has kit or footprint ownership; audit before fitting")
    rgb, candidate = canvas(atlas, screen["tiles"])
    owned, metrics = owned_pixels(rgb, candidate)
    tile_members = [[SCREEN, "t", i] for i, t in enumerate(screen["tiles"][:96])
                    if int(t["tile"]) in FOREST_CELLS]
    donors = {str(m[2]): donor_for_tile(screen["tiles"], m[2]) for m in tile_members}
    trim_members = []
    trim_heights = []
    for i, e in enumerate(screen["sprites"]):
        if e["seq"] == 32 and e["frame"] in (9, 10) and e["type"] == 1 and e["hard"] == 1:
            frame = seqs["32"]["frames"][e["frame"] - 1]
            parts = trim_parts(Image.open(ROOT / "game" / frame["path"]))
            trim_members.append({"member": [SCREEN, "s", i], "editor_index": int(e["index"]),
                                 "path": frame["path"],
                                 "at": [int(e["x"]), int(e["y"])], "parts_rows": parts,
                                 "ownership": "fp_world.seam_parts/coincident_first; retained, not claimed"})
            trim_heights += [p[1] + 1 - p[0] for p in parts]
    height = float(np.median(trim_heights))
    segments = boundary_segments(owned, height)
    projected = projected_shell(segments)
    hard, _ = tile_mask(world, SCREEN)
    hard = hard[:, 20:620]
    trim = visible_trim_mask(screen, seqs)
    visible = owned | trim
    distance = ndimage.distance_transform_edt(~visible)
    hidden = hard & (distance > 4)
    source_foliage = owned | trim
    proposal_foliage = projected | trim
    intersection = int((source_foliage & proposal_foliage).sum())
    union = int((source_foliage | proposal_foliage).sum())
    metrics.update({
        "tile_hard_px": int(hard.sum()),
        "trim_original_view_px": int(trim.sum()),
        "hard_farther_than_4px_from_forest_or_trim_px": int(hidden.sum()),
        "hard_to_visible_p95_px": round(float(np.percentile(distance[hard], 95)), 3),
        "hard_to_visible_max_px": round(float(distance[hard].max()), 3),
        "boundary_segments": len(segments),
        "boundary_length_px": int(sum(abs(s["b"][0] - s["a"][0]) + abs(s["b"][1] - s["a"][1]) for s in segments)),
        "height_source_part_spans_px": trim_heights,
        "height_px": height,
        "height_m": round(height * 0.025, 4),
        "ground_changed_outside_owned_px": 0,
        "original_camera_source_foliage_px": int(source_foliage.sum()),
        "original_camera_shell_plus_trim_px": int(proposal_foliage.sum()),
        "original_camera_intersection_px": intersection,
        "original_camera_iou": round(intersection / union, 6),
        "original_camera_recall": round(intersection / int(source_foliage.sum()), 6),
        "original_camera_missing_source_px": int((source_foliage & ~proposal_foliage).sum()),
        "fit_status": "negative: contour shell does not recover atlas canopy coverage",
    })
    record = {
        "schema": "rc4-forest-mask-prototype-1", "screen": SCREEN,
        "provenance": {
            "atlas": "res://assets/tiles/ts01.png", "world": "game/data/world.json",
            "sequence": "game/data/sequences.json:32:9,10",
            "atlas_sha256": hashlib.sha256(ATLAS.read_bytes()).hexdigest(),
            "world_sha256": hashlib.sha256(WORLD.read_bytes()).hexdigest(),
            "sequences_sha256": hashlib.sha256(SEQUENCES.read_bytes()).hexdigest(),
            "mask": "authored game/data/world.json hardness; measured only, never modified",
            "camera": "original oblique: screen=(X,Z-Y), source pixels; 0.025 m/source pixel",
            "prior_mechanisms": ["facade_fit.kit_canvas member [screen,t|s,index] tracking",
                                 "fp_world.ground_tile same parity donors",
                                 "fp_world.stack_rows/seam_parts/coincident_first",
                                 "fp_world.clean_texture/sprite_foot/shadow_twin for retained trim sprites"],
        },
        "ownership": {
            "class": "forest tile ground pixels and path-facing shell only",
            "tile_members": tile_members, "trim_members_unclaimed": trim_members,
            "existing_kit_members": kit_claims, "existing_footprint": footprint_claim,
            "sprite_suppression": [], "hardness_changed": False,
            "mask_size": [600, 400], "mask_runs": rle(owned),
            "donor_tile_by_member_index": donors,
            "grass_donor_atlas_cells": sorted(GRASS_DONORS),
        },
        "geometry": {
            "class": "segmented vertical boundary shell",
            "projection_uv": "u=(screen_x-2*outward_x)/600; v=(screen_y-2*outward_y-height_px)/400; repeat source phase",
            "segment_grid_px": GRID, "height_px": height,
            "height_basis": "trial from whole drawn-part span, not identified canopy elevation",
            "contour_basis": "source foliage silhouette, not authored hardness edge",
            "uv_basis": "heuristic 2px inward shift and whole-screen repeat; not independently derived",
            "surfaces": [{"kind": "source_foliage", "segments": segments,
                          "texture": "source screen tile composite before owned-pixel repaint",
                          "collision": "none; authored mask remains source of collision"}],
        },
        "fit": metrics,
        "limitations": ["Source atlas is a pre-rendered forest collage, not separable complete tree frames.",
                        "177.5px is a drawn-part extent, not recovered canopy elevation; contour UVs are heuristic.",
                        "Original-camera projection misses most of the source canopy; do not ship this shell alone.",
                        "The contour shell's eye-level appearance requires the root's rendered review.",
                        "Original-view trim coverage is diagnostic; seam ownership is resolved by fp_world at runtime."],
    }
    OUT.write_text(json.dumps(record, separators=(",", ":")) + "\n")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    Image.fromarray(owned.astype(np.uint8) * 255).save(EVIDENCE / "forest-owned-mask.png")
    overlay = rgb.copy()
    overlay[owned] = (overlay[owned] * .35 + np.array([240, 20, 190]) * .65).astype(np.uint8)
    Image.fromarray(overlay).save(EVIDENCE / "forest-mask-overlay.png")
    Image.fromarray(projected.astype(np.uint8) * 255).save(EVIDENCE / "projected-shell-mask.png")
    replacement = rgb.copy()
    for member in tile_members:
        i = member[2]
        y, x = divmod(i, 12)
        yy, xx = y * CELL, x * CELL
        piece_mask = owned[yy:yy + CELL, xx:xx + CELL]
        patch = replacement[yy:yy + CELL, xx:xx + CELL]
        donor = atlas_cell(atlas, donors[str(i)])
        patch[piece_mask] = donor[piece_mask]
    Image.fromarray(replacement).save(EVIDENCE / "forest-ground-replacement.png")
    print(json.dumps(metrics, indent=2))
    print(OUT)


if __name__ == "__main__":
    main()
