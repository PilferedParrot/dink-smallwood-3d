"""Independent partial pixel cues, their limits, and source-event safety."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from detail_pixels import inspect, measure
ART = ROOT / "game/assets/graphics/lands/Details"


def test_partial_shadow_rule_has_raised_controls_and_abstains_on_skulls():
    for name in [f"grave-{i:02}.png" for i in [7, 8, 9, 10]] + [f"fores-{i:02}.png" for i in [2, 3, 4]]:
        assert inspect(ART / name)["class"] == "upright_cue", name
    for name in ["grave-05.png", "grave-06.png", "fores-05.png"]:
        assert inspect(ART / name)["class"] == "undecidable", name


def test_shadow_cue_uses_pixels_and_responds_to_shadow_removal():
    rgba = np.asarray(Image.open(ART / "fores-01.png").convert("RGBA")).copy()
    assert measure(rgba)["class"] == "upright_cue"
    assert measure(rgba[:, ::-1])["class"] == "upright_cue"
    black = (rgba[..., 3] >= 128) & (rgba[..., :3].astype(int).sum(-1) < 10)
    adjacent = np.zeros_like(black)
    adjacent[1:] |= black[:-1]; adjacent[:-1] |= black[1:]
    adjacent[:, 1:] |= black[:, :-1]; adjacent[:, :-1] |= black[:, 1:]
    rgba[black & ~adjacent, 3] = 0
    assert measure(rgba)["class"] == "undecidable"


def test_departed_ground_scripts_have_no_ray_interaction_handlers():
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    scripts = json.loads((ROOT / "game/data/story.json").read_text())["scripts"]
    for screen, editor, expected in [(277,2,"s1-hole"),(180,1,"s6-hole2"),(209,4,"s1-hole3"),(243,13,"s6-hole"),(192,5,"thorn")]:
        entry = next(e for e in world[str(screen)]["sprites"] if e["index"] == editor)
        assert entry["script"] == expected
        procedures = scripts[expected]["procedures"]
        assert not set(procedures) & {"hit", "talk", "push"}, (screen, editor, expected)
        assert "touch" in procedures if expected != "thorn" else set(procedures) == {"main"}


def test_departed_scripts_do_not_replace_or_forward_their_target_script():
    scripts = json.loads((ROOT / "game/data/story.json").read_text())["scripts"]
    def calls(value):
        if isinstance(value, dict):
            if value.get("op") == "call" or value.get("kind") == "call":
                yield value.get("name", "").lower()
            for nested in value.values():
                yield from calls(nested)
        elif isinstance(value, list):
            for nested in value:
                yield from calls(nested)
    for name in ["s1-hole", "s6-hole2", "s1-hole3", "s6-hole", "thorn"]:
        assert not set(calls(scripts[name])) & {"sp_script", "external", "spawn"}, name
