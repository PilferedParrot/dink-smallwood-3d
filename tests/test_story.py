import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / 'tools'))
from compile_story import compile_file, parse_story

def test_nested_control_flow_and_expression_ast():
    out = parse_story('void main(void) { int &x = random(2, 1); if (&x == 1) { say_stop(&current_sprite, "hello"); } else return; }', 'X')
    code = out['scripts']['x']['procedures']['main']['code']
    assert code[0]['op'] == 'set' and code[0]['expr']['kind'] == 'call'
    assert code[1]['op'] == 'if' and code[1]['condition']['op'] == '=='
    assert out['report']['complete']

def test_labels_calls_and_overrides():
    out = parse_story('void main() { loop: wait(1)\n goto loop; }', 'X')
    code = out['scripts']['x']['procedures']['main']['code']
    assert [x['op'] for x in code] == ['label', 'call', 'goto']
    out = parse_story('void main() { say_stop(&current_sprite, "old"); }', 'X', {'old': 'new'})
    assert out['scripts']['x']['procedures']['main']['code'][0]['args'][1]['value'] == 'new'

def test_unsupported_syntax_is_reported_and_retained():
    out = parse_story('void main() { mystery @; }', 'X')
    assert not out['report']['complete']
    assert any(x['op'] == 'unsupported' for x in out['scripts']['x']['procedures']['main']['code'])


def test_choice_positions_and_script_scoped_overrides():
    source = '''void main() {
        choice_start()
        (&gate == 1) "Hidden first"
        "Second"
        choice_end()
    }'''
    overrides = {
        'global': {},
        'scripts': {'first-script': {'Second': 'Changed second'}}
    }
    first = parse_story(source, 'FIRST-SCRIPT', overrides)
    second = parse_story(source, 'SECOND-SCRIPT', overrides)
    first_choices = [x for x in first['scripts']['first-script']['procedures']['main']['code'] if x['op'] == 'choice_option']
    assert [x['result'] for x in first_choices] == [1, 2]
    assert first_choices[1]['text'] == 'Changed second'
    assert first['report']['dialogue_overrides'] == {'Second': 1}
    second_choices = [x for x in second['scripts']['second-script']['procedures']['main']['code'] if x['op'] == 'choice_option']
    assert second_choices[1]['text'] == 'Second'
    assert second['report']['dialogue_overrides'] == {}


def test_installed_campaign_compiles_without_unsupported_code():
    source = Path('/usr/share/games/dink/dink/Story')
    if not source.is_dir():
        return
    overrides = json.loads((Path(__file__).parents[1] / 'tools' / 'dialogue_overrides.json').read_text())
    compiled = [compile_file(path, overrides) for path in sorted(source.glob('*.c'))]
    assert len(compiled) == 381
    assert all(item['report']['complete'] for item in compiled)
    assert sum(len(item['report']['unsupported']) for item in compiled) == 0
    assert sum(len(item['report']['recoveries']) for item in compiled) == 14
    excluded = [entry for item in compiled for entry in item['report']['excluded']]
    assert excluded == [{'line': 20, 'procedure': '2become1', 'reason': 'non-executable numeric procedure excluded'}]
    applied = {key for item in compiled for key in item['report']['dialogue_overrides']}
    expected = {key for values in overrides['scripts'].values() for key in values}
    assert applied == expected
    assert sum(sum(item['report']['dialogue_overrides'].values()) for item in compiled) == 41
    spice = next(item for item in compiled if 'spice' in item['scripts'])
    assert '2become1' not in spice['scripts']['spice']['procedures']


def test_dink_vm_regressions():
    root = Path(__file__).parents[1]
    candidates = [
        os.environ.get('GODOT'),
        shutil.which('godot4'),
        shutil.which('godot'),
        '/home/chris/.local/bin/Godot_v4.6.1-stable_linux.x86_64',
    ]
    godot = next((candidate for candidate in candidates if candidate and Path(candidate).is_file()), None)
    if godot is None:
        return
    completed = subprocess.run(
        [godot, '--headless', '--path', str(root / 'game'), '--script', str(root / 'tests' / 'vm_test.gd')],
        cwd=root,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert 'DinkVM regression tests passed' in completed.stdout
