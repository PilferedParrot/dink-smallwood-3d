from pathlib import Path

from tools.playtest import PlaytestSession
from tools.playtest_restart import continue_from_save, death_restart


ROOT = Path(__file__).resolve().parents[1]
def test_cold_continue_uses_earned_isolated_save(tmp_path):
    # Earn this opening save in a separate isolated process through normal input.
    with PlaytestSession(tmp_path / "earned", mode="campaign", timeout=20) as earned:
        earned.menu_key("enter")
        for _ in range(5):
            state = earned.wait(120)["telemetry"]
            if state["dialogue"]: earned.menu_key("enter")
        earned.pause()
        earned.menu_key("down")
        saved = earned.menu_key("enter")["telemetry"]
        assert saved["save"]["adventure"] and saved["globals"]["story"] == 1
        save = Path(earned.session_dir) / "xdg/data/godot/app_userdata/Dink Smallwood 3D/adventure.json"
    result = continue_from_save(save, tmp_path / "cold")
    assert result["ok"], result
    assert result["title"]["save"]["adventure"]
    assert result["continued"]["globals"]["story"] == 1
    assert result["state_match"]
    assert (Path(result["session_dir"]) / "xdg").exists()


def test_bounded_death_and_restart_uses_actual_menu_input(tmp_path):
    result = death_restart(tmp_path)
    assert result["ok"], result
    assert result["defeated"]["ui"]["page"] == "defeat"
    assert result["restarted"]["playing"]


def test_letter_cold_continue_expected_globals_include_map_unlock(tmp_path):
    import json
    save = tmp_path / "adventure.json"
    save.write_text(json.dumps({"screen": 439, "entities": {"1": {"x": 362, "y": 303}},
                                "fps_camera": {}, "items": [],
                                "vm": {"globals": {"story": 6, "letter": 2, "s2-map": 1}}}), encoding="utf-8")
    expected = __import__("tools.playtest_restart", fromlist=["_source_metadata"])._source_metadata(save, None)
    assert expected["globals"]["letter"] == 2
    assert expected["globals"]["s2-map"] == 1
