"""The strip mask cannot excuse changes to the rest of the original picture."""

import json
import os
from pathlib import Path
import shutil
import subprocess

import numpy as np
from PIL import Image
import pytest
from tools.building_render_gate import compare

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/building_continuations"


def test_original_camera_keeps_every_pixel_outside_the_registered_source_mask(tmp_path):
    godot = (
        os.environ.get("GODOT")
        or shutil.which("godot")
        or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
    )
    if not Path(godot).is_file() or not shutil.which("xvfb-run"):
        pytest.skip("Godot and xvfb-run required")
    bundle = tmp_path / "views.json"
    bundle.write_text(
        json.dumps(
            [{"screen": n, "name": str(n), "original": True} for n in (439, 440, 537)]
        )
    )
    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    result = subprocess.run(
        [
            "nice",
            "-n",
            "10",
            "xvfb-run",
            "-a",
            godot,
            "--audio-driver",
            "Dummy",
            "--resolution",
            "1280x800",
            "--path",
            str(ROOT / "game"),
            "--script",
            str(ROOT / "tests/building_capture.gd"),
            "--",
            f"--bundle={bundle}",
            f"--out-dir={tmp_path}",
        ],
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in output, output[-6000:]
    for n in (439, 440, 537):
        before = FIXTURES / f"{n}-before.png"
        mask = FIXTURES / f"{n}-mask.png"
        after = tmp_path / f"{n}.png"
        metrics = compare(before, after, mask)
        assert metrics["outside_mask"] == 0, (n, metrics)
        # This same mask must reject a change to an untouched pixel. It cannot
        # accidentally bless a whole frame or be fitted to observed differences.
        allowed = np.asarray(Image.open(mask).convert("L")) != 0
        y, x = np.argwhere(~allowed)[len(np.argwhere(~allowed)) // 2]
        altered = np.array(Image.open(after).convert("RGB"))
        altered[y, x, 0] ^= 255
        control = tmp_path / f"{n}-negative-control.png"
        Image.fromarray(altered).save(control)
        assert compare(before, control, mask)["outside_mask"] > 0
