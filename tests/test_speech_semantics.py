import json
from test_speech_input import run_speech


def test_source_speech_yields_only_its_caller_with_independent_text_lifetime(tmp_path):
    result = run_speech(tmp_path, "speech_semantics_test.gd")
    assert result.returncode == 0 and "SPEECH SEMANTICS PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr


def test_speech_contract_table_can_reject_a_wrong_row(tmp_path):
    result = run_speech(tmp_path, "speech_semantics_test.gd", "--flip-row")
    assert result.returncode == 1 and "say caller wait=true" in result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stdout + result.stderr
    errors = json.loads(next(line.removeprefix("SPEECH FAILURES ") for line in result.stdout.splitlines() if line.startswith("SPEECH FAILURES ")))
    assert len(errors) == 1 and errors[0].startswith("say caller wait=true"), errors
