from test_speech_input import run_speech


def test_ambient_speech_does_not_capture_dismissal_and_saves_follow_source(tmp_path):
    result = run_speech(tmp_path, "speech_review_test.gd", timeout=120)
    assert result.returncode == 0 and "SPEECH REVIEW PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
