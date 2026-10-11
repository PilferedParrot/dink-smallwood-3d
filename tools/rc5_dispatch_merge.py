#!/usr/bin/env python3
"""Merge bounded native witnesses with exhaustive native negative proofs."""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def key(record: dict) -> tuple[int, int, str]:
    return int(record["screen"]), int(record["list_index"]), str(record["mode"])


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bounded",type=Path,required=True,help="bounded native witness census")
    parser.add_argument("--exhaustive",type=Path,required=True,help="exhaustive native negative census")
    parser.add_argument("--game-script",type=Path,required=True,help="fps_game.gd used by native probe")
    parser.add_argument("--candidates",type=Path,required=True,help="candidate index used by native probe")
    parser.add_argument("--out",type=Path,required=True,help="merged report output")
    args=parser.parse_args()
    bounded = json.loads(args.bounded.read_text())
    exhaustive = json.loads(args.exhaustive.read_text())
    assert bounded["schema"] == exhaustive["schema"] == "rc5-native-full-dispatch-census-1"
    assert bounded["counts"]["records"] == 579 and exhaustive["counts"]["records"] == 3
    index = {key(r): r for r in exhaustive["records"]}
    assert len(index) == 3
    combined = []
    for record in bounded["records"]:
        k = key(record)
        q = index.get(k, record)
        if k in index:
            assert not record["before"]["actual_dispatch_cells"] and not record["after"]["actual_dispatch_cells"]
        result = {field: q[field] for field in ("screen", "list_index", "editor_index", "script", "mode", "source_xy", "entity_id", "talk_procedure")}
        for when in ("before", "after"):
            cell = q[when]
            assert cell["visited_cells"] <= cell["eligible_cells"]
            status = "WITNESS" if cell["actual_dispatch_cells"] and cell["witness_xy"] else "EXHAUSTIVE_NO_DISPATCH"
            if status == "EXHAUSTIVE_NO_DISPATCH":
                assert cell["exhaustive_or_witness"] == "exhaustive" and cell["visited_cells"] == cell["eligible_cells"]
            result[when] = {"status": status, "eligible_cells": cell["eligible_cells"],
                            "visited_cells": cell["visited_cells"], "witness_xy": cell["witness_xy"],
                            "fail_first": cell["fail_first"] if status != "WITNESS" else {}}
        combined.append(result)
    assert len(combined) == 579 and len({key(r) for r in combined}) == 579
    statuses = Counter((r["before"]["status"], r["after"]["status"]) for r in combined)
    assert statuses == {("WITNESS", "WITNESS"): 576,
                        ("EXHAUSTIVE_NO_DISPATCH", "EXHAUSTIVE_NO_DISPATCH"): 3}
    modes = Counter((r["mode"], r["talk_procedure"]) for r in combined)
    assert modes == {("talk_nearest_any_facing_90px", True): 97,
                     ("hit_default_fist_48px", True): 56,
                     ("hit_default_fist_48px", False): 426}
    out = {"schema": "rc5-native-dispatch-availability-1",
           "setting": "current post-source-LoS fix; native FPS _talk/_fps_melee_target; isolated vision0 screens, scripts-off, static-warp-reachable integer cells, camera aimed at each source actor",
           "records": combined,
           "counts": {"records": 579, "actual_dispatch_witness_before_and_after": 576,
                      "exhaustive_no_dispatch_both": 3, "lost_all_from_before": 0,
                      "talk_with_procedure": 97, "hit_without_talk_procedure": 426,
                      "before_reachable_range_cells": int(bounded["source_candidate_counts"]["before_cells"]),
                      "after_reachable_range_cells": int(bounded["source_candidate_counts"]["after_cells"]),
                      "negative_cells_exhaustively_visited_before": exhaustive["counts"]["before_visited"],
                      "negative_cells_exhaustively_visited_after": exhaustive["counts"]["after_visited"]},
           "limits": [
               "Positive records have an exact native dispatch witness but their other eligible cells were not exhaustively probed; a benchmark of 4000 native cells took 10.668 s, making all 10.59 million cells roughly 7.8 CPU hours.",
               "Negative records were exhaustively probed at every exact static-warp-reachable integer cell inside authored talk or melee range.",
               "The camera is aimed at each actor. Actual gaze, campaign/screen startup scripts, dynamic motion, saved vision, and full input dispatch remain separate playtest concerns.",
               "Mode-specific hit checks call the actual FPS melee selector. Hit-only records without a TALK procedure are not reported as talk failures.",
           ],
           }
    out["sha256"] = {str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): sha(path)
                     for path in (args.bounded,args.exhaustive,args.game_script,args.candidates)}
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(out, indent=2) + "\n")
    print("NATIVE DISPATCH AVAILABILITY", out["counts"])


if __name__ == "__main__":
    main()
