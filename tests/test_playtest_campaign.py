import hashlib
import json
import math

import pytest

from tools.playtest_campaign import Campaign, RouteFailure, clearance_grid, earned_letter_source, grid_path, saved_state_matches
from tools.playtest import PlaytestSession


class DelayedDialogue:
    """Bridge fixture: only wait/input advances state, never an observation."""

    def __init__(self, states):
        self.states = states
        self.index = 0
        self.waits = 0

    def observe(self):
        return {"ok": True, "telemetry": self.states[self.index]}

    def wait(self, frames):
        self.waits += 1
        self.index = min(self.index + 1, len(self.states) - 1)
        return self.observe()

    def menu_key(self, key):
        assert key == "enter"
        return self.observe()


def test_feed_waypoint_tolerance_fits_the_actual_item_pig_acceptance_box():
    screen, points, radius = Campaign.WAYPOINTS["pig_farm"]
    x, y = points[-1]
    assert screen == 407
    # The whole accepted waypoint disk must lie in ITEM-PIG's trigger box,
    # including approaches from either side and changed seam landing positions.
    assert 200 <= x - radius <= x + radius <= 400
    assert 180 <= y - radius <= y + radius <= 306


def test_native_grid_step_api_rejects_non_integral_or_unbounded_sampling():
    session = object.__new__(PlaytestSession)
    session.request = lambda command, **fields: {"command": command, **fields}
    for step in (1, 5):
        assert session.navigation_grid(step)["step"] == step
    for step in (0, 2, True, 1.0, -1, 100):
        with pytest.raises(ValueError, match="1 or 5"):
            session.navigation_grid(step)


def test_native_pixel_barrier_and_waypoint_tolerance_both_constrain_the_plan():
    rows = ["." * 41] * 21
    rows[8] = "." * 20 + "#" * 11 + "." * 10
    raw = {"screen": 378, "rows": rows, "step": 1, "origin": [0, 0]}
    planned = clearance_grid(raw)
    assert planned["planning_clearance"] == 3  # 2px waypoint tolerance + 1px sample.
    assert raw["rows"][8][30] == "#"  # Input observations remain intact.
    path = grid_path(planned, (25, 15), (25, 3))
    assert any(x >= 34 for x, y in path)
    assert path[-1] == (25, 3)
    for x, y in path:
        assert all(raw["rows"][yy][xx] == "."
                   for yy in range(y - 3, y + 4) for xx in range(x - 3, x + 4))


def test_disconnected_edge_candidate_is_rejected_before_expensive_search(monkeypatch):
    raw = {"rows": ["." * 30 + "#" + "." * 30] * 21, "step": 1, "origin": [0, 0]}
    planned = clearance_grid(raw)
    monkeypatch.setattr("tools.playtest_campaign.heapq.heappop",
                        lambda _: pytest.fail("disconnected candidate reached A*"))
    with pytest.raises(RouteFailure, match="no route"):
        grid_path(planned, (25, 15), (40, 15))


@pytest.mark.parametrize("scale", [0.5, 1.0, 800 / 540, 3.0])
@pytest.mark.parametrize("yaw", [0.0, math.pi - 0.01, -math.pi + 0.01, 4 * math.pi + 1.5])
def test_aim_faces_target_before_walking_despite_viewport_scaling(scale, yaw):
    class MouseSession:
        def __init__(self):
            self.state = {"x": 268.57, "y": 392.63, "yaw": yaw}

        def observe(self):
            return {"ok": True, "telemetry": dict(self.state)}

        def look(self, dx, dy):
            assert abs(dx) <= 2000 and dy == 0
            self.state["yaw"] -= dx * 0.002 * scale
            return self.observe()

    session = MouseSession()
    campaign = Campaign(session)
    target = (500, 390)
    aimed = campaign._aim(dict(session.state), target, "scaled-door-approach")
    expected = math.atan2(-(500 - aimed["x"]), -(390 - aimed["y"]))
    assert abs(campaign._wrap(aimed["yaw"] - expected)) <= 0.002
    assert campaign.look_gain == pytest.approx(0.002 * scale)


def test_door_approach_stops_on_an_unexpected_map(monkeypatch):
    campaign = Campaign(DelayedDialogue([{"screen": 409, "x": 270, "y": 392}]))
    monkeypatch.setattr(campaign, "_walk_point", lambda *args: {"screen": 441})
    with pytest.raises(RouteFailure, match="entered unexpected map 441") as exc:
        campaign._walk_to_authored_door_trigger(409, 2, (397, 301), "ethel-return-house")
    assert exc.value.kind == "harness"


@pytest.mark.parametrize("capture_ready", [True, False])
def test_aim_allows_one_capture_tick_and_rejects_unresponsive_input(capture_ready):
    session = DelayedDialogue([{"x": 0, "y": 0, "yaw": 0}])
    session.observe = lambda: {"ok": True, "telemetry": dict(session.states[0])}
    looks = []

    def look(dx, dy):
        looks.append(dx)
        if capture_ready and len(looks) > 1:
            session.states[0]["yaw"] -= dx * 0.002
        return session.observe()

    session.look = look
    campaign = Campaign(session)
    if capture_ready:
        result = campaign._aim(dict(session.states[0]), (100, 0), "capture")
        assert abs(campaign._wrap(result["yaw"] + math.pi / 2)) <= 0.002
    else:
        with pytest.raises(RouteFailure, match="did not change yaw") as exc:
            campaign._aim(dict(session.states[0]), (100, 0), "capture")
        assert exc.value.kind == "harness"
        assert len(looks) == 2
    assert session.waits == 1


@pytest.mark.parametrize("has_item", [True, False])
def test_nut_collected_during_fall_does_not_require_a_settled_sprite(monkeypatch, has_item):
    before = {"screen": 474, "globals": {"story": 2, "nuttree": 0},
              "entities": [{"id": 2, "script": "s1-ntree", "x": 428, "y": 109, "active": 1}]}
    after = {"screen": 474, "globals": {"story": 3, "nuttree": 1}, "entities": [],
             "recent_dialogue": ["I picked up a nut!"],
             "inventory": [{"script": "item-nut"}] if has_item else []}
    session = DelayedDialogue([before, after])
    monkeypatch.setattr(session, "hold", lambda action, frames: session.observe(), raising=False)
    campaign = Campaign(session)
    monkeypatch.setattr(campaign, "_walk_point", lambda *args: before)
    monkeypatch.setattr(campaign, "_aim", lambda state, *args: state)
    if has_item:
        assert campaign.alktree_pickup() == after
        assert session.waits == 1
        assert campaign.checkpoints["alktree-nut-collected"] == after
    else:
        with pytest.raises(RouteFailure, match="did not grant item-nut"):
            campaign.alktree_pickup()


def state(lines=(), *, dialogue=False, frozen=False):
    return {"globals": {"story": 2}, "recent_dialogue": list(lines),
            "dialogue": dialogue, "frozen": frozen, "disabled": 0, "nocontrol": 0}


def test_cutscene_acceptance_waits_past_early_quest_flag_and_control_gap():
    session = DelayedDialogue([
        state(), state(),  # Quest flag has changed; the cutscene has not started.
        state(["first"], dialogue=True, frozen=True),
        state(["first", "last"], dialogue=True, frozen=True),
        state(["first", "last"], frozen=True),  # Final line alone is insufficient.
        state(["first", "last"]),
    ])
    result = Campaign(session).await_lines(["first", "last"], limit=10)
    assert session.index == 5 and session.waits == 5
    assert not result["frozen"] and not result["dialogue"]


def test_cutscene_acceptance_rejects_quest_flag_without_conversation():
    with pytest.raises(RouteFailure, match="observed 0/2 required lines"):
        Campaign(DelayedDialogue([state()])).await_lines(["first", "last"], limit=3)


def test_cutscene_acceptance_tracks_lines_across_the_five_line_telemetry_window():
    lines = [str(i) for i in range(6)]
    states = [state(lines[max(0, i - 4):i + 1], dialogue=True, frozen=True)
              for i in range(6)] + [state(lines[-5:])]
    session = DelayedDialogue(states)
    Campaign(session).await_lines(lines, limit=12)
    assert session.index == 6


def test_alktree_route_rejects_early_flags_without_earned_ethel_dialogue():
    session = DelayedDialogue([state()])
    with pytest.raises(RouteFailure, match="earned Ethel prerequisites"):
        Campaign(session).run_alktree()


def test_alktree_route_requires_observed_request_line_even_with_flags():
    s = state()
    s["globals"].update({"story": 2, "pig_story": 1, "old_womans_duck": 4})
    with pytest.raises(RouteFailure, match="observed Ethel request dialogue"):
        Campaign(DelayedDialogue([s])).run_alktree()


def test_alktree_aftermath_rejects_story_five_without_exterior_fire_lines():
    s = state()
    s["globals"].update({"story": 5, "vision": 2})
    s["screen"] = 439
    with pytest.raises(RouteFailure, match="observed 0/2 required lines"):
        Campaign(DelayedDialogue([s])).await_lines([
            "What, the house, mother nooooo!!!",
            "She's still in there!!",
        ], limit=3)


def test_alktree_aftermath_rejects_story_five_without_neighbour_dialogue():
    s = state()
    s["globals"].update({"story": 5, "vision": 2})
    s["screen"] = 439
    with pytest.raises(RouteFailure, match="observed 0/6 required lines"):
        Campaign(DelayedDialogue([s])).await_lines([
            "Dink!!!", "I .. I couldn't save her", "I was too late.",
            "It's not your fault Dink.", "There was nothing you could do..",
            "Don't blame yourself kid.",
        ], limit=3)


def test_letter_route_rejects_story_five_flag_without_guard_lines():
    s = state()
    s["globals"].update({"story": 5, "vision": 1, "letter": 1})
    s["screen"] = 408
    with pytest.raises(RouteFailure, match="observed 0/5 required lines"):
        Campaign(DelayedDialogue([s])).await_lines([
            "Sorry about what happened Dink, I hope you're ok.",
            "Thanks, I'll be ok.",
            "By the way, a letter came for you.  It's at your house,",
            "you should go take a look at it.", "Thanks.",
        ], limit=3)


def test_letter_completion_requires_released_controls_and_finished_vm_tasks():
    s = state([
        "Dear Dink,", "We've just gotten word of the tragic accident that happened at...",
        "your home a short while ago.  Needless to say we are shocked.",
        "This must be a hard time for you, being so young and suffering...",
        "such a great loss.  You are completely welcome to come and stay...",
        "with us in Terris for a while, I don't think Jack will mind.",
        "Sincerely, Aunt Maria Kneedlewood", "Hmm... Terris.  I think that is west of here.",
        "Hey!  A map was enclosed!", "(Press M or button 6 for map toggle)",
    ], frozen=True)
    s["globals"].update({"story": 6, "letter": 2, "s2-map": 1, "vision": 2})
    s["screen"] = 439
    s["scripts"] = {"dialogue_busy": True, "vm_live_tasks": 1}
    with pytest.raises(RouteFailure, match="observed 10/10 required lines"):
        Campaign(DelayedDialogue([s])).await_lines(Campaign.LETTER_LINES, limit=1)


def test_letter_post_fade_task_is_not_assumed_finished_by_released_controls():
    s = state(Campaign.LETTER_LINES)
    s.update({"screen": 439, "frozen": False, "disabled": 0, "nocontrol": 0,
              "scripts": {"dialogue_busy": False, "vm_live_tasks": 1}})
    s["globals"].update({"story": 6, "letter": 2, "s2-map": 1, "vision": 2})
    # The line collector can finish while the persistent S1-LTR task is still
    # live; acceptance must perform its bounded settle window first.
    campaign = Campaign(DelayedDialogue([s]))
    with pytest.raises(RouteFailure, match="letter script task remains active"):
        campaign.await_scripts_clear(s, "letter", limit=2)


@pytest.mark.parametrize("prefix", ["", "Selected: "])
def test_chest_selection_uses_live_description_case_and_real_enter(prefix):
    inventory = [{"script": "item-fst"}, {"script": "item-b1"}, {"script": "item-pig"}]
    def chest(label, equipped=2, page="inventory", back_focused=False):
        return {"inventory": inventory, "globals": {"cur_weapon": equipped}, "page": page,
                "ui": {"labels": [prefix + label], "buttons": [{"text": "Back to adventure", "focused": back_focused}]}}
    session = DelayedDialogue([chest("Item: Fists"), chest("Item: Bow · Equipped"),
                               chest("Item: Pig feed"), chest("", 3, "game")])
    keys = []
    def key(key):
        keys.append(key)
        session.index += 1
        return session.observe()
    session.menu_key = key
    result = Campaign(session).equip_item("item-pig", "Pig Feed")
    assert keys == ["right", "right", "enter"]
    assert result["globals"]["cur_weapon"] == 3


@pytest.mark.parametrize("prefix", ["", "Selected: "])
def test_chest_rejects_stale_description_when_back_has_focus(prefix):
    session = DelayedDialogue([{
        "inventory": [{"script": "item-pig"}], "globals": {"cur_weapon": 1},
        "page": "inventory", "ui": {"labels": [prefix + "Item: Pig feed"],
                                    "buttons": [{"text": "Back to adventure", "focused": True}]},
    }])
    session.menu_key = lambda key: session.observe()
    with pytest.raises(RouteFailure, match="inventory focus did not expose") as exc:
        Campaign(session).equip_item("item-pig", "Pig Feed")
    assert exc.value.kind == "harness"


def test_grid_planner_takes_open_corridor_around_solid_wall():
    grid = {"rows": ["..#..", "..#..", "....."], "step": 5, "origin": [20, 0]}
    path = grid_path(grid, (20, 0), (40, 0))
    assert (25, 10) in path or (20, 10) in path
    assert path[-1] == (40, 0)
    previous = (20, 0)
    for point in path:
        assert previous[0] == point[0] or previous[1] == point[1]
        for x in range(min(previous[0], point[0]), max(previous[0], point[0]) + 1, 5):
            for y in range(min(previous[1], point[1]), max(previous[1], point[1]) + 1, 5):
                assert grid["rows"][y // 5][(x - 20) // 5] == "."
        previous = point


def test_grid_planner_does_not_treat_disconnected_direction_as_game_failure():
    with pytest.raises(RouteFailure, match="no route") as exc:
        grid_path({"rows": [".#.", ".#."], "step": 5, "origin": [20, 0]}, (20, 0), (30, 0))
    assert exc.value.kind == "bot/incomplete"


def test_rounded_blocked_start_keeps_nearby_open_sample_as_a_real_waypoint():
    grid = {"rows": ["......#....", "..........."], "step": 5, "origin": [0, 0]}
    path = grid_path(grid, (28.946, 0.033), (40, 0))
    assert path[0] == (25, 0)
    assert path[-1] == (40, 0)
    assert any(y == 5 for x, y in path)  # Route around, rather than through, x30.


def test_start_projection_stays_local_and_does_not_rewrite_a_blocked_goal():
    grid = {"rows": ["......#....", "..........."], "step": 5, "origin": [0, 0]}
    with pytest.raises(RouteFailure, match="endpoint is blocked"):
        grid_path(grid, (28.946, 0.033), (30, 0))
    solid = {"rows": ["##############...."] * 4, "step": 5, "origin": [0, 0]}
    with pytest.raises(RouteFailure, match="endpoint is blocked"):
        grid_path(solid, (45, 5), (80, 5))


@pytest.mark.parametrize("observed_x,saved_x", [(320, 320.000001), (362.416656494141, 362.416666666667)])
def test_partial_terris_report_can_resume_only_its_exact_earned_letter_save(tmp_path, observed_x, saved_x):
    report = tmp_path / "route.json"
    session = report.with_suffix(".session") / "session-earned"
    save = session / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    save.parent.mkdir(parents=True)
    state = {"screen": 439, "x": observed_x, "y": 300, "inventory": [], "magic_inventory": [],
             "globals": {"story": 6, "letter": 2, "s2-map": 1, "s2-aunt": 0}}
    serialized = {"screen": 439, "entities": {"1": {"x": saved_x, "y": 300}},
                  "items": [], "magic_items": [], "vm": {"globals": state["globals"]}}
    save.write_text(json.dumps(serialized))
    data = {"ok": False, "milestone": "terris", "startup": {"setup": {
        "mode": "campaign", "test_mode": False, "load_map_scripts": True}},
        "session_dir": str(session), "checkpoints": {
            "letter-complete": state, "terris-letter-earned-save": state}}
    report.write_text(json.dumps(data))
    source, path, provenance = earned_letter_source(report)
    assert source["ok"] is False  # A continuation never rewrites the failed verdict.
    assert source["resume_checkpoint"] == state and path == save
    assert provenance["source_ok"] is False
    serialized["entities"]["1"]["x"] += 1
    save.write_text(json.dumps(serialized))
    with pytest.raises(ValueError, match="does not match its earned LETTER"):
        earned_letter_source(report)


def terris_state(*, lines=(), frozen=False, aunt=1, story=7, tasks=0):
    return {"screen": 36, "globals": {"s2-aunt": aunt, "story": story, "letter": 2, "s2-map": 1},
            "recent_dialogue": list(lines), "frozen": frozen, "dialogue": False,
            "disabled": 0, "nocontrol": 0, "scripts": {"vm_live_tasks": tasks, "dialogue_busy": False}}


def test_terris_arrival_rejects_flags_without_its_actual_conversation():
    with pytest.raises(RouteFailure, match="observed 0/15 required lines"):
        Campaign(DelayedDialogue([terris_state()]), max_commands=2000).terris_arrival()


def test_terris_arrival_waits_for_control_and_task_completion():
    states = [terris_state(lines=Campaign.TERRIS_LINES, frozen=True, tasks=1),
              terris_state(lines=Campaign.TERRIS_LINES, tasks=1),
              terris_state(lines=Campaign.TERRIS_LINES)]
    session = DelayedDialogue(states)
    campaign = Campaign(session)
    campaign.terris_arrival()
    assert session.index == 2
    assert campaign.checkpoints["terris-arrival-complete"]["globals"]["s2-aunt"] == 1


def test_terris_arrival_requires_source_bridge_story_progression():
    with pytest.raises(RouteFailure, match="story=7 and s2-aunt=1") as exc:
        Campaign(DelayedDialogue([terris_state(lines=Campaign.TERRIS_LINES, story=6)])).terris_arrival()
    assert exc.value.kind == "game suspected"


def test_terris_route_rejects_unearned_letter():
    session = DelayedDialogue([{"screen": 439, "globals": {"story": 6, "letter": 1, "s2-map": 1, "s2-aunt": 0}}])
    with pytest.raises(RouteFailure, match="completed LETTER"):
        Campaign(session).run_terris()


def test_letter_continuation_rejects_scenario_setup_and_unrelated_save(tmp_path):
    report = tmp_path / "letter.json"
    data = {"ok": True, "startup": {"setup": {"mode": "scenario", "test_mode": False, "load_map_scripts": True}}}
    report.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="real campaign"):
        earned_letter_source(report)

    data["startup"]["setup"]["mode"] = "campaign"
    data["checkpoints"] = {"letter-complete": {}, "save-reload": {
        "screen": 439, "globals": {"story": 6, "letter": 2, "s2-map": 1, "s2-aunt": 0},
    }}
    data["session_dir"] = str(tmp_path / "player-profile")
    report.write_text(json.dumps(data))
    with pytest.raises(ValueError, match="isolated session"):
        earned_letter_source(report)

def test_grid_planner_cannot_use_transition_space_to_bypass_a_wall():
    # The bridge probes x=0..640; x<20 and x>620 change maps on movement.
    rows = ["." * 129, "." * 4 + "#" * 121 + "." * 4, "." * 129]
    with pytest.raises(RouteFailure, match="no route"):
        grid_path({"rows": rows, "step": 5, "origin": [0, 0]}, (100, 0), (100, 10))


@pytest.mark.parametrize("edge", ["east", "south"])
def test_planning_excludes_the_exact_continuous_crossing_boundary(edge):
    if edge == "south":
        rows = ["." * 30 + "#" + "." * 98] * 80 + ["." * 129]
        start, goal = (100, 390), (200, 390)
    else:
        rows = ["." * 129] * 81
        rows[40] = "." * 4 + "#" * 120 + "." * 5
        start, goal = (610, 100), (610, 300)
    # x620/y400 already changes the screen; it is not a local detour.
    with pytest.raises(RouteFailure, match="no route"):
        grid_path({"rows": rows, "step": 5, "origin": [0, 0]}, start, goal)


def test_grid_planner_prefers_clearance_over_hugging_a_sampled_boundary():
    rows = ["#" * 82 + "." * 47 if y <= 25 else "." * 129 for y in range(81)]
    path = grid_path({"rows": rows, "step": 5, "origin": [0, 0]}, (380, 140), (430, 80))
    # x410 is the first open sample beside the wall. The live player's
    # waypoint tolerance can leave x409.8, which is still obstructed.
    assert any(x >= 415 and y >= 135 for x, y in path)
    assert path[-1] == (430, 80)


def test_planned_navigation_rejects_unexpected_door_transition(monkeypatch):
    campaign = Campaign(DelayedDialogue([{"screen": 500, "x": 260, "y": 360}]))
    monkeypatch.setattr(campaign, "_walk_point", lambda *args: {"screen": 33})
    with pytest.raises(RouteFailure, match="unexpectedly entered map 33"):
        campaign._follow_path(500, [(260, 350)], "maria-door")


@pytest.mark.parametrize("lost", ["fireball", "life", "magic", "defense", "exp", "level"])
def test_save_acceptance_detects_lost_magic_and_changed_combat_stats(lost):
    expected = {"screen": 36, "x": 320, "y": 300, "inventory": [{"script": "item-fst"}],
                "magic_inventory": [{"script": "item-fb"}],
                "globals": {"life": 10, "magic": 1, "defense": 0, "exp": 100, "level": 2}}
    actual = json.loads(json.dumps(expected))
    assert saved_state_matches(expected, actual)
    if lost == "fireball":
        actual["magic_inventory"] = []
    else:
        actual["globals"][lost] += 1
    assert not saved_state_matches(expected, actual)


def test_map_wide_corridor_is_split_to_fit_normal_walking_budget(monkeypatch):
    session = DelayedDialogue([{"screen": 375, "x": 608, "y": 200}])
    campaign = Campaign(session)
    legs = []
    def walk(screen, point, radius, label):
        previous = session.states[0]
        assert abs(point[0] - previous["x"]) <= 220
        legs.append(point)
        session.states[0] = {"screen": screen, "x": point[0], "y": point[1]}
        return session.states[0]
    monkeypatch.setattr(campaign, "_walk_point", walk)
    result = campaign._follow_path(375, [(25, 200)], "west-corridor")
    assert len(legs) == 3
    assert (result["x"], result["y"]) == (25, 200)


def test_continuation_rejects_changed_save_when_report_records_its_hash(tmp_path):
    report = tmp_path / "letter.json"
    session = tmp_path / "letter.session/session-earned"
    save = session / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    save.parent.mkdir(parents=True)
    save.write_text('{"life": 10}')
    data = {"ok": True, "startup": {"setup": {"mode": "campaign", "test_mode": False, "load_map_scripts": True}},
            "checkpoints": {"letter-complete": {}, "save-reload": {
                "screen": 439, "globals": {"story": 6, "letter": 2, "s2-map": 1, "s2-aunt": 0}}},
            "session_dir": str(session), "earned_save_sha256": hashlib.sha256(save.read_bytes()).hexdigest()}
    report.write_text(json.dumps(data))
    assert earned_letter_source(report)[2]["digest_binding"] == "recorded"
    save.write_text('{"life": 999}')
    with pytest.raises(ValueError, match="recorded hash"):
        earned_letter_source(report)


@pytest.mark.parametrize("can_escape,frozen", [(False, False), (True, False), (False, True)])
def test_landing_probe_requires_all_directions_blocked_and_released_controls(can_escape, frozen):
    base = {"screen": 377, "x": 32.0, "y": 375.0, "playing": True, "page": "game", "frozen": frozen}
    session = DelayedDialogue([base])
    keys = []
    def hold(action, frames):
        keys.append(action)
        assert frames == 12
        if can_escape and action == "back":
            session.states[0] = dict(base, x=25.0)
        return session.observe()
    session.hold = hold
    campaign = Campaign(session)
    if not can_escape and not frozen:
        with pytest.raises(RouteFailure, match="four normal movement directions") as exc:
            campaign.probe_blocked_landing(377, "forest")
        assert exc.value.kind == "game suspected"
    else:
        campaign.probe_blocked_landing(377, "forest")
    assert keys == ["forward", "back", "left", "right"]
