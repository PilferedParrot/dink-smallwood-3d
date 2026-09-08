import pytest

from tools.playtest_campaign import Campaign, RouteFailure


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
