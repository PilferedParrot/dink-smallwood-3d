#!/usr/bin/env python3
"""Report source-art eye-height proximity to existing and completed fir cards.

This is a deterministic 2D disk proxy around measured art feet, not a 3D
occlusion test. Native Godot inventories own the actual 5x5 seam visibility.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image


EYE_PX = 66.0  # 1.65 m / fp_world.SCALE (0.025 m/px)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def art_slice(path: str, foot_x: float, foot_y: float, art_root: Path) -> dict:
    art = np.asarray(Image.open(art_root / Path(path).name).convert("RGBA"))
    # A bottom-edge foot at integer y places the eye on the boundary of two
    # source rows. The documented radius uses the lower row; keep its upper
    # neighbor in evidence so half-pixel ambiguity is visible.
    row = int(round(foot_y - EYE_PX))
    spans = []
    for yy in (row - 1, row):
        if not 0 <= yy < art.shape[0]:
            spans.append({"row": yy, "nonblack_span_px": None, "radius_px": 0.0})
            continue
        drawn = (art[yy, :, 3] > 127) & (art[yy, :, :3].astype(np.int16).sum(axis=1) >= 11)
        xs = np.flatnonzero(drawn)
        if not len(xs):
            spans.append({"row": yy, "nonblack_span_px": None, "radius_px": 0.0})
            continue
        left, right = int(xs[0]), int(xs[-1])
        # Pixel centers and the measured foot are in the same art frame.
        spans.append({"row": yy, "nonblack_span_px": [left, right],
                      "nonblack_pixels": int(len(xs)),
                      "relative_center_span_px": [left + 0.5 - foot_x, right + 0.5 - foot_x],
                      "radius_px": max(abs(left + 0.5 - foot_x), abs(right + 0.5 - foot_x))})
    return {"path": path, "foot_art_px": [foot_x, foot_y], "eye_height_px": EYE_PX,
            "row_used": row, "neighbor_rows": spans, "radius_px": spans[-1]["radius_px"]}


def circle_patch(foot_local: tuple[float, float], radius: float):
    fx, fy = foot_local
    x0 = max(20, int(np.ceil(fx - radius)))
    x1 = min(620, int(np.floor(fx + radius)) + 1)
    y0 = max(0, int(np.ceil(fy - radius)))
    y1 = min(400, int(np.floor(fy + radius)) + 1)
    if x0 >= x1 or y0 >= y1:
        return None
    xx = np.arange(x0, x1, dtype=np.float32)[None, :]
    yy = np.arange(y0, y1, dtype=np.float32)[:, None]
    inside = (xx - fx) ** 2 + (yy - fy) ** 2 <= radius ** 2 + 1e-6
    return x0, x1, y0, y1, inside


def global_hb(screen: int, local: list[float]) -> list[float]:
    ox, oy = ((screen - 1) % 32) * 600 - 20, ((screen - 1) // 32) * 400
    return [local[0] + ox, local[1] + oy, local[2] + ox, local[3] + oy]


def margins(hb: list[float], foot: list[float], radius: float) -> dict:
    rel = [hb[0] - foot[0], hb[1] - foot[1], hb[2] - foot[0], hb[3] - foot[1]]
    return {"relative_hb_w_n_e_s_px": rel,
            "grown4_w_n_e_s_px": [rel[0] - 4, rel[1] - 4, rel[2] + 4, rel[3] + 4],
            "disk_reach_beyond_grown4_w_n_e_s_px": [
                max(0.0, radius + rel[0] - 4),
                max(0.0, radius + rel[1] - 4),
                max(0.0, radius - rel[2] - 4),
                max(0.0, radius - rel[3] - 4),
            ]}


def cohort_items(completed: dict, existing: dict, slices: dict) -> list[dict]:
    out = []
    for placement in completed["placements"]:
        for part in placement["parts"]:
            centers = list(map(int, part["scene5x5_shown_centers"]))
            if not centers:
                continue
            foot = list(map(float, part["global_foot_xy"]))
            scale = float(part["uniform_scale"])
            radius = float(slices["completed"]["radius_px"]) * scale
            source_hb = global_hb(int(placement["screen"]), placement["source_hardbox_xyxy"])
            # The complete original frame's hardbox relative to its measured
            # physical foot; only 92 unsupported roots gain this new collider.
            rel = [-50.5, -31.0, 43.5, 5.0]
            template_hb = [foot[0] + scale * rel[0], foot[1] + scale * rel[1],
                           foot[0] + scale * rel[2], foot[1] + scale * rel[3]]
            owner = {"id": f"{placement['screen']}:{placement['list_index']}:{part['part']}",
                     "cohort": "completed", "source_screen": int(placement["screen"]),
                     "editor_index": int(placement["editor_index"]),
                     "source_frame": int(placement["frame"]), "source_path": placement["path"],
                     "source_type": int(placement["source_type"]), "part": int(part["part"]),
                     "source_rows": part["rows"], "global_foot_xy": foot,
                     "scene5x5_shown_centers": centers, "fullworld_shown": bool(part["fullworld_seam"]["shown"]),
                     "radius_px": radius, "uniform_scale": scale,
                     "source_hard": int(placement["source_hard"]),
                     "source_hb_global_xyxy": source_hb, "source_hb_compare": margins(source_hb, foot, radius),
                     "template_hb_global_xyxy": template_hb,
                     "template_hb_compare": margins(template_hb, foot, radius),
                     "authorized_fir_collision": bool(part["normalized_foot"]["valid_outdoor_neighbor"])
                     and not bool(part["footpoint_collision"].get("effective_total_collision", False)),
                     "before_reachable_disk_px": 0, "after_reachable_disk_px": 0,
                     "after_reachable_outside_source_hb_grow4_px": 0,
                     "after_reachable_outside_template_hb_grow4_px": 0}
            out.append(owner)
    for item in existing["placements"]:
        frame = int(item["frame"])
        if frame not in (1, 2) or not item["scene5x5_shown_centers"]:
            continue
        # Source art, not the old model key, determines species. Tree-01 is
        # the same complete fir used by the new constructor; tree-02 is an oak
        # despite its legacy `pine_tree` key and stays a separate control.
        cohort = "existing_oak_tree02_keyed_pine_tree" if frame == 2 else "existing_fir_tree01_keyed_oak_tree"
        foot = list(map(float, item["global_foot_xy"]))
        radius = float(slices[str(frame)]["radius_px"])
        source_hb = global_hb(int(item["screen"]), item["source_hardbox_xyxy"])
        out.append({"id": f"{item['screen']}:{item['list_index']}:0", "cohort": cohort,
                    "source_screen": int(item["screen"]), "editor_index": int(item["editor_index"]),
                    "source_frame": frame, "source_path": item["path"], "source_type": 1,
                    "part": 0, "global_foot_xy": foot,
                    "scene5x5_shown_centers": list(map(int, item["scene5x5_shown_centers"])),
                    "fullworld_shown": bool(item["fullworld_shown"]), "radius_px": radius,
                    "uniform_scale": 1.0, "source_hard": int(item["source_hard"]),
                    "source_hb_global_xyxy": source_hb, "source_hb_compare": margins(source_hb, foot, radius),
                    "before_reachable_disk_px": 0, "after_reachable_disk_px": 0,
                    "after_reachable_outside_source_hb_grow4_px": 0})
    return out


def run(completed_path: Path, existing_path: Path, fit_path: Path, world_path: Path,
        masks_path: Path, output_path: Path, art_root: Path,
        baseline_existing_path: Path | None = None) -> dict:
    completed = json.loads(completed_path.read_text())
    existing = json.loads(existing_path.read_text())
    fit = json.loads(fit_path.read_text())
    world = json.loads(world_path.read_text())["screens"]
    assert completed["schema"] == "rc5-fir-source-support-1"
    assert existing["schema"] == "rc5-native-existing-standing-tree-inventory-1"
    assert existing["outdoor_scene_centers"] == len([v for v in world.values() if not v.get("indoor")]) == 570
    assert completed["counts"]["placements"] == 123
    assert sum(bool(p["scene5x5_shown_centers"]) for q in completed["placements"] for p in q["parts"]) == 165
    assert existing["counts"]["pine_tree:2"]["shown_union"] == 79
    assert existing["counts"]["oak_tree:1"]["shown_union"] == 199
    if baseline_existing_path is not None:
        assert existing_path.read_bytes() == baseline_existing_path.read_bytes(), "RC4/current native existing-tree ownership differs"
    template = fit["template"]
    slices = {"completed": art_slice(template["path"], *template["source_foot_px"], art_root)}
    for frame in (1, 2):
        witness = next(p for p in existing["placements"] if p["frame"] == frame)
        slices[str(frame)] = art_slice(witness["path"], *witness["foot_art_px"], art_root)
    assert slices["completed"]["radius_px"] == slices["1"]["radius_px"] == 43.0
    assert slices["2"]["radius_px"] == 17.0
    owners = cohort_items(completed, existing, slices)
    by_center: dict[int, list[dict]] = defaultdict(list)
    for owner in owners:
        for center in owner["scene5x5_shown_centers"]:
            by_center[center].append(owner)
    per_screen = {}
    totals: Counter = Counter()
    with np.load(masks_path, allow_pickle=False) as masks:
        before = masks["before_reachable"]
        after = masks["after_reachable"]
        before_hard = masks["before_hard"]
        after_hard = masks["after_hard"]
        assert before.shape == after.shape == before_hard.shape == after_hard.shape == (9600, 19200)
        for sn, screen in world.items():
            if screen.get("indoor"):
                continue
            n = int(sn)
            row, col = divmod(n - 1, 32)
            oy, ox = row * 400, col * 600
            global_x0, global_y0 = col * 600 - 20, row * 400
            rb = before[oy:oy + 400, ox:ox + 600]
            ra = after[oy:oy + 400, ox:ox + 600]
            maps = {name: np.zeros((400, 600), dtype=bool) for name in
                    ("completed", "existing_oak_tree02_keyed_pine_tree", "existing_fir_tree01_keyed_oak_tree")}
            visible_count = Counter()
            for owner in by_center.get(n, []):
                cohort = owner["cohort"]
                visible_count[cohort] += 1
                foot = owner["global_foot_xy"]
                patch = circle_patch((foot[0] - global_x0, foot[1] - global_y0), owner["radius_px"])
                if patch is None:
                    continue
                x0, x1, y0, y1, inside = patch
                sl = np.s_[y0:y1, x0 - 20:x1 - 20]
                maps[cohort][sl] |= inside
                old = inside & rb[sl]
                new = inside & ra[sl]
                owner["before_reachable_disk_px"] += int(old.sum())
                owner["after_reachable_disk_px"] += int(new.sum())
                xx = np.arange(x0, x1)[None, :] + global_x0
                yy = np.arange(y0, y1)[:, None] + global_y0
                h = owner["source_hb_global_xyxy"]
                source_grown = (xx >= h[0] - 4) & (xx < h[2] + 4) & (yy >= h[1] - 4) & (yy < h[3] + 4)
                owner["after_reachable_outside_source_hb_grow4_px"] += int((new & ~source_grown).sum())
                if cohort == "completed":
                    h = owner["template_hb_global_xyxy"]
                    template_grown = (xx >= h[0] - 4) & (xx < h[2] + 4) & (yy >= h[1] - 4) & (yy < h[3] + 4)
                    owner["after_reachable_outside_template_hb_grow4_px"] += int((new & ~template_grown).sum())
            oak_control = maps["existing_oak_tree02_keyed_pine_tree"]
            tree01 = maps["existing_fir_tree01_keyed_oak_tree"]
            completed_map = maps["completed"]
            old_firs = tree01
            union = old_firs | completed_map
            overlap = old_firs & completed_map
            stats = {"before_reachable_px": int(rb.sum()), "after_reachable_px": int(ra.sum()),
                     "shown_instances": dict(visible_count)}
            for label, area in (("completed", completed_map), ("existing_oak_tree02_keyed_pine_tree", oak_control),
                                ("existing_fir_tree01_keyed_oak_tree", tree01), ("existing_firs_union", old_firs),
                                ("completed_existing_overlap", overlap), ("all_firs_union", union)):
                stats[f"{label}_before_eye_px"] = int((area & rb).sum())
                stats[f"{label}_after_eye_px"] = int((area & ra).sum())
            stats["completed_inside_after_hard_px"] = int((completed_map & after_hard[oy:oy + 400, ox:ox + 600]).sum())
            for key, value in stats.items():
                if key != "shown_instances":
                    totals[key] += value
            per_screen[sn] = stats
    counts = Counter(o["cohort"] for o in owners)
    assert counts == {"completed": 165, "existing_oak_tree02_keyed_pine_tree": 79,
                      "existing_fir_tree01_keyed_oak_tree": 199}, counts
    # The old screenshot's (260,500) coordinate belongs to the screen below,
    # not to current screen 251's logical 0..399 movement mask.
    eye251 = {"current_scene_screen": 251, "old_scene_source_xy": [260, 500],
              "natural_destination_screen": 283, "natural_local_xy": [260, 100],
              "source_owner_id": "283:4:1"}
    owner = next(o for o in owners if o["cohort"] == "completed" and o["source_screen"] == 283
                 and o["editor_index"] == 5 and o["part"] == 1)
    eye251["source_owner_id"] = owner["id"]
    dx = 260.0 - (owner["global_foot_xy"][0] - (((283 - 1) % 32) * 600 - 20))
    dy = 100.0 - (owner["global_foot_xy"][1] - (((283 - 1) // 32) * 400))
    eye251["owner_foot_local_283_xy"] = [260.0 - dx, 100.0 - dy]
    eye251["distance_to_foot_px"] = float(np.hypot(dx, dy))
    eye251["inside_2d_radius_proxy"] = eye251["distance_to_foot_px"] <= owner["radius_px"]
    n = 283
    iy = ((n - 1) // 32) * 400 + 100
    ix = ((n - 1) % 32) * 600 + 260 - 20
    with np.load(masks_path, allow_pickle=False) as masks:
        eye251["natural_cell_before_hard"] = bool(masks["before_hard"][iy, ix])
        eye251["natural_cell_after_hard"] = bool(masks["after_hard"][iy, ix])
        eye251["natural_cell_before_reachable"] = bool(masks["before_reachable"][iy, ix])
        eye251["natural_cell_after_reachable"] = bool(masks["after_reachable"][iy, ix])
    report = {"schema": "rc5-fir-eye-census-1", "metric": "yaw-independent source-pixel disk around measured nonblack art foot; radius is maximum absolute horizontal nonblack pixel-center extent at 66px eye-height row", "limits": [
        "Each fir is a fixed-Y camera-facing billboard, not a round 3D crown. These disks conservatively mark possible close-canopy views; they cannot certify alpha visibility, occlusion, clipping or player experience.",
        "Only source static vision-0 objects and native 5x5 seam-visible parts are inventoried; script/story changes, editor save state and other vision layers are outside this census.",
        "Masks are exact final integer-pixel static-warp reachability, not fractional player movement or a rendered scene. The old screen-251 y500 camera is outside its logical screen; its natural screen-283 cell is reported separately.",
        "Original source hardboxes are geometric comparisons. A source hard=1 or footprint-replaced box is not automatically an active movement obstacle; the after reachability mask is authoritative for static collision.",
        "Legacy model_key labels misidentify species: source tree-01 is a conical fir keyed oak_tree; source tree-02 is a broadleaf oak keyed pine_tree. The latter is a separate control, not counted in the fir union. Other tree frames 3-7 are inventoried but excluded."
    ], "eye_height_m": 1.65, "source_px_per_m": 40, "art_slices": slices,
              "inventory": {"outdoor_screens": 570, "existing_native_counts": existing["counts"],
                            "completed_native_counts": completed["counts"], "selected_shown_owners": dict(counts)},
              "totals": dict(totals), "per_screen": per_screen, "owners": owners,
              "screen251_old_eye": eye251,
              "input_sha256": {str(p): digest(p) for p in
                               (masks_path, completed_path, existing_path, fit_path, world_path,
                                art_root / "tree-01.png", art_root / "tree-02.png")
                               + ((baseline_existing_path,) if baseline_existing_path is not None else ())}}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--completed", type=Path, required=True, help="completed fir native-support inventory")
    parser.add_argument("--existing", type=Path, required=True, help="existing-tree native inventory")
    parser.add_argument("--fit", type=Path, required=True, help="rc5_firs.json")
    parser.add_argument("--world", type=Path, required=True, help="world.json")
    parser.add_argument("--masks", type=Path, required=True, help="before/after reachability masks NPZ")
    parser.add_argument("--art-root", type=Path, required=True, help="directory containing tree-01.png and tree-02.png")
    parser.add_argument("--out", type=Path, required=True, help="output census JSON")
    parser.add_argument("--baseline-existing", type=Path, help="optional RC4 inventory whose bytes must match existing")
    args = parser.parse_args()
    result = run(args.completed, args.existing, args.fit, args.world, args.masks, args.out, args.art_root, args.baseline_existing)
    print("FIR EYE CENSUS", result["inventory"]["selected_shown_owners"], result["totals"])
