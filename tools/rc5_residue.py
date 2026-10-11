#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Decompose RC5 reachable vision-0 `nothing` boundary pixels by their source masks.

This is a source-map census, not a campaign playthrough or an eye-level visibility test.
All four input artifacts are passed explicitly; JSON and gzip-compressed JSON are accepted.
"""
from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
from scipy import ndimage

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from collision_map import rect_mask, tile_mask  # noqa: E402

SCHEMA_CENSUS = "rc5-hardness-census-1"
SCHEMA_NATIVE = "rc5-render-dispatch-2"
PLAYABLE_MIN_X, PLAYABLE_MAX_X = 20, 620
GROW = 4
SOURCE_KINDS = ("tile_default", "tile_custom", "sprite_hardbox")
COMBO_NAMES = {
    0: "none",
    1: "tile_default_only",
    2: "tile_custom_only",
    3: "tile_default_and_custom_invalid",
    4: "sprite_hardbox_only",
    5: "tile_default_and_sprite_hardbox",
    6: "tile_custom_and_sprite_hardbox",
    7: "tile_default_custom_and_sprite_invalid",
}


def read_json(path: Path) -> Any:
    """Read a JSON or .json.gz artifact from an explicit path."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    """Write deterministic plain or gzip JSON, selected by the output suffix."""
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if path.suffix == ".gz":
        with path.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped:
                zipped.write(payload)
    else:
        path.write_bytes(payload)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def mask_from_component_runs(record: dict[str, Any]) -> np.ndarray:
    """Reconstruct the exact `reachable_unowned_components` mask (screen x/y coordinates)."""
    mask = np.zeros((400, 640), dtype=bool)
    for component in record.get("reachable_unowned_components", []):
        for y, x0, x1 in component["runs"]:
            mask[int(y), int(x0):int(x1)] = True
    return mask


def hardbox_mask(rect: list[float] | tuple[float, ...]) -> np.ndarray:
    """Native half-open hardbox, grown by the game's four source-pixel clearance."""
    mask = rect_mask([rect], GROW)
    mask[:, :PLAYABLE_MIN_X] = False
    mask[:, PLAYABLE_MAX_X:] = False
    return mask


def presence_bits(domain: np.ndarray, masks: dict[str, np.ndarray]) -> np.ndarray:
    """Encode source membership in stable bit positions; callers count only `domain` pixels."""
    bits = np.zeros(domain.shape, dtype=np.uint8)
    for bit, name in enumerate(SOURCE_KINDS):
        if name in masks:
            bits |= masks[name].astype(np.uint8) << bit
    return bits


def presence_counts(domain: np.ndarray, masks: dict[str, np.ndarray]) -> dict[str, int]:
    """Return exact mutually exclusive membership classes, including no-source pixels."""
    encoded = presence_bits(domain, masks)
    values, counts = np.unique(encoded[domain], return_counts=True)
    return {COMBO_NAMES.get(int(value), str(int(value))): int(count)
            for value, count in zip(values, counts)}


def source_presence_summary(domain: np.ndarray, masks: dict[str, np.ndarray]) -> dict[str, int]:
    """Compute union, exclusive/source overlap, and no-source populations from exact masks."""
    count_masks = [masks.get(name, np.zeros_like(domain)) & domain for name in SOURCE_KINDS]
    incidence = sum(int(mask.sum()) for mask in count_masks)
    total = int(domain.sum())
    covered = np.zeros_like(domain)
    membership = np.zeros(domain.shape, dtype=np.uint8)
    for mask in count_masks:
        covered |= mask
        membership += mask.astype(np.uint8)
    return {
        "source_covered_union_px": int(covered.sum()),
        "source_owner_incidences_px": incidence,
        "source_only_px": int(((membership == 1) & domain).sum()),
        "source_overlap_px": int(((membership >= 2) & domain).sum()),
        "no_identified_source_px": total - int(covered.sum()),
    }


def edge_masks(shape: tuple[int, int]) -> dict[str, np.ndarray]:
    """Perimeter location masks; they do not imply a hardness source."""
    h, w = shape
    left = np.zeros(shape, dtype=bool); left[:, PLAYABLE_MIN_X] = True
    right = np.zeros(shape, dtype=bool); right[:, PLAYABLE_MAX_X - 1] = True
    top = np.zeros(shape, dtype=bool); top[0, :] = True
    bottom = np.zeros(shape, dtype=bool); bottom[h - 1, :] = True
    return {"x20": left, "x619": right, "y0": top, "y399": bottom,
            "perimeter": left | right | top | bottom}


def _tile_source_masks(world_doc: dict[str, Any], screen: int, screen_record: dict[str, Any],
                       footprints: dict[str, Any], residual: np.ndarray) -> tuple[np.ndarray, np.ndarray, dict[str, dict[str, np.ndarray]], dict[str, dict[str, Any]]]:
    screen_text = str(screen)
    footprint = footprints.get(screen_text, {})
    live_tile, per_tile = tile_mask(world_doc, screen, footprint.get("revert", ()), footprint.get("clear", ()))
    default_mask = np.zeros_like(residual)
    custom_mask = np.zeros_like(residual)
    families: dict[str, dict[str, np.ndarray]] = {"default": {}, "custom": {}}
    family_info: dict[str, dict[str, Any]] = {}
    cleared = set(map(int, footprint.get("clear", ())))
    reverted = set(map(int, footprint.get("revert", ())))
    defaults = world_doc["hardness"]["tile_defaults"]
    for index, tile in enumerate(screen_record.get("tiles", [])[:96]):
        tile_id = int(tile.get("tile", 0))
        default_id = int(defaults[tile_id]) if 0 <= tile_id < len(defaults) else 0
        is_custom = int(tile.get("hard", 0)) != 0 and index not in cleared and index not in reverted
        mask = (per_tile == index) & live_tile & residual
        if not mask.any():
            continue
        kind = "custom" if is_custom else "default"
        if kind == "custom":
            custom_mask |= mask
        else:
            default_mask |= mask
        family = f"ts{tile_id // 128 + 1:02d}"
        families[kind][family] = families[kind].get(family, np.zeros_like(residual)) | mask
        stats = family_info.setdefault(family, {
            "default_hard_boundary_px": 0,
            "custom_hard_boundary_px": 0,
            "screens": set(),
            "tile_ids": collections.Counter(),
            "default_hardness_ids": collections.Counter(),
            "custom_hardness_ids": collections.Counter(),
        })
        pixels = int(mask.sum())
        stats[f"{kind}_hard_boundary_px"] += pixels
        stats["screens"].add(screen)
        stats["tile_ids"][str(tile_id)] += pixels
        if is_custom:
            stats["custom_hardness_ids"][str(int(tile.get("hard", 0)))] += pixels
        else:
            stats["default_hardness_ids"][str(default_id)] += pixels
    return default_mask, custom_mask, families, family_info


def _flat_and_type0(world_screen: dict[str, Any], inventory: list[dict[str, Any]], screen: int,
                    boundary: np.ndarray, replaced: set[int]) -> tuple[np.ndarray, list[dict[str, Any]], dict[str, Any]]:
    """Build active flat type-0 mask and full source-art inventory statistics for one screen."""
    flat_union = np.zeros_like(boundary)
    hits: list[dict[str, Any]] = []
    stats: dict[str, Any] = {
        "all_type0_entries": 0,
        "vision0_hard0_including_warps": 0,
        "vision0_hard0_warp_entries": 0,
        "vision0_hard0_nonwarp_entries": 0,
        "painted_flat_hard0_placements": 0,
        "nonflat_hard0_placements": 0,
        "supplementary_type0": collections.Counter(),
        "supplementary_hard0": collections.Counter(),
        "warp_paths": collections.Counter(),
        "nonflat_paths": collections.Counter(),
        "families": collections.defaultdict(lambda: {
            "placements": 0, "screens": set(), "grown_hardbox_pixels": 0,
            "boundary_owner_incidences": 0, "boundary_hit_screens": set(),
        }),
    }
    family_masks: dict[str, np.ndarray] = {}
    for entity, inv in zip(world_screen.get("sprites", []), inventory, strict=True):
        if int(entity.get("type", 1)) != 0:
            continue
        stats["all_type0_entries"] += 1
        vision = int(entity.get("vision", 0))
        hard0 = int(entity.get("hard", 1)) == 0
        path = str(inv["path"])
        if vision > 0:
            stats["supplementary_type0"][vision] += 1
            if hard0:
                stats["supplementary_hard0"][vision] += 1
        if vision != 0 or not hard0:
            continue
        stats["vision0_hard0_including_warps"] += 1
        if entity.get("warp") is not None:
            stats["vision0_hard0_warp_entries"] += 1
            stats["warp_paths"][path] += 1
            continue
        index = int(entity.get("index", -1))
        if index in replaced:
            # Match census_screen live_boxes: a footprint owner replaces its source box.
            continue
        stats["vision0_hard0_nonwarp_entries"] += 1
        mask = hardbox_mask(inv["hard_rect"])
        flat = bool(inv.get("ground", False)) and inv.get("category") == "ground_picture"
        if not flat:
            stats["nonflat_hard0_placements"] += 1
            stats["nonflat_paths"][path] += 1
            continue
        stats["painted_flat_hard0_placements"] += 1
        family = stats["families"][path]
        family["placements"] += 1
        family["screens"].add(screen)
        family["grown_hardbox_pixels"] += int(mask.sum())
        family_masks.setdefault(path, np.zeros_like(boundary))
        family_masks[path] |= mask & boundary
        hit = mask & boundary
        hit_px = int(hit.sum())
        if hit_px:
            family["boundary_owner_incidences"] += hit_px
            family["boundary_hit_screens"].add(screen)
            hits.append({"screen": screen, "index": index, "path": path,
                         "hard_rect": inv["hard_rect"], "boundary_hit_px": hit_px})
        flat_union |= hit
    for path, family_mask in family_masks.items():
        stats["families"][path]["boundary_union_pixels"] = int(family_mask.sum())
    return flat_union, hits, stats


def _sprite_source_mask(world_screen: dict[str, Any], inventory: list[dict[str, Any]], screen: int,
                        residual: np.ndarray, footprint: dict[str, Any]) -> tuple[np.ndarray, list[dict[str, Any]]]:
    """Active vision-0 original sprite boxes, excluding flat type-0 boxes already subtracted."""
    mask = np.zeros_like(residual)
    sources = []
    replaced = set(map(int, footprint.get("sprites", ())))
    for entity, inv in zip(world_screen.get("sprites", []), inventory, strict=True):
        if int(entity.get("vision", 0)) != 0 or int(entity.get("hard", 1)) != 0 or entity.get("warp") is not None:
            continue
        if int(entity.get("index", -1)) in replaced:
            continue
        is_flat_type0 = (int(entity.get("type", 1)) == 0 and bool(inv.get("ground", False))
                         and inv.get("category") == "ground_picture")
        if is_flat_type0:
            continue
        hit = hardbox_mask(inv["hard_rect"]) & residual
        if hit.any():
            mask |= hit
            sources.append({"index": int(entity.get("index", -1)), "type": int(entity.get("type", 1)),
                            "path": str(inv["path"]), "category": inv.get("category"), "hit_px": int(hit.sum())})
    return mask, sources


def _jsonable_type0(totals: dict[str, Any], hits: list[dict[str, Any]]) -> dict[str, Any]:
    family_rows = {}
    for path, row in sorted(totals["families"].items()):
        family_union = int(row.pop("union_boundary_pixels", 0))
        family_rows[path] = {**row,
                             "screens": len(row["screens"]), "screen_ids": sorted(row["screens"]),
                             "boundary_hit_screens": len(row["boundary_hit_screens"]),
                             "boundary_hit_screen_ids": sorted(row["boundary_hit_screens"]),
                             "union_boundary_pixels_within_art_path": family_union}
    return {
        "all_outdoor_type0_entries": totals["all_type0_entries"],
        "vision0_hard0_entries_including_warps": totals["vision0_hard0_including_warps"],
        "vision0_hard0_warp_entries_excluded_from_boxes": totals["vision0_hard0_warp_entries"],
        "vision0_hard0_nonwarp_entries": totals["vision0_hard0_nonwarp_entries"],
        "painted_flat_hard0_placements": totals["painted_flat_hard0_placements"],
        "painted_flat_art_path_count": len(family_rows),
        "painted_flat_grown_box_pixel_incidences": sum(v["grown_hardbox_pixels"] for v in family_rows.values()),
        "painted_flat_boundary_owner_incidences": sum(v["boundary_owner_incidences"] for v in family_rows.values()),
        "painted_flat_boundary_union_pixels": totals["flat_union_px"],
        "painted_flat_union_share_of_nothing_boundary": totals["flat_union_px"] / totals["boundary_px"] if totals["boundary_px"] else None,
        "overlap_excess_owner_hits": sum(v["boundary_owner_incidences"] for v in family_rows.values()) - totals["flat_union_px"],
        "families_by_path": family_rows,
        "positive_hit_instances": hits,
        "nonflat_hard0_placements_by_path": dict(sorted(totals["nonflat_paths"].items())),
        "nonflat_hard0_placements": totals["nonflat_hard0_placements"],
        "hard0_warp_placements_by_path": dict(sorted(totals["warp_paths"].items())),
        "supplementary_authored_vision_type0_by_vision": {str(k): int(v) for k, v in sorted(totals["supplementary_type0"].items())},
        "supplementary_authored_vision_hard0_type0_by_vision": {str(k): int(v) for k, v in sorted(totals["supplementary_hard0"].items())},
    }


def analyze(world_doc: dict[str, Any], footprints_doc: dict[str, Any], census: dict[str, Any],
            inventory_doc: dict[str, Any], *, inputs: dict[str, Any] | None = None) -> dict[str, Any]:
    """Analyze all screens in the supplied source/census/native artifacts."""
    if census.get("schema") != SCHEMA_CENSUS:
        raise ValueError(f"expected census schema {SCHEMA_CENSUS}, got {census.get('schema')!r}")
    if inventory_doc.get("schema") != SCHEMA_NATIVE:
        raise ValueError(f"expected native schema {SCHEMA_NATIVE}, got {inventory_doc.get('schema')!r}")
    world = world_doc["screens"]
    footprints = footprints_doc.get("screens", {})
    inventory = inventory_doc["screens"]
    if set(census["screens"]) != set(inventory):
        raise ValueError("census and native inventory screen sets differ")
    outdoor = sorted(inventory, key=int)
    if len(outdoor) != 570:
        raise ValueError(f"expected 570 outdoor screens, got {len(outdoor)}")
    base_nothing = int(census["walking_reachability"]["boundary_categories_px"]["nothing"])
    run_total = 0
    flat_total = residual_total = 0
    source_class_totals = collections.Counter()
    presence_combos = collections.Counter()
    perimeter_combos = collections.Counter()
    family_totals: dict[str, dict[str, Any]] = {}
    per_screen: dict[str, Any] = {}
    type0_totals: dict[str, Any] = {
        "all_type0_entries": 0, "vision0_hard0_including_warps": 0,
        "vision0_hard0_warp_entries": 0, "vision0_hard0_nonwarp_entries": 0,
        "painted_flat_hard0_placements": 0, "nonflat_hard0_placements": 0,
        "supplementary_type0": collections.Counter(), "supplementary_hard0": collections.Counter(),
        "warp_paths": collections.Counter(), "nonflat_paths": collections.Counter(),
        "families": collections.defaultdict(lambda: {
            "placements": 0, "screens": set(), "grown_hardbox_pixels": 0,
            "boundary_owner_incidences": 0, "boundary_hit_screens": set(),
            "union_boundary_pixels": 0}),
        "flat_union_px": 0, "boundary_px": base_nothing,
    }
    type0_hits: list[dict[str, Any]] = []
    edge_totals = collections.Counter()
    component_rows: list[dict[str, Any]] = []
    all_component_rows: list[dict[str, Any]] = []
    nothing_by_screen: list[dict[str, Any]] = []
    all_vision0_boundary_px = 0

    for screen_text in outdoor:
        number = int(screen_text)
        if screen_text not in world or bool(world[screen_text].get("indoor", False)):
            raise ValueError(f"native inventory screen {screen_text} is missing/outdoor mismatch")
        if len(world[screen_text].get("sprites", [])) != len(inventory[screen_text]):
            raise ValueError(f"world/native sprite entry count mismatch on screen {screen_text}")
        screen_census = census["screens"][screen_text][0]
        boundary = mask_from_component_runs(screen_census)
        nothing_px = int(boundary.sum())
        if nothing_px != int(screen_census["reachable_boundary_categories_px"]["nothing"]):
            raise ValueError(f"reachable component runs disagree on screen {screen_text}")
        run_total += nothing_px
        all_vision0_boundary_px += nothing_px
        nothing_by_screen.append({"screen": number, "nothing_boundary_px": nothing_px,
                                  "component_count": len(screen_census.get("reachable_unowned_components", []))})
        screen_components = screen_census.get("reachable_unowned_components", [])
        for component in screen_components:
            all_component_rows.append({"screen": number, "pixels": int(component["pixels"]),
                                       "bbox_xyxy": component["bbox_xyxy"]})

        footprint = footprints.get(screen_text, {})
        flat, hits, screen_type0 = _flat_and_type0(world[screen_text], inventory[screen_text],
                                                   number, boundary, set(map(int, footprint.get("sprites", ()))))
        flat_px = int(flat.sum())
        flat_total += flat_px
        type0_totals["flat_union_px"] += flat_px
        for key in ("all_type0_entries", "vision0_hard0_including_warps", "vision0_hard0_warp_entries",
                    "vision0_hard0_nonwarp_entries", "painted_flat_hard0_placements", "nonflat_hard0_placements"):
            type0_totals[key] += screen_type0[key]
        type0_totals["supplementary_type0"].update(screen_type0["supplementary_type0"])
        type0_totals["supplementary_hard0"].update(screen_type0["supplementary_hard0"])
        type0_totals["warp_paths"].update(screen_type0["warp_paths"])
        type0_totals["nonflat_paths"].update(screen_type0["nonflat_paths"])
        type0_hits.extend(hits)
        for path, family in screen_type0["families"].items():
            out_family = type0_totals["families"][path]
            for key in ("placements", "grown_hardbox_pixels", "boundary_owner_incidences"):
                out_family[key] += family[key]
            out_family["screens"].add(number)
            out_family["boundary_hit_screens"].update(family["boundary_hit_screens"])
            out_family["union_boundary_pixels"] += family["boundary_union_pixels"]

        residual = boundary & ~flat
        residual_px = int(residual.sum())
        residual_total += residual_px
        default_tile, custom_tile, tile_families, family_info = _tile_source_masks(
            world_doc, number, world[screen_text], footprints, residual)
        for family, row in family_info.items():
            total = family_totals.setdefault(family, {
                "default_hard_boundary_px": 0, "custom_hard_boundary_px": 0,
                "screens": set(), "tile_ids": collections.Counter(),
                "default_hardness_ids": collections.Counter(), "custom_hardness_ids": collections.Counter(),
            })
            total["default_hard_boundary_px"] += row["default_hard_boundary_px"]
            total["custom_hard_boundary_px"] += row["custom_hard_boundary_px"]
            total["screens"].update(row["screens"])
            total["tile_ids"].update(row["tile_ids"])
            total["default_hardness_ids"].update(row["default_hardness_ids"])
            total["custom_hardness_ids"].update(row["custom_hardness_ids"])
        sprite, sprite_owners = _sprite_source_mask(world[screen_text], inventory[screen_text], number,
                                                   residual, footprint)
        source_masks = {"tile_default": default_tile, "tile_custom": custom_tile,
                        "sprite_hardbox": sprite}
        if np.any(default_tile & custom_tile):
            raise ValueError(f"default/custom source tile masks overlap on screen {screen_text}")
        combo = presence_bits(residual, source_masks)
        for value, count in exact_counts(combo, residual).items():
            presence_combos[value] += count
        source_summary = source_presence_summary(residual, source_masks)
        for key, count in source_summary.items():
            source_class_totals[key] += count
        edges = edge_masks(residual.shape)
        edge = edges["perimeter"] & residual
        for edge_name, edge_mask in edges.items():
            if edge_name == "perimeter":
                edge_totals["perimeter_unique_px"] += int(edge.sum())
            else:
                edge_totals[edge_name] += int((edge_mask & residual).sum())
        for value, count in exact_counts(combo, edge).items():
            perimeter_combos[value] += count

        labels, count_components = ndimage.label(residual)
        for label in range(1, count_components + 1):
            component = labels == label
            ys, xs = np.where(component)
            bbox = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
            center_x = (bbox[0] + bbox[2]) / 2
            center_y = (bbox[1] + bbox[3]) / 2
            aim_i = int(np.argmin((xs - center_x) ** 2 + (ys - center_y) ** 2))
            family_hits = []
            for kind in ("default", "custom"):
                for family, family_mask in tile_families[kind].items():
                    pixels = int((component & family_mask).sum())
                    if pixels:
                        family_hits.append({"family": family, "kind": kind, "pixels": pixels})
            family_hits.sort(key=lambda row: -row["pixels"])
            component_row = {
                "screen": number, "pixels": int(component.sum()), "bbox_xyxy": bbox,
                "aim_xy": [int(xs[aim_i]), int(ys[aim_i])],
                "source_presence_counts": exact_counts(combo, component),
                "source_pixels": {name: int((component & mask).sum()) for name, mask in source_masks.items()},
                "source_covered_union_px": int((component & (default_tile | custom_tile | sprite)).sum()),
                "none_px": int((component & ~(default_tile | custom_tile | sprite)).sum()),
                "edge_strip_px": int((component & edge).sum()),
                "tile_family_top5": family_hits[:5],
                "sprite_sources_top8": sorted(sprite_owners, key=lambda row: -row["hit_px"])[:8],
            }
            component_rows.append(component_row)

        per_screen[screen_text] = {
            "nothing_boundary_px": nothing_px,
            "flat_type0_boundary_union_px": flat_px,
            "residual_boundary_px": residual_px,
            "default_tile_px": int(default_tile.sum()), "custom_tile_px": int(custom_tile.sum()),
            "sprite_hardbox_union_px": int(sprite.sum()),
            **source_summary,
            "perimeter_residual_px": int(edge.sum()),
            "perimeter_presence_counts": exact_counts(combo, edge),
            "residual_presence_counts": exact_counts(combo, residual),
            "unattributed_source_px": int(source_summary["no_identified_source_px"]),
            "flat_type0_positive_owner_hits": sum(row["boundary_hit_px"] for row in hits),
        }

    if run_total != base_nothing:
        raise ValueError(f"nothing boundary reconstruction {run_total} != census aggregate {base_nothing}")
    if flat_total + residual_total != base_nothing:
        raise ValueError(f"flat/residual partition {flat_total}+{residual_total} != {base_nothing}")
    if int(census.get("native_collision_mismatches", []) != []):
        raise ValueError("input census contains native collision mismatches")
    flat_family_report = {}
    for path, row in sorted(type0_totals["families"].items()):
        flat_family_report[path] = {
            "placements": row["placements"], "screens": len(row["screens"]),
            "screen_ids": sorted(row["screens"]), "grown_hardbox_pixels_sum": row["grown_hardbox_pixels"],
            "boundary_owner_incidences_px": row["boundary_owner_incidences"],
            "boundary_hit_screens": len(row["boundary_hit_screens"]),
            "boundary_hit_screen_ids": sorted(row["boundary_hit_screens"]),
            "unique_union_boundary_pixels_within_art_path": row["union_boundary_pixels"],
        }
    all_boundary_screens = [{"screen": int(ns), "nothing_boundary_px": int(row["nothing_boundary_px"]),
                             "component_count": int(row["component_count"])} for ns, row in
                            ((n, {"nothing_boundary_px": census["screens"][n][0]["reachable_boundary_categories_px"]["nothing"],
                                  "component_count": len(census["screens"][n][0].get("reachable_unowned_components", []))})
                             for n in census["screens"])]
    all_boundary_screens.sort(key=lambda row: (-row["nothing_boundary_px"], row["screen"]))
    all_boundary_components = []
    for ns in census["screens"]:
        for component in census["screens"][ns][0].get("reachable_unowned_components", []):
            all_boundary_components.append({"screen": int(ns), "pixels": int(component["pixels"]),
                                            "bbox_xyxy": component["bbox_xyxy"]})
    all_boundary_components.sort(key=lambda row: (-row["pixels"], row["screen"], row["bbox_xyxy"]))
    component_rows.sort(key=lambda row: (-row["pixels"], row["screen"], row["bbox_xyxy"]))
    screen_rank = sorted(((int(ns), row) for ns, row in per_screen.items()),
                         key=lambda pair: (-pair[1]["residual_boundary_px"], pair[0]))
    source_combo_report = {COMBO_NAMES.get(k, str(k)): v for k, v in sorted(presence_combos.items())}
    edge_combo_report = {COMBO_NAMES.get(k, str(k)): v for k, v in sorted(perimeter_combos.items())}
    tile_families = {}
    for family, row in sorted(family_totals.items()):
        tile_families[family] = {
            "default_hard_boundary_px": row["default_hard_boundary_px"],
            "custom_hard_boundary_px": row["custom_hard_boundary_px"],
            "union_boundary_px": row["default_hard_boundary_px"] + row["custom_hard_boundary_px"],
            "screens": len(row["screens"]), "screen_ids": sorted(row["screens"]),
            "tile_ids": dict(sorted(row["tile_ids"].items(), key=lambda item: int(item[0]))),
            "default_hardness_ids": dict(sorted(row["default_hardness_ids"].items(), key=lambda item: int(item[0]))),
            "custom_hardness_ids": dict(sorted(row["custom_hardness_ids"].items(), key=lambda item: int(item[0]))),
        }
    flat_hits_by_family = {path: row["boundary_owner_incidences_px"] for path, row in flat_family_report.items()}
    primary_summary = {
        "flat_hard_type0_placements": type0_totals["painted_flat_hard0_placements"],
        "flat_hard_type0_art_path_count": len(flat_family_report),
        "hard0_type0_including_warps": type0_totals["vision0_hard0_including_warps"],
        "hard0_type0_warps_excluded_from_sprite_boxes": type0_totals["vision0_hard0_warp_entries"],
        "hard0_type0_nonwarp": type0_totals["vision0_hard0_nonwarp_entries"],
        "all_outdoor_type0_entries": type0_totals["all_type0_entries"],
        "supplementary_authored_vision_type0_by_vision": {str(k): int(v) for k, v in sorted(type0_totals["supplementary_type0"].items())},
        "supplementary_authored_vision_hard0_type0_by_vision": {str(k): int(v) for k, v in sorted(type0_totals["supplementary_hard0"].items())},
        "nonflat_hard_type0_by_path": dict(sorted(type0_totals["nonflat_paths"].items())),
        "hard0_type0_warps_by_path": dict(sorted(type0_totals["warp_paths"].items())),
        "flat_hardbox_union_boundary_px": flat_total,
        "flat_hardbox_union_share_of_boundary": flat_total / base_nothing if base_nothing else None,
        "flat_hardbox_owner_pixel_incidences_px": sum(flat_hits_by_family.values()),
        "flat_hardbox_overlap_excess_px": sum(flat_hits_by_family.values()) - flat_total,
        "flat_hard_type0_families": flat_family_report,
        "flat_hard_type0_positive_hit_instances": type0_hits,
    }
    # Perimeter axis totals are computed directly per screen in the loop above.
    # Keep the four edge-strip results distinct and the perimeter union deduplicated.
    edge_counts = collections.Counter()
    source_boundary_counts = collections.Counter()
    pairwise = {a: {b: 0 for b in SOURCE_KINDS} for a in SOURCE_KINDS}
    # Counts at the edge are already available in each per-screen presence table; component masks
    # carry no edge-axis split, so reconstruct the edge axes once from the source census masks below.
    # This pass also provides the inclusive source overlap matrix used by reviewers.
    # (Per-screen matrices remain small; no geometry or renderer state is added.)
    for ns in outdoor:
        number = int(ns)
        boundary = mask_from_component_runs(census["screens"][ns][0])
        flat, _, _ = _flat_and_type0(world[ns], inventory[ns], number, boundary,
                                     set(map(int, footprints.get(ns, {}).get("sprites", ()))))
        residual = boundary & ~flat
        footprint = footprints.get(ns, {})
        default, custom, _, _ = _tile_source_masks(world_doc, number, world[ns], footprints, residual)
        sprite, _ = _sprite_source_mask(world[ns], inventory[ns], number, residual, footprint)
        masks = {"tile_default": default, "tile_custom": custom, "sprite_hardbox": sprite}
        edge = edge_masks(residual.shape)
        for edge_name in ("x20", "x619", "y0", "y399"):
            edge_counts[edge_name] += int((residual & edge[edge_name]).sum())
        edge_counts["perimeter_unique_px"] += int((residual & edge["perimeter"]).sum())
        edge_counts["corners_px"] += int((residual & edge["x20"] & edge["y0"]).sum())
        edge_counts["corners_px"] += int((residual & edge["x619"] & edge["y0"]).sum())
        edge_counts["corners_px"] += int((residual & edge["x20"] & edge["y399"]).sum())
        edge_counts["corners_px"] += int((residual & edge["x619"] & edge["y399"]).sum())
        bits = presence_bits(residual, masks)
        for edge_name in ("x20", "x619", "y0", "y399", "perimeter"):
            mask = residual & edge[edge_name]
            for value, count in exact_counts(bits, mask).items():
                source_boundary_counts[(edge_name, value)] += count
        for a in SOURCE_KINDS:
            for b in SOURCE_KINDS:
                pairwise[a][b] += int((masks[a] & masks[b] & residual).sum())
    for ns, row in per_screen.items():
        row["edge_source_presence_counts"] = {
            edge_name: {COMBO_NAMES.get(combo, str(combo)): count
                        for (name, combo), count in source_boundary_counts.items() if name == edge_name}
            for edge_name in ("x20", "x619", "y0", "y399", "perimeter")}
    result = {
        "schema": "rc5-residue-report-1",
        "basis": {
            "reachability": census.get("basis"),
            "phase": census.get("phase", "baseline"),
            "world_sha256": (inputs or {}).get("world_sha256"),
            "footprints_sha256": (inputs or {}).get("footprints_sha256"),
            "census_sha256": (inputs or {}).get("census_sha256"),
            "native_inventory_sha256": (inputs or {}).get("native_inventory_sha256"),
            "native_inventory_basis": inventory_doc.get("basis"),
            "no_render_or_gameplay_run": True,
        },
        "scope": {
            "outdoor_screens": len(outdoor),
            "vision_layer": 0,
            "reachable_boundary_source": "screens[n][0].reachable_unowned_components",
            "flat_hard_type0_definition": "type==0, vision==0, hard==0, warp absent, inventory ground==true/category ground_picture, and not replaced by a fitted owner",
            "source_kinds_after_flat_type0_union": list(SOURCE_KINDS),
            "custom_tile_definition": "tile.hard nonzero and tile index not in footprint clear or revert; revert reads atlas default mask",
            "tile_family_definition": "tsNN = tile_id // 128 + 1",
            "edge_definition": "playable perimeter x=20, x=619, y=0, y=399; a location flag only, not an extra hardness source",
            "sprite_hardbox_definition": "vision0 hard==0, warp absent, not footprint-replaced, excluding flat type0 already removed",
        },
        "denominator_and_residue": {
            "reachable_nothing_boundary_px": base_nothing,
            "reconstructed_component_run_px": run_total,
            "flat_type0_union_boundary_px": flat_total,
            "residual_nothing_boundary_px": residual_total,
            "equation": f"{base_nothing} - {flat_total} = {residual_total}",
            "screens_with_reachable_nothing_boundary": sum(row["nothing_boundary_px"] > 0 for row in nothing_by_screen),
            "screens_with_residual_nothing_boundary": sum(row["residual_boundary_px"] > 0 for row in per_screen.values()),
        },
        "flat_type0_hardboxes": primary_summary,
        "source_partition": {
            "tile_default_hard_px": int(sum(row["default_tile_px"] for row in per_screen.values())),
            "tile_per_screen_custom_hard_px": int(sum(row["custom_tile_px"] for row in per_screen.values())),
            "sprite_hardbox_union_px": int(sum(row["sprite_hardbox_union_px"] for row in per_screen.values())),
            **{key: int(value) for key, value in source_class_totals.items()},
            "presence_combinations_px": source_combo_report,
            "pairwise_inclusive_overlap_matrix_px": pairwise,
        "no_source_unattributed_px": int(sum(row["unattributed_source_px"] for row in per_screen.values())),
        },
        "tile_families": tile_families,
        "perimeter": {
            "by_location_px": {key: int(edge_counts[key]) for key in ("x20", "x619", "y0", "y399", "perimeter_unique_px", "corners_px")},
            "presence_combinations": {
                edge_name: {COMBO_NAMES.get(combo, str(combo)): count
                            for (name, combo), count in source_boundary_counts.items() if name == edge_name}
                for edge_name in ("x20", "x619", "y0", "y399", "perimeter")},
        },
        "rankings": {
            "whole_nothing_screens_top5": all_boundary_screens[:5],
            "whole_nothing_components_top20": all_boundary_components[:20],
            "residual_screens_top5": [row for _, row in screen_rank[:5]],
            "residual_components_top20": component_rows[:20],
        },
        "per_screen": per_screen,
        "limitations": [
            "Static vision0 source-free 4-connected reachability plus authored vision0 warp edges, not campaign/live input proof.",
            "Hardbox overlap identifies source collision geometry; it does not certify legibility at eye level.",
            "The residual is built from only the exact active flat type0 union; overlapping removed bodies are not credited again.",
            "Edge pixels are reported as a location cross-tab; no invisible edge hardness rule is inferred.",
            "New fitted wall/fir geometry is not added as a source sprite hardbox; this is source-origin accounting.",
        ],
    }
    return result


def exact_counts(encoded: np.ndarray, domain: np.ndarray) -> dict[int, int]:
    values, counts = np.unique(encoded[domain], return_counts=True)
    return {int(value): int(count) for value, count in zip(values, counts)}


def mask_count(mask: np.ndarray) -> int:
    return int(mask.sum())


def build_report(world_path: Path, footprints_path: Path, census_path: Path,
                 inventory_path: Path) -> dict[str, Any]:
    world_doc = read_json(world_path)
    footprints_doc = read_json(footprints_path)
    census = read_json(census_path)
    inventory = read_json(inventory_path)
    metadata = {
        "world_sha256": sha256(world_path), "footprints_sha256": sha256(footprints_path),
        "census_sha256": sha256(census_path), "native_inventory_sha256": sha256(inventory_path),
        "input_paths": {"world": str(world_path), "footprints": str(footprints_path),
                         "census": str(census_path), "native_inventory": str(inventory_path)},
    }
    return analyze(world_doc, footprints_doc, census, inventory, inputs=metadata)


def write_report(output: Path, report: dict[str, Any]) -> None:
    """Write JSON or deterministic gzip JSON based on `.gz` suffix."""
    payload = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if output.suffix == ".gz":
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                compressed.write(payload)
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(payload)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--world", type=Path, required=True, help="world.json")
    parser.add_argument("--footprints", type=Path, required=True, help="footprints.json")
    parser.add_argument("--census", type=Path, required=True, help="RC5 census JSON or JSON.GZ")
    parser.add_argument("--inventory", type=Path, required=True, help="native dispatch inventory JSON or JSON.GZ")
    parser.add_argument("--out", type=Path, required=True, help="report JSON or JSON.GZ output")
    args = parser.parse_args(argv)
    report = build_report(args.world, args.footprints, args.census, args.inventory)
    write_report(args.out, report)
    print(json.dumps({"out": str(args.out),
                      "nothing_boundary_px": report["denominator_and_residue"]["reachable_nothing_boundary_px"],
                      "flat_type0_removed_px": report["denominator_and_residue"]["flat_type0_union_boundary_px"],
                      "residual_px": report["denominator_and_residue"]["residual_nothing_boundary_px"],
                      "source_partition": {k: report["source_partition"][k] for k in
                                           ("tile_default_hard_px", "tile_per_screen_custom_hard_px", "sprite_hardbox_union_px", "source_covered_union_px", "source_only_px", "source_overlap_px", "no_source_unattributed_px")}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
