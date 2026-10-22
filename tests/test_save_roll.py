"""Save slots that say what they are, and one startup roll per visit (save-roll unit)."""
from test_speech_input import run_speech


def _run(tmp_path, script, marker, timeout):
    result = run_speech(tmp_path, script, timeout=timeout)
    out = result.stdout + result.stderr
    assert result.returncode == 0 and marker in result.stdout and "SCRIPT ERROR" not in out, out


def test_save_slots_say_what_they_hold_and_load_their_own_state(tmp_path):
    _run(tmp_path, "save_slots_test.gd", "SAVE SLOTS PASS", 200)


def test_every_input_to_a_slot_label_and_a_slot_choice(tmp_path):
    _run(tmp_path, "save_label_class_test.gd", "SAVE LABEL CLASS PASS", 200)


def test_a_startup_roll_lives_one_visit(tmp_path):
    _run(tmp_path, "arrival_visit_roll_test.gd", "ARRIVAL ROLL PASS", 400)


def test_every_startup_draw_screen_rolls_per_visit(tmp_path):
    _run(tmp_path, "arrival_visit_class_test.gd", "ARRIVAL CLASS PASS", 400)


def test_a_previewed_screen_is_the_screen_met_beside_a_shared_startup_script(tmp_path):
    _run(tmp_path, "arrival_adjacent_test.gd", "ARRIVAL ADJACENT PASS", 600)


def test_startup_state_is_not_reused_across_a_load_or_a_sandbox_run(tmp_path):
    _run(tmp_path, "startup_state_reuse_test.gd", "STARTUP STATE REUSE PASS", 400)
