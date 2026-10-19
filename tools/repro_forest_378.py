#!/usr/bin/env python3
"""Reproduce map378's forest-mask witness, optionally in a Linux export.

Run under the shared Godot flock, timeout and Xvfb (see route-0.3.2.md).
Setup is a labeled scenario: campaign progression/map startup are skipped.
All subsequent movement, saving and exported-game input use normal controls.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.playtest import PlaytestSession, find_godot
from tools.playtest_campaign import Campaign


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--export", dest="exported", type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    exported = args.exported.resolve() if args.exported else None
    if exported and not exported.is_file():
        parser.error("--export must be an existing Linux executable")
    out.mkdir(parents=True, exist_ok=True)
    os.chdir(ROOT)
    engine = find_godot()
    os.environ.update(DINK_CAMPAIGN_GODOT=engine, DINK_CAMPAIGN_ENGINE="1",
                      GODOT=str(ROOT / "tools/run_campaign_route.sh"),
                      LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe")
    with PlaytestSession(out / "native", rendered=True, mode="scenario",
                         screen=378, x=75, y=160, yaw=0, timeout=60) as session:
        campaign = Campaign(session)
        campaign.earned_save("scenario378")
        before = session.observe()["telemetry"]
        started = time.monotonic()
        grid = session.navigation_grid(step=1)["navigation_grid"]
        duration = time.monotonic() - started
        assert session.observe()["telemetry"] == before, "native probe advanced simulation"
        coarse = session.navigation_grid(step=5)["navigation_grid"]
        assert all(grid["rows"][y][x] == coarse["rows"][y // 5][x // 5]
                   for y in range(0, 401, 5) for x in range(0, 641, 5))
        session.screenshot("before.png")
        blocked = session.hold("forward", 12)["telemetry"]
        session.screenshot("blocked.png")
        escaped = session.hold("back", 12)["telemetry"]
        session.screenshot("escaped.png")
        session_dir = session.session_dir
    saved = session_dir / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    result = {
        "setup": "Scenario: skips campaign progression/map startup; starts378 at75,160 facing north. Save and movement use normal input.",
        "grid_seconds": duration, "session_dir": str(session_dir),
        "native_x75_y145_150": [grid["rows"][y][75] == "#" for y in range(145, 151)],
        "before": [before["x"], before["y"]],
        "after_forward12": [blocked["x"], blocked["y"]],
        "after_back12": [escaped["x"], escaped["y"]],
        "fixture_sha256": hashlib.sha256(saved.read_bytes()).hexdigest(),
    }
    assert result["native_x75_y145_150"] == [False, True, True, True, False, False]
    assert blocked["y"] >= 149 and escaped["y"] > blocked["y"] + 10
    (out / "native-grid.json").write_text(json.dumps(grid) + "\n")
    if exported:
        sequence = [
            {"name": "title", "expect": "Begin adventure", "wait": 1},
            # A saved profile puts Continue first and focuses it at startup.
            {"name": "loaded", "keys": ["Return"], "wait": 1},
            {"name": "blocked", "hold": {"key": "w", "seconds": 1}, "keys": ["F9"], "wait": 0.5},
            {"name": "escaped", "hold": {"key": "s", "seconds": 0.5}, "wait": 6},
            {"name": "escape-record", "keys": ["F9"], "wait": 0.5},
        ]
        sequence_path = out / "export-sequence.json"
        sequence_path.write_text(json.dumps(sequence) + "\n")
        subprocess.run([sys.executable, str(ROOT / "tools/ui_capture.py"), str(exported),
                        str(out / "export"), "--size", "960x540", "--sequence", str(sequence_path),
                        "--save-source", str(saved)], check=True, timeout=240)
        reports = sorted((out / "export/profile/data/godot/app_userdata/Dink Smallwood 3D/bug_reports").glob("*.json"))
        assert len(reports) == 2, "export did not produce both F9 state records"
        snapshots = [json.loads(path.read_text()) for path in reports]
        assert all(r["snapshot"]["screen"] == 378 and r["build"]["version"] == "0.3.2" for r in snapshots)
        first, last = [r["snapshot"]["player"] for r in snapshots]
        assert 149 <= first["y"] < 150 and abs(first["x"] - 75) < 0.01
        assert last["y"] > first["y"] + 10, "normal S input did not escape"
        result["export"] = {"sha256": hashlib.sha256(exported.read_bytes()).hexdigest(),
                            "blocked": first, "escaped": last,
                            "reports": [str(path) for path in reports]}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
