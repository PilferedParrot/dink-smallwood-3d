#!/usr/bin/env python3
"""One real-input cave-route attempt with explicit source-component leg targets.

Loads an unmodified, earned wizard-training save through Continue adventure.
The leg data changes route knowledge only; Campaign's planner is unchanged.
Invoke under the shared Godot lock, timeout and Xvfb; see route-0.3.2.md.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import sys

import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.playtest import PlaytestSession, find_godot
from tools.playtest_campaign import Campaign, RouteFailure, saved_state_matches


class CaveRoute(Campaign):
    def configure_legs(self, specification: dict) -> None:
        census_path = ROOT / specification["census"]
        if hashlib.sha256(census_path.read_bytes()).hexdigest() != specification["census_sha256"]:
            raise ValueError("route leg census no longer matches its recorded hash")
        self.census = json.loads(gzip.decompress(census_path.read_bytes()))
        self.legs = specification["legs"]
        self.components = {}

    def component(self, state: dict) -> tuple[int, int]:
        screen = int(state["screen"])
        if screen not in self.components:
            hard = np.zeros((400, 600), dtype=bool)
            for y, a, b, _ in self.census["screens"][str(screen)][0]["classification_runs"]:
                hard[y, a - 20:b - 20] = True
            self.components[screen] = ndimage.label(~hard)[0]
        x, y = int(state["x"]), int(state["y"])
        tag = int(self.components[screen][y, x - 20]) if 20 <= x < 620 and 0 <= y < 400 else 0
        return screen, tag

    def travel_route(self, screens: list[int], label: str) -> dict:
        if label != "wizard-cave-road":
            return super().travel_route(screens, label)
        # Replay the already exercised road, then use the explicit component
        # sequence instead of greedily accepting the wrong entry into341.
        state = super().travel_route(screens[:screens.index(341) + 1], label + "-prefix")
        for index, leg in enumerate(self.legs):
            if self.component(state) != tuple(leg["source"]):
                raise RouteFailure("explicit route source component mismatch: %s, expected %s" %
                                   (self.component(state), leg["source"]), "harness")
            screen, _ = leg["source"]
            target, component = leg["target"]
            name = "component-leg-%d-%d" % (index, target)
            self.navigate(screen, tuple(leg["approach"]), name + "-approach")
            self._cross(target, name, tuple(leg["cross"]))
            self._call(name + "-arrival", lambda: self.session.wait(3))
            state = self.dialogue(require_release=True)
            if self.component(state) != (target, component):
                raise RouteFailure("explicit route entered component %s, expected %s" %
                                   (self.component(state), leg["target"]), "harness")
            self.checkpoint(name + "-verified", state)
        return state

    def finish_terris(self) -> dict:
        # The remaining route is the same input sequence as run_terris(),
        # starting after the cave proof and wizard reward have been earned.
        self._warp(6, 251, (467, 387), "terris-wizard-leave")
        self.travel_route([283, 315, 314, 346, 378, 377, 376, 375, 407, 406, 405, 404], "terris-bridge-road")
        gold = int(self.observe("toll-before")["globals"]["gold"])
        if gold < 100:
            raise RouteFailure("earned wizard reward cannot cover bridge toll", "game suspected")
        self.navigate(404, (430, 250), "terris-toll-approach")
        self.talk_to_script("s1-brg2", "terris-toll")
        self.await_button("Pay the toll")
        self.menu_button("Pay the toll")
        state = self.await_lines(["Thanks.  Have a nice day."], limit=180, capture="terris-toll-paid")
        state = self.await_scripts_clear(state, "terris-toll")
        if state["globals"].get("story") != 7 or state["globals"].get("gold") != gold - 100:
            raise RouteFailure("normal bridge payment did not spend100 gold and set story7", "game suspected")
        self.checkpoint("terris-toll-complete", state)
        self.travel_route([403, 435, 467, 499, 500], "terris-town-road")
        self.navigate(500, (261, 350), "terris-maria-door")
        self._warp(500, 36, (261, 329), "terris-enter-maria")
        return self.terris_arrival()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--legs", type=Path, default=ROOT / "docs/playtest/route-0.3.2/guided-legs.json")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    source = json.loads(args.source_report.read_text())
    expected = source["checkpoints"]["wizard-training-earned-save"]
    setup = source["startup"]["setup"]
    if setup.get("mode") != "campaign" or setup.get("test_mode") is not False or setup.get("load_map_scripts") is not True:
        raise ValueError("source is not a real campaign session")
    if expected["globals"].get("wizard_see") != 2 or expected["globals"].get("strength") != 4:
        raise ValueError("source lacks earned Bonca quest and strength potion")
    saved = Path(source["session_dir"]) / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if not saved.resolve().is_relative_to(args.source_report.with_suffix(".session").resolve()):
        raise ValueError("source save is outside its isolated report session")
    engine = find_godot()
    os.environ.update(DINK_CAMPAIGN_GODOT=engine, DINK_CAMPAIGN_ENGINE="1",
                      GODOT=str(ROOT / "tools/run_campaign_route.sh"))
    result = {"ok": False, "source_report_sha256": hashlib.sha256(args.source_report.read_bytes()).hexdigest(),
              "source_save_sha256": hashlib.sha256(saved.read_bytes()).hexdigest(),
              "setup": "Normal Continue of unmodified earned wizard-training save; explicit component leg targets; no scenario or quest injection."}
    with PlaytestSession(args.report.with_suffix(".session"), rendered=True, mode="campaign",
                         save_source=saved, timeout=60) as session:
        campaign = CaveRoute(session, rendered=True, max_commands=18000)
        campaign.configure_legs(json.loads(args.legs.read_text()))
        try:
            campaign.checkpoint("title")
            campaign.menu_button("Continue adventure")
            loaded = campaign._call("resume-earned-training", lambda: session.wait(3))
            if not saved_state_matches(expected, loaded):
                raise RouteFailure("normal Continue did not restore earned training save", "harness")
            campaign.checkpoint("resume-earned-training", loaded)
            campaign.wizard_cave()
            campaign.wizard_reward()
            campaign.finish_terris()
            campaign.earned_save("terris-complete")
            result.update(ok=True, verdict="pass")
        except RouteFailure as failure:
            session.screenshot("failure.png")
            result.update(error=str(failure), failure_class=failure.kind,
                          verdict="game suspected" if failure.kind == "game suspected" else "inconclusive")
            if "S1-ROC.push" in str(failure):
                state = campaign._call("rock-back-control", lambda: session.hold("back", 12))
                campaign.checkpoint("rock-back-control", state)
                session.screenshot("rock-back-control.png")
        except (RuntimeError, TimeoutError, OSError, ValueError, KeyError) as failure:
            result.update(error=str(failure), failure_class="harness", verdict="inconclusive")
        result.update(startup=session.startup, session_dir=str(session.session_dir),
                      commands=campaign.commands, checkpoints=campaign.checkpoints, trace=campaign.trace)
    final_save = session.session_dir / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if final_save.is_file():
        result["final_save_sha256"] = hashlib.sha256(final_save.read_bytes()).hexdigest()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: result.get(k) for k in ("ok", "verdict", "failure_class", "error", "commands")}, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
