#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Independent raw FreeDink boundary census; optionally compare a native report.

FreeDink109.6: EditorMap.cpp43-63, freedink.cpp132-242,
live_screen.cpp132-169,216-239, game_engine.cpp477-503,570-577.
This is the unlocked, vision0 editor layer without scripts/persistence. It does
not assert arbitrary DinkC state reachability. Raw hard warps can redirect
before edge checking (update_frame.cpp347-353); plain wall and runtime portal
controls distinguish that case. Native reports come from
 tests/fps_indoor_edges_test.gd, which separately retains FPS incoming collision.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from collision_map import tile_mask


def census(world: dict, sequences: dict) -> list[dict]:
    records, masks = [], {}
    screens = world["screens"]
    for key, screen in screens.items():
        source = int(key)
        for delta, direction in [(-1, "west"), (1, "east"), (-32, "north"), (32, "south")]:
            target = source + delta
            if str(target) not in screens:
                continue
            # FPS intentionally rejects horizontal grid-row wrapping. These
            # are listed separately, outside the115 geometric indoor pairs.
            if delta == -1 and (source - 1) % 32 == 0 or delta == 1 and (source - 1) % 32 == 31:
                continue
            a, b = screen["indoor"], screens[str(target)]["indoor"]
            if not a and not b:
                continue
            if source not in masks:
                raw, _ = tile_mask(world, source)
                for entity in screen["sprites"]:
                    if entity["vision"] != 0 or entity["hard"] != 0:
                        continue
                    frames = sequences.get(str(entity["seq"]), {}).get("frames", [])
                    if not 0 < entity["frame"] <= len(frames):
                        continue
                    left, top, right, bottom = frames[entity["frame"] - 1]["hardbox"]
                    x, y = entity["x"], entity["y"]
                    # FreeDink add_hardness uses unscaled frame boxes and
                    # half-open integer loops, including hard warp sprites.
                    x0, x1 = max(20, x + left), min(620, x + right)
                    y0, y1 = max(0, y + top), min(400, y + bottom)
                    if x0 < x1 and y0 < y1:
                        raw[y0:y1, x0:x1] = True
                masks[source] = raw
            raw = masks[source]
            values = {"west": raw[:, 20], "east": raw[:, 619],
                      "north": raw[0, 20:620], "south": raw[399, 20:620]}[direction]
            records.append(dict(source=source, target=target, direction=direction,
                                kind="indoor_indoor" if a and b else "mixed",
                                samples=len(values), original_open=int((~values).sum())))
    return records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    world = ROOT / "game/data/world.json"
    sequences = ROOT / "game/data/sequences.json"
    records = census(json.loads(world.read_text()), json.loads(sequences.read_text())["sequences"])
    result = {"setup": __doc__, "sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                            for p in (world, sequences)}, "edges": records}
    counts = {}
    for kind in ("indoor_indoor", "mixed"):
        group = [r for r in records if r["kind"] == kind]
        counts[kind] = dict(directed=len(group), original_open=sum(r["original_open"] > 0 for r in group),
                            fully_hard=sum(r["original_open"] == 0 for r in group))
    result["counts"] = counts
    screens = json.loads(world.read_text())["screens"]
    result["retained_row_wrap_exclusions"] = [
        dict(source=int(k), target=int(k)+delta, original_metadata_allowed=True,
             fps_metadata_allowed=False, reason="retained no-horizontal-row-wrap rule")
        for k, screen in screens.items() for delta in (-1, 1)
        if (delta == -1 and (int(k)-1) % 32 == 0 or delta == 1 and (int(k)-1) % 32 == 31)
        and str(int(k)+delta) in screens
        and (screen["indoor"] or screens[str(int(k)+delta)]["indoor"])]
    ok = counts["indoor_indoor"]["directed"] == 230
    if args.native:
        native = json.loads(args.native.read_text())
        by_pair = {(e["source"], e["target"]): e for e in native["edges"]}
        differences = []
        for record in records:
            pair = record["source"], record["target"]
            observed = by_pair.get(pair)
            if observed is None or any(observed[k] != record[k] for k in record):
                differences.append(dict(pair=pair, expected=record, observed=observed))
        extras = sorted(set(by_pair) - {(e["source"], e["target"]) for e in records})
        result["native_comparison"] = dict(differences=differences, extra_pairs=extras,
                                           report_sha256=hashlib.sha256(args.native.read_bytes()).hexdigest())
        ok = ok and not differences and not extras
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(ok=ok, counts=counts, native_mismatches=len(result.get("native_comparison", {}).get("differences", [])))))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
