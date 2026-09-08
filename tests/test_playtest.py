import pytest
import time

from tools.playtest import PlaytestSession


def test_playtest_ticks_pause_and_headless_screenshot_rejection():
    with PlaytestSession(screen=439, x=505, y=340) as session:
        start = session.observe()["telemetry"]
        one = session.hold("forward", 1)["telemetry"]
        ten = session.hold("forward", 10)["telemetry"]
        assert one["frame_count"] == 1
        assert one["y"] - start["y"] == pytest.approx(-1.75)
        assert ten["frame_count"] == 11
        assert ten["y"] - one["y"] == pytest.approx(-17.5)
        time.sleep(0.1)
        idle = session.observe()["telemetry"]
        assert idle == ten
        session.pause()
        paused = session.observe()["telemetry"]
        session.hold("back", 30)
        still = session.observe()["telemetry"]
        assert paused["modal"] and (still["x"], still["y"]) == (paused["x"], paused["y"])
        session.pause()
        resumed = session.hold("back", 10)["telemetry"]
        assert not resumed["modal"]
        assert resumed["y"] - still["y"] == pytest.approx(17.5)
        result = session.screenshot()
        assert not result["ok"] and "headless" in result["error"]


def test_playtest_rejects_unbounded_or_non_integral_actions():
    with PlaytestSession(screen=439, x=505, y=340) as session:
        with pytest.raises(ValueError):
            session.hold("back", 1.5)
        with pytest.raises(ValueError):
            session.hold("back", True)
        with pytest.raises(ValueError):
            session.look(float("nan"), 0)


def test_navigation_grid_is_read_only_and_keeps_solid_pigpen():
    with PlaytestSession(screen=407, x=320, y=390) as session:
        before = session.observe()["telemetry"]
        result = session.navigation_grid()
        assert result["ok"]
        grid = result["navigation_grid"]
        assert grid["screen"] == 407 and grid["step"] == 5
        assert len(grid["rows"]) == 81 and all(len(row) == 129 for row in grid["rows"])
        # The established solid south rail remains a planning obstacle.
        assert any(grid["rows"][y // 5][320 // 5] == "#" for y in range(310, 386, 5))
        assert session.observe()["telemetry"] == before


def test_headless_mouse_look_is_reported_as_unsupported():
    with PlaytestSession(screen=439, x=505, y=340) as session:
        result = session.look(120, 0)
        assert not result["ok"]
        assert "rendered" in result["error"]


def test_invalid_startup_fails_and_retains_log(tmp_path):
    with pytest.raises(RuntimeError, match="setup screen does not exist"):
        PlaytestSession(tmp_path, screen=99999)
    assert list(tmp_path.glob("session-*/godot.log"))


def test_campaign_boots_real_title_and_starts_with_menu_input():
    with PlaytestSession(mode="campaign") as session:
        title = session.observe()["telemetry"]
        assert title["mode"] == "campaign"
        assert title["ui"]["title"]
        assert title["ui"]["buttons"][0]["focused"]
        assert [button["text"] for button in title["ui"]["buttons"]][-1] == "Quit"
        started = session.menu_key("enter")["telemetry"]
        assert started["playing"]
        assert started["screen"] == 1
        assert started["save"]["adventure"] is False
        assert started["inventory"]


def test_title_quit_requires_explicit_expected_exit():
    with PlaytestSession(mode="campaign") as session:
        for _ in range(3):
            session.menu_key("down")
        result = session.exit_via_menu()
        assert result == {"ok": True, "process_exit": True, "exit_code": 0}


def test_campaign_opening_dialogue_and_ui_save_reload(tmp_path):
    with PlaytestSession(tmp_path, mode="campaign", timeout=20) as session:
        session.menu_key("enter")
        for _ in range(3):
            state = session.wait(120)["telemetry"]
            if state["dialogue"]:
                session.menu_key("enter")
        stable = session.observe()["telemetry"]
        assert not stable["dialogue"]
        assert stable["recent_dialogue"]

        session.pause()
        session.menu_key("down")
        saved = session.menu_key("enter")["telemetry"]
        assert saved["save"]["adventure"]
        saved_position = (saved["x"], saved["y"])
        session.menu_key("escape")
        session.hold("forward", 10)
        assert (session.observe()["telemetry"]["x"], session.observe()["telemetry"]["y"]) != saved_position

        session.pause()
        session.menu_key("down")
        session.menu_key("down")
        loaded = session.menu_key("enter")["telemetry"]
        assert (loaded["x"], loaded["y"]) == saved_position
        session_dir = session.session_dir
    assert (session_dir / "xdg").exists()
    assert (session_dir / "trace.jsonl").exists()
