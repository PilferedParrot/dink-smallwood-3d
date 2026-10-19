"""Catch hardcoded control names in game script prose, wherever it is displayed.

The binding registry owns event names and can spell them in its label table.
Other scripts should interpolate its labels into player-facing instructions.
This lexical gate cannot prove that prose is rendered or identify every future
device nickname; the runtime tests verify the bow toast's actual binding data.
"""

from pathlib import Path
import re
import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "game/scripts"

# These are remappable keyboard/pad names, including standalone letters in
# instructions ("Press K", "E marks ...", "K to fire"). The descriptive
# "mouse look" and generic native UI "click" are not binding promises.
NAMED_CONTROL = re.compile(
    r"\b(?:WASD|D[- ]pad|Arrows?|Space(?:bar)?|Enter|Escape|Esc|Tab|"
    r"Shift|Ctrl|Alt|Backspace|Home|End|Insert|Delete|Page[- ]?(?:Up|Down)|"
    r"F(?:[1-9]|[12][0-9]|3[0-5])|RT|LT|LB|RB|LS|RS)\b"
)
MEDIA_CONTROL = re.compile(
    r"\b(?:Media[- ](?:Play|Pause|Stop|Next|Previous|Record|Rewind|"
    r"Fast[- ]Forward)|Launch[- ](?:Mail|Media|App ?[12]|Calculator)|"
    r"Volume[- ](?:Up|Down)|Browser[- ](?:Back|Forward|Refresh|Home))\b"
)
CLICK_CONTROL = re.compile(r"\b(?:left|right|middle)\s+click\b", re.I)
MOUSE_CONTROL = re.compile(r"\b(?:left|right|middle)\s+mouse\s+(?:button|click)\b", re.I)
DEVICE_CONTROL = re.compile(
    r"\b(?i:left|right)\s+(?i:trigger|bumper|shoulder|stick)\b"
    r"|\b(?i:mouse)\s+(?:[1-9]|(?i:wheel))\b"
    r"|\b[A-Z]\s+(?i:button|key)\b"
    r"|\b(?i:key)\s+[A-Z]\b"
    r"|\b(?i:press|tap|hold|hit|use)\s+(?:(?i:the)\s+)?(?:(?i:key)\s+)?Return\b"
)
LETTER_INSTRUCTION = re.compile(
    r"\b(?i:press|tap|hold|hit|use)\s+(?:(?i:the)\s+)?(?:(?i:key)\s+)?[A-Z0-9]\b"
    r"|\b[A-Z0-9]\s+(?:to\s+(?:fire|attack|talk|open|close|jump|move|"
    r"choose|confirm|pause|equip|cast|interact)|marks?\s+equipped|"
    r"(?:fires?|attacks?|opens?|closes?|jumps?|pauses?|equips?|casts?)\b)",
)
# This E describes the equipped-state badge drawn by dink_equipment_chest.gd,
# not a key. Keep the exemption exact so a new "G marks equipped" claim fails.
EQUIPPED_MARKER_EXPLANATION = "Choose a filled slot to equip it. E marks equipped items."


def gd_strings(source: str):
    """Yield (line, literal) while ignoring comments and escaped delimiters.

    GDScript supports single, double and triple-quoted strings. We need the
    lexical value only: no source line search that can mistake comments for UI.
    """
    i = 0
    line = 1
    while i < len(source):
        char = source[i]
        if char == "#":
            newline = source.find("\n", i)
            if newline < 0:
                return
            i = newline
            continue
        if char not in "\"'":
            line += char == "\n"
            i += 1
            continue
        start_line = line
        quote = char * (3 if source.startswith(char * 3, i) else 1)
        i += len(quote)
        content = []
        while i < len(source) and not source.startswith(quote, i):
            if source[i] == "\\" and i + 1 < len(source):
                content.append(source[i + 1])
                i += 2
                continue
            content.append(source[i])
            line += source[i] == "\n"
            i += 1
        if i >= len(source):
            raise AssertionError(f"Unterminated GDScript string at line {start_line}")
        i += len(quote)
        yield start_line, "".join(content)


def hardcoded_control_hints(source: str, path: Path | None = None):
    lines = source.splitlines()
    return [
        (line, value)
        for line, value in gd_strings(source)
        if not (path is not None and path.name == "game_ui.gd"
                 and value == EQUIPPED_MARKER_EXPLANATION
                 and "_label(" in lines[line - 1])
        and not (path is not None and path.name == "dink_equipment_chest.gd"
                 and value == "E" and 'marker.text = "E"' in lines[line - 1])
        and (NAMED_CONTROL.search(value)
             or MEDIA_CONTROL.search(value)
             or CLICK_CONTROL.search(value)
             or MOUSE_CONTROL.search(value)
             or DEVICE_CONTROL.search(value)
             or LETTER_INSTRUCTION.search(value)
             or re.fullmatch(r"[A-Z]", value))
    ]


def test_game_scripts_use_binding_labels_in_control_prose():
    failures = []
    for path in sorted(SCRIPTS.glob("*.gd")):
        if path.name == "input_bindings.gd":
            continue  # Registry is the single source for literal event names.
        failures.extend(
            f"{path.relative_to(ROOT)}:{line}: {value!r}"
            for line, value in hardcoded_control_hints(path.read_text(), path)
        )
    assert not failures, "Hardcoded input name outside binding registry:\n" + "\n".join(failures)


def test_historical_bow_hint_is_caught_without_replacing_source():
    # Literal from fps_game.gd:91 at 7fa270e. Keep the negative control portable
    # to shallow checkouts and cherry-picks without that historical Git object.
    frozen = 'ui.notify("A travel bow is ready. Left click or RT to fire.")'
    assert (1, "A travel bow is ready. Left click or RT to fire.") in hardcoded_control_hints(frozen)
    with pytest.raises(AssertionError, match="Left click"):
        assert not hardcoded_control_hints(frozen), hardcoded_control_hints(frozen)


def test_new_key_prose_mutations_are_caught():
    for prose in ("Press K to fire.", "Tap J to talk.", "Use Z for magic.",
                  "G marks equipped items.", "Middle click to attack.",
                  "Hit F2 for help.", "Use D-pad right to choose.",
                  "Right trigger attacks.", "B button to talk.",
                  "Key K attacks.", "K", "Press Home to pause.",
                  "Tap PageDown to scroll.", "Press F35 for help.",
                  "Use Media Play to fire.", "Press Launch Mail to talk.",
                  "Press Return to confirm."):
        assert hardcoded_control_hints(f'ui.notify("{prose}")'), prose
    assert not hardcoded_control_hints('# ui.notify("Press K to fire.")\n')
    assert not hardcoded_control_hints('ui.notify("A travel bow is ready.")')
    assert not hardcoded_control_hints('ui._button("Return to adventure", "resume")')
    assert not hardcoded_control_hints('ui.notify("%s to fire." % bindings.label("attack"))')
    assert not hardcoded_control_hints(
        f'_label("{EQUIPPED_MARKER_EXPLANATION}")', SCRIPTS / "game_ui.gd"
    )
    chest = SCRIPTS / "dink_equipment_chest.gd"
    assert 'marker.text = "E"' in chest.read_text()
    assert not hardcoded_control_hints('marker.text = "E"', chest)
