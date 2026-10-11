"""RC5 complete firs from all three partial source frames."""
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
    assert len(fit["source_parts"]) == 3
    for path, parts in fit["source_parts"].items():
        if path.endswith("tree-08.png"):
            assert len(parts) == 4
            measured, evidence = module.measure_strip8(path, {**whole, "path": whole["path"]})
            assert parts == measured and fit["source08_apex_evidence"] == evidence
            assert [p["source_foot_in_full_art_px"] for p in parts] == [
                [3.5, 188.0], [42.0, 176.0], [125.5, 176.0], [203.5, 188.0]
            ]
            assert [p["source_window_x_px"] for p in parts] == [
                [0, 20], [20, 81], [81, 162], [162, 200]
            ]
            assert parts[3]["source_foot_in_full_art_px"][0] - parts[0]["source_foot_in_full_art_px"][0] == 200
            continue
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
                  and e.get("frame") in (8, 9, 10) and e.get("vision", 0) == 0]
    assert len(placements) == 163
    assert sum(e["type"] == 1 for e in placements) == 154
    assert sum(e["type"] == 0 for e in placements) == 9
    assert sum(e["frame"] == 8 and e["type"] == 1 for e in placements) == 38
    assert sum(e["frame"] == 8 and e["type"] == 0 for e in placements) == 2
    assert [(int(n), e["index"]) for n, screen in world.items() for e in screen["sprites"]
            if not screen.get("indoor") and e.get("seq") == 32 and e.get("frame") == 8
            and e.get("type") == 0] == [(188, 4), (284, 1)]
    # The new strip crowns do not duplicate a 9/10 whole-fir root, even when
    # all authored members (including scene-hidden ones) are considered.
    frames = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]["32"]["frames"]
    roots = {8: [], 9: [], 10: []}
    for n, screen in world.items():
        if screen.get("indoor"):
            continue
        ox, oy = ((int(n)-1) % 32) * 600 - 20, ((int(n)-1) // 32) * 400
        for e in screen["sprites"]:
            if e.get("seq") != 32 or e.get("frame") not in roots or e.get("vision", 0) != 0:
                continue
            frame = e["frame"]
            d = frames[frame-1]
            for p in fit["source_parts"][d["path"]]:
                fx, fy = p["source_foot_in_full_art_px"]
                roots[frame].append((ox+e["x"]-d["dx"]+fx, oy+e["y"]-d["dy"]+fy))
    assert not [(a, b) for a in roots[8] for b in (*roots[9], *roots[10])
                if abs(a[0]-b[0]) <= 3 and abs(a[1]-b[1]) <= 3]


def _godot(tmp_path: Path, *args: str) -> str:
    if not Path(GODOT).is_file():
        pytest.skip("Godot unavailable; set GODOT")
    env = os.environ.copy()
    env.update({"OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
                "LP_NUM_THREADS": "4", "XDG_DATA_HOME": str(tmp_path / "profile"),
                "XDG_CONFIG_HOME": str(tmp_path / "config"), "XDG_CACHE_HOME": str(tmp_path / "cache")})
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
    assert "WHOLE FIR PASS placements=163 type1=154 type0=9 shown=267 strip_type1=131 strip_type0=8" in output


def test_live_host_replaces_partial_art_in_439_and_768_views(tmp_path: Path):
    # This is red on RC4: three cropped tree-09/10 cards still stand in 439's
    # scene, including 375 editor 1 lower part. It checks actual integration.
    output = _godot(tmp_path, "--live")
    assert "WHOLE FIR LIVE PASS" in output
