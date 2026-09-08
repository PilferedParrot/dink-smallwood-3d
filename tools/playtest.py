"""Local controller for tests/playtest_session.gd.

The bridge uses only atomic JSON files in a private session directory. It is
deliberately small enough to be used by an external model without a plugin or
network service.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SESSION_SCRIPT = ROOT / "tests" / "playtest_session.gd"
KEYS = {"forward", "back", "left", "right", "sprint", "jump", "attack", "magic", "talk", "inventory", "map"}
MENU_KEYS = {"up", "down", "left", "right", "enter", "space", "escape", "i",
             "ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"}


def find_godot() -> str:
    configured = os.environ.get("GODOT")
    if configured:
        return configured
    for candidate in ("godot", "godot4", str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")):
        if shutil.which(candidate):
            return candidate
    raise FileNotFoundError("Godot 4.6 not found; set GODOT to its executable")


class PlaytestSession:
    """Own one Godot process and a private command/response directory."""

    def __init__(self, session_dir: str | os.PathLike[str] | None = None, *, rendered: bool = False,
                 screen: int = 407, x: float = 320, y: float = 390, yaw: float = 0.0,
                 pitch: float = -0.08, timeout: float = 15.0,
                 mode: str = "scenario", save_source: str | os.PathLike[str] | None = None,
                 death_fixture: bool = False):
        if mode not in {"scenario", "campaign"}:
            raise ValueError("mode must be 'scenario' or 'campaign'")
        if isinstance(screen, bool) or not isinstance(screen, int):
            raise ValueError("screen must be an integer")
        for value in (x, y, yaw, pitch, timeout):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ValueError("coordinates, orientation, and timeout must be finite numbers")
        if not 0 < timeout <= 60:
            raise ValueError("timeout must be between 0 and 60 seconds")
        parent = Path(session_dir).absolute() if session_dir is not None else None
        if parent is not None:
            parent.mkdir(parents=True, exist_ok=True)
        self.session_dir = Path(tempfile.mkdtemp(prefix="session-", dir=str(parent) if parent else None)).absolute()
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.timeout = timeout
        self.mode = mode
        self.save_source = Path(save_source).absolute() if save_source is not None else None
        if self.save_source is not None:
            if not self.save_source.is_file() or self.save_source.name != "adventure.json":
                raise ValueError("save_source must be an existing adventure.json file")
        if death_fixture and mode != "scenario":
            raise ValueError("death_fixture is only available in scenario mode")
        self.death_fixture = death_fixture
        self._next_id = 1
        self._closed = False
        self._log = self.session_dir / "godot.log"
        env = os.environ.copy()
        self._xdg = Path(tempfile.mkdtemp(prefix="dink-playtest-xdg-"))
        env["XDG_DATA_HOME"] = str(self._xdg / "data")
        env["XDG_CONFIG_HOME"] = str(self._xdg / "config")
        if self.save_source is not None:
            isolated_user = self._xdg / "data" / "godot" / "app_userdata" / "Dink Smallwood 3D"
            isolated_user.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.save_source, isolated_user / "adventure.json")
        try:
            godot = find_godot()
        except Exception:
            shutil.rmtree(self._xdg, ignore_errors=True)
            shutil.rmtree(self.session_dir, ignore_errors=True)
            raise
        args = [godot, "--audio-driver", "Dummy", "--path", str(ROOT / "game")]
        if not rendered:
            args.append("--headless")
        args += ["--script", str(SESSION_SCRIPT), "--", f"--session-dir={self.session_dir}",
                 f"--mode={mode}", f"--screen={screen}", f"--x={x}", f"--y={y}",
                 f"--yaw={yaw}", f"--pitch={pitch}"]
        if death_fixture:
            args.append("--death-fixture")
        self._process = None
        try:
            with self._log.open("w") as log:
                self._process = subprocess.Popen(args, cwd=ROOT, env=env, stdout=log,
                                                 stderr=subprocess.STDOUT, start_new_session=True)
            self.startup = self._wait_for_response("startup", timeout=max(timeout, 30.0))
            if not self.startup.get("ok", False):
                raise RuntimeError(self.startup.get("error", "playtest startup failed"))
        except Exception:
            if self._process is not None and self._process.poll() is None:
                self._process.terminate()
                try:
                    self._process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._process.kill()
                    self._process.wait(timeout=3)
            self._retain_xdg()
            raise

    def __enter__(self) -> "PlaytestSession":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    @property
    def process(self) -> subprocess.Popen[bytes]:
        return self._process

    def request(self, command: str, **fields: Any) -> dict[str, Any]:
        if self._closed:
            raise RuntimeError("playtest session is closed")
        if "id" in fields or "command" in fields:
            raise ValueError("protocol identifiers are reserved")
        if command not in {"observe", "navigation_grid", "hold", "wait", "look", "pause", "menu_key", "screenshot", "quit"}:
            raise ValueError(f"unknown command: {command}")
        if command in {"hold", "wait"}:
            if command == "wait" and "action" in fields:
                raise ValueError("wait does not accept an action")
            if command == "hold" and fields.get("action") not in KEYS:
                raise ValueError("hold action is not allowlisted")
            raw_frames = fields.get("frames", 0)
            if isinstance(raw_frames, bool) or not isinstance(raw_frames, int):
                raise ValueError("hold frames must be an integer")
            frames = raw_frames
            if not 0 <= frames <= 120:
                raise ValueError("frames must be between 0 and 120")
        if command == "menu_key":
            key = fields.get("key")
            if not (isinstance(key, str) and key in MENU_KEYS) and not (isinstance(key, int) and key >= 0):
                raise ValueError("menu key must be an allowlisted name or non-negative keycode")
            if "expect_exit" in fields and not isinstance(fields["expect_exit"], bool):
                raise ValueError("expect_exit must be a boolean")
        ident = str(self._next_id)
        self._next_id += 1
        payload = {"id": ident, "command": command, **fields}
        command_path = self.session_dir / "command.json"
        temp = self.session_dir / f"command.{ident}.tmp"
        temp.write_text(json.dumps(payload, allow_nan=False), encoding="utf-8")
        os.replace(temp, command_path)
        if command == "menu_key" and fields.get("expect_exit", False):
            return self._wait_for_expected_exit()
        return self._wait_for_response(ident)

    def observe(self) -> dict[str, Any]:
        return self.request("observe")

    def navigation_grid(self) -> dict[str, Any]:
        """Read the current map's collision probes without advancing the game."""
        return self.request("navigation_grid")

    def hold(self, action: str, frames: int) -> dict[str, Any]:
        return self.request("hold", action=action, frames=frames)

    def wait(self, frames: int = 1) -> dict[str, Any]:
        return self.request("wait", frames=frames)

    def menu_key(self, key: str | int, *, expect_exit: bool = False) -> dict[str, Any]:
        return self.request("menu_key", key=key, expect_exit=expect_exit)

    def exit_via_menu(self, key: str | int = "enter") -> dict[str, Any]:
        """Activate a focused menu item and require a clean process exit."""
        return self.menu_key(key, expect_exit=True)

    def _wait_for_expected_exit(self) -> dict[str, Any]:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            code = self._process.poll()
            if code is not None:
                return {"ok": code == 0, "process_exit": True, "exit_code": code}
            time.sleep(0.01)
        raise TimeoutError("expected menu exit did not occur")

    def wait_for_exit(self, timeout: float | None = None) -> int:
        """Wait for a normal menu-driven process exit; never sends the quit command."""
        limit = self.timeout if timeout is None else timeout
        if not 0 < limit <= 60:
            raise ValueError("exit timeout must be between 0 and 60 seconds")
        try:
            return self._process.wait(timeout=limit)
        except subprocess.TimeoutExpired as exc:
            raise TimeoutError("game did not exit through its menu") from exc

    def look(self, dx: float, dy: float) -> dict[str, Any]:
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in (dx, dy)):
            raise ValueError("look deltas must be finite numbers")
        return self.request("look", dx=dx, dy=dy)

    def pause(self) -> dict[str, Any]:
        return self.request("pause")

    def screenshot(self, path: str = "screenshot.png") -> dict[str, Any]:
        return self.request("screenshot", path=path)

    def _wait_for_response(self, ident: str, *, timeout: float | None = None) -> dict[str, Any]:
        response = self.session_dir / "response.json"
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        while time.monotonic() < deadline:
            if response.exists():
                try:
                    value = json.loads(response.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    value = None
                if isinstance(value, dict) and str(value.get("id")) == ident:
                    response.unlink(missing_ok=True)
                    return value
            if self._process.poll() is not None:
                raise RuntimeError(f"Godot exited with code {self._process.returncode}; see {self._log}")
            time.sleep(0.01)
        raise TimeoutError(f"timed out waiting for playtest response {ident}; see {self._log}")

    def close(self) -> None:
        if self._closed:
            return
        if self._process.poll() is None:
            try:
                self.request("quit")
            except (RuntimeError, TimeoutError):
                self._process.terminate()
            try:
                self._process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait(timeout=3)
        self._closed = True
        self._retain_xdg()

    def _retain_xdg(self) -> None:
        """Keep the isolated save/settings tree beside the session report."""
        retained = self.session_dir / "xdg"
        if retained.exists() or not self._xdg.exists():
            shutil.rmtree(self._xdg, ignore_errors=True)
            return
        try:
            shutil.copytree(self._xdg, retained)
        finally:
            shutil.rmtree(self._xdg, ignore_errors=True)


def smoke(rendered: bool = False, session_dir: Path | None = None) -> dict[str, Any]:
    with PlaytestSession(session_dir=session_dir, rendered=rendered, screen=439, x=505, y=340) as session:
        before = session.observe()["telemetry"]
        moved = session.hold("forward", 30)["telemetry"]
        session.pause()
        paused = session.observe()["telemetry"]
        before_pause = paused
        session.hold("back", 30)
        during_pause = session.observe()["telemetry"]
        session.pause()
        session.hold("back", 30)
        resumed = session.observe()["telemetry"]
        report = {"before": before, "after_move": moved, "pause": paused,
                  "during_pause": during_pause, "after_resume": resumed,
                  "movement_delta": [moved["x"] - before["x"], moved["y"] - before["y"]],
                  "pause_position_unchanged": (before_pause["x"], before_pause["y"]) ==
                  (during_pause["x"], during_pause["y"]),
                  "resume_movement_delta": [resumed["x"] - during_pause["x"], resumed["y"] - during_pause["y"]],
                  "resume_frame_count": resumed["frame_count"], "startup": session.startup,
                  "session_dir": str(session.session_dir)}
        report["screenshot"] = session.screenshot()
        capture_ok = report["screenshot"].get("ok", False) if rendered else (
            not report["screenshot"].get("ok", True) and "headless" in report["screenshot"].get("error", ""))
        report["ok"] = (capture_ok and abs(report["movement_delta"][0]) + abs(report["movement_delta"][1]) > 0.01
                        and report["pause_position_unchanged"] and paused["modal"]
                        and not resumed["modal"]
                        and abs(report["resume_movement_delta"][0]) + abs(report["resume_movement_delta"][1]) > 0.01)
        return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a local Dink Smallwood 3D playtest")
    parser.add_argument("--mode", choices=("scenario", "campaign"), default="scenario",
                        help="scenario smoke checks or the normal opening campaign route")
    parser.add_argument("--rendered", action="store_true", help="run with a renderer for screenshots")
    parser.add_argument("--report", type=Path, default=None,
                        help="write JSON report and retained session artifacts")
    parser.add_argument("--max-commands", type=int, default=900,
                        help="campaign command budget (campaign mode only)")
    parser.add_argument("--milestone", choices=("opening", "ethel", "alktree", "letter"), default="opening",
                        help="campaign milestone; use a larger command budget for Ethel, AlkTree, or letter")
    args = parser.parse_args()
    if args.report is None:
        args.report = ROOT / "builds/playtests" / ("campaign" if args.mode == "campaign" else "smoke") / "report.json"
    if args.mode == "campaign":
        try:
            from tools.playtest_campaign import run as campaign_run
        except ModuleNotFoundError:
            from playtest_campaign import run as campaign_run
        report = campaign_run(args.rendered, args.report, max(1, args.max_commands), args.milestone)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({key: report.get(key) for key in
                          ("ok", "verdict", "failure_class", "error", "commands", "session_dir")}, indent=2))
        return 0 if report.get("ok") else 1
    artifact_dir = args.report.with_suffix(".session") if args.report else None
    try:
        report = smoke(args.rendered, artifact_dir)
    except (RuntimeError, TimeoutError, OSError, ValueError, KeyError) as exc:
        report = {"ok": False, "verdict": "inconclusive", "error": str(exc)}
    text = json.dumps(report, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
