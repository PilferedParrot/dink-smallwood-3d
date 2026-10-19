from test_speech_input import run_speech


def test_speech_wait_option_persists_and_uses_each_remapped_talk_binding(tmp_path):
    for phase in ["write", "read"]:
        result = run_speech(tmp_path, "speech_accessibility_test.gd", phase)
        assert result.returncode == 0 and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
    assert "SPEECH ACCESSIBILITY PASS" in result.stdout
