#!/usr/bin/env python3
"""Continue the P1 earned pre-push save toward Bonca/Terris with real input.

Run under the shared Godot lock, Xvfb, a timeout and silent software rendering.
Set DINK_CAMPAIGN_PACK to the one current Linux export for packed resources.
The actual exported executable is checked separately by repro_cave_rock.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.playtest import PlaytestSession, find_godot
from tools.playtest_campaign import RouteFailure, saved_state_matches
from tools.playtest_cave_route import CaveRoute


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = args.source_report.resolve()
    source = json.loads(report.read_text())
    setup = source["startup"]["setup"]
    if not (setup.get("mode") == "campaign" and setup.get("test_mode") is False
            and setup.get("load_map_scripts") is True):
        raise ValueError("source is not an earned campaign session")
    expected = source["checkpoints"]["wizard-rock-before-push-earned-save"]
    if not (expected["screen"] == 277 and expected["globals"]["strength"] >= 4
            and expected["globals"]["wizard_see"] == 2 and expected["globals"]["rock_placement"] == 0):
        raise ValueError("source is not the earned pre-push checkpoint")
    session_path = Path(source["session_dir"]).resolve()
    if session_path.parent != report.with_suffix(".session"):
        raise ValueError("source save lies outside its recorded isolated session")
    saved = session_path / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if digest(saved) != source["final_save_sha256"]:
        raise ValueError("earned save changed after source report")
    engine = find_godot()
    os.environ.update(DINK_CAMPAIGN_GODOT=engine, DINK_CAMPAIGN_ENGINE="1",
                      GODOT=str(ROOT / "tools/run_campaign_route.sh"))
    pack = Path(os.environ["DINK_CAMPAIGN_PACK"]).resolve() if os.environ.get("DINK_CAMPAIGN_PACK") else None
    result = {"ok": False, "source_report_sha256": digest(report), "source_save_sha256": digest(saved),
              "pack_sha256": digest(pack) if pack else None,
              "setup": "Normal Continue of unmodified earned P1 pre-push save; no progression or entity injection. Same campaign controller and cave, combat, reward and Terris route."}
    with PlaytestSession(args.report.with_suffix(".session"), rendered=True, mode="campaign",
                         save_source=saved, timeout=60) as session:
        campaign = CaveRoute(session, rendered=True, max_commands=18000)
        try:
            campaign.checkpoint("title")
            campaign.menu_button("Continue adventure")
            loaded = campaign._call("resume-earned-rock", lambda: session.wait(3))
            if not saved_state_matches(expected, loaded):
                raise RouteFailure("Continue did not restore the earned pre-push save", "harness")
            campaign.checkpoint("resume-earned-rock", loaded)
            campaign.cave_from_rock()
            campaign.wizard_reward()
            campaign.finish_terris()
            campaign.earned_save("terris-complete")
            result.update(ok=True, verdict="pass")
        except RouteFailure as failure:
            session.screenshot("failure.png")
            result.update(error=str(failure), failure_class=failure.kind,
                          verdict="game suspected" if failure.kind == "game suspected" else "inconclusive")
        except (RuntimeError, TimeoutError, OSError, ValueError, KeyError) as failure:
            result.update(error=str(failure), failure_class="harness", verdict="inconclusive")
        result.update(startup=session.startup, session_dir=str(session.session_dir),
                      commands=campaign.commands, checkpoints=campaign.checkpoints, trace=campaign.trace)
    final_save = session.session_dir / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if final_save.is_file():
        result["final_save_sha256"] = digest(final_save)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: result.get(k) for k in ("ok", "verdict", "failure_class", "error", "commands")}, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
