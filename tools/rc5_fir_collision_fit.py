#!/usr/bin/env python3
"""Compile native unsupported whole-fir roots into original hardbox collision.

First run rc5_fir_collision_inventory.gd headlessly to refresh
tmp/fir-collision/native.json. This compiler never infers scene visibility or
support from images; it consumes the native baseline and rechecks its counts.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "tmp/fir-collision/native.json"
OUTPUT = ROOT / "game/prototype/rc5_fir_collision.json"
FIT = ROOT / "game/prototype/rc5_firs.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_id(p: dict) -> str:
    return f"{p['source_screen']}:{p['source_list_index']}:{p['part']}"


def source_provenance(p: dict) -> dict:
    keys = ("source_screen", "source_list_index", "source_editor_index", "source_type",
            "source_frame", "source_path", "part", "rows", "source_window_x_px", "source_apex_px")
    return {key: p[key] for key in keys if key in p}


def touched_screens(rect: list[float], world: dict) -> list[int]:
    """Every outdoor playfield with a nonempty intersection with rect+4px."""
    x0, y0, x1, y1 = rect
    out = []
    for row in range(max(0, int((y0 - 4) // 400)), int((y1 + 4) // 400) + 1):
        for col in range(max(0, int((x0 - 4) // 600)), min(31, int((x1 + 4) // 600)) + 1):
            n = row * 32 + col + 1
            if str(n) not in world or world[str(n)].get("indoor"):
                continue
            sx0, sy0 = col * 600, row * 400
            if x0 - 4 < sx0 + 600 and x1 + 4 > sx0 and y0 - 4 < sy0 + 400 and y1 + 4 > sy0:
                out.append(n)
    return out


def compile_fit(inventory: dict, fit: dict, world: dict, sequences: dict, inventory_path: Path = INVENTORY) -> dict:
    counts = inventory["counts"]
    assert inventory["schema"] == "rc5-fir-collision-native-inventory-1"
    parts = inventory["parts"]
    assert len(parts) == counts["source_parts"]
    source_entities = {(p["source_screen"], p["source_list_index"]) for p in parts}
    assert len(source_entities) == counts["placements"]
    assert {p["source_frame"] for p in parts} == {8, 9, 10}
    shown = [p for p in parts if p["full_world_shown"] or p["scene5x5_shown_centers"]]
    assert len(shown) == counts["shown_union"]
    assert sum(not p["normalized_foot"]["valid_outdoor_neighbor"] for p in shown) == counts["invalid_unsupported"]
    assert sum(p["normalized_foot"]["valid_outdoor_neighbor"] and not p["baseline_blocked"]
               for p in shown) == counts["valid_unsupported"]
    assert fit["schema"] == "rc5-whole-fir-fit-1"
    template = fit["template"]
    assert (template["seq"], template["frame"]) == (32, 1)
    frame = sequences["32"]["frames"][0]
    assert frame["path"] == template["path"]
    assert frame["hardbox"] == [-48, -13, 46, 23]
    fx, fy = template["source_foot_px"]
    dx, dy = frame["dx"], frame["dy"]
    hb = frame["hardbox"]
    rel = [float(hb[0] + dx - fx), float(hb[1] + dy - fy),
           float(hb[2] + dx - fx), float(hb[3] + dy - fy)]
    assert rel == [-50.5, -31.0, 43.5, 5.0]

    records = []
    skipped = []
    for part in parts:
        if not part["full_world_shown"] and not part["scene5x5_shown_centers"]:
            continue
        source_path = part["source_path"]
        source_part = fit["source_parts"][source_path][part["part"]]
        assert part["rows"] == source_part["rows"]
        assert part["source_foot_in_full_art_px"] == source_part["source_foot_in_full_art_px"]
        assert abs(part["uniform_scale"] - source_part["uniform_scale"]) < 1e-10
        if "source_window_x_px" in source_part:
            assert part["source_window_x_px"] == source_part["source_window_x_px"]
            assert part["source_apex_px"] == source_part["source_apex_px"]
        if not part["normalized_foot"]["valid_outdoor_neighbor"]:
            skipped.append({"source": source_provenance(part),
                "global_foot_xy": part["global_foot_xy"],
                "normalized_foot": part["normalized_foot"],
                "reason": "destination screen absent or indoor"})
            continue
        if part["baseline_blocked"]:
            continue
        scale = float(part["uniform_scale"])
        root_x, root_y = map(float, part["global_foot_xy"])
        rect = [root_x + scale * rel[0], root_y + scale * rel[1],
                root_x + scale * rel[2], root_y + scale * rel[3]]
        assert rect[0] < root_x < rect[2] and rect[1] < root_y < rect[3]
        records.append({
            "id": source_id(part),
            "source": source_provenance(part),
            "source_foot_in_full_art_px": part["source_foot_in_full_art_px"],
            "global_foot_xy": part["global_foot_xy"],
            "destination_screen": part["normalized_foot"]["screen"],
            "destination_local_foot_xy": part["normalized_foot"]["local_xy"],
            "uniform_scale": scale,
            "rect_global_xyxy": rect,
            "full_world_shown": bool(part["full_world_shown"]),
            "scene5x5_shown_centers": part["scene5x5_shown_centers"],
            "baseline_blocked": False,
        })
    assert len(records) == counts["valid_unsupported"], len(records)
    assert len(skipped) == counts["invalid_unsupported"], len(skipped)

    # Keep each source record, even when rectangles overlap. The runtime OR is
    # the union; retaining every record preserves why each body was authorized.
    by_screen: dict[str, list[dict]] = {}
    touched = Counter()
    for record in records:
        rect = record["rect_global_xyxy"]
        for screen in touched_screens(rect, world):
            col, row = (screen - 1) % 32, (screen - 1) // 32
            ox, oy = col * 600 - 20, row * 400
            by_screen.setdefault(str(screen), []).append({
                "id": record["id"],
                "rect_local_xyxy": [rect[0] - ox, rect[1] - oy, rect[2] - ox, rect[3] - oy],
            })
            touched[record["id"]] += 1
    assert all(touched[r["id"]] >= 1 for r in records)
    source_files = {
        "world.json": ROOT / "game/data/world.json",
        "sequences.json": ROOT / "game/data/sequences.json",
        "footprints.json": ROOT / "game/data/footprints.json",
        "rc5_firs.json": FIT,
        "native_inventory.json": inventory_path,
        template["path"]: ROOT / "game" / template["path"],
    }
    for source_path in fit["source_parts"]:
        source_files[source_path] = ROOT / "game" / source_path
    return {
        "schema": "rc5-fir-collision-fit-1",
        "selection": "shown in full world or a real 5x5 scene block; valid outdoor foot; native RC4 baseline _blocked false",
        "movement": "original Rect2 grow(4) band; moving within band allowed away/parallel unless entering body",
        "template": {"path": template["path"], "seq": 32, "frame": 1,
                     "source_foot_px": template["source_foot_px"],
                     "hardbox_from_original_frame_px": hb,
                     "hardbox_relative_to_measured_foot_xyxy": rel,
                     "crown_height_px": template["crown_height_px"]},
        "counts": {"source_placements": counts["placements"], "source_parts": counts["source_parts"],
                   "shown_union": counts["shown_union"], "authorized_roots": len(records),
                   "skipped_invalid": len(skipped), "screen_entries": sum(map(len, by_screen.values())),
                   "screens_touched": len(by_screen),
                   "multi_screen_roots": sum(v > 1 for v in touched.values())},
        "rectangles": records,
        "by_screen": by_screen,
        "skipped_invalid": skipped,
        "source_sha256": {name: sha(path) for name, path in source_files.items()},
    }


def main() -> None:
    inventory = json.loads(INVENTORY.read_text())
    fit = json.loads(FIT.read_text())
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    compiled = compile_fit(inventory, fit, world, sequences)
    OUTPUT.write_text(json.dumps(compiled, indent=2) + "\n")
    print(f"Wrote {OUTPUT}: {compiled['counts']}")


if __name__ == "__main__":
    main()
