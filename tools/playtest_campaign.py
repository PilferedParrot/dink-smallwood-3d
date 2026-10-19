"""Deterministic, input-only campaign playtest through Terris arrival.

The campaign bridge owns the real game process and save directory.  This file
only sends allowlisted keys, observes telemetry, and writes a retained report.
It intentionally has no test-mode, teleport, or state-injection path.
"""
from __future__ import annotations

import argparse
from collections import deque
import heapq
import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

try:
    from tools.playtest import PlaytestSession
except ModuleNotFoundError:  # direct ``python tools/playtest_campaign.py``
    from playtest import PlaytestSession

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPORT = ROOT / "builds/playtests/campaign/report.json"
SAVE_GLOBALS = (
    "story", "pig_story", "old_womans_duck", "nuttree", "wizard_again",
    "letter", "s2-map", "s2-aunt", "wizard_see", "rock_placement",
    "gold", "strength", "magic", "life", "lifemax", "defense", "exp",
    "level", "speed", "cur_weapon", "cur_magic", "magic_level", "magic_cost",
)


class RouteFailure(RuntimeError):
    def __init__(self, message: str, kind: str = "bot/incomplete") -> None:
        super().__init__(message)
        self.kind = kind


def clearance_grid(grid: dict[str, Any], radius: float = 2.0) -> dict[str, Any]:
    """Reserve waypoint tolerance plus one native sample around each node.

    A summed-area table makes square clearance queries constant time. This is
    only a conservative planning mask: movement still uses native collision.
    """
    rows = grid["rows"]
    step = grid["step"]
    ox, oy = grid["origin"]
    height, width = len(rows), len(rows[0])
    grow = math.ceil(radius / step) + 1
    sums = [[0] * (width + 1)]
    for y, row in enumerate(rows):
        above = sums[-1]
        current = [0]
        count = 0
        for x, value in enumerate(row):
            count += value == "#" or not (20 <= ox + x * step < 620 and 0 <= oy + y * step < 400)
            current.append(above[x + 1] + count)
        sums.append(current)
    planned = []
    for y in range(height):
        row = []
        for x in range(width):
            x0, y0, x1, y1 = x - grow, y - grow, x + grow + 1, y + grow + 1
            clear = (x0 >= 0 and y0 >= 0 and x1 <= width and y1 <= height
                     and sums[y1][x1] - sums[y0][x1] - sums[y1][x0] + sums[y0][x0] == 0)
            row.append("." if clear else "#")
        planned.append("".join(row))
    # One flood fill avoids running a full failed A* for each candidate edge
    # on the other side of a screen's forest or building barrier.
    components = [0] * (width * height)
    component = 0
    for y, row in enumerate(planned):
        for x, value in enumerate(row):
            index = y * width + x
            if value != "." or components[index]:
                continue
            component += 1
            components[index] = component
            pending = deque([index])
            while pending:
                current = pending.popleft()
                cy, cx = divmod(current, width)
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    neighbor = ny * width + nx
                    if not components[neighbor] and planned[ny][nx] == ".":
                        components[neighbor] = component
                        pending.append(neighbor)
    return {**grid, "rows": planned, "start_search": grow + 1,
            "waypoint_radius": radius, "planning_clearance": grow * step,
            "_components": components}


def grid_path(grid: dict[str, Any], start: tuple[float, float],
              target: tuple[float, float]) -> list[tuple[float, float]]:
    """Plan on the bridge's read-only collision probes; never move the player.

    Cardinal grid steps avoid cutting solid corners. Penalize cells beside
    solids: a sampled boundary can be open while a player's subpixel approach
    stops just beside it. Keep only turns for ordinary forward holds.
    """
    rows = grid["rows"]
    step = int(grid["step"])
    ox, oy = grid["origin"]
    def cell(point: tuple[float, float]) -> tuple[int, int]:
        return round((point[0] - ox) / step), round((point[1] - oy) / step)
    def open_cell(p: tuple[int, int]) -> bool:
        x, y = p
        # The probes extend beyond the map. Those open columns are transition
        # space, not a corridor around obstacles on the current screen.
        inside_map = 20 <= ox + x * step < 620 and 0 <= oy + y * step < 400
        return inside_map and 0 <= y < len(rows) and 0 <= x < len(rows[y]) and rows[y][x] == "."
    first, goal = cell(start), cell(target)
    prefix = []
    if not open_cell(first) and 20 <= start[0] < 620 and 0 <= start[1] < 400:
        # A subpixel landing can round onto a solid sample while standing in
        # its escapable clearance band. Include the neighboring open sample
        # as a real walking waypoint; never pretend the player moved there.
        reach = int(grid.get("start_search", 1))
        nearby = [(first[0] + dx, first[1] + dy)
                  for dx in range(-reach, reach + 1) for dy in range(-reach, reach + 1)
                  if open_cell((first[0] + dx, first[1] + dy))]
        if nearby:
            first = min(nearby, key=lambda p: (math.hypot(ox + p[0] * step - start[0], oy + p[1] * step - start[1]), p))
            prefix = [(ox + first[0] * step, oy + first[1] * step)]
    if not open_cell(first) or not open_cell(goal):
        raise RouteFailure("navigation endpoint is blocked", "bot/incomplete")
    components = grid.get("_components")
    if components is not None:
        width = len(rows[0])
        if components[first[1] * width + first[0]] != components[goal[1] * width + goal[0]]:
            raise RouteFailure("collision grid has no route to waypoint", "bot/incomplete")
    frontier = [(0, first)]
    costs = {first: 0}
    parents = {}
    wall_costs = {}
    def wall_cost(p: tuple[int, int]) -> int:
        if p not in wall_costs:
            x, y = p
            near_wall = any(0 <= y + dy < len(rows) and 0 <= x + dx < len(rows[y + dy])
                            and rows[y + dy][x + dx] == "#"
                            for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            wall_costs[p] = 12 if near_wall else 0
        return wall_costs[p]
    while frontier:
        _, current = heapq.heappop(frontier)
        if current == goal:
            break
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            neighbor = current[0] + dx, current[1] + dy
            cost = costs[current] + 1 + wall_cost(neighbor)
            if open_cell(neighbor) and cost < costs.get(neighbor, math.inf):
                costs[neighbor] = cost
                parents[neighbor] = current
                distance = abs(goal[0] - neighbor[0]) + abs(goal[1] - neighbor[1])
                heapq.heappush(frontier, (cost + distance, neighbor))
    if goal not in costs:
        raise RouteFailure("collision grid has no route to waypoint", "bot/incomplete")
    path = [goal]
    while path[-1] != first:
        path.append(parents[path[-1]])
    path.reverse()
    turns = []
    for i in range(1, len(path)):
        if i == len(path) - 1 or (path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]) != (path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1]):
            turns.append((ox + path[i][0] * step, oy + path[i][1] * step))
    return prefix + turns


def _telemetry(session: PlaytestSession) -> dict[str, Any]:
    result = session.observe()
    if not result.get("ok") or not isinstance(result.get("telemetry"), dict):
        raise RouteFailure("observe failed: " + str(result.get("error", "invalid telemetry")), "harness")
    return result["telemetry"]


def saved_state_matches(expected: dict[str, Any], actual: dict[str, Any]) -> bool:
    return (all(actual.get(k) == expected.get(k) for k in ("screen", "x", "y", "inventory", "magic_inventory"))
            and all(actual.get("globals", {}).get(k) == expected.get("globals", {}).get(k) for k in SAVE_GLOBALS))


class Campaign:
    WIZARD_LINES = [
        "What the...", "Who are you?", "I am a great magician.",
        "No way! You're so cute and tiny!", "I am nothing of the sort!",
        "You cannot measure magic by size!", "I just have to pet you!",
        "Huh?  I just walked right through you.", "You are not really here, are you!",
        "Of course I am.. just not physically.",
        "If you would like to learn more.. Come to my hidden cabin.",
        "How am I supposed to find it if it's hidden?",
        "Good point.  It lies behind some trees north-east of here.",
        "Ok, I may drop by later.. are you in a circus?", "DON'T ANGER ME, HUMAN!",
    ]
    LYNA_LINES = [
        "Hey, that's Lyna with Milder Flatstomp!",
        "You know I love you baby... so what's the problem?",
        "Milder... I want to get to know you first.", "I have a mind too, you know.",
        "You kinda talk too much, you know that?", "You're an ass!",
        "Hhhmph, people!",  # Existing, audited S1-BLOVE dialogue override.
    ]
    LETTER_LINES = [
        "Dear Dink,",
        "We've just gotten word of the tragic accident that happened at...",
        "your home a short while ago.  Needless to say we are shocked.",
        "This must be a hard time for you, being so young and suffering...",
        "such a great loss.  You are completely welcome to come and stay...",
        "with us in Terris for a while, I don't think Jack will mind.",
        "Sincerely, Aunt Maria Kneedlewood",
        "Hmm... Terris.  I think that is west of here.",
        "Hey!  A map was enclosed!",
        "(Press M or button 6 for map toggle)",
    ]
    TERRIS_LINES = [
        "Hello.", "Who the hell are you?",
        "I'm.. I'm Dink Smallwood.  I got a letter and...",
        "I ain't sent no letter to nobody nohow.", "But I...",
        "Git outta my house.", "Dink!  You made it!", "Auntie Maria!",
        "What the? How do you know my wife?  You two been cheatin' on me?",
        "Jack, this is my nephew from Stonebrook.",
        "He's going to be staying with us a while.",
        "Huh?  Since when? Gawd dammit!",
        "Dink, I've prepared a room for you upstairs.",
        "Thanks, I'm sure it will be fine.", "Just ask if you need anything.",
    ]
    WIZARD_PROOF_LINES = [
        "Martridge, I .. I can handle it.  I'm prepared.",
        "I promise I'll be honorable and learn to use it right.",
        "Well Dink, you must prove yourself.", "Ah man, how do I do that?",
        "Well in a cave on these hills, there lies a beast.",
        "It's called a Bonca.  Slay it and return.",
        "I'll do it, I can fight the beast.", "Excellent, excellent.",
        "Where does it dwell?", "In a cave to the west Dink.",
        "I won't fail you.",
        "Here Dink, take this.  This red potion will strengthen you.",
    ]
    WIZARD_REWARD_LINES = [
        "Hey, it's a scroll from Martridge!", "Let's see ...", "Dear Dink,",
        "If you're able to see this then it means you",
        "truly do possess the ability for magic.",
        "I unfortunately have been called away and cannot",
        "instruct you any further.  But there are many",
        "teachers out there, you will find one and further", "your training.",
        "There are 200 gold pieces enclosed, spend them wisely.",
        "For now I leave you with this, your first spell.",
        "Enjoy it Dink, you've earned it.",
        "All right, my first spell! Maybe I can burn down some trees...",
        "I now have fireball magic!",
    ]
    # Named checkpoints make the retained trace useful when route steering gets
    # obstructed.  Coordinates are source-map coordinates, as requested by the
    # campaign task; transition waypoints are deliberately broad.
    # These are source-map points.  The intermediate points deliberately take
    # the player around the cottage furniture and the south pigpen fence.
    WAYPOINTS = {
        "sack": (1, [(430.0, 160.0), (464.0, 137.0), (468.0, 130.0)], 20.0),
        "cottage_exit": (1, [(420.0, 200.0), (325.0, 365.0),
                               (325.0, 437.0)], 28.0),
        "cottage_inside": (439, [(365.0, 307.0)], 30.0),
        # ITEM-PIG accepts x>=200. A radius larger than 20 around x=220
        # can stop short of that source-defined feed zone after a seam crossing.
        "pig_farm": (407, [(110.0, 300.0), (110.0, 270.0), (220.0, 270.0)], 20.0),
    }

    def __init__(self, session: PlaytestSession, rendered: bool = False,
                 max_commands: int = 900) -> None:
        self.session = session
        self.rendered = rendered
        self.max_commands = max_commands
        self.milestone = "opening"
        self.commands = 0
        self.look_gain = 0.002
        self.trace: list[dict[str, Any]] = []
        self.checkpoints: dict[str, Any] = {}
        self.captured: set[str] = set()
        self.resume_letter: dict[str, Any] | None = None

    def _call(self, label: str, fn: Any) -> dict[str, Any]:
        self.commands += 1
        if self.commands > self.max_commands:
            raise RouteFailure("command budget exhausted at " + label)
        before = _telemetry(self.session)
        result = fn()
        after = result.get("telemetry") if isinstance(result, dict) else None
        if not isinstance(after, dict): after = _telemetry(self.session)
        self.trace.append({"label": label, "before": before, "after": after,
                           "ok": bool(result.get("ok", False)), "error": result.get("error")})
        if "navigation_grid" in result:
            self.trace[-1]["navigation_grid"] = result["navigation_grid"]
        if not result.get("ok", False):
            raise RouteFailure(label + ": " + str(result.get("error", "bridge command failed")), "harness")
        return after

    def observe(self, label: str) -> dict[str, Any]:
        state = _telemetry(self.session)
        self.trace.append({"label": label, "after": state, "ok": True})
        return state

    def checkpoint(self, name: str, state: dict[str, Any] | None = None) -> dict[str, Any]:
        state = state or self.observe(name)
        self.checkpoints[name] = state
        # Keep visual review focused on actual gameplay milestones; the full
        # input/telemetry trace still contains every navigation command.
        if self.rendered and name in {
            "title", "opening", "sack-collected", "to-pig-farm", "pig-story", "save-reload",
            "letter-complete", "wizard-training-earned-save", "wizard-rock-pushed",
            "wizard-bonca-defeated", "wizard-reward-earned-save", "terris-toll-complete",
            "wizard-bonca-road-99", "wizard-bonca-road-100",
            "terris-arrival-complete",
        }:
            self._call("screenshot-" + name, lambda: self.session.screenshot(name + ".png"))
        return state

    def menu_button(self, text: str) -> dict[str, Any]:
        state = self.observe("menu-before-" + text)
        buttons = state.get("ui", {}).get("buttons", [])
        index = next((i for i, button in enumerate(buttons) if str(button.get("text", "")) == text), -1)
        if index < 0:
            raise RouteFailure("menu button not present: " + text, "harness")
        focused = next((i for i, button in enumerate(buttons) if button.get("focused")), -1)
        if focused < 0:
            raise RouteFailure("menu has no focused button: " + text, "harness")
        # Drive from the focus the game actually reports.  In particular, do
        # not pretend repeated Up returns focus to the first widget: Godot UI
        # containers can wrap focus.
        direction = "down" if index >= focused else "up"
        for expected in range(abs(index - focused)):
            state = self._call("menu-" + direction, lambda direction=direction: self.session.menu_key(direction))
            current = state.get("ui", {}).get("buttons", [])
            if not any(button.get("focused") for button in current):
                raise RouteFailure("menu focus disappeared while selecting " + text, "harness")
        selected = state.get("ui", {}).get("buttons", [])
        if not any(button.get("text") == text and button.get("focused") for button in selected):
            raise RouteFailure("menu focus did not reach " + text, "harness")
        return self._call("menu-enter-" + text, lambda: self.session.menu_key("enter"))

    def dialogue(self, limit: int = 80, require_release: bool = False, capture: str = "") -> dict[str, Any]:
        """Advance ordinary dialogue, allowing delayed VM lines to become live."""
        state = self.observe("dialogue-start")
        for _ in range(limit):
            active = bool(state.get("dialogue", state.get("ui", {}).get("dialogue", False)))
            if active:
                if self.rendered and capture and capture not in self.captured:
                    self._call("screenshot-" + capture, lambda: self.session.screenshot(capture + ".png"))
                    self.captured.add(capture)
                # A line can close and a later VM continuation can open another
                # one.  Always tick after Enter; do not return between them.
                self._call("dialogue-enter", lambda: self.session.menu_key("enter"))
            self._call("dialogue-wait", lambda: self.session.wait(15))
            state = self.observe("dialogue-step")
            active = bool(state.get("dialogue", state.get("ui", {}).get("dialogue", False)))
            controlled = not state.get("frozen", False) and not state.get("disabled", 0) and not state.get("nocontrol", 0)
            if not active and (not require_release or controlled):
                return state
        raise RouteFailure("dialogue did not finish within bounded Enter steps")

    def equip_item(self, script: str, name: str) -> dict[str, Any]:
        """Select opening equipment through the actual inventory keyboard UI.

        The chest's nested icon buttons are absent from the bridge's shallow
        button list, but its focused item's full description is observable.
        These opening items occupy the first row; never infer focus from the
        currently equipped slot or inject an equipment action.
        """
        state = self.observe("equip-" + script)
        slot = next((i + 1 for i, item in enumerate(state.get("inventory", []))
                     if str(item.get("script", "")).lower() == script), None)
        if slot is None:
            raise RouteFailure("earned inventory lacks " + script, "game suspected")
        if any(button.get("text") == name for button in state.get("ui", {}).get("buttons", [])):
            state = self.menu_button(name)
        else:
            selected = False
            for direction in ("right", "left"):
                for _ in range(16):
                    labels = state.get("ui", {}).get("labels", [])
                    back_focused = any(button.get("focused") for button in state.get("ui", {}).get("buttons", []))
                    focused_item = any(str(label).removeprefix("Selected: ").split("\n")[0].split(" · ")[0].casefold() == ("Item: " + name).casefold() for label in labels)
                    if not back_focused and focused_item:
                        selected = True
                        break
                    state = self._call("equipment-" + direction, lambda direction=direction: self.session.menu_key(direction))
                if selected:
                    break
            if not selected:
                raise RouteFailure("inventory focus did not expose " + name, "harness")
            state = self._call("equipment-enter-" + script, lambda: self.session.menu_key("enter"))
        if int(state.get("globals", {}).get("cur_weapon", -1)) != slot or state.get("page") != "game":
            raise RouteFailure("normal equipment input did not equip " + name, "game suspected")
        return state

    def await_button(self, text: str, limit: int = 100) -> dict[str, Any]:
        """Advance delayed dialogue until a specific normal choice is visible."""
        state = self.observe("await-button-" + text)
        for _ in range(limit):
            buttons = state.get("ui", {}).get("buttons", [])
            if any(str(button.get("text", "")) == text for button in buttons):
                return state
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                self._call("await-button-enter-" + text, lambda: self.session.menu_key("enter"))
            self._call("await-button-wait-" + text, lambda: self.session.wait(15))
            state = self.observe("await-button-state-" + text)
        raise RouteFailure("dialogue did not expose choice: " + text)

    def await_global(self, name: str, value: int, limit: int = 100, capture: str = "") -> dict[str, Any]:
        """Let normal VM dialogue/cutscene work reach an observed quest value."""
        state = self.observe("await-" + name)
        for _ in range(limit):
            if int(state.get("globals", {}).get(name, 0)) == value and not state.get("frozen", False) and not state.get("nocontrol", 0):
                return state
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                dialogue_text = " ".join(str(x) for x in state.get("ui", {}).get("labels", []) + state.get("recent_dialogue", []))
                capture_ready = capture != "milder-dialogue" or "milder" in dialogue_text.lower() or "lookie" in dialogue_text.lower()
                if self.rendered and capture and capture not in self.captured and capture_ready:
                    self._call("screenshot-" + capture, lambda: self.session.screenshot(capture + ".png"))
                    self.captured.add(capture)
                self._call("await-" + name + "-enter", lambda: self.session.menu_key("enter"))
            self._call("await-" + name + "-wait", lambda: self.session.wait(15))
            state = self.observe("await-" + name + "-state")
        raise RouteFailure("script did not reach %s=%d with control released" % (name, value))

    def await_lines(self, lines: list[str], limit: int = 200,
                    capture: str = "", line_captures: dict[str, str] | None = None) -> dict[str, Any]:
        """Wait through delayed cutscene startup and require its actual dialogue.

        Mother sets story=2 before moving Dink and freezing controls. Neither
        that flag nor a temporarily empty dialogue panel certifies completion.
        """
        matched = 0
        state = self.observe("await-lines-start")
        for _ in range(limit):
            recent = state.get("recent_dialogue", [])
            for line in recent:
                if matched < len(lines) and line == lines[matched]:
                    matched += 1
            active = bool(state.get("dialogue", False))
            released = not any(state.get(key, False) for key in ("frozen", "disabled", "nocontrol"))
            if matched == len(lines) and not active and released:
                return state
            if active:
                labels = state.get("ui", {}).get("labels", [])
                capture_ready = labels and (capture != "home-alktree" or any("AlkTree nuts" in str(label) for label in labels))
                if self.rendered and capture and capture not in self.captured and capture_ready:
                    self._call("screenshot-" + capture, lambda: self.session.screenshot(capture + ".png"))
                    self.captured.add(capture)
                for line, name in (line_captures or {}).items():
                    if self.rendered and line in labels and name not in self.captured:
                        self._call("screenshot-" + name, lambda name=name: self.session.screenshot(name + ".png"))
                        self.captured.add(name)
                self._call("await-lines-enter", lambda: self.session.menu_key("enter"))
            state = self._call("await-lines-wait", lambda: self.session.wait(15))
        raise RouteFailure("return-home dialogue did not finish: observed %d/%d required lines" % (matched, len(lines)))

    def await_scripts_clear(self, state: dict[str, Any], label: str, limit: int = 12) -> dict[str, Any]:
        """Allow a completed fade/load task to detach before accepting it."""
        for _ in range(limit):
            scripts = state.get("scripts", {})
            released = not any(state.get(key, False) for key in ("frozen", "disabled", "nocontrol"))
            if released and not scripts.get("dialogue_busy") and int(scripts.get("vm_live_tasks", 0)) == 0:
                return state
            state = self._call(label + "-settle", lambda: self.session.wait(3))
        raise RouteFailure(label + " script task remains active", "game suspected")

    @staticmethod
    def _wrap(angle: float) -> float:
        return (angle + math.pi) % (2 * math.pi) - math.pi

    def _aim(self, state: dict[str, Any], target: tuple[float, float], label: str) -> dict[str, Any]:
        # Mouse-relative events are transformed by Godot's viewport stretch.
        # Measure the real input gain and close the loop before any walking;
        # nonzero yaw movement alone does not prove we face the waypoint.
        gain = self.look_gain
        capture_retry = False
        for _ in range(8):
            target_yaw = math.atan2(-(target[0] - float(state["x"])), -(target[1] - float(state["y"])))
            delta = self._wrap(target_yaw - float(state["yaw"]))
            if abs(delta) <= 0.002:
                self.look_gain = gain
                return state
            # Limit the first turn so a scaled event cannot hide a whole
            # rotation in the wrapped yaw measurement.
            turn = max(-math.pi / 4, min(math.pi / 4, delta))
            dx = max(-2000.0, min(2000.0, -turn / gain))
            aimed = self._call("aim-" + label, lambda dx=dx: self.session.look(dx, 0.0))
            actual = self._wrap(float(aimed["yaw"]) - float(state["yaw"]))
            if abs(actual) < 0.0001:
                if capture_retry:
                    raise RouteFailure("ordinary look input did not change yaw at " + label, "harness")
                capture_retry = True
                state = self._call("aim-capture-tick-" + label, lambda: self.session.wait(1))
                continue
            measured = -actual / dx
            if measured <= 0 or abs(actual) >= math.pi - 0.01:
                raise RouteFailure("ambiguous mouse input gain at " + label, "harness")
            gain = measured
            state = aimed
        raise RouteFailure("ordinary look input did not converge at " + label, "harness")

    def _walk_point(self, screen: int, target: tuple[float, float], radius: float, label: str) -> dict[str, Any]:
        state = self.observe("approach-" + label)
        stalled = 0
        for _ in range(90):
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                # Native say_stop currently blocks input even without freeze
                # (unlike FreeDink). Normal Enter is a labelled workaround for
                # that game fidelity defect, not proof of a physical obstacle.
                state = self.dialogue(require_release=True)
                stalled = 0
            if int(state.get("screen", -1)) != screen:
                return state
            distance = math.hypot(float(state["x"]) - target[0], float(state["y"]) - target[1])
            if distance <= radius:
                return state
            state = self._aim(state, target, label)
            frames = 1 if distance < 10 else (4 if distance < 38 else 10)
            after = self._call("walk-" + label, lambda: self.session.hold("forward", frames))
            if int(after.get("screen", -1)) != screen:
                return after
            if after.get("dialogue", after.get("ui", {}).get("dialogue", False)):
                state = after
                continue
            new_distance = math.hypot(float(after["x"]) - target[0], float(after["y"]) - target[1])
            stalled = stalled + 1 if new_distance >= distance - 0.2 else 0
            # This reports the live blocked position.  It never rewinds Python
            # state after exploratory keys, unlike the former four-key probe.
            if stalled >= 5:
                raise RouteFailure("live forward route stalled at %s near (%.1f, %.1f), target (%.1f, %.1f)" %
                                   (label, after["x"], after["y"], target[0], target[1]))
            state = after
        raise RouteFailure("waypoint budget exhausted: " + label)

    def move_to(self, name: str) -> dict[str, Any]:
        screen, points, radius = self.WAYPOINTS[name]
        state = self.observe("approach-" + name)
        if int(state.get("screen", -1)) != screen:
            raise RouteFailure(f"expected map {screen} for {name}, got {state.get('screen')}")
        for point_number, point in enumerate(points):
            state = self._walk_point(screen, point, radius if point_number == len(points) - 1 else 22.0,
                                     name + "-%d" % point_number)
            if int(state.get("screen", -1)) != screen:
                return self.checkpoint(name, state)
        return self.checkpoint(name, state)

    def seek_screen(self, target: int, label: str) -> dict[str, Any]:
        """Cross an ordinary map edge using bounded holds and telemetry."""
        if label == "to-pig-farm":
            # The direct north line from the cottage lands in the outdoor
            # obstacle run.  Follow the open east side before crossing north.
            for number, point in enumerate(((560.0, 326.0), (560.0, 20.0), (110.0, 20.0))):
                state = self._walk_point(439, point, 26.0, label + "-east-%d" % number)
                if int(state.get("screen", -1)) == target:
                    return self.checkpoint(label, state)
        # Continue through the map edge facing the intended exit; probing all
        # four keys would itself walk the live player away from the edge.
        for _ in range(36):
            state = self.observe("edge-" + label)
            if int(state.get("screen", -1)) == target:
                return self.checkpoint(label, state)
            # Edges lie outside the nearest source-map boundary.
            edge = (float(state["x"]), -50.0 if label == "to-pig-farm" else 650.0)
            state = self._aim(state, edge, "edge-" + label)
            after = self._call("edge-" + label, lambda: self.session.hold("forward", 12))
            if int(after.get("screen", -1)) == target:
                return self.checkpoint(label, after)
        raise RouteFailure(f"could not cross into map {target} at {label}")

    def talk_to_mother(self) -> dict[str, Any]:
        """Find the moving mother by her live campaign script and talk normally."""
        for attempt in range(3):
            state = self.observe("mother-live-%d" % attempt)
            mother = next((entity for entity in state.get("entities", [])
                           if str(entity.get("script", "")).lower() == "s1-h1-m" and int(entity.get("active", 1))), None)
            if mother is None:
                raise RouteFailure("mother script entity is absent on home map", "game suspected")
            target = (float(mother["x"]), float(mother["y"]))
            distance = math.hypot(float(state["x"]) - target[0], float(state["y"]) - target[1])
            if distance > 60.0:
                self._walk_point(1, target, 42.0, "mother-live-%d" % attempt)
                state = self.observe("mother-after-walk-%d" % attempt)
                mother = next((entity for entity in state.get("entities", [])
                               if str(entity.get("script", "")).lower() == "s1-h1-m" and int(entity.get("active", 1))), None)
                if mother is None:
                    raise RouteFailure("mother moved out of telemetry", "bot/incomplete")
                target = (float(mother["x"]), float(mother["y"]))
            state = self._aim(state, target, "mother-live-%d" % attempt)
            state = self._call("talk-mother-%d" % attempt, lambda: self.session.hold("talk", 1))
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                return state
            # A talk event can schedule its first line for the next tick.
            self._call("mother-talk-wait-%d" % attempt, lambda: self.session.wait(2))
            state = self.observe("mother-dialogue-%d" % attempt)
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                return state
        raise RouteFailure("ordinary talk did not open mother dialogue at her live position")

    def _entity(self, script: str, state: dict[str, Any] | None = None) -> dict[str, Any] | None:
        state = state or self.observe("find-" + script)
        wanted = script.lower()
        return next((entity for entity in state.get("entities", [])
                     if str(entity.get("script", "")).lower() == wanted
                     and int(entity.get("active", 1))), None)

    def talk_to_script(self, script: str, label: str, limit: int = 4) -> dict[str, Any]:
        """Approach and talk to a live scripted actor using normal inputs."""
        for attempt in range(limit):
            state = self.observe("%s-live-%d" % (label, attempt))
            entity = self._entity(script, state)
            if entity is None:
                raise RouteFailure("%s script entity is absent on map %s" % (script, state.get("screen")),
                                   "game suspected")
            target = (float(entity["x"]), float(entity["y"]))
            if math.hypot(float(state["x"]) - target[0], float(state["y"]) - target[1]) > 58.0:
                self._walk_point(int(state["screen"]), target, 42.0, "%s-%d" % (label, attempt))
                state = self.observe("%s-after-walk-%d" % (label, attempt))
                entity = self._entity(script, state)
                if entity is None:
                    continue
                target = (float(entity["x"]), float(entity["y"]))
            self._aim(state, target, "%s-%d" % (label, attempt))
            state = self._call("talk-%s-%d" % (label, attempt), lambda: self.session.hold("talk", 1))
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                return state
            self._call("%s-talk-wait-%d" % (label, attempt), lambda: self.session.wait(2))
            state = self.observe("%s-dialogue-%d" % (label, attempt))
            if state.get("dialogue", state.get("ui", {}).get("dialogue", False)):
                return state
        raise RouteFailure("ordinary talk did not open %s dialogue" % label)

    def _cross(self, target: int, label: str, edge: tuple[float, float]) -> dict[str, Any]:
        """Walk to one map edge and require the expected adjacent screen."""
        for _ in range(38):
            state = self.observe("edge-%s" % label)
            if int(state.get("screen", -1)) == target:
                return self.checkpoint(label, state)
            self._aim(state, edge, "edge-%s" % label)
            state = self._call("cross-%s" % label, lambda: self.session.hold("forward", 12))
            if int(state.get("screen", -1)) == target:
                return self.checkpoint(label, state)
            if int(state.get("screen", -1)) != int(self.trace[-1]["before"].get("screen", -1)):
                raise RouteFailure("edge %s entered unexpected map %s, expected %d" %
                                   (label, state.get("screen"), target), "bot/incomplete")
        raise RouteFailure("could not cross into map %d at %s" % (target, label))

    def navigate(self, screen: int, point: tuple[float, float], label: str,
                 transition: int | None = None) -> dict[str, Any]:
        """Use live collision observations to steer normal inputs around props."""
        state = self._call("grid-" + label, lambda: self.session.navigation_grid(step=1))
        grid = clearance_grid(self.trace[-1]["navigation_grid"])
        self.trace[-1]["planning_clearance"] = grid["planning_clearance"]
        if int(state.get("screen", -1)) != screen or int(grid["screen"]) != screen:
            raise RouteFailure("navigation screen mismatch at " + label, "harness")
        path = grid_path(grid, (float(state["x"]), float(state["y"])), point)
        return self._follow_path(screen, path, label, transition)

    def _follow_path(self, screen: int, path: list[tuple[float, float]], label: str,
                     transition: int | None = None) -> dict[str, Any]:
        state = self.observe("path-" + label)
        for i, target in enumerate(path):
            start = float(state["x"]), float(state["y"])
            distance = math.hypot(target[0] - start[0], target[1] - start[1])
            # The normal opening speed is only 35 source pixels/second.
            # A map-wide straight leg can exceed _walk_point's fixed budget;
            # subdivide it without changing the planned corridor.
            pieces = max(1, math.ceil(distance / 220.0))
            for piece in range(1, pieces + 1):
                point = (start[0] + (target[0] - start[0]) * piece / pieces,
                         start[1] + (target[1] - start[1]) * piece / pieces)
                state = self._walk_point(screen, point, 2.0, label + "-%d-%d" % (i, piece))
                if int(state.get("screen", -1)) != screen:
                    if int(state.get("screen", -1)) == transition:
                        return state
                    raise RouteFailure("planned path %s unexpectedly entered map %s" % (label, state.get("screen")))
        return state

    def travel(self, target: int, label: str) -> dict[str, Any]:
        """Choose a reachable ordinary edge from the live collision grid."""
        state = self._call("edge-grid-" + label, lambda: self.session.navigation_grid(step=1))
        screen = int(state["screen"])
        delta = target - screen
        if delta not in (-32, -1, 1, 32):
            raise RouteFailure("travel requires adjacent maps", "harness")
        grid = clearance_grid(self.trace[-1]["navigation_grid"])
        self.trace[-1]["planning_clearance"] = grid["planning_clearance"]
        start = float(state["x"]), float(state["y"])
        horizontal = abs(delta) == 1
        # Cross horizontally at x<20 / x>620, vertically at y<0 / y>400.
        # Plan just inside the boundary, then keep walking through that edge.
        values = range(10, 391, 5) if horizontal else range(25, 616, 5)
        preferred = start[1] if horizontal else start[0]
        for value in sorted(values, key=lambda value: (abs(value - preferred), value)):
            point = ((615.0 if delta == 1 else 25.0), float(value)) if horizontal else (float(value), 5.0 if delta == -32 else 395.0)
            try:
                path = grid_path(grid, start, point)
            except RouteFailure:
                continue
            moved = self._follow_path(screen, path, label + "-approach", target)
            if int(moved["screen"]) == target:
                return self.checkpoint(label, moved)
            edge = ((650.0 if delta == 1 else -50.0), float(value)) if horizontal else (float(value), -50.0 if delta == -32 else 650.0)
            return self._cross(target, label, edge)
        # Rounding onto a blocked probe alone is inconclusive. Test the real
        # input path in all four directions before calling a landing stuck.
        cell_x, cell_y = round(start[0] / grid["step"]), round(start[1] / grid["step"])
        if grid["rows"][cell_y][cell_x] == "#":
            self.probe_blocked_landing(screen, label)
        raise RouteFailure("no observed collision-grid path to map %d from %d" % (target, screen))

    def probe_blocked_landing(self, screen: int, label: str) -> dict[str, Any]:
        """Probe actual movement without restoring or inventing Python state."""
        state = self.observe(label + "-landing-probe-start")
        origin = float(state["x"]), float(state["y"])
        moved = False
        controlled = True
        for action in ("forward", "back", "left", "right"):
            state = self._call(label + "-landing-probe-" + action,
                               lambda action=action: self.session.hold(action, 12))
            moved = moved or int(state.get("screen", -1)) != screen or math.hypot(float(state["x"]) - origin[0], float(state["y"]) - origin[1]) > 0.2
            controlled = controlled and state.get("playing", False) and state.get("page") == "game" and not any(state.get(k, False) for k in ("modal", "changing", "frozen", "disabled", "nocontrol"))
        if not moved and controlled:
            self.checkpoint("blocked-landing-all-directions", state)
            raise RouteFailure("map %d landing at (%.2f, %.2f) is blocked: four normal movement directions produced no displacement with controls released" % (screen, origin[0], origin[1]), "game suspected")
        return state

    def travel_route(self, screens: list[int], label: str) -> dict[str, Any]:
        state = self.observe(label + "-start")
        for target in screens:
            state = self.travel(target, label + "-%d" % target)
            # A map can contain its own startup conversation. Advance it
            # through the same bounded Enter path before more movement.
            self._call(label + "-arrival-tick", lambda: self.session.wait(3))
            state = self.dialogue(require_release=True)
        return state

    def earned_save(self, label: str) -> dict[str, Any]:
        # LRAISE waits one second before opening its attribute choice. It can
        # replace Pause during navigation after an earned combat victory.
        def level_choice(state: dict[str, Any]) -> bool:
            return [b.get("text") for b in state.get("ui", {}).get("buttons", [])] == [
                "Increase Attack", "Increase Defense", "Increase Magic"]

        for _ in range(3):
            state = self.observe(label + "-before-save")
            if not level_choice(state):
                try:
                    if not any(b.get("text") == "Save adventure" for b in state.get("ui", {}).get("buttons", [])):
                        self._call(label + "-pause-save", self.session.pause)
                    self.menu_button("Save adventure")
                except RouteFailure:
                    state = self.observe(label + "-save-interrupted")
                    if not level_choice(state):
                        raise
                else:
                    self._call(label + "-resume-save", self.session.pause)
                    return self.checkpoint(label + "-earned-save")
            self.menu_button("Increase Attack")
            self._call(label + "-level-choice-settle", lambda: self.session.wait(3))
        raise RouteFailure("level-up repeatedly interrupted earned save", "harness")

    def _warp(self, screen: int, target: int, point: tuple[float, float], label: str) -> dict[str, Any]:
        """Use a map's ordinary scripted door/edge warp and require its target."""
        approaches = []
        if screen == 409 and point == (397.0, 301.0):
            # Approach below the roadside prop, then along the cottage's
            # open southeast side; a direct diagonal crosses its footprint.
            approaches = [((250.0, 390.0), 24.0), ((500.0, 390.0), 24.0),
                          ((500.0, 330.0), 20.0), ((397.0, 330.0), 18.0)]
        for index, (position, radius) in enumerate(approaches + [(point, 5.0)]):
            state = self._walk_point(screen, position, radius, label + "-approach-%d" % index)
            if int(state.get("screen", -1)) == target:
                return self.checkpoint(label, state)
            if int(state.get("screen", -1)) != screen:
                raise RouteFailure("door approach %s entered unexpected map %s" % (label, state.get("screen")), "harness")
        for _ in range(10):
            state = self.observe(label + "-wait")
            if int(state.get("screen", -1)) == target:
                return self.checkpoint(label, state)
            self._aim(state, point, label)
            self._call(label + "-step", lambda: self.session.hold("forward", 4))
        raise RouteFailure("scripted warp did not reach map %d at %s" % (target, label))

    def _leave_ethel_outdoor(self, label: str) -> dict[str, Any]:
        """Take the collision-grid-validated lane from Ethel's door to 408."""
        self._walk_point(409, (350.0, 355.0), 8.0, label + "-lane")
        self._walk_point(409, (30.0, 355.0), 8.0, label + "-west")
        return self._cross(408, label, (-50.0, 350.0))

    def run_ethel(self) -> dict[str, Any]:
        """Continue from the completed pig conversation through Ethel's duck quest."""
        # Home exit and the confirmed outdoor route to Ethel's house.
        self._walk_point(1, (325.0, 437.0), 24.0, "ethel-home-exit")
        self._cross(439, "ethel-to-cottage", (325.0, 650.0))
        self._cross(440, "ethel-to-east-road", (650.0, 280.0))
        self._walk_point(440, (60.0, 230.0), 24.0, "ethel-north-road-west-approach")
        self._walk_point(440, (60.0, 20.0), 24.0, "ethel-north-road-approach")
        self._cross(408, "ethel-to-north-road", (320.0, -50.0))
        self._cross(409, "ethel-to-ethel-outdoor", (650.0, 200.0))
        self._warp(409, 2, (397.0, 301.0), "ethel-enter-house")

        state = self.talk_to_script("s1-h2-o", "ethel")
        if not any("Ask after her pet" in str(button.get("text", ""))
                   for button in state.get("ui", {}).get("buttons", [])):
            raise RouteFailure("Ethel dialogue did not expose the pet request", "game suspected")
        self.menu_button("Ask after her pet")
        state = self.await_button("Agree whole heartedly")
        self.menu_button("Agree whole heartedly")
        state = self.await_global("old_womans_duck", 1, 100, capture="ethel-request")
        self.checkpoint("ethel-request", state)

        # Leave Ethel's house before searching. FINDDUCK rolls when its map is
        # entered.  Read the live actor list at each entry rather than walking
        # speculative patterns through prop-dense village maps.
        self._warp(2, 409, (314.0, 433.0), "ethel-leave-before-search")
        duck_state: dict[str, Any] | None = None
        for attempt in range(6):
            # 409 -> 408 -> 440 is the actual west/north route.  Do not ask a
            # same-screen walk helper to cross an edge: it intentionally
            # returns on a screen mismatch and used to leave this route on 409.
            # The cottage exit lands beside its west wall; go south around the
            # wall before seeking the west map edge.
            self._leave_ethel_outdoor("duck-search-408-enter-%d" % attempt)
            self._cross(440, "duck-search-440-enter-%d" % attempt, (320.0, 650.0))
            state = self.observe("duck-search-440-%d" % attempt)
            if self._entity("s1-oldd", state) is not None:
                duck_state = self.talk_to_script("s1-oldd", "duck")
                break
            self._cross(441, "duck-search-441-enter-%d" % attempt, (650.0, 200.0))
            state = self.observe("duck-search-441-%d" % attempt)
            if self._entity("s1-oldd", state) is not None:
                duck_state = self.talk_to_script("s1-oldd", "duck")
                break
            # Return through the confirmed open north-west line before trying
            # the next independent FINDDUCK entry roll.
            self._cross(440, "duck-search-440-return-%d" % attempt, (-50.0, 200.0))
            # Grid planning from the 441 west entry (about 520,200) follows
            # the open north lane; the old direct west diagonal hit the
            # central house collision.
            self._walk_point(440, (500.0, 115.0), 8.0, "duck-search-road-east-lane-%d" % attempt)
            self._walk_point(440, (60.0, 10.0), 8.0, "duck-search-road-north-lane-%d" % attempt)
            self._cross(408, "duck-search-408-return-%d" % attempt, (60.0, -50.0))
            self._cross(409, "duck-search-409-return-%d" % attempt, (650.0, 200.0))
        if duck_state is None:
            raise RouteFailure("bounded duck search found no live s1-oldd actor", "bot/incomplete")
        if not any("Yell at it" in str(button.get("text", ""))
                   for button in duck_state.get("ui", {}).get("buttons", [])):
            raise RouteFailure("duck dialogue did not expose Yell at it", "game suspected")
        self.menu_button("Yell at it")
        state = self.await_global("old_womans_duck", 2, 140, capture="duck-returned")
        self.checkpoint("duck-returned-alive", state)
        # This is a stable, genuinely earned retry point: preserve it through
        # the same pause-menu Save input used by the acceptance route.
        self._call("duck-returned-pause-save", self.session.pause)
        self.menu_button("Save adventure")
        self._call("duck-returned-resume-save", self.session.pause)
        self.checkpoint("duck-returned-earned-save")

        # Re-enter Ethel's house to advance her quest, then return through the
        # normal road and home warp for the AlkTree nuts conversation.
        duck_screen = int(state.get("screen", -1))
        if duck_screen == 440:
            self._cross(408, "duck-to-north-road", (320.0, -50.0))
            self._cross(409, "duck-to-ethel-road", (650.0, 200.0))
        elif duck_screen == 441:
            self._cross(409, "duck-to-ethel-road", (320.0, -50.0))
        elif duck_screen != 409:
            raise RouteFailure("duck search ended on unexpected map %s" % state.get("screen"))
        self._warp(409, 2, (397.0, 301.0), "ethel-return-house")
        # S1-H2-O main, not talk(), acknowledges Quackers on the ordinary
        # house-entry script and advances the flag to 4.  Do not walk through
        # the cottage furniture toward Ethel while that automatic dialogue is
        # already running.
        self.dialogue(120, require_release=True, capture="ethel-acknowledgment")
        state = self.observe("ethel-complete")
        if int(state.get("globals", {}).get("old_womans_duck", 0)) != 4:
            raise RouteFailure("re-entering Ethel's house did not mark duck returned", "game suspected")
        self._warp(2, 409, (314.0, 433.0), "ethel-leave-house")
        self._leave_ethel_outdoor("ethel-return-south-road")
        self._walk_point(408, (60.0, 395.0), 8.0, "ethel-return-408-south")
        self._cross(440, "ethel-return-east-road", (60.0, 650.0))
        self._walk_point(440, (60.0, 230.0), 12.0, "ethel-return-440-west")
        self._cross(439, "ethel-return-west-road", (-50.0, 230.0))
        self._walk_point(439, (560.0, 326.0), 24.0, "ethel-return-439-east")
        self._warp(439, 1, (368.0, 280.0), "ethel-home-warp")
        state = self.observe("ethel-home-returned")
        if int(state.get("screen", -1)) != 1:
            raise RouteFailure("normal Ethel return route did not enter home map")
        state = self.await_lines([
            "Dink, can you do something for me?",
            "Yes, what is it?",
            "Can you go out to the woods and see if you can get,",
            "some AlkTree nuts, I think they're in season.",
            "No problem, I'll be right back.",
            "You're a dear.",
        ], capture="home-alktree")
        if int(state.get("globals", {}).get("story", 0)) != 2:
            raise RouteFailure("home AlkTree conversation did not set story=2", "game suspected")
        self.checkpoint("home-alktree-complete", state)
        return state

    def run_alktree(self) -> dict[str, Any]:
        self.alktree_depart()
        self.alktree_woods()
        self.alktree_pickup()
        return self.alktree_return()

    def run_letter(self) -> dict[str, Any]:
        """Earn Renton's letter and read Aunt Maria's invitation normally."""
        self.letter_guard()
        return self.letter_home()

    def run_terris(self) -> dict[str, Any]:
        """Earn the bridge toll, then complete S2-AUNTP's real arrival.

        S1-MH-F awards 200 gold after Martridge's Bonca proof quest. S1-BRG2
        spends 100 and advances story to 7; Maria's arrival sets s2-aunt=1.
        Every door and cave entrance below runs its ordinary map script.
        """
        state = self.observe("terris-prerequisites")
        expected = {"story": 6, "letter": 2, "s2-map": 1, "s2-aunt": 0}
        if int(state.get("screen", -1)) != 439 or any(int(state.get("globals", {}).get(k, -1)) != v for k, v in expected.items()):
            raise RouteFailure("Terris route requires completed LETTER on map 439")
        self.earned_save("terris-letter")
        self.wizard_training()
        self.wizard_cave()
        self.wizard_reward()
        # Return along the source-map corridor to the Stonebrook bridge.
        self._warp(6, 251, (467.0, 387.0), "terris-wizard-leave")
        self.travel_route([283, 315, 314, 346, 378, 377, 376, 375, 407, 406, 405, 404], "terris-bridge-road")
        state = self.observe("terris-toll-before")
        gold = int(state.get("globals", {}).get("gold", 0))
        if gold < 100:
            raise RouteFailure("earned wizard reward cannot cover bridge toll", "game suspected")
        self.navigate(404, (430.0, 250.0), "terris-toll-approach")
        self.talk_to_script("s1-brg2", "terris-toll")
        self.await_button("Pay the toll")
        self.menu_button("Pay the toll")
        state = self.await_lines(["Thanks.  Have a nice day."], limit=180, capture="terris-toll-paid")
        state = self.await_scripts_clear(state, "terris-toll")
        if int(state.get("globals", {}).get("story", 0)) != 7 or int(state.get("globals", {}).get("gold", -1)) != gold - 100:
            raise RouteFailure("bridge payment did not spend 100 gold and advance story=7", "game suspected")
        self.checkpoint("terris-toll-complete", state)
        self.travel_route([403, 435, 467, 499, 500], "terris-town-road")
        self.navigate(500, (261.0, 350.0), "terris-maria-door")
        self._warp(500, 36, (261.0, 329.0), "terris-enter-maria")
        return self.terris_arrival()

    def wizard_training(self) -> dict[str, Any]:
        # This corridor avoids the ridge's closed edges. Map 346's barrier
        # allows story>=3; the introductory 376 scene was earned before LETTER.
        self.travel_route([440, 408, 376, 377, 378, 346, 314, 315, 283, 251], "wizard-cabin-road")
        self.navigate(251, (264.0, 345.0), "wizard-cabin-door")
        self._warp(251, 6, (264.0, 319.0), "wizard-enter-cabin")
        self.navigate(6, (440.0, 195.0), "wizard-teacher-approach")
        self.talk_to_script("s1-mh-m", "wizard-teacher")
        self.await_button("Tell him you're worthy", limit=200)
        self.menu_button("Tell him you're worthy")
        state = self.await_lines(self.WIZARD_PROOF_LINES, limit=200, capture="wizard-proof-request")
        state = self.await_scripts_clear(state, "wizard-proof-request")
        if int(state.get("globals", {}).get("wizard_see", 0)) != 2:
            raise RouteFailure("Martridge did not assign Bonca proof quest", "game suspected")
        strength = int(state.get("globals", {}).get("strength", 0))
        self.navigate(6, (187.0, 157.0), "wizard-strength-potion")
        state = self.observe("wizard-potion-collected")
        if int(state.get("globals", {}).get("strength", 0)) != strength + 1:
            raise RouteFailure("ordinary potion pickup did not increase strength", "game suspected")
        return self.earned_save("wizard-training")

    def wizard_cave(self) -> dict[str, Any]:
        self._warp(6, 251, (467.0, 387.0), "wizard-leave-cabin")
        self.travel_route([283, 315, 314, 346, 378, 377, 376, 375, 374, 373, 372, 340, 341, 309, 277], "wizard-cave-road")
        return self.cave_from_rock()

    def cave_from_rock(self) -> dict[str, Any]:
        """Continue from an earned map277 checkpoint with the same real inputs."""
        state = self.push_cave_rock()
        if int(state.get("screen", -1)) == 277:
            self.navigate(277, (275.0, 162.0), "wizard-cave-hole", transition=131)
        elif int(state.get("screen", -1)) != 131:
            raise RouteFailure("push ended outside the cave approach or entrance", "harness")
        # S1-HOLE moves/animates Dink and loads 131. The runner only waits.
        for _ in range(30):
            state = self._call("wizard-hole-wait", lambda: self.session.wait(15))
            if int(state.get("screen", -1)) == 131:
                break
        if int(state.get("screen", -1)) != 131:
            raise RouteFailure("S1-HOLE did not enter cave map 131", "game suspected")
        self.dialogue(require_release=True)
        self.travel_route([99, 100], "wizard-bonca-road")
        return self.fight_bonca()

    def push_cave_rock(self) -> dict[str, Any]:
        state = self.observe("wizard-rock-prerequisites")
        rock = self._entity("s1-roc", state)
        if int(state.get("screen", -1)) != 277 or int(state.get("globals", {}).get("strength", 0)) < 4 or rock is None:
            raise RouteFailure("cave push requires live rock on 277 and earned strength>=4")
        self.navigate(277, (225.0, 180.0), "wizard-rock-west-side")
        self.earned_save("wizard-rock-before-push")
        if self.rendered:
            self._call("wizard-rock-before-frame", lambda: self.session.screenshot("wizard-rock-before.png"))
        for attempt in range(3):
            state = self.observe("wizard-rock-push-%d" % attempt)
            rock = self._entity("s1-roc", state)
            if rock is None:
                raise RouteFailure("rock disappeared during push", "game suspected")
            self._aim(state, (float(rock["x"]), float(rock["y"])), "wizard-rock-east-facing")
            state = self._call("wizard-rock-forward-push", lambda: self.session.hold("forward", 120))
            if int(state.get("globals", {}).get("rock_placement", 0)) == 1:
                state = self.dialogue(require_release=True)
                return self.checkpoint("wizard-rock-pushed", state)
        # This is a source-defined interaction, not a complaint that one
        # direction is obstructed: strength and east-side approach are checked,
        # then six seconds of normal forward input must invoke S1-ROC.push.
        raise RouteFailure("ordinary east-facing push did not run S1-ROC.push or set rock_placement=1 after 360 frames", "game suspected")

    def fight_bonca(self) -> dict[str, Any]:
        """Use the game's starter bow, live aiming, and bounded attack presses."""
        self._call("bonca-open-equipment", lambda: self.session.hold("inventory", 1))
        self.equip_item("item-b1", "Bow")
        for shot in range(60):
            state = self.observe("bonca-live-%d" % shot)
            if int(state.get("globals", {}).get("wizard_see", 0)) == 3:
                return self.checkpoint("wizard-bonca-defeated", state)
            if int(state.get("globals", {}).get("life", 0)) < 1 or state.get("page") == "dead":
                raise RouteFailure("Bonca fight killed the player; combat route incomplete")
            enemy = self._entity("s1-cavem", state)
            if enemy is None:
                raise RouteFailure("Bonca absent before its source death flag", "game suspected")
            target = float(enemy["x"]), float(enemy["y"])
            self._aim(state, target, "bonca-live")
            distance = math.hypot(float(state["x"]) - target[0], float(state["y"]) - target[1])
            if distance < 80:
                self._call("bonca-retreat", lambda: self.session.hold("back", 12))
            self._call("bonca-shot", lambda: self.session.hold("attack", 1))
            self._call("bonca-flight", lambda: self.session.wait(30))
            self.dialogue(require_release=True)
        raise RouteFailure("bounded normal bow route did not defeat Bonca")

    def wizard_reward(self) -> dict[str, Any]:
        self.travel_route([99, 131], "wizard-cave-return")
        self._warp(131, 277, (288.0, 397.0), "wizard-leave-cave")
        self.travel_route([309, 341, 340, 372, 373, 374, 375, 376, 377, 378, 346, 314, 315, 283, 251], "wizard-reward-road")
        self.navigate(251, (264.0, 345.0), "wizard-reward-door")
        self._warp(251, 6, (264.0, 319.0), "wizard-reward-enter")
        self.navigate(6, (346.0, 220.0), "wizard-scroll-approach")
        before = self.observe("wizard-reward-before")
        self.talk_to_script("s1-mh-f", "wizard-scroll")
        state = self.await_lines(self.WIZARD_REWARD_LINES, limit=200, capture="wizard-scroll-reward")
        state = self.await_scripts_clear(state, "wizard-reward")
        globals_ = state.get("globals", {})
        if int(globals_.get("wizard_see", 0)) != 4 or int(globals_.get("gold", 0)) != int(before["globals"].get("gold", 0)) + 200 or not any(item.get("script") == "item-fb" for item in state.get("magic_inventory", [])):
            raise RouteFailure("wizard scroll did not grant earned 200 gold and fireball", "game suspected")
        return self.earned_save("wizard-reward")

    def terris_arrival(self) -> dict[str, Any]:
        state = self.await_lines(self.TERRIS_LINES, limit=300, capture="terris-maria-arrival")
        state = self.await_scripts_clear(state, "terris-arrival")
        expected = {"story": 7, "s2-aunt": 1, "letter": 2, "s2-map": 1}
        if int(state.get("screen", -1)) != 36 or any(int(state.get("globals", {}).get(k, -1)) != v for k, v in expected.items()):
            raise RouteFailure("Maria arrival did not finish on map 36 with story=7 and s2-aunt=1", "game suspected")
        return self.checkpoint("terris-arrival-complete", state)

    def letter_guard(self) -> dict[str, Any]:
        current = self.observe("letter-entry")
        if int(current.get("screen", -1)) != 439 or int(current.get("globals", {}).get("story", 0)) != 5:
            raise RouteFailure("letter route requires the completed story-5 home aftermath", "bot/incomplete")
        # The guard is reached through the same north road used by the
        # completed AlkTree route.  This deliberately uses live map transitions
        # and the actor's source coordinates instead of a map fixture.
        # Take the open east side first; the cottage doorway and west road can
        # retrigger the home script when the route crosses the doorway.
        self._walk_point(439, (560.0, 326.0), 24.0, "letter-home-east-road")
        self._cross(440, "letter-to-east-road", (650.0, 280.0))
        self._walk_point(440, (60.0, 230.0), 8.0, "letter-east-road-west")
        self._walk_point(440, (60.0, 20.0), 8.0, "letter-east-road-north")
        self._cross(408, "letter-to-north-gate", (60.0, -50.0))
        state = self._walk_point(408, (451.0, 108.0), 28.0, "letter-guard")
        if int(state.get("screen", -1)) != 408:
            raise RouteFailure("letter guard route did not reach map 408")
        if int(state.get("globals", {}).get("story", 0)) != 5 or int(state.get("globals", {}).get("vision", 0)) != 1:
            raise RouteFailure("letter guard entered with unexpected story/vision", "game suspected")
        guard = self._entity("s1-gg", state)
        if guard is None or (float(guard.get("x", -1)), float(guard.get("y", -1))) != (451.0, 108.0):
            raise RouteFailure("s1-gg guard is absent from its source position", "game suspected")
        # S1-GG performs two source move_stop calls before opening its first
        # line.  Send exactly one talk input and let await_lines own all later
        # dialogue advancement; retrying E here can start duplicate guard VM
        # tasks and repeat the first line.
        self._aim(state, (float(guard["x"]), float(guard["y"])), "letter-guard")
        self._call("talk-letter-guard", lambda: self.session.hold("talk", 1))
        state = self.await_lines([
            "Sorry about what happened Dink, I hope you're ok.",
            "Thanks, I'll be ok.",
            "By the way, a letter came for you.  It's at your house,",
            "you should go take a look at it.",
            "Thanks.",
        ], limit=180, capture="letter-guard-dialogue")
        if int(state.get("globals", {}).get("letter", 0)) != 1:
            raise RouteFailure("guard dialogue did not set letter=1", "game suspected")
        if state.get("frozen") or state.get("disabled") or state.get("nocontrol"):
            raise RouteFailure("guard dialogue controls remain blocked", "game suspected")
        self.checkpoint("letter-guard-complete", state)
        return state

    def letter_home(self) -> dict[str, Any]:
        # Return through the ordinary west edge and enter the cottage.  The
        # home script creates S1-LTR and performs the source map reload itself.
        # Renton's script moves Dink to y=190. Walk south down the open gate
        # lane before turning west; the eastern perimeter remains solid.
        for i, point in enumerate(((450.0, 375.0), (60.0, 375.0), (60.0, 395.0))):
            self._walk_point(408, point, 8.0, "letter-return-gate-%d" % i)
        self._cross(440, "letter-return-east-road", (60.0, 650.0))
        self._walk_point(440, (60.0, 230.0), 8.0, "letter-return-west-road")
        self._cross(439, "letter-return-cottage-road", (-50.0, 230.0))
        self._walk_point(439, (560.0, 326.0), 8.0, "letter-door-east")
        self._warp(439, 1, (368.0, 280.0), "letter-enter-home")
        return self.letter_read()

    def letter_read(self) -> dict[str, Any]:
        state = self.await_lines(self.LETTER_LINES, limit=420, capture="letter-dialogue")
        # Fade/load transitions can release controls before the persistent VM
        # task has removed itself.  Give that bounded source task a chance to
        # settle before classifying it as a stuck script.
        state = self.await_scripts_clear(state, "letter")
        globals_ = state.get("globals", {})
        if int(globals_.get("letter", 0)) != 2 or int(globals_.get("story", 0)) != 6:
            raise RouteFailure("letter script did not finish with story=6 and letter=2", "game suspected")
        if int(globals_.get("s2-map", 0)) != 1:
            raise RouteFailure("letter script did not set s2-map=1", "game suspected")
        if int(state.get("screen", -1)) != 439 or int(globals_.get("vision", 0)) != 2:
            raise RouteFailure("letter script did not return to exterior map 439 vision 2", "game suspected")
        scripts = state.get("scripts", {})
        if scripts.get("dialogue_busy") or int(scripts.get("vm_live_tasks", 0)) != 0:
            raise RouteFailure("letter script task remains active", "game suspected")
        if state.get("frozen") or state.get("disabled") or state.get("nocontrol"):
            raise RouteFailure("letter script controls remain blocked", "game suspected")
        self.checkpoint("letter-complete", state)
        # BUTTON6.c is the original map display path.  Open and close through
        # the same ordinary M action, recording the actual UI page both times.
        opened = self._call("letter-open-map", lambda: self.session.hold("map", 1))
        if opened.get("page") != "map" or opened.get("ui", {}).get("page") != "map":
            raise RouteFailure("M input did not open the world map", "game suspected")
        if self.rendered:
            self._call("screenshot-aunt-maria-map", lambda: self.session.screenshot("aunt-maria-map.png"))
        self.checkpoint("letter-map-open", opened)
        blocked = self._call("letter-map-movement-blocked", lambda: self.session.hold("forward", 8))
        if blocked.get("page") != "map" or (blocked.get("x"), blocked.get("y")) != (opened.get("x"), opened.get("y")):
            raise RouteFailure("player moved while world map was open", "game suspected")
        closed = self._call("letter-close-map", lambda: self.session.hold("map", 1))
        if closed.get("page") != "game" or closed.get("ui", {}).get("page") != "game":
            raise RouteFailure("M input did not close the world map", "game suspected")
        if closed.get("frozen") or closed.get("disabled") or closed.get("nocontrol"):
            raise RouteFailure("controls were not released after map close", "game suspected")
        self.checkpoint("letter-map-closed", closed)
        return closed

    def alktree_depart(self) -> dict[str, Any]:
        """Collect one nut through the original tree/nut scripts.

        This route starts only after the earned Ethel return-home conversation.
        The tree's hit handler creates the nut; the runner never creates an
        item or changes a quest flag itself.
        """
        home = self.observe("alktree-prerequisites")
        globals_ = home.get("globals", {})
        required = {"story": 2, "pig_story": 1, "old_womans_duck": 4}
        if any(int(globals_.get(name, -1)) != value for name, value in required.items()):
            raise RouteFailure("AlkTree route requires earned Ethel prerequisites", "bot/incomplete")
        if not any("some AlkTree nuts" in line for line in home.get("recent_dialogue", [])):
            raise RouteFailure("AlkTree route lacks the observed Ethel request dialogue", "bot/incomplete")

        # Select Fists through the ordinary equipment panel.  The original
        # tree only creates a nut from its hit procedure; walking into it or
        # carrying a later weapon is not evidence that this procedure ran.
        self._call("alktree-open-inventory", lambda: self.session.hold("inventory", 1))
        self.equip_item("item-fst", "Fists")
        equipped = self.observe("alktree-fists-equipped")
        # item-fst is equipment slot 1 in the imported original inventory.
        if int(equipped.get("globals", {}).get("cur_weapon", -1)) != 1:
            raise RouteFailure("ordinary Fists selection did not equip Fists", "game suspected")

        # Story 2 opens the north gate (S1-GATE hides vision-1 Renton).
        # The village's east/south perimeter is solid; reach the ordinary
        # map-474 tree from the woods outside that perimeter.
        self._walk_point(1, (325.0, 437.0), 24.0, "alktree-home-exit")
        self._cross(439, "alktree-to-cottage-road", (325.0, 650.0))
        self._cross(440, "alktree-to-east-road", (650.0, 280.0))
        self._walk_point(440, (60.0, 230.0), 12.0, "alktree-north-road-west")
        self._walk_point(440, (60.0, 20.0), 12.0, "alktree-north-road")
        return self._cross(408, "alktree-to-gate", (60.0, -50.0))

    def alktree_woods(self) -> dict[str, Any]:
        for i, point in enumerate(((60.0, 375.0), (450.0, 375.0), (450.0, 5.0))):
            self._walk_point(408, point, 3.0, "alktree-gate-%d" % i)
        self._cross(376, "alktree-outside-gate", (450.0, -50.0))
        state = self.await_lines(self.WIZARD_LINES, limit=350, capture="wizard-introduction")
        self.checkpoint("wizard-introduction-complete", state)
        self._cross(377, "alktree-forest-east", (650.0, 200.0))
        self._cross(409, "alktree-forest-south", (320.0, 650.0))
        self._cross(410, "alktree-outside-village", (650.0, 20.0))
        self._cross(442, "alktree-east-woods", (320.0, 650.0))
        # The central tree cluster has irregular source hardness. The observed
        # collision grid leaves a broad clear lane down the western side.
        for i, point in enumerate(((90.0, 10.0), (90.0, 325.0), (125.0, 325.0),
                                   (125.0, 335.0), (320.0, 335.0), (320.0, 395.0))):
            self._walk_point(442, point, 3.0, "alktree-woods-lane-%d" % i)
        return self._cross(474, "alktree-to-tree-screen", (320.0, 650.0))

    def alktree_pickup(self) -> dict[str, Any]:
        state = self._walk_point(474, (428.0, 109.0), 28.0, "alktree-tree")
        tree = self._entity("s1-ntree", state)
        if tree is None or (float(tree.get("x", -1)), float(tree.get("y", -1))) != (428.0, 109.0):
            raise RouteFailure("ordinary map 474 AlkTree is absent at its source position", "game suspected")
        self._aim(state, (428.0, 109.0), "alktree-hit")
        if self.rendered:
            self._call("screenshot-alktree", lambda: self.session.screenshot("alktree-hit.png"))
        self._call("alktree-hit", lambda: self.session.hold("attack", 1))
        nut = None
        previous = None
        stable = 0
        for _ in range(50):
            state = self._call("alktree-fall-wait", lambda: self.session.wait(15))
            # A random drop can touch Dink before we ever observe it settled.
            # Validate the earned item and source response instead of waiting
            # for a sprite that the successful pickup has already removed.
            if int(state.get("globals", {}).get("nuttree", 0)) == 1:
                return self._accept_nut_pickup(state)
            nut = self._entity("s1-nut", state)
            if nut is None:
                continue
            position = (float(nut["x"]), float(nut["y"]))
            stable = stable + 1 if position == previous else 0
            previous = position
            if stable >= 2:
                break
        if nut is None or stable < 2:
            raise RouteFailure("AlkTree hit did not produce a settled observable nut")
        # The first sighting is still falling at y=86. Observe the landing
        # before approaching, and go around the tree's northern scenery.
        self._walk_point(474, (380.0, 210.0), 8.0, "alktree-nut-south-aisle")
        self._walk_point(474, (float(nut["x"]), 210.0), 5.0, "alktree-nut-below")
        stalled = 0
        for _ in range(45):
            state = self.observe("alktree-live-pickup")
            if int(state.get("globals", {}).get("nuttree", 0)) == 1:
                break
            nut = self._entity("s1-nut", state)
            if nut is None:
                raise RouteFailure("nut disappeared before an observed pickup")
            target = (float(nut["x"]), float(nut["y"]))
            self._aim(state, target, "alktree-live-nut")
            distance = math.hypot(float(state["x"]) - target[0], float(state["y"]) - target[1])
            after = self._call("alktree-touch-step", lambda: self.session.hold("forward", 1 if distance < 12 else 4))
            moved = math.hypot(float(after["x"]) - float(state["x"]), float(after["y"]) - float(state["y"]))
            stalled = stalled + 1 if moved < 0.2 else 0
            if stalled >= 5:
                raise RouteFailure("observed nut landing is obstructed; another normal hit may be needed")
        state = self.observe("alktree-pickup-complete")
        return self._accept_nut_pickup(state)

    def _accept_nut_pickup(self, state: dict[str, Any]) -> dict[str, Any]:
        if int(state.get("globals", {}).get("nuttree", 0)) != 1:
            raise RouteFailure("normal walking did not collect the observed nut")
        if int(state.get("globals", {}).get("story", 0)) != 3:
            raise RouteFailure("nut pickup did not advance story through s1-nut", "game suspected")
        if not any(str(item.get("script", "")).lower() == "item-nut" for item in state.get("inventory", [])):
            raise RouteFailure("nut pickup did not grant item-nut", "game suspected")
        if "I picked up a nut!" not in state.get("recent_dialogue", []):
            raise RouteFailure("nut pickup lacks its original script response", "game suspected")
        self.checkpoint("alktree-nut-collected", state)
        if self.rendered:
            self._call("screenshot-nut-collected", lambda: self.session.screenshot("nut-collected.png"))
        return state

    def alktree_return(self) -> dict[str, Any]:
        # Returning with story 3 first runs the exterior's two-line fire
        # reaction (S1-H1-O), then entering home runs S1-H1-S's five grief
        # lines.  Leaving the home again runs S1-H1-O's six-neighbour scene.
        # Keep the stages separate: a later story value cannot stand in for
        # dialogue the runner did not observe.
        self._cross(442, "alktree-return-north-woods", (320.0, -50.0))
        for i, point in enumerate(((320.0, 335.0), (125.0, 335.0), (125.0, 325.0),
                                   (90.0, 325.0), (90.0, 20.0))):
            self._walk_point(442, point, 3.0, "alktree-return-woods-lane-%d" % i)
        self._cross(410, "alktree-return-east-woods", (90.0, -50.0))
        state = self.await_lines(self.LYNA_LINES, limit=350, capture="lyna-milder",
                                 line_captures={self.LYNA_LINES[2]: "lyna-speaking"})
        if int(state.get("globals", {}).get("nuttree", 0)) != 2:
            raise RouteFailure("Milder/Lyna scene did not finish its departure", "game suspected")
        self.checkpoint("lyna-milder-complete", state)
        return self.alktree_home()

    def alktree_home(self) -> dict[str, Any]:
        self._walk_point(410, (60.0, 20.0), 8.0, "alktree-return-north-lane")
        self._cross(409, "alktree-return-outside-village", (-50.0, 20.0))
        self._cross(377, "alktree-return-forest-north", (320.0, -50.0))
        self._cross(376, "alktree-return-forest-west", (-50.0, 200.0))
        self._walk_point(376, (450.0, 390.0), 8.0, "alktree-return-gate-approach")
        self._cross(408, "alktree-return-gate", (450.0, 650.0))
        for i, point in enumerate(((450.0, 375.0), (60.0, 375.0), (60.0, 395.0))):
            self._walk_point(408, point, 3.0, "alktree-return-gate-%d" % i)
        self._cross(440, "alktree-return-east-road", (60.0, 650.0))
        self._walk_point(440, (60.0, 230.0), 8.0, "alktree-return-west-road")
        self._cross(439, "alktree-return-cottage-road", (-50.0, 230.0))
        exterior = self.await_lines([
            "What, the house, mother nooooo!!!",
            "She's still in there!!",
        ], capture="alktree-fire")
        if int(exterior.get("globals", {}).get("story", 0)) != 3:
            raise RouteFailure("home exterior fire scene changed story before its source completion", "game suspected")
        self.checkpoint("alktree-home-fire", exterior)
        self._walk_point(439, (560.0, 326.0), 8.0, "alktree-fire-door-east")
        self._warp(439, 1, (368.0, 280.0), "alktree-return-home")
        # S1-H1-S moves the frozen player through the doorway after the fifth
        # grief line.  The host preserves that scripted move and starts
        # S1-H1-O outside, so require both stages as one uninterrupted trace.
        aftermath = self.await_lines([
            "Mother noooooo!",
            "Mother, you can't die, nooo I  I ...",
            "never knew how much I really cared about you",
            "until now.",
            "Ahh, too much smoke .... gotta get out ...",
            "Dink!!!",
            "I .. I couldn't save her",
            "I was too late.",
            "It's not your fault Dink.",
            "There was nothing you could do..",
            "Don't blame yourself kid.",
        ], limit=350, capture="alktree-grief", line_captures={
            "Mother, you can't die, nooo I  I ...": "mother-fire-interior",
            "It's not your fault Dink.": "neighbors-aftermath",
        })
        # force_vision resets the incoming map before the final fade-up wait.
        # Demand the source task's completion, not that temporary release gap.
        for _ in range(12):
            if not aftermath.get("scripts", {}).get("dialogue_busy") and not aftermath.get("scripts", {}).get("vm_live_tasks"):
                break
            aftermath = self._call("aftermath-settle", lambda: self.session.wait(3))
        if int(aftermath.get("globals", {}).get("story", 0)) != 5:
            raise RouteFailure("AlkTree aftermath did not complete story=5", "game suspected")
        if int(aftermath.get("globals", {}).get("vision", 0)) != 2 or int(aftermath.get("screen", -1)) != 439:
            raise RouteFailure("AlkTree aftermath did not reach outdoor vision 2", "game suspected")
        scripts = aftermath.get("scripts", {})
        if scripts.get("dialogue_busy") or int(scripts.get("vm_live_tasks", 0)) != 0:
            raise RouteFailure("AlkTree aftermath script task remains active", "game suspected")
        self.checkpoint("alktree-aftermath-complete", aftermath)
        if self.rendered:
            self._call("screenshot-aftermath-complete", lambda: self.session.screenshot("aftermath-complete.png"))
        return aftermath

    def run_from_title(self) -> None:
        self.menu_button("Begin adventure")
        self.dialogue(require_release=True, capture="opening-dialogue")
        opening = self.checkpoint("opening")
        if int(opening.get("globals", {}).get("story", 0)) != 1 or opening.get("recent_dialogue", [])[-3:] != ["Dink, would you go feed the pigs?", "What, now?", "YES, NOW."]:
            raise RouteFailure("opening did not complete its three normal story lines", "game suspected")
        self.move_to("sack")
        self.dialogue()
        sack = self.checkpoint("sack-collected")
        if not any(str(item.get("script", "")).lower() == "item-pig" for item in sack.get("inventory", [])):
            raise RouteFailure("touching s1-sack did not grant item-pig", "game suspected")
        self.move_to("cottage_exit")
        self.seek_screen(439, "to-cottage")
        self.move_to("cottage_inside")
        self.dialogue()
        # Inventory is opened with the ordinary I key.  The bridge reports the
        # equipment buttons, allowing selection without injecting cur_weapon.
        self._call("open-inventory", lambda: self.session.hold("inventory", 1))
        self.equip_item("item-pig", "Pig Feed")
        self.seek_screen(407, "to-pig-farm")
        self.move_to("pig_farm")
        # The item-pig script accepts the feed only from its in-world box. Aim
        # north from the live point, with the source script's (+8, -50) offset.
        state = self.observe("pig-feed-position")
        if not (200.0 <= float(state["x"]) <= 400.0 and 180.0 <= float(state["y"]) <= 306.0):
            raise RouteFailure("did not reach the item-pig feed box", "harness")
        self._aim(state, (float(state["x"]) + 8.0, float(state["y"]) - 50.0), "pig-feed-north")
        # Attack is an ordinary left-click equivalent in the bridge.  Hold
        # briefly, then allow the scripted bully dialogue to finish normally.
        self._call("scatter-feed", lambda: self.session.hold("attack", 1))
        state = self.await_global("pig_story", 1, capture="milder-dialogue")
        self.checkpoint("pig-story", state)
        # Return through the actual edges: pig farm -> cottage -> home.
        # Return through the same west gate, then the open north edge of map
        # 439; do not run through the intentionally solid southern pigpen rail.
        for number, point in enumerate(((110.0, 270.0), (110.0, 390.0))):
            self._walk_point(407, point, 26.0, "return-gate-%d" % number)
        self.seek_screen(439, "return-cottage")
        for number, point in enumerate(((110.0, 20.0), (560.0, 20.0), (560.0, 326.0), (368.0, 280.0))):
            state = self._walk_point(439, point, 14.0 if number == 3 else 30.0, "return-home-%d" % number)
            if int(state.get("screen", -1)) == 1: break
        if int(state.get("screen", -1)) != 1:
            raise RouteFailure("normal return route did not enter home map")
        state = self.talk_to_mother()
        if not any("Tell her you fed the pigs" in str(button.get("text", "")) for button in state.get("ui", {}).get("buttons", [])):
            raise RouteFailure("mother dialogue did not expose the fed-pigs choice")
        self.menu_button("Tell her you fed the pigs")
        state = self.dialogue(120, require_release=True, capture="home-completion")
        completion = state.get("recent_dialogue", [])
        if not any("finished with my chores" in line.lower() for line in completion) or not any("good boy" in line.lower() for line in completion):
            raise RouteFailure("mother conversation did not complete the fed-pigs path", "game suspected")
        self.checkpoint("mother-fed-pigs")
        if self.milestone in {"ethel", "alktree", "letter", "terris"}:
            self.run_ethel()
        if self.milestone in {"alktree", "letter", "terris"}:
            self.run_alktree()
        if self.milestone in {"letter", "terris"}:
            self.run_letter()
        if self.milestone == "terris":
            self.run_terris()

    def run(self) -> dict[str, Any]:
        state = self.checkpoint("title")
        if not state.get("ui", {}).get("title", False):
            raise RouteFailure("campaign did not start at title screen", "harness")
        if self.resume_letter is None:
            self.run_from_title()
        else:
            self.menu_button("Continue adventure")
            state = self._call("resume-letter-settle", lambda: self.session.wait(3))
            expected = self.resume_letter.get("resume_checkpoint")
            if expected is None:
                expected = self.resume_letter["checkpoints"]["save-reload"]
            if not saved_state_matches(expected, state):
                raise RouteFailure("normal Load did not restore the recorded earned LETTER save", "harness")
            self.checkpoint("resume-earned-letter", state)
            self.run_terris()
        # Stable point: use pause menu save, then load, and verify state survives.
        before_save = self.observe("save-before")
        if self.rendered:
            self._call("screenshot-before-save", lambda: self.session.screenshot("before-save.png"))
        self._call("pause-for-save", self.session.pause)
        self.menu_button("Save adventure")
        # Saving leaves the pause UI open. Resume, move, then reopen it before
        # loading so the load assertion proves a real restore.
        self._call("resume-after-save", self.session.pause)
        self._call("move-after-save", lambda: self.session.hold("back", 8))
        moved_after_save = self.observe("save-moved-away")
        self._call("pause-for-load", self.session.pause)
        self.menu_button("Load saved adventure")
        self._call("settle-after-load", lambda: self.session.wait(1))
        reloaded = self.checkpoint("save-reload")
        if (self.milestone != "terris" and not before_save.get("render_geometry", {}).get("structural_models")) or reloaded.get("render_geometry") != before_save.get("render_geometry"):
            raise RouteFailure("save/reload changed structural meshes or colliders", "game suspected")
        if (not saved_state_matches(before_save, reloaded) or
                (moved_after_save.get("x"), moved_after_save.get("y")) == (before_save.get("x"), before_save.get("y"))):
            raise RouteFailure("save/reload did not restore actual position, inventory, and quest state", "game suspected")
        self._call("pause-check", self.session.pause)
        if self.rendered:
            self._call("screenshot-pause", lambda: self.session.screenshot("pause.png"))
        before = self.observe("paused-before-move")
        if not before.get("modal") or before.get("page") != "pause":
            raise RouteFailure("pause input did not open the pause menu", "game suspected")
        self._call("move-while-paused", lambda: self.session.hold("back", 8))
        during = self.observe("paused-after-move")
        if not during.get("modal") or during.get("page") != "pause" or (before.get("x"), before.get("y")) != (during.get("x"), during.get("y")):
            raise RouteFailure("player moved while paused", "game suspected")
        self._call("resume-check", self.session.pause)
        before_resume = self.observe("resumed-before-move")
        self._call("move-after-resume", lambda: self.session.hold("back", 8))
        resumed = self.checkpoint("resumed")
        if resumed.get("modal") or (before_resume.get("x"), before_resume.get("y")) == (resumed.get("x"), resumed.get("y")):
            raise RouteFailure("player did not move after pause resume", "game suspected")
        self._call("pause-for-title", self.session.pause)
        self.menu_button("Title screen")
        # The final activation intentionally ends the bridge process, so use
        # its expected-exit API rather than asking _call for telemetry.
        quit_state = self.observe("quit-menu")
        if not any(button.get("text") == "Quit" for button in quit_state.get("ui", {}).get("buttons", [])):
            raise RouteFailure("title menu did not expose Quit", "harness")
        # Title screen starts with Begin adventure focused; record each normal
        # Down input as it changes focus, then demand process exit on Enter.
        while not any(button.get("text") == "Quit" and button.get("focused") for button in quit_state.get("ui", {}).get("buttons", [])):
            quit_state = self._call("quit-menu-down", lambda: self.session.menu_key("down"))
        exit_result = self.session.exit_via_menu()
        self.trace.append({"label": "quit", "after": exit_result, "ok": bool(exit_result.get("ok")), "error": exit_result.get("error")})
        if not exit_result.get("ok"):
            raise RouteFailure("menu quit returned nonzero exit code", "game suspected")
        return {"ok": True, "verdict": "pass", "checkpoints": self.checkpoints,
                "trace": self.trace, "commands": self.commands}


def earned_letter_source(report: Path) -> tuple[dict[str, Any], Path, dict[str, Any]]:
    """Continue recorded normal play, never accept a standalone save fixture."""
    source = json.loads(report.read_text())
    if not isinstance(source, dict):
        raise ValueError("continuation report must be a JSON object")
    setup = source.get("startup", {}).get("setup", {})
    checkpoints = source.get("checkpoints", {})
    partial = (source.get("ok") is False and source.get("milestone") == "terris"
               and "terris-letter-earned-save" in checkpoints)
    if (source.get("ok") is not True and not partial) or setup.get("mode") != "campaign" or setup.get("test_mode") is not False or setup.get("load_map_scripts") is not True:
        raise ValueError("continuation requires a real campaign report with an earned LETTER save")
    checkpoint_name = "terris-letter-earned-save" if partial else "save-reload"
    if "letter-complete" not in checkpoints or checkpoint_name not in checkpoints:
        raise ValueError("continuation lacks earned LETTER and its recorded save checkpoint")
    state = checkpoints[checkpoint_name]
    required = {"story": 6, "letter": 2, "s2-map": 1, "s2-aunt": 0}
    if int(state.get("screen", -1)) != 439 or any(int(state.get("globals", {}).get(k, -1)) != v for k, v in required.items()):
        raise ValueError("continuation save is not the completed LETTER state")
    session = Path(source["session_dir"]).resolve()
    if session.parent != report.with_suffix(".session").resolve():
        raise ValueError("continuation save must belong to the report's isolated session")
    save = session / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    if not save.is_file() or not save.resolve().is_relative_to(session):
        raise ValueError("earned campaign save is absent from the isolated session")
    digest = hashlib.sha256(save.read_bytes()).hexdigest()
    if source.get("earned_save_sha256") is not None and source["earned_save_sha256"] != digest:
        raise ValueError("earned campaign save no longer matches its recorded hash")
    if partial:
        # A later route failure does not invalidate its earlier earned save.
        # Bind the actual serialized state before allowing normal Load, and
        # preserve the source report's failed outcome in provenance.
        data = json.loads(save.read_text())
        player = data.get("entities", {}).get("1", {})
        coordinates = [player.get("x"), player.get("y")]
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in coordinates):
            raise ValueError("partial route save has invalid player coordinates")
        # The bridge emits a Vector2 (float32), while saved entities retain
        # their scalar double precision. Compare in the bridge's representation.
        x, y = [struct.unpack("<f", struct.pack("<f", v))[0] for v in coordinates]
        saved = {"screen": data.get("screen"), "x": x, "y": y,
                 "inventory": data.get("items"), "magic_inventory": data.get("magic_items"),
                 "globals": data.get("vm", {}).get("globals", {})}
        observed = dict(state)
        for key in ("x", "y"):
            observed[key] = struct.unpack("<f", struct.pack("<f", float(state[key])))[0]
        if not saved_state_matches(observed, saved):
            raise ValueError("partial route save does not match its earned LETTER checkpoint")
        source["resume_checkpoint"] = state
    return source, save, {"source_report": str(report.resolve()),
                          "source_report_sha256": hashlib.sha256(report.read_bytes()).hexdigest(),
                          "earned_save": str(save),
                          "earned_save_sha256": digest,
                          "source_ok": source.get("ok"), "earned_checkpoint": checkpoint_name,
                          "digest_binding": "recorded" if source.get("earned_save_sha256") else "legacy; verify loaded checkpoint"}


def run(rendered: bool, report: Path, max_commands: int, milestone: str = "opening",
        resume_letter_report: Path | None = None) -> dict[str, Any]:
    session_dir = report.with_suffix(".session")
    campaign: Campaign | None = None
    session: PlaytestSession | None = None
    provenance = None
    try:
        source = None
        save_source = None
        if resume_letter_report is not None:
            if milestone != "terris":
                raise ValueError("earned LETTER continuation requires --milestone terris")
            source, save_source, provenance = earned_letter_source(resume_letter_report)
        with PlaytestSession(session_dir=session_dir, rendered=rendered, mode="campaign", save_source=save_source, timeout=60.0) as session:
            campaign = Campaign(session, rendered, max_commands)
            campaign.milestone = milestone
            campaign.resume_letter = source
            try:
                result = campaign.run()
            except RouteFailure:
                if rendered:
                    try:
                        session.screenshot("failure.png")
                    except (RuntimeError, TimeoutError, OSError, ValueError) as frame_error:
                        campaign.trace.append({"label": "failure-frame", "ok": False, "error": str(frame_error)})
                raise
            result["startup"] = session.startup
            result["milestone"] = milestone
            result["continuation"] = provenance
            result["session_dir"] = str(session.session_dir)
        saved = session.session_dir / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
        if saved.is_file():
            result["earned_save_sha256"] = hashlib.sha256(saved.read_bytes()).hexdigest()
        return result
    except RouteFailure as exc:
        return {"ok": False, "verdict": "game suspected" if exc.kind == "game suspected" else "inconclusive",
                "failure_class": exc.kind, "error": str(exc), "milestone": milestone,
                "continuation": provenance, "startup": session.startup if session else None,
                "trace": campaign.trace if campaign else [],
                "checkpoints": campaign.checkpoints if campaign else {},
                "commands": campaign.commands if campaign else 0,
                "session_dir": str(session.session_dir) if session else str(session_dir)}
    except (RuntimeError, TimeoutError, OSError, ValueError, KeyError) as exc:
        return {"ok": False, "verdict": "inconclusive", "failure_class": "harness", "error": str(exc), "milestone": milestone,
                "continuation": provenance, "startup": session.startup if session else None,
                "trace": campaign.trace if campaign else [],
                "checkpoints": campaign.checkpoints if campaign else {},
                "commands": campaign.commands if campaign else 0,
                "session_dir": str(session.session_dir) if session else str(session_dir)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a deterministic campaign milestone")
    parser.add_argument("--rendered", action="store_true", help="retain selected rendered screenshots")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--max-commands", type=int,
                        help="input command budget (default 12000 for Terris, 900 otherwise)")
    parser.add_argument("--milestone", choices=("opening", "ethel", "alktree", "letter", "terris"), default="opening",
                        help="opening, Ethel, AlkTree, letter, or Terris arrival (allow ~12000 commands)")
    parser.add_argument("--resume-letter-report", type=Path,
                        help="normal Load of an earned LETTER save, including a later failed Terris route")
    args = parser.parse_args()
    budget = args.max_commands if args.max_commands is not None else (12000 if args.milestone == "terris" else 900)
    result = run(args.rendered, args.report, max(1, budget), args.milestone, args.resume_letter_report)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    # The report retains the complete telemetry trace.  Keep stdout compact so
    # a failed campaign is still practical to inspect in CI logs.
    print(json.dumps({key: result.get(key) for key in ("ok", "verdict", "failure_class", "error", "commands", "session_dir")}, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
