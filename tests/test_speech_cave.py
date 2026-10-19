from test_speech_input import run_speech


def test_normal_cave_noise_allows_walking_in_labelled_scenario(tmp_path):
    result = run_speech(tmp_path, "speech_cave_test.gd")
    assert result.returncode == 0 and "SPEECH CAVE PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout + result.stderr, result.stdout + result.stderr
