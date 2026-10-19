#!/usr/bin/env python3
"""Probe the cave rock in an actual Linux export using an earned campaign save.

Run under the shared Godot lock and a timeout; see docs/playtest/route-0.3.2.md.
The save is copied without editing. Continue, D/A movement and F9 are OS input.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rock(snapshot: dict) -> dict:
    matches = [e for e in snapshot["entities"].values() if e.get("script") == "s1-roc"]
    assert len(matches) == 1, "expected one live cave rock"
    return {key: matches[0][key] for key in ("x", "y", "active", "script")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--export", dest="exported", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--expect-push", action="store_true", help="Verify fixed PUSH, script completion and newly open passage")
    args = parser.parse_args()
    report = args.source_report.resolve()
    source = json.loads(report.read_text())
    setup = source.get("startup", {}).get("setup", {})
    assert setup.get("mode") == "campaign" and setup.get("test_mode") is False and setup.get("load_map_scripts") is True
    expected = source["checkpoints"]["wizard-rock-before-push-earned-save"]
    session = Path(source["session_dir"]).resolve()
    assert session.parent == report.with_suffix(".session"), "save is outside its recorded isolated session"
    saved = session / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    assert digest(saved) == source["final_save_sha256"], "earned save changed after the route report"
    data = json.loads(saved.read_text())
    assert data["screen"] == expected["screen"] == 277
    for key in ("strength", "wizard_see", "rock_placement"):
        assert data["vm"]["globals"][key] == expected["globals"][key]
    assert data["vm"]["globals"]["strength"] >= 4 and data["vm"]["globals"]["rock_placement"] == 0
    # This earned camera faces north. D therefore moves/faces east without
    # synthetic camera edits or calibration of exported mouse capture.
    assert abs(math.remainder(data["fps_camera"]["yaw"], 2 * math.pi)) < 0.01
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sequence = [
        {"name": "title", "expect": "Begin adventure", "wait": 1},
        {"name": "loaded", "keys": ["Return"], "wait": 1},
        {"name": "before", "keys": ["F9"], "wait": 6},
        {"name": "blocked", "hold": {"key": "d", "seconds": 4}, "keys": ["F9"], "wait": 6},
        {"name": "escaped", "hold": {"key": "a", "seconds": 0.3}, "keys": ["F9"], "wait": 0.5},
    ]
    if args.expect_push:
        sequence = sequence[:3] + [
            # Release during the script's own movement, then let move_stop
            # complete before recording. Held movement never carries Dink
            # into the newly exposed cave-hole cutscene during this proof.
            {"name": "pushing", "hold": {"key": "d", "seconds": 1.2}, "wait": 4},
            {"name": "pushed", "keys": ["F9"], "wait": 6},
            {"name": "passage", "hold": {"key": "d", "seconds": 0.1}, "keys": ["F9"], "wait": 1},
        ]
    sequence_path = out / "sequence.json"
    sequence_path.write_text(json.dumps(sequence) + "\n")
    subprocess.run([sys.executable, str(ROOT / "tools/ui_capture.py"), str(args.exported.resolve()),
                    str(out / "capture"), "--size", "960x540", "--sequence", str(sequence_path),
                    "--save-source", str(saved)], check=True, timeout=240)
    records = sorted((out / "capture/profile/data/godot/app_userdata/Dink Smallwood 3D/bug_reports").glob("*.json"))
    assert len(records) == 3, "expected before, blocked and escaped F9 records"
    snapshots = [json.loads(path.read_text()) for path in records]
    assert all(d["build"]["version"] == "0.3.2" and d["snapshot"]["screen"] == 277 for d in snapshots)
    before, blocked, escaped = [d["snapshot"] for d in snapshots]
    assert all(abs(before["player"][key] - expected[key]) < 0.001 for key in ("x", "y"))
    assert blocked["player"]["dir"] == 6, "D did not produce the original east-facing direction6"
    if args.expect_push:
        assert before["globals"]["rock_placement"] == 0 and rock(before)["x"] == 285
        assert all(d["globals"]["rock_placement"] == 1 and d["globals"]["strength"] >= 4 for d in (blocked, escaped))
        assert abs(rock(blocked)["x"] - 350) < 1 and rock(blocked) == rock(escaped)
        assert 230 <= blocked["player"]["x"] < 231 and escaped["player"]["x"] > 231
        # F9's compact player block has coordinates/direction only; control
        # state belongs to the full entity. Never pass on missing telemetry.
        assert blocked["entities"]["1"]["frozen"] is False
        assert not blocked["entities"]["1"].get("nocontrol", 0)
    else:
        assert 230 <= blocked["player"]["x"] < 231 and escaped["player"]["x"] < blocked["player"]["x"] - 10
        assert all(d["globals"]["rock_placement"] == 0 and d["globals"]["strength"] >= 4 for d in (before, blocked, escaped))
        assert rock(before) == rock(blocked) == rock(escaped) and rock(blocked)["x"] == 285
    result = {
        "setup": ("Normal Continue of an unmodified earned map277 pre-push save; no scenario/progression injection. OS D1.2s pushes east, release allows original script completion, D0.1s passes the old collision boundary; F9 records actual executable state."
                  if args.expect_push else "Normal Continue of an unmodified earned map277 pre-push save; no scenario/progression injection. OS D4s moves and faces east, A0.3s escapes; F9 records actual executable state."),
        "source_report_sha256": digest(report), "earned_save_sha256": digest(saved),
        "export_sha256": digest(args.exported),
        "records": [str(path) for path in records],
        "states": [{"player": d["player"], "camera": d["camera"], "rock": rock(d),
                    "globals": {k: d["globals"][k] for k in ("strength", "wizard_see", "rock_placement")}}
                   for d in (before, blocked, escaped)],
        "reproduced_missing_push": not args.expect_push,
        "verified_push": args.expect_push,
    }
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
