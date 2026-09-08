import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
import playtest_qwen


class Reply:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def read(self):
        return json.dumps(self.body).encode()


def fake_replies(monkeypatch, actions, *, finish_reason="stop", extra=None):
    values = iter(actions)

    def response(*_args, **_kwargs):
        content = {"action": next(values), "reason": "probe"}
        if extra:
            content.update(extra)
        return Reply({
            "model": "qwen",
            "usage": {"completion_tokens": 1},
            "choices": [{"finish_reason": finish_reason, "message": {"content": json.dumps(content)}}],
        })

    monkeypatch.setattr(playtest_qwen.urllib.request, "urlopen", response)


class Session:
    def __init__(self, fail=None, modal_moves=False, runtime_failure=False):
        self.fail = fail
        self.modal_moves = modal_moves
        self.runtime_failure = runtime_failure
        self.x = self.y = 0.0
        self.modal = False
        self.calls = []
        self.session_dir = Path("/tmp/test-qwen-session")

    def result(self, ok=True):
        return {
            "ok": ok,
            "error": "bridge failed" if not ok else "",
            "telemetry": {"screen": 407, "x": self.x, "y": self.y,
                          "modal": self.modal, "page": "menu" if self.modal else "game"},
        }

    def observe(self):
        self.calls.append("observe")
        return self.result(self.fail != "observe")

    def hold(self, action, _frames):
        self.calls.append(action)
        if self.runtime_failure:
            raise TimeoutError("bridge timeout")
        if self.fail == action:
            return self.result(False)
        if not self.modal or self.modal_moves:
            self.x += 1
        return self.result()

    def pause(self):
        self.calls.append("pause")
        if self.fail == "pause":
            return self.result(False)
        self.modal = not self.modal
        return self.result()


def test_invalid_action_is_inconclusive_and_retains_usage(monkeypatch):
    fake_replies(monkeypatch, ["shell"])
    chooser = playtest_qwen.ActionChooser()
    try:
        chooser.choose({}, "test", ["up", "down"])
    except playtest_qwen.QwenInconclusive:
        pass
    else:
        raise AssertionError("illegal action must not become success")
    assert chooser.records[0]["usage"] == {"completion_tokens": 1}
    assert chooser.records[0]["latency_ms"] >= 0


def test_truncated_and_extra_fields_are_inconclusive(monkeypatch):
    fake_replies(monkeypatch, ["up"], finish_reason="length")
    with_chooser = playtest_qwen.ActionChooser()
    try:
        with_chooser.choose({}, "test", ["up", "down"])
    except playtest_qwen.QwenInconclusive:
        pass
    else:
        raise AssertionError("truncated response must be rejected")
    fake_replies(monkeypatch, ["up"], extra={"extra": True})
    try:
        playtest_qwen.ActionChooser().choose({}, "test", ["up", "down"])
    except playtest_qwen.QwenInconclusive:
        pass
    else:
        raise AssertionError("extra JSON fields must be rejected")


def test_runner_history_and_pause_protect_false_positive(monkeypatch):
    fake_replies(monkeypatch, ["up", "down", "left"])
    result = playtest_qwen.run_session(Session(), max_actions=8)
    assert result["verdict"] == "pass"
    assert len(result["history"]) == 8
    assert [item["actor"] for item in result["history"]].count("qwen") == 3
    assert result["history"][3]["actor"] == "runner"
    assert result["paused_hold_verified"] and result["recovery_verified"]
    assert all("delta" in item and "before" in item for item in result["history"])


def test_modal_movement_is_never_a_pass(monkeypatch):
    fake_replies(monkeypatch, ["up", "down", "left"])
    result = playtest_qwen.run_session(Session(modal_moves=True), max_actions=8)
    assert result["verdict"] == "inconclusive"
    assert "movement" in result["error"]


def test_command_failure_budget_and_bridge_exception_are_reported(monkeypatch, tmp_path):
    fake_replies(monkeypatch, ["up"])
    path = tmp_path / "report.json"
    result = playtest_qwen.run_session(Session(fail="forward"), str(path), max_actions=8)
    assert result["verdict"] == "inconclusive"
    assert result["history"][-1]["response_ok"] is False
    assert json.loads(path.read_text())["qwen"]

    fake_replies(monkeypatch, ["up"])
    assert playtest_qwen.run_session(Session(), max_actions=1)["verdict"] == "inconclusive"

    fake_replies(monkeypatch, ["up"])
    runtime = playtest_qwen.run_session(Session(runtime_failure=True), max_actions=8)
    assert runtime["verdict"] == "inconclusive"
    assert "bridge timeout" in runtime["error"]
