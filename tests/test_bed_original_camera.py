"""Only the registered bed envelopes may change in the source-camera picture."""

import hashlib, json, os, shutil, subprocess
from pathlib import Path
import numpy as np
from PIL import Image
import pytest
from tools.building_render_gate import compare

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/bed_parts"


def test_bed_original_camera_changes_only_inside_committed_source_envelopes(tmp_path):
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    for name, sha in manifest["files"].items():
        assert hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest() == sha, name
    godot = (
        os.environ.get("GODOT")
        or shutil.which("godot")
        or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
    )
    if not Path(godot).is_file() or not shutil.which("xvfb-run"):
        pytest.skip("Godot and xvfb-run required")
    # Start with the known occluded case. The next view changes screen so the
    # per-bed material mutation probe cannot leak into the real fixtures.
    views = [
        {
            "name": "occluded-control",
            "screen": 1,
            "original": True,
            "retain_ceiling": True,
            "stable_wall_ties": True,
        }
    ]
    order = [n for n in manifest["screens"] if n != 1] + [1]
    views += [
        {"name": str(n), "screen": n, "original": True, "stable_wall_ties": True}
        for n in order
    ]
    views += manifest["isolated_views"]
    bundle = tmp_path / "views.json"
    bundle.write_text(json.dumps(views))
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
            str(ROOT / "tests/bed_capture.gd"),
            "--",
            f"--bundle={bundle}",
            f"--out-dir={tmp_path}",
            "--bed-visibility",
        ],
        capture_output=True,
        text=True,
        timeout=600,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in output, output[-6000:]
    occluded = json.loads((tmp_path / "occluded-control-visibility.json").read_text())
    assert occluded and all(r["pixels"] == 0 for r in occluded)
    changes = 0
    cases = [str(n) for n in manifest["screens"]] + [
        v["name"] for v in manifest["isolated_views"]
    ]
    for n in cases:
        visible = json.loads((tmp_path / f"{n}-visibility.json").read_text())
        if n in ("6", "36"):
            assert visible and all(
                r["pixels"] == 0 and r["first_hit_key"] == "wall" for r in visible
            ), (n, visible)
        else:
            assert visible and all(r["pixels"] >= 100 for r in visible), (n, visible)
        before = FIXTURES / f"{n}-before.png"
        mask = FIXTURES / f"{n}-mask.png"
        after = tmp_path / f"{n}.png"
        metrics = compare(before, after, mask)
        changes += metrics["changed"]
        assert metrics["outside_mask"] == 0, (n, metrics)
        allowed = np.asarray(Image.open(mask).convert("L")) != 0
        assert 0 < allowed.sum() < allowed.size // 5, (
            "A bed mask cannot bless the frame"
        )
        y, x = np.argwhere(~allowed)[0]
        altered = np.array(Image.open(after).convert("RGB"))
        altered[y, x, 0] ^= 255
        control = tmp_path / f"{n}-unrelated-mutation.png"
        Image.fromarray(altered).save(control)
        assert compare(before, control, mask)["outside_mask"] > 0
    assert changes > 0, (
        "A zero-change result must not hide the 70% stand-in replacement"
    )
