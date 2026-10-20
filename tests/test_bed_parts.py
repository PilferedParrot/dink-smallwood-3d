"""Source-part separation must reject the actual unsplit bed and preserve native art."""

import hashlib, json, os, shutil, subprocess
from pathlib import Path
import numpy as np
from PIL import Image
import pytest
from tools.bed_parts import SOURCE, build, domains, face_report

ROOT = Path(__file__).resolve().parents[1]


def test_bed_source_parts_regenerate_and_controls_discriminate(tmp_path):
    for path in [
        Path("game") / SOURCE,
        Path("game/data/interior.json"),
        Path("game/data/bed_measurements.json"),
    ]:
        (tmp_path / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, tmp_path / path)
    data, audit = build(tmp_path)
    assert data == json.loads((ROOT / "game/data/bed_parts.json").read_text())
    assert all(
        not r["ok"] and r["mixed_local_windows"] > 0 for r in audit["baseline_faces"]
    )
    assert audit["controls"]["authored_wood_grain"]["ok"]
    assert audit["controls"]["authored_bedding_pattern"]["ok"]
    assert not audit["controls"]["unfixed_composite"]["ok"]
    source = np.asarray(Image.open(ROOT / "game" / SOURCE).convert("RGBA"))
    masks = domains(
        source, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    for role, texture in data["textures"].items():
        pixels = np.asarray(Image.open(ROOT / "game" / texture["path"]).convert("RGBA"))
        assert (tmp_path / "game" / texture["path"]).read_bytes() == (
            ROOT / "game" / texture["path"]
        ).read_bytes()
        ids = np.asarray(texture["donors"]).reshape(source.shape[:2])
        assert masks[role].ravel()[ids].all()
        assert np.array_equal(pixels[:, :, :3], source[:, :, :3].reshape(-1, 3)[ids])
        # Source-authored samples stay byte-exact. Inferred pixels are recorded.
        assert np.array_equal(pixels[masks[role]], source[masks[role]])
        # An edge-extruded or one-pixel donor cannot pass native spacing.
        assert not ((ids[:, 1:] == ids[:, :-1]) | False).any()
        assert not (ids[1:, :] == ids[:-1, :]).any()


def test_all_native_beds_use_separate_parts_and_scaled_ray_geometry(tmp_path):
    godot = (
        os.environ.get("GODOT")
        or shutil.which("godot")
        or str(Path.home() / ".local/bin/Godot_v4.6.1-stable_linux.x86_64")
    )
    if not Path(godot).is_file() or not shutil.which("xvfb-run"):
        pytest.skip("Godot and xvfb-run required")
    report = tmp_path / "beds.json"
    result = subprocess.run(
        [
            "nice",
            "-n",
            "10",
            "xvfb-run",
            "-a",
            godot,
            "--headless",
            "--audio-driver",
            "Dummy",
            "--path",
            str(ROOT / "game"),
            "--script",
            str(ROOT / "tests/bed_parts_test.gd"),
            "--",
            f"--report={report}",
        ],
        capture_output=True,
        text=True,
        timeout=180,
    )
    output = result.stdout + result.stderr
    assert (
        result.returncode == 0
        and "SCRIPT ERROR" not in output
        and "BED PARTS DONE" in output
    ), output[-6000:]
    records = json.loads(report.read_text())
    assert not records["failures"]
    assert len(records["instances"]) == 16
    rgba = np.asarray(Image.open(ROOT / "game" / SOURCE).convert("RGBA"))
    masks = domains(
        rgba, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    roles = np.zeros(rgba.shape[:2], np.uint8)
    roles[masks["wood"]] = 1
    roles[masks["bedding"]] = 2
    data = json.loads((ROOT / "game/data/bed_parts.json").read_text())
    for surface in records["faces"]:
        role = surface["role"]
        ids = np.asarray(data["textures"][role]["donors"]).reshape(roles.shape)
        pixels = np.asarray(
            Image.open(ROOT / "game" / data["textures"][role]["path"]).convert("RGBA")
        )
        assert surface["texture_sha256"] == hashlib.sha256(pixels.tobytes()).hexdigest()
        for uv in surface["faces"]:
            metrics = face_report(uv, ids, roles, 1 if role == "wood" else 2)
            assert metrics["ok"], (surface["part"], metrics)
    identity = np.arange(roles.size).reshape(roles.shape)
    for surface in records["legacy_faces"]:
        for uv in surface["faces"]:
            assert not face_report(uv, identity, roles)["ok"]
