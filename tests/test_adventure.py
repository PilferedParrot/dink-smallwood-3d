import os
from pathlib import Path
import shutil
import subprocess
import pytest

ROOT = Path(__file__).parents[1]
GODOT = os.environ.get('GODOT') or shutil.which('godot') or shutil.which('godot4') or str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64')

@pytest.mark.skipif(not Path(GODOT).is_file(), reason='Set GODOT to execute gameplay tests')
def test_opening_adventure_and_all_imported_screens():
    result = subprocess.run([GODOT, '--headless', '--path', 'game', '--script', str(ROOT / 'tests/adventure_test.gd')], cwd=ROOT, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0 and 'ADVENTURE PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout + result.stderr

@pytest.mark.skipif(not Path(GODOT).is_file(), reason='Set GODOT to execute combat tests')
def test_combat_brains_and_callbacks():
    result = subprocess.run([GODOT, '--headless', '--path', 'game', '--script', str(ROOT / 'tests/combat_test.gd')], cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0 and 'COMBAT PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout + result.stderr
