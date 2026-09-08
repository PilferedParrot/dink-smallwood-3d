"""Bounded local-Qwen action selection for the deterministic playtest bridge.

The model can select only a remaining directional probe.  The runner owns all
other inputs, validation, and the final verdict.
"""
from __future__ import annotations

import argparse
import json
import math
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ENDPOINT = "http://127.0.0.1:8080/v1/chat/completions"
MOVES = ("up", "down", "left", "right")
MOVE_KEYS = {"up": "forward", "down": "back", "left": "left", "right": "right"}


class QwenUnavailable(RuntimeError):
    """The local endpoint could not complete a request."""


class QwenInconclusive(RuntimeError):
    """The bounded model response or runner evidence cannot support a verdict."""


@dataclass
class Probe:
    action: str
    reason: str
    latency_ms: int
    model: str | None
    usage: dict[str, Any] | None
    raw: dict[str, Any] = field(repr=False)


def action_schema(legal_actions: list[str]) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "action": {"type": "string", "enum": legal_actions},
            "reason": {"type": "string", "maxLength": 160},
        },
        "required": ["action", "reason"],
        "additionalProperties": False,
    }


def finite_telemetry(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    screen = value.get("screen")
    if isinstance(screen, bool) or not isinstance(screen, int):
        return False
    for key in ("x", "y"):
        coordinate = value.get(key)
        if isinstance(coordinate, bool) or not isinstance(coordinate, (int, float)):
            return False
        if not math.isfinite(float(coordinate)):
            return False
    return True


def position_delta(before: dict[str, Any], after: dict[str, Any]) -> dict[str, float]:
    return {
        "x": round(float(after["x"]) - float(before["x"]), 4),
        "y": round(float(after["y"]) - float(before["y"]), 4),
    }


def displaced(delta: dict[str, float]) -> bool:
    return abs(delta["x"]) + abs(delta["y"]) > 0.01


class ActionChooser:
    def __init__(self, endpoint: str = ENDPOINT, max_actions: int = 12,
                 timeout: float = 45.0) -> None:
        self.endpoint = endpoint
        self.max_actions = max(1, int(max_actions))
        self.timeout = min(45.0, max(1.0, float(timeout)))
        self.steps = 0
        self.records: list[dict[str, Any]] = []

    def choose(self, state: dict[str, Any], task: str,
               legal_actions: list[str]) -> Probe:
        if self.steps >= self.max_actions:
            raise QwenInconclusive("bounded model request limit reached")
        if len(legal_actions) < 2:
            raise QwenInconclusive("model called without a meaningful choice")

        prompt = (
            "Choose exactly one action from legal_actions. You select only a "
            "bounded directional probe; the supervisor evaluates results.\nTask: "
            + task + "\nlegal_actions: " + json.dumps(legal_actions)
            + "\nstate: " + json.dumps(state, separators=(",", ":"))
        )
        payload = {
            "model": "qwen3-coder-next",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0,
            "max_tokens": 160,
            "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "playtest_action",
                    "strict": True,
                    "schema": action_schema(legal_actions),
                },
            },
            "stream": False,
        }
        started = time.monotonic()
        try:
            request = urllib.request.Request(
                self.endpoint, json.dumps(payload).encode(), {"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                result = json.load(response)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            self.records.append({"step": self.steps + 1, "legal_actions": legal_actions,
                                 "error": str(exc)})
            raise QwenUnavailable("Qwen request failed: " + str(exc)) from exc

        latency = round((time.monotonic() - started) * 1000)
        response_record = {
            "step": self.steps + 1,
            "legal_actions": legal_actions,
            "latency_ms": latency,
            "model": result.get("model") if isinstance(result, dict) else None,
            "usage": result.get("usage") if isinstance(result, dict) else None,
        }
        try:
            choice = result["choices"][0]
            if choice.get("finish_reason") != "stop":
                raise ValueError("finish_reason must be stop")
            content = json.loads(choice["message"]["content"])
            if not isinstance(content, dict) or set(content) != {"action", "reason"}:
                raise ValueError("model JSON must contain exactly action and reason")
            action, reason = content["action"], content["reason"]
            if action not in legal_actions or not isinstance(reason, str) or len(reason) > 160:
                raise ValueError("action is outside current legal schema")
        except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
            response_record["error"] = str(exc)
            self.records.append(response_record)
            raise QwenInconclusive("invalid Qwen response: " + str(exc)) from exc

        self.steps += 1
        response_record.update({"action": action, "reason": reason})
        self.records.append(response_record)
        return Probe(action, reason, latency, response_record["model"], response_record["usage"], result)


def write_report(path: str | None, report: dict[str, Any]) -> None:
    if path:
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def run_session(session: Any, report: str | None = None, max_actions: int = 12,
                endpoint: str = ENDPOINT, timeout: float = 45.0,
                rendered: bool = False) -> dict[str, Any]:
    """Run a bounded mobility and menu scenario using an existing session."""
    chooser = ActionChooser(endpoint, max_actions, timeout)
    history: list[dict[str, Any]] = []
    movement: dict[str, bool] = {}
    startup: dict[str, Any] = {}
    initial_telemetry: dict[str, Any] = {}
    state: dict[str, Any] = {}
    phase = "directions"
    failure: str | None = None
    screenshot: dict[str, Any] | None = None
    pause_ok = held_ok = resume_ok = recovery_ok = False

    def add_command(action: str, actor: str, reason: str, response: dict[str, Any],
                    before: dict[str, Any]) -> dict[str, Any]:
        after = response.get("telemetry")
        entry = {"action": action, "actor": actor, "reason": reason, "before": before,
                 "after": after, "response_ok": bool(response.get("ok")),
                 "error": response.get("error")}
        if finite_telemetry(after):
            entry["delta"] = position_delta(before, after)
        history.append(entry)
        if not response.get("ok"):
            raise QwenInconclusive("bridge command failed: " + str(response.get("error", "unknown error")))
        if not finite_telemetry(after):
            raise QwenInconclusive("bridge returned invalid telemetry")
        return after

    try:
        observed = session.observe()
        startup = getattr(session, "startup", observed)
        if not observed.get("ok") or not finite_telemetry(observed.get("telemetry")):
            raise QwenInconclusive("initial observe failed or returned invalid telemetry")
        state = observed["telemetry"]
        initial_telemetry = dict(state)
        task = (f"Characterize four-direction mobility and pause behavior from "
                f"screen {state['screen']} at ({state['x']},{state['y']}).")

        while len(movement) < len(MOVES):
            if len(history) >= max_actions:
                raise QwenInconclusive("bounded action limit reached before directional coverage")
            legal = [action for action in MOVES if action not in movement]
            if len(legal) == 1:
                action, actor, reason = legal[0], "runner", "only remaining directional probe"
            else:
                model_state = {
                    "position": [state["screen"], state["x"], state["y"]],
                    "delta": history[-1].get("delta", {"x": 0, "y": 0}) if history else {"x": 0, "y": 0},
                    "modal": state.get("modal"), "page": state.get("page"),
                    "history": [{"action": item["action"], "delta": item.get("delta"),
                                 "modal": item["after"].get("modal") if isinstance(item["after"], dict) else None}
                                for item in history[-6:]],
                }
                probe = chooser.choose(model_state, task, legal)
                action, actor, reason = probe.action, "qwen", probe.reason
            before = state
            state = add_command(action, actor, reason, session.hold(MOVE_KEYS[action], 8), before)
            movement[action] = displaced(history[-1]["delta"])

        recovery_action = next((action for action in MOVES if movement[action]), MOVES[0])
        deterministic = [
            ("pause", "open modal menu", lambda: session.pause()),
            (recovery_action, "hold movement while modal is open", lambda: session.hold(MOVE_KEYS[recovery_action], 8)),
            ("resume", "close modal menu", lambda: session.pause()),
            (recovery_action, "verify movement after resume", lambda: session.hold(MOVE_KEYS[recovery_action], 8)),
        ]
        for action, reason, command in deterministic:
            if len(history) >= max_actions:
                raise QwenInconclusive("bounded action limit reached before menu coverage")
            before = state
            state = add_command(action, "runner", reason, command(), before)
            if reason == "open modal menu":
                pause_ok = bool(state.get("modal"))
                if not pause_ok:
                    raise QwenInconclusive("pause command did not open a modal menu")
            elif reason == "hold movement while modal is open":
                held_ok = bool(state.get("modal")) and not displaced(history[-1]["delta"])
                if not held_ok:
                    raise QwenInconclusive("modal menu closed or movement occurred during held movement")
            elif reason == "close modal menu":
                resume_ok = not bool(state.get("modal"))
                if not resume_ok:
                    raise QwenInconclusive("resume command did not close modal menu")
            else:
                recovery_ok = displaced(history[-1]["delta"])
        phase = "done"
        if rendered:
            screenshot = session.screenshot("qwen-final.png")
            if not screenshot.get("ok"):
                raise QwenInconclusive("rendered screenshot failed: " + str(screenshot.get("error", "unknown error")))
    except (QwenUnavailable, QwenInconclusive, RuntimeError, TimeoutError) as exc:
        failure = str(exc)

    all_immobile = len(movement) == len(MOVES) and not any(movement.values())
    mobility = "suspected_stuck" if all_immobile else ("pass" if any(movement.values()) else "inconclusive")
    menu = "pass" if pause_ok and held_ok and resume_ok and recovery_ok else "inconclusive"
    session_dir = getattr(session, "session_dir", None)
    result = {
        "verdict": "pass" if not failure and mobility == "pass" and menu == "pass" else "inconclusive",
        "error": failure,
        "scenario": {key: initial_telemetry.get(key) for key in ("screen", "x", "y")} if initial_telemetry else {},
        "startup": startup,
        "session_dir": str(session_dir) if session_dir else None,
        "movement": movement,
        "mobility_check": mobility,
        "menu_check": menu,
        "pause_verified": pause_ok,
        "paused_hold_verified": held_ok,
        "resumed_verified": resume_ok,
        "recovery_verified": recovery_ok,
        "remaining_probes": [] if phase == "done" else [phase],
        "history": history,
        "qwen": chooser.records,
        "screenshot": screenshot,
        "limits": {"max_actions": max_actions, "timeout_seconds": chooser.timeout,
                   "max_tokens": 160, "temperature": 0},
    }
    write_report(report, result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Run bounded local-Qwen Dink playtest")
    parser.add_argument("--report", default="builds/playtests/qwen/report.json")
    parser.add_argument("--max-actions", type=int, default=12)
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--screen", type=int, default=407)
    parser.add_argument("--x", type=float, default=320)
    parser.add_argument("--y", type=float, default=390)
    args = parser.parse_args()

    from playtest import PlaytestSession
    session_dir = Path(args.report).with_suffix(".session")
    try:
        with PlaytestSession(session_dir=session_dir, rendered=args.rendered, screen=args.screen,
                             x=args.x, y=args.y) as session:
            result = run_session(session, args.report, args.max_actions, timeout=args.timeout,
                                 rendered=args.rendered)
    except Exception as exc:
        result = {"verdict": "inconclusive", "error": "harness failure: " + str(exc),
                  "session_dir": str(session_dir)}
        write_report(args.report, result)
    print(json.dumps(result, indent=2))
    return 0 if result.get("verdict") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
