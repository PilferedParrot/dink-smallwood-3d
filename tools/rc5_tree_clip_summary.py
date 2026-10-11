#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Summarize native RC5 5x5 tree dispatch with nonshadow source-art evidence.

This measures source masks and native geometry, not rendered camera occlusion.
Frame-level visual readings are kept separate from alpha-edge measurements:
an opaque edge pixel alone is never called a truncated crown.
"""
from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "tmp/rc5-tree-clip-census/native.json"
OUT = ROOT / "tmp/rc5-tree-clip-census/census.json"
SUMMARY = ROOT / "tmp/rc5-tree-clip-census/summary.txt"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def longest_run(row: np.ndarray) -> int:
    d = np.diff(np.pad(row.astype(np.int8), (1, 1)))
    starts, ends = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
    return int((ends - starts).max()) if len(starts) else 0


def frame_evidence(frame: dict) -> dict:
    path = ROOT / "game" / frame["path"]
    rgba = np.asarray(Image.open(path).convert("RGBA"))
    alpha = rgba[..., 3] >= 128
    nonblack = alpha & (rgba[..., :3].astype(np.int16).sum(axis=2) >= 11)
    y, x = np.where(nonblack)
    dy = int(frame["dy"])
    # Sprite texel row r is sampled at its centre. The generic billboard
    # places that centre at (dy-r-0.5) * pixel_size above ground; row dy is
    # already below zero. Checking only rows dy+1.. missed a full source row.
    below = nonblack.copy()
    below[:dy] = False
    independent_pixel_center_count = sum(int(nonblack[row].sum())
                                         for row in range(nonblack.shape[0]) if row + 0.5 > dy)
    if int(below.sum()) != independent_pixel_center_count:
        raise ValueError(f"pixel-centre ground classification disagrees for {frame['path']}")
    # A colour observation, not a definitive crown segmenter. The source
    # contact sheet must be viewed before assigning a source-truncation label.
    r, g, b = (rgba[..., i].astype(float) for i in range(3))
    greenish = below & (g > 1.15 * r) & (g > 1.10 * b) & (g > 35)
    labels, _ = ndimage.label(nonblack, structure=np.ones((3, 3), bool))
    sizes = np.bincount(labels.ravel())[1:]
    edges = {"top": int(nonblack[0].sum()), "bottom": int(nonblack[-1].sum()),
             "left": int(nonblack[:, 0].sum()), "right": int(nonblack[:, -1].sum())}
    longest = {"top": longest_run(nonblack[0]), "bottom": longest_run(nonblack[-1]),
               "left": longest_run(nonblack[:, 0]), "right": longest_run(nonblack[:, -1])}
    return {"path": frame["path"], "sha256": sha(path),
            "image_size_px": [int(rgba.shape[1]), int(rgba.shape[0])],
            "hotspot_px": [int(frame["dx"]), dy],
            "nonblack_opaque_px": int(nonblack.sum()),
            "nonblack_bbox_xyxy": [int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1],
            "edge_nonblack_px": edges, "edge_longest_run_px": longest,
            "nonblack_alpha_components": int(len(sizes)),
            "largest_component_px": int(sizes.max()) if len(sizes) else 0,
            "generic_pixel_center_rule": "world_y=(hotspot_dy-row-0.5)*pixel_size; below iff row+0.5>hotspot_dy",
            "nonblack_at_hotspot_row_px": int(nonblack[dy].sum()) if 0 <= dy < len(nonblack) else 0,
            "nonblack_below_generic_ground_px": int(below.sum()),
            "green_dominant_below_generic_ground_px": int(greenish.sum())}


def classification(row: dict, source: dict) -> tuple[str, list[str]]:
    frame = int(row["frame"])
    dispatch = row["dispatch"]
    shown = any(row["shown_centers_by_part"])
    if dispatch == "ground_paint":
        return "not_standing_ground_paint", ["source type-0 art is painted into the floor"]
    if not shown:
        return "not_shown_in_any_outdoor_5x5_scene", ["native seam/vision ownership shows no standing part"]
    geometry = row.get("native_geometry_sample", [])
    reasons = []
    if any(g.get("region_enabled") for g in geometry):
        reasons.append("explicit_sprite_region_crop")
    if any(g.get("depth_px") is not None for g in geometry):
        reasons.append("shader_depth_order_shift; rendered overlap requires visual check")
    if row.get("native_on_surface"):
        reasons.append("surface placement; ground-plane inference requires per-scene check")
    if dispatch == "whole_source_fir":
        return "partial_source_art_rebuilt_as_whole_fir", reasons + ["shared SourceFir.at_foot replaces the shown partial source crowns"]
    if frame == 8:
        return "source_truncated_crown_and_generic_ground_intersection", reasons + [
            "source PNG visibly ends several independent crowns at left/right/bottom",
            "native generic card uses dy=69; source has green foliage below ground"]
    if frame in (11, 12, 13):
        return "source_stump_without_standing_crown", reasons + ["source picture is a stump; border contacts do not establish a crown cut"]
    if source["green_dominant_below_generic_ground_px"]:
        return "whole_tree_small_lower_foliage_ground_intersection_proxy", reasons + [
            "source image reads as a complete tree; small green-dominant pixels below generic hotspot are a colour proxy"]
    if any(source["edge_nonblack_px"].values()):
        return "whole_tree_with_border_frond_contact", reasons + [
            "source tree appears whole; border alpha alone cannot establish truncation"]
    return "whole_tree_no_measured_crown_cut", reasons


def build(native_path: Path = NATIVE, prior_census_path: Path = ROOT / "docs/rc5/tree-clip-census-8b70efa.json.gz") -> dict:
    native = json.loads(native_path.read_text())
    world_data = json.loads((ROOT / "game/data/world.json").read_text())
    prior_bytes = prior_census_path.read_bytes()
    if prior_census_path.suffix == ".gz":
        prior_bytes = gzip.decompress(prior_bytes)
    prior_instrument = json.loads(prior_bytes)["prior_123_246_instrument"]
    seqdoc = json.loads((ROOT / "game/data/sequences.json").read_text())
    frames = seqdoc["sequences"]["32"]["frames"]
    source = {str(i): frame_evidence(frame) for i, frame in enumerate(frames, 1)}
    if source["8"]["nonblack_below_generic_ground_px"] != 3535 \
            or source["8"]["nonblack_at_hotspot_row_px"] != 127:
        raise ValueError("tree-08 pixel-centre regression: row 69 must count below ground")
    # Human source-image inspection distinguishes collage cut from natural
    # frond/stump contact; the numeric evidence remains available to challenge.
    source["8"]["source_image_review"] = "multiple crowns visibly truncated at image left, right and bottom"
    source["9"]["source_image_review"] = "two stacked left trim fragments; SourceFir rebuilds each shown part"
    source["10"]["source_image_review"] = "two stacked right trim fragments; SourceFir rebuilds each shown part"
    for i in (1, 2, 3, 4, 5, 6, 7):
        source[str(i)]["source_image_review"] = "whole tree picture; sparse border fronds alone inconclusive"
    for i in (11, 12, 13):
        source[str(i)]["source_image_review"] = "stump picture, no standing crown"
    placements = []
    by_screen = {str(n): {"source_tree_placements": 0, "shown_standing": 0,
                          "frame8_source_truncated_standing": 0,
                          "whole_fir_replacements_shown": 0,
                          "generic_region_crops_shown": 0,
                          "generic_ground_intersections_shown": 0}
                 for n in map(int, native["per_scene"])}
    category_counts = collections.Counter()
    neighbor_fingerprint_collisions = []
    for source_screen, screen in world_data["screens"].items():
        if screen.get("indoor"):
            continue
        grouped = collections.defaultdict(list)
        for e in screen["sprites"]:
            if e.get("seq") == 32 and e.get("frame") in range(8, 14) \
                    and e.get("type", 1) == 1 and e.get("vision", 0) == 0:
                # fp_world's neighbor dedup key is model_key:x:y; frames8..13
                # all dispatch as dead_tree. Type-0 paint has a :ground suffix.
                grouped[(e["x"], e["y"])].append((e["index"], e["frame"]))
        for xy, owners in grouped.items():
            if len(owners) > 1 and any(frame == 8 for _, frame in owners):
                neighbor_fingerprint_collisions.append({"screen": int(source_screen),
                                                        "source_xy": list(xy), "owners": owners})
    rebuilt_parts_shown = sum(sum(bool(centers) for centers in row["shown_centers_by_part"])
                              for row in native["placements"] if row["frame"] in (9, 10))
    if rebuilt_parts_shown != int(prior_instrument["scene5x5_shown_parts_crosscheck"]):
        raise ValueError("native whole-fir part visibility disagrees with the prior independent 9/10 inventory")
    for row in native["placements"]:
        frame = str(row["frame"])
        src = source[frame]
        category, notes = classification(row, src)
        shown = any(row["shown_centers_by_part"])
        geometry = row.get("native_geometry_sample", [])
        record = {"source_screen": row["source_screen"],
                  "source_list_index": row["source_list_index"],
                  "editor_index": row["editor_index"], "seq": row["seq"],
                  "frame": row["frame"], "path": row["path"],
                  "vision": row["vision"], "source_type": row["source_type"],
                  "scripted": row["scripted"], "source_xy": row["source_xy"],
                  "dispatch": row["dispatch"], "source_part_rows": row["source_part_rows"],
                  "shown_centers_by_part": row["shown_centers_by_part"],
                  "native_geometry_scene_center": row.get("native_geometry_scene_center"),
                  "native_geometry": geometry,
                  "native_on_surface": row.get("native_on_surface", False),
                  "classification": category, "classification_evidence": notes}
        placements.append(record)
        category_counts[category] += 1
        screen = by_screen[str(row["source_screen"])]
        screen["source_tree_placements"] += 1
        if shown:
            screen["shown_standing"] += 1
            if row["frame"] == 8 and row["dispatch"] == "generic_billboard":
                screen["frame8_source_truncated_standing"] += 1
            if row["dispatch"] == "whole_source_fir":
                screen["whole_fir_replacements_shown"] += 1
            if row["dispatch"] == "generic_billboard" and any(g.get("region_enabled") for g in geometry):
                screen["generic_region_crops_shown"] += 1
            if row["dispatch"] == "generic_billboard" and src["nonblack_below_generic_ground_px"] \
                    and any(g.get("physical_bottom_m", 0) < -0.0001 for g in geometry):
                screen["generic_ground_intersections_shown"] += 1
    per_scene = {key: {**counts, "frame8_truncated_source_owners": 0}
                 for key, counts in native["per_scene"].items()}
    for row in placements:
        if row["classification"] != "source_truncated_crown_and_generic_ground_intersection":
            continue
        for centers in row["shown_centers_by_part"]:
            for center in centers:
                per_scene[str(center)]["frame8_truncated_source_owners"] += 1
    # A source-screen record and a scene-center record are different lenses.
    # Include all 570 screens in both, including their explicit zero rows.
    counts = {"outdoor_screens": len(per_scene),
              "source_tree_placements": len(placements),
              "other_tree_dispatch_sequence_placements": sum(p["seq"] != 32 for p in placements),
              "shown_standing_source_placements": sum(any(p["shown_centers_by_part"]) for p in placements),
              "shown_scripted_source_placements": sum(p["scripted"] and any(p["shown_centers_by_part"])
                                                       for p in placements),
              "shown_alternate_vision_placements": sum(p["vision"] != 0 and any(p["shown_centers_by_part"])
                                                         for p in placements),
              "shown_vision0_placements": sum(p["vision"] == 0 and any(p["shown_centers_by_part"])
                                              for p in placements),
              "shown_without_native_geometry_sample": sum(any(p["shown_centers_by_part"]) and not p["native_geometry"]
                                                          for p in placements),
              "frame8_source_placements": sum(p["frame"] == 8 for p in placements),
              "frame8_truncated_standing_placements": category_counts["source_truncated_crown_and_generic_ground_intersection"],
              "frame8_affected_source_screens": sum(q["frame8_source_truncated_standing"] > 0 for q in by_screen.values()),
              "frame8_affected_scene_centers": sum(q["frame8_truncated_source_owners"] > 0 for q in per_scene.values()),
              "frame8_scene_appearances": sum(q["frame8_truncated_source_owners"] for q in per_scene.values()),
              "frame8_on_surface": sum(p["frame"] == 8 and p["native_on_surface"] for p in placements),
              "frame8_depth_shader_shift": sum(p["frame"] == 8 and any(g.get("depth_px") is not None
                                                                              for g in p["native_geometry"])
                                                for p in placements),
              "frame8_neighbor_dedup_source_collisions": len(neighbor_fingerprint_collisions),
              "generic_region_crops_shown": sum(q["generic_region_crops_shown"] for q in by_screen.values()),
              "source_screen_zero_tree_rows": sum(q["source_tree_placements"] == 0 for q in by_screen.values()),
              "scene_center_zero_standing_rows": sum(q["standing_vision0"] == 0 and q["standing_vision1"] == 0
                                                     for q in per_scene.values()),
              "classifications": dict(category_counts)}
    if counts["shown_without_native_geometry_sample"]:
        raise ValueError("a shown tree lacks a native sprite geometry sample")
    return {"schema": "rc5-tree-clip-source-native-census-1",
            "source_sha256": {"world.json": sha(ROOT / "game/data/world.json"),
                              "sequences.json": sha(ROOT / "game/data/sequences.json"),
                              "fp_world.gd": sha(ROOT / "game/scripts/fp_world.gd"),
                              "source_fir.gd": sha(ROOT / "game/scripts/source_fir.gd"),
                              "archived_initial_census": sha(prior_census_path),
                              "native.json": sha(native_path)},
            "prior_123_246_instrument": {"source_placements": int(prior_instrument["source_placements"]),
                                        "source_parts": int(prior_instrument["source_parts"]),
                                        "scene5x5_shown_parts_crosscheck": rebuilt_parts_shown,
                                        "source_filter": "probe.gd accepts only seq32 frames9/10; frame8 excluded before census"},
            "scope": "outdoor 5x5 native seam-flag potential visibility, all seq32 1..13 and any renderer tree-family dispatch; own authored vision layers evaluated separately",
            "neighbor_frame8_fingerprint_source_audit": neighbor_fingerprint_collisions,
            "limits": ["seam flags plus one representative native geometry build per source owner; 570 fully assembled scenes were not built or rendered",
                       "neighbor startup scripts could alter source state; the source duplicate-key audit covers static authored positions only",
                       "no rendered-eye occlusion certification from headless geometry",
                       "static source state; scripted and alternate-vision tree visibility can change with campaign execution",
                       "a source border pixel alone is insufficient to call a crown truncated",
                       "green-dominant colour count below hotspot is a diagnostic proxy, not semantic foliage segmentation",
                       "Sprite3D billboard AABB is conservative in horizontal axes; vertical min is used only with source alpha"],
            "counts": counts, "frames": source, "per_source_screen": by_screen,
            "per_scene_center": per_scene, "placements": placements}


def summary(result: dict) -> str:
    c = result["counts"]
    frame8 = result["frames"]["8"]
    affected = sorted(int(k) for k, row in result["per_source_screen"].items()
                      if row["frame8_source_truncated_standing"])
    by_frame = collections.Counter(p["frame"] for p in result["placements"] if any(p["shown_centers_by_part"]))
    lines = ["RC5 source/native tree clipping census — 2026-10-11",
             f"Inputs SHA256: {json.dumps(result['source_sha256'], sort_keys=True)}",
             f"Outdoor screens: {c['outdoor_screens']}; source tree placements: {c['source_tree_placements']}; native seam-flag eligible standing placements in their own authored visions: {c['shown_standing_source_placements']} ({c['shown_vision0_placements']} vision0, {c['shown_alternate_vision_placements']} alternate vision).",
             f"Source tree-08 collage: {frame8['image_size_px'][0]}x{frame8['image_size_px'][1]}, hotspot row {frame8['hotspot_px'][1]}, nonblack border pixels {frame8['edge_nonblack_px']}; {frame8['nonblack_below_generic_ground_px']} nonblack and {frame8['green_dominant_below_generic_ground_px']} green-dominant pixels below its generic ground anchor. Its hotspot row alone contributes {frame8['nonblack_at_hotspot_row_px']} pixels: pixel centres at row69 are already below ground.",
             f"Confirmed source-truncated frame-8 standing placements: {c['frame8_truncated_standing_placements']} on {c['frame8_affected_source_screens']} source screens; potentially included by native seam flags in {c['frame8_affected_scene_centers']} 5x5 scene centers ({c['frame8_scene_appearances']} owner appearances, not assembled-scene visual proof).",
             f"Affected source screens still dispatched as partial generic cards: {affected}.",
             f"Standing placements by source frame: {dict(sorted(by_frame.items()))}.",
             f"Tree-08 on-surface moves {c['frame8_on_surface']}, shader depth-shift cases {c['frame8_depth_shader_shift']} (rendered effect unverified). Generic frame-8 cards in the archived initial RC5 census had quad bottoms 0.65m below ground.",
             f"Visible generic region crops: {c['generic_region_crops_shown']}. Earlier {result['prior_123_246_instrument']['source_placements']}/{result['prior_123_246_instrument']['source_parts']} census filtered only frames 9/10, excluding frame 8 by construction.",
             f"Other source tree dispatch sequences: {c['other_tree_dispatch_sequence_placements']}; shown scripted source placements: {c['shown_scripted_source_placements']}; shown alternate-vision placements: {c['shown_alternate_vision_placements']}; shown trees missing native geometry sample: {c['shown_without_native_geometry_sample']}.",
             f"Neighbor backdrop source dedup check: {c['frame8_neighbor_dedup_source_collisions']} authored same-screen dead_tree:x:y collisions involving frame8; dynamic neighbor state remains a limit.",
             f"Zero rows preserved: {c['source_screen_zero_tree_rows']} source screens without tree placements; {c['scene_center_zero_standing_rows']} scene centers without standing trees.",
             "Technical cause in the initial RC5: tree-08 is a source collage cut at multiple crown boundaries; its generic card also put its bottom 26 source pixels beneath ground. One generic billboard could not reconstruct those crowns.",
             "Why we made it: the earlier 123/246 part census and SourceFir selector were scoped to frames 9/10. They did not test whether other tree frames were self-contained or whether their generic hotspots placed foliage below ground.",
             f"Tree-01/02 have small green-dominant below-hotspot counts ({result['frames']['1']['green_dominant_below_generic_ground_px']}/{result['frames']['2']['green_dominant_below_generic_ground_px']} source pixels); they are colour-proxy ground intersections, not a certified visible half-crown. Other whole frames' edge contacts read as natural fronds or remain inconclusive.",
             "Headless geometry says where opaque source art and sprite quads stand; it does not prove 3D occlusion or what a particular eye camera sees. Source image tree-08 was visually inspected on disk; no game render performed."]
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, default=NATIVE)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--summary", type=Path, default=SUMMARY)
    parser.add_argument("--prior-census", type=Path, default=ROOT / "docs/rc5/tree-clip-census-8b70efa.json.gz",
                        help="Archived initial census JSON or gzip; 9/10 visibility cross-check")
    parser.add_argument("--require-complete-firs", action="store_true",
                        help="Fail if any shown frame8/9/10 remains a partial generic card")
    parser.add_argument("--controls-native", type=Path,
                        help="Archived native census; require unchanged whole-tree/dead/stump controls")
    args = parser.parse_args()
    result = build(args.native, args.prior_census)
    if args.require_complete_firs:
        partial = [p for p in result["placements"] if p["frame"] in (8, 9, 10)
                   and any(p["shown_centers_by_part"]) and p["dispatch"] != "whole_source_fir"]
        if partial:
            raise ValueError(f"shown partial fir source owners remain: {partial[:3]}")
        malformed = [p for p in result["placements"] if p["dispatch"] == "whole_source_fir"
                     and any(p["shown_centers_by_part"])
                     and any(g["path"] != "assets/graphics/lands/Trees/tree-01.png"
                             or g["region_enabled"] for g in p["native_geometry"])]
        if malformed:
            raise ValueError(f"incomplete replacement texture/region: {malformed[:3]}")
        result["complete_fir_class_gate"] = "PASS_ZERO_SHOWN_PARTIAL_FIR_OWNERS"
    if args.controls_native:
        old = json.loads(args.controls_native.read_text())
        def controls(native):
            return {(p["source_screen"], p["editor_index"]): p
                    for p in native["placements"] if p["frame"] not in (8, 9, 10)}
        before, after = controls(old), controls(json.loads(args.native.read_text()))
        if before != after:
            changed = [key for key in before.keys() | after.keys() if before.get(key) != after.get(key)]
            raise ValueError(f"natural-contact controls changed: {changed[:20]}")
        result["unchanged_natural_controls"] = {"placements": len(before),
            "archived_native_sha256": sha(args.controls_native), "status": "PASS_EXACT_NATIVE_RECORD_EQUALITY"}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    args.summary.write_text(summary(result))
    print(summary(result), end="")


if __name__ == "__main__":
    main()
