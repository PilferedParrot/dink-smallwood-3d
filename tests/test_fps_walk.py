import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', str(Path.home() / '.local/bin/Godot_v4.6.1-stable_linux.x86_64'))


def test_opening_route_with_three_dimensional_collision():
    result = subprocess.run(
        [GODOT, '--headless', '--path', 'game', '--script', str(ROOT / 'tests/fps_walk_test.gd')],
        cwd=ROOT, text=True, capture_output=True, timeout=40,
    )
    assert result.returncode == 0 and 'FPS WALK PASS' in result.stdout and 'SCRIPT ERROR' not in result.stderr, result.stdout + result.stderr
