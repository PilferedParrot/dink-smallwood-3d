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


def continuation_checkpoint(source: dict, phase: str) -> dict:
    name = {"all": "wizard-rock-before-push-earned-save", "bonca": "wizard-rock-before-push-earned-save",
            "reward": "bonca-complete-earned-save", "terris": "wizard-reward-earned-save"}[phase]
    expected = source["checkpoints"][name]
    globals_ = expected["globals"]
    if phase in {"all", "bonca"}:
        valid = (expected["screen"] == 277 and globals_["strength"] >= 4
                 and globals_["wizard_see"] == 2 and globals_["rock_placement"] == 0)
    elif phase == "reward":
        valid = expected["screen"] == 100 and globals_["wizard_see"] == 3 and globals_["rock_placement"] == 1
    else:
        valid = (expected["screen"] == 6 and globals_["wizard_see"] == 4
                 and any(item.get("script") == "item-fb" for item in expected["magic_inventory"]))
    if not valid:
        raise ValueError("source lacks the earned checkpoint for " + phase)
    return expected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--phase", choices=("all", "bonca", "reward", "terris"), default="all",
                        help="Finish one normal-save leg, then release the Godot lock before the next Continue")
    args = parser.parse_args()
    report = args.source_report.resolve()
    source = json.loads(report.read_text())
    setup = source["startup"]["setup"]
    if not (setup.get("mode") == "campaign" and setup.get("test_mode") is False
            and setup.get("load_map_scripts") is True):
        raise ValueError("source is not an earned campaign session")
    expected = continuation_checkpoint(source, args.phase)
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
    result = {"ok": False, "phase": args.phase, "source_report_sha256": digest(report), "source_save_sha256": digest(saved),
              "initial_earned_save_sha256": source.get("initial_earned_save_sha256", digest(saved)),
              "pack_sha256": digest(pack) if pack else None,
              "setup": "Normal Continue of an unmodified earned campaign checkpoint; no progression or entity injection. Each leg ends with a normal in-game save; reports bind the source report and save hashes back to P1's earned pre-push checkpoint."}
    with PlaytestSession(args.report.with_suffix(".session"), rendered=True, mode="campaign",
                         save_source=saved, timeout=60) as session:
        campaign = CaveRoute(session, rendered=True, max_commands=18000)
        try:
            campaign.checkpoint("title")
            campaign.menu_button("Continue adventure")
            loaded = campaign._call("resume-earned-" + args.phase, lambda: session.wait(3))
            if not saved_state_matches(expected, loaded):
                raise RouteFailure("Continue did not restore the earned " + args.phase + " checkpoint", "harness")
            campaign.checkpoint("resume-earned-" + args.phase, loaded)
            if args.phase in {"all", "bonca"}:
                campaign.cave_from_rock()
                if args.phase == "bonca": campaign.earned_save("bonca-complete")
            if args.phase in {"all", "reward"}:
                campaign.wizard_reward()
            if args.phase in {"all", "terris"}:
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
