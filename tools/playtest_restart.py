"""Cold Continue and bounded death/restart checks for the local playtest host."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from tools.playtest import PlaytestSession
except ModuleNotFoundError:  # direct ``python tools/playtest_restart.py``
    from playtest import PlaytestSession

ROOT = Path(__file__).resolve().parents[1]


def _source_metadata(save_source: Path, campaign_report: Path | None) -> dict[str, Any]:
    source = json.loads(save_source.read_text(encoding="utf-8"))
    metadata: dict[str, Any] = {"screen": int(source["screen"]),
        "position": [float(source["entities"]["1"]["x"]), float(source["entities"]["1"]["y"])],
        "camera": source.get("fps_camera", {}), "inventory": source["items"],
        "globals": {key: source["vm"]["globals"].get(key) for key in
                     ["story", "pig_story", "old_womans_duck", "nuttree", "wizard_again", "letter", "s2-map", "life", "lifemax", "level", "strength", "defense", "gold", "exp"]}}
    if campaign_report is not None:
        report = json.loads(campaign_report.read_text(encoding="utf-8"))
        metadata["render_geometry"] = report.get("checkpoints", {}).get("save-reload", {}).get("render_geometry", {})
    return metadata


def continue_from_save(save_source: Path, session_dir: Path | None = None, *, rendered: bool = False,
                       campaign_report: Path | None = None) -> dict[str, Any]:
    """Start a fresh process and activate Continue using the title-menu input."""
    expected = _source_metadata(save_source, campaign_report)
    with PlaytestSession(session_dir=session_dir, rendered=rendered, mode="campaign",
                         save_source=save_source, timeout=20) as session:
        title = session.observe()["telemetry"]
        continued = session.menu_key("enter")["telemetry"]
        # Allow the normal 0.15-second HUD refresh and renderer to settle, so
        # cold-start captures include equipment and health as well as geometry.
        continued = session.wait(12)["telemetry"]
        player = next(entity for entity in continued["entities"] if entity["id"] == 1)
        # Top-level x/y pass through Godot's float32 Vector2 collision view.
        # Compare the original entity scalars to the save, retaining exact
        # double-precision scripted movement coordinates without a loose epsilon.
        actual = {"screen": continued["screen"], "position": [player["x"], player["y"]],
                  "collision_position": [continued["x"], continued["y"]],
                  "camera": {"yaw": continued["yaw"], "pitch": continued["pitch"]},
                  "inventory": continued["inventory"],
                  "globals": {key: continued["globals"].get(key) for key in expected["globals"]},
                  "render_geometry": continued.get("render_geometry", {})}
        state_match = (actual["screen"] == expected["screen"] and
                       actual["position"] == expected["position"] and
                       actual["camera"] == expected["camera"] and
                       actual["inventory"] == expected["inventory"] and
                       actual["globals"] == expected["globals"] and
                       (not expected.get("render_geometry") or actual["render_geometry"] == expected["render_geometry"]))
        result = {
            "kind": "cold_continue",
            "save_source": str(save_source),
            "title": title,
            "continued": continued,
            "source": expected, "actual": actual, "state_match": state_match,
            "ok": bool(title["ui"]["title"] and title["save"]["adventure"] and
                       any(button["text"] == "Continue adventure" and button["focused"]
                           for button in title["ui"]["buttons"]) and
                       continued["playing"] and continued["inventory"] and state_match),
            "session_dir": str(session.session_dir),
        }
        result["screenshot"] = session.screenshot("cold-continue.png") if rendered else {
            "ok": False, "error": "headless session; rendered capture omitted"
        }
        return result


def death_restart(session_dir: Path | None = None, *, rendered: bool = False) -> dict[str, Any]:
    """Exercise the defeat page and Begin again through actual menu input.

    The hostile actor and one-health state are an explicit scenario fixture;
    they are not evidence of a naturally reached campaign death.
    """
    with PlaytestSession(session_dir=session_dir, rendered=rendered, mode="scenario",
                         screen=407, x=320, y=390, death_fixture=True, timeout=20) as session:
        before = session.observe()["telemetry"]
        session.hold("forward", 1)
        defeated = session.observe()["telemetry"]
        defeat_screenshot = session.screenshot("defeat.png") if rendered else {
            "ok": False, "error": "headless session; rendered capture omitted"
        }
        # Defeat presents Load first and Begin again second.
        buttons = defeated["ui"]["buttons"]
        load_focused = any(button["text"] == "Load saved adventure" and button["focused"] for button in buttons)
        selected = session.menu_key("down")["telemetry"]
        for _ in range(2):
            if any(button["text"] == "Begin again" and button["focused"] for button in selected["ui"]["buttons"]):
                break
            selected = session.menu_key("down")["telemetry"]
        begin_focused = load_focused and any(button["text"] == "Begin again" and button["focused"]
                                             for button in selected["ui"]["buttons"])
        restarted = session.menu_key("enter")["telemetry"]
        for _ in range(20):
            if restarted["dialogue"]:
                session.menu_key("enter")
            restarted = session.wait(120)["telemetry"]
            if (not restarted["dialogue"] and restarted["globals"].get("story") == 1 and
                    len(restarted["recent_dialogue"]) >= 3):
                break
        before_move = (restarted["x"], restarted["y"])
        moved = session.hold("left", 10)["telemetry"]
        result = {
            "kind": "death_restart",
            "setup": session.startup.get("setup", {}),
            "before": before,
            "defeated": defeated,
            "restarted": restarted,
            "after_move": moved,
            "ok": (before["globals"].get("life") == 1 and before["ui"]["page"] == "game" and
                   begin_focused and defeated["globals"].get("life") == 0 and
                   defeated["ui"]["page"] == "defeat" and defeated["ui"]["modal"] and
                   restarted["playing"] and restarted["screen"] == 1 and
                   not restarted["dialogue"] and not restarted["frozen"] and
                   not restarted["disabled"] and restarted["nocontrol"] == 0 and
                   restarted["globals"].get("story") == 1 and restarted["globals"].get("life") == 10 and
                   restarted["recent_dialogue"][-3:] == ["Dink, would you go feed the pigs?", "What, now?", "YES, NOW."] and
                   (moved["x"], moved["y"]) != before_move),
            "session_dir": str(session.session_dir),
            "limitations": ["synthetic one-health touch attacker; normal campaign death route not certified"],
        }
        result["defeat_screenshot"] = defeat_screenshot
        result["screenshot"] = session.screenshot("restart.png") if rendered else {
            "ok": False, "error": "headless session; rendered capture omitted"
        }
        return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--save", type=Path,
                        help="earned isolated adventure.json used for cold Continue")
    parser.add_argument("--campaign-report", type=Path,
                        help="campaign report used for expected structural geometry and session discovery")
    parser.add_argument("--report", type=Path, default=ROOT / "builds/playtests/restart/report.json")
    parser.add_argument("--rendered", action="store_true")
    args = parser.parse_args()
    if args.save is None and args.campaign_report is None:
        raise SystemExit("provide --save or --campaign-report")
    if args.save is None:
        campaign = json.loads(args.campaign_report.read_text(encoding="utf-8"))
        args.save = Path(campaign["session_dir"]) / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if not args.save.is_file():
        raise SystemExit(f"missing retained save: {args.save}")
    report = {"continue": continue_from_save(args.save, args.report.parent, rendered=args.rendered,
                                               campaign_report=args.campaign_report),
              "death_restart": death_restart(args.report.parent, rendered=args.rendered)}
    report["ok"] = report["continue"]["ok"] and report["death_restart"]["ok"]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "report": str(args.report)}, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
