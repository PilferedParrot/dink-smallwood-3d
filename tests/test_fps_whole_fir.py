"""RC5 complete original fir: fitted source feet, exhaustive logic and live host."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
FIT = ROOT / "game/prototype/rc5_firs.json"
GODOT = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4") or str(
    Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64"
)


def test_fit_matches_original_pixels():
    # The fit must be recalculable from source art, and scene visibility must
    # never be baked into this shared geometry file.
    from importlib.util import module_from_spec, spec_from_file_location

    spec = spec_from_file_location("rc5_fir_fit", ROOT / "tools/rc5_fir_fit.py")
    assert spec and spec.loader
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    fit = json.loads(FIT.read_text())
    assert fit["schema"] == "rc5-whole-fir-fit-1"
    assert "placements" not in fit and "visibility" not in fit
    whole = fit["template"]
    assert whole["path"] == "assets/graphics/lands/Trees/tree-01.png"
    assert whole["crown_height_px"] == 176
    assert whole["source_foot_px"] == [83.5, 176]
    assert module.measure(whole["path"]) == {
        key: whole[key] for key in ("rows", "source_foot_px", "crown_bbox_px",
                                  "crown_height_px", "image_size_px")
    }
    assert len(fit["source_parts"]) == 2
    for path, parts in fit["source_parts"].items():
        assert len(parts) == 2
        for part in parts:
            row0, row1 = part["rows"]
            measured = module.measure(path, row0, row1)
            assert all(part[key] == value for key, value in measured.items())
            assert part["source_foot_in_full_art_px"] == [
                measured["source_foot_px"][0], row0 + measured["source_foot_px"][1]
            ]
            assert part["uniform_scale"] == measured["crown_height_px"] / whole["crown_height_px"]
    world = json.loads((ROOT / "game/data/world.json").read_text())["screens"]
    placements = [e for screen in world.values() if not screen.get("indoor")
                  for e in screen["sprites"] if e.get("seq") == 32
                  and e.get("frame") in (9, 10) and e.get("vision", 0) == 0]
    assert len(placements) == 123
    assert sum(e["type"] == 1 for e in placements) == 116
    assert sum(e["type"] == 0 for e in placements) == 7


def _godot(tmp_path: Path, *args: str) -> str:
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "LP_NUM_THREADS": "4", "XDG_DATA_HOME": str(tmp_path / "profile")})
    command = ["nice", "-n", "10", GODOT, "--headless", "--audio-driver", "Dummy",
               "--path", str(ROOT / "game"), "--script", "res://../tests/fps_whole_fir_test.gd"]
    if args:
        command.extend(("--", *args))
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "SCRIPT ERROR" not in output, output
    return output


def test_all_source_parts_build_complete_geometry(tmp_path: Path):
    output = _godot(tmp_path)
    assert "WHOLE FIR PASS placements=123 type1=116 type0=7" in output


def test_live_host_replaces_partial_art_in_439_view(tmp_path: Path):
    # This is red on RC4: three cropped tree-09/10 cards still stand in 439's
    # scene, including 375 editor 1 lower part. It checks actual integration.
    output = _godot(tmp_path, "--live")
    assert "WHOLE FIR LIVE PASS" in output
