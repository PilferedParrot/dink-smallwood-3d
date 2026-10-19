"""Normal-save campaign legs preserve their earned checkpoint requirements."""
from copy import deepcopy
import pytest
from tools.playtest_push_route import continuation_checkpoint


@pytest.mark.parametrize("phase,screen,wizard,rock,name", [
    ("bonca", 277, 2, 0, "wizard-rock-before-push-earned-save"),
    ("reward", 100, 3, 1, "bonca-complete-earned-save"),
    ("terris", 6, 4, 1, "wizard-reward-earned-save"),
])
def test_continuation_requires_the_actual_earned_leg(phase, screen, wizard, rock, name):
    expected = {"screen": screen, "globals": {"strength": 4, "wizard_see": wizard, "rock_placement": rock},
                "magic_inventory": [{"script": "item-fb"}] if phase == "terris" else []}
    source = {"checkpoints": {name: expected}}
    assert continuation_checkpoint(source, phase) is expected
    changed = deepcopy(source)
    changed["checkpoints"][name]["globals"]["wizard_see"] = 0
    with pytest.raises(ValueError, match="earned checkpoint"):
        continuation_checkpoint(changed, phase)
    assert source["checkpoints"][name] == expected


def test_terris_leg_requires_the_earned_spell():
    source = {"checkpoints": {"wizard-reward-earned-save": {
        "screen": 6, "globals": {"wizard_see": 4}, "magic_inventory": []}}}
    with pytest.raises(ValueError, match="earned checkpoint"):
        continuation_checkpoint(source, "terris")
