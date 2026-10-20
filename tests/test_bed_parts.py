"""Source-part separation must reject the actual unsplit bed and preserve native art."""

import hashlib, json, os, shutil, subprocess
from pathlib import Path
import numpy as np
from PIL import Image
import pytest
from tools.bed_parts import (
    SOURCE,
    build,
    domains,
    face_report,
    face_domains,
    donor_report,
    expected_face_domain,
)
from tools.bed_contact import contact_report

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
    masks = face_domains(
        source, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    identity = np.arange(source.shape[0] * source.shape[1]).reshape(source.shape[:2])
    measured = json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    for role, (x, y, side) in measured["cloth_donor_squares"].items():
        patch = [[x, y], [x + side, y], [x + side, y + side], [x, y + side]]
        assert donor_report(patch, identity, masks[role])["ok"], (
            "Original hanging-cloth detail must remain green"
        )
    contaminated = np.load(
        ROOT / "tests/fixtures/bed_parts/cloth-contaminated-post-donors.npy"
    )
    # Actual packed first-fix atlas: a post outline included cloth in front of it.
    assert np.count_nonzero(~masks["post"].ravel()[contaminated]) > 0
    assert np.all(masks["post"].ravel()[identity[masks["post"]]])
    for role, texture in data["textures"].items():
        pixels = np.asarray(Image.open(ROOT / "game" / texture["path"]).convert("RGBA"))
        assert (tmp_path / "game" / texture["path"]).read_bytes() == (
            ROOT / "game" / texture["path"]
        ).read_bytes()
        ids = np.asarray(texture["donors"]).reshape(source.shape[:2])
        allowed = (
            (masks["rail_long"] | masks["rail_end"])
            if role.startswith("rail_")
            else masks[role]
        )
        assert allowed.ravel()[ids].all()
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
    assert len(records["faces"]) == 36
    assert len(records["instances"]) == 16
    rgba = np.asarray(Image.open(ROOT / "game" / SOURCE).convert("RGBA"))
    masks = domains(
        rgba, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    roles = np.zeros(rgba.shape[:2], np.uint8)
    roles[masks["wood"]] = 1
    roles[masks["bedding"]] = 2
    data = json.loads((ROOT / "game/data/bed_parts.json").read_text())
    parts = {}
    for surface in records["faces"]:
        parts.setdefault(surface["part"].removeprefix("bed:"), []).extend(
            surface["vertices"]
        )
    contact = contact_report(parts)
    assert contact["pass"], contact
    moved = {k: np.asarray(v).copy() for k, v in parts.items()}
    direction = moved["post0"].mean(0) - moved["bedding"].mean(0)
    direction[1] = 0
    direction /= np.linalg.norm(direction)
    moved["post0"] += direction * 0.1
    assert not contact_report(moved)[
        "pass"
    ]  # 4 native source pixels, correct materials
    transformed = {k: np.asarray(v) * 1.7 + [120, 3, -35] for k, v in parts.items()}
    assert contact_report(transformed)["pass"]
    face_masks = face_domains(
        rgba, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    for surface in records["faces"]:
        role = surface["role"]
        domain = surface["domain"]
        ids = np.asarray(data["textures"][domain]["donors"]).reshape(roles.shape)
        pixels = np.asarray(
            Image.open(ROOT / "game" / data["textures"][domain]["path"]).convert("RGBA")
        )
        assert surface["texture_sha256"] == hashlib.sha256(pixels.tobytes()).hexdigest()
        for uv, vertices in zip(surface["faces"], surface["face_vertices"]):
            metrics = face_report(uv, ids, roles, 1 if role == "wood" else 2)
            assert metrics["ok"], (surface["part"], metrics)
            part = surface["part"].removeprefix("bed:")
            physical = np.asarray(vertices, float)
            centre = np.asarray(parts[part], float).mean(0)
            normal = np.cross(physical[1] - physical[0], physical[2] - physical[0])
            if normal @ (physical.mean(0) - centre) < 0:
                normal = -normal
            normal /= np.linalg.norm(normal)
            if normal[2] > 0.1 or normal[1] > 0.1:
                projected = (
                    np.c_[physical[:, 0], physical[:, 2] - physical[:, 1]] / 0.025
                )
                assert np.allclose(projected, uv, atol=5e-4), (
                    "Measured visible faces keep native source projection"
                )
            expected = expected_face_domain(part, vertices, parts[part])
            allowed = (
                (face_masks["rail_long"] | face_masks["rail_end"])
                if expected == "rail"
                else face_masks[expected]
            )
            provenance = donor_report(uv, ids, allowed)
            assert provenance["ok"], (part, surface["surface"], expected, provenance)
            if expected in ["cloth_long", "cloth_end"]:
                # Both are cloth: a wood-vs-cloth gate would wrongly accept.
                wrong = "cloth_end" if expected == "cloth_long" else "cloth_long"
                wrong_ids = np.asarray(data["textures"][wrong]["donors"]).reshape(
                    roles.shape
                )
                assert not donor_report(uv, wrong_ids, allowed)["ok"]
                top_ids = np.asarray(data["textures"]["bedding_top"]["donors"]).reshape(
                    roles.shape
                )
                assert not donor_report(uv, top_ids, allowed)["ok"]
    identity = np.arange(roles.size).reshape(roles.shape)
    for surface in records["legacy_faces"]:
        for uv in surface["faces"]:
            assert not face_report(uv, identity, roles)["ok"]


def test_reviewed_bed_artifact_fails_contact_and_side_content_gates():
    fixture = json.loads(
        (ROOT / "tests/fixtures/bed_parts/reviewed-meshes.json").read_text()
    )
    assert fixture["candidate"] == "18897e843d1f27ec7a159f4fef2d5a3969fa54e6"
    parts = {}
    for surface in fixture["faces"]:
        parts.setdefault(surface["part"].removeprefix("bed:"), []).extend(
            surface["vertices"]
        )
    assert not contact_report(parts)["pass"]
    rgba = np.asarray(Image.open(ROOT / "game" / SOURCE).convert("RGBA"))
    masks = face_domains(
        rgba, json.loads((ROOT / "game/data/bed_measurements.json").read_text())
    )
    ids = np.load(ROOT / "tests/fixtures/bed_parts/reviewed-bedding-donors.npy")
    failures = []
    for surface in fixture["faces"]:
        if surface["part"] != "bed:bedding":
            continue
        for uv, vertices in zip(surface["faces"], surface["face_vertices"]):
            if np.ptp(np.asarray(vertices)[:, 1]) < 1e-6:
                continue
            expected = expected_face_domain("bedding", vertices, parts["bedding"])
            if expected in ["cloth_long", "cloth_end"]:
                failures.append(not donor_report(uv, ids, masks[expected])["ok"])
    assert len(failures) >= 4 and all(failures)
