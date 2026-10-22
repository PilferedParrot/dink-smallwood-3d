"""Cave terrain classes: outline pinches, the interior's open-edge colour, replaced tile pixels (headless)."""
from test_speech_input import run_speech


def test_outline_pinches_edge_colour_and_replaced_pixels(tmp_path):
    result = run_speech(tmp_path, "terrain_class_test.gd", timeout=400)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and "TERRAIN CLASS PASS" in result.stdout and "SCRIPT ERROR" not in out, out
