#!/usr/bin/env python3
"""Separate the source bed's wooden frame/posts and bedding at native texel scale.

Measurements are source-pixel landmarks, not target screenshots. Unknown wood
and quilt samples use P4a's native authored-square continuation, never edge fill.
"""

from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

try:
    from .bed_contact import compute_height
except ImportError:
    from bed_contact import compute_height

try:
    from .building_continuations import authored_mask, polygon_mask, native_tile
except ImportError:
    from building_continuations import authored_mask, polygon_mask, native_tile
ROOT = Path(__file__).resolve().parents[1]
SOURCE = "assets/graphics/inside/details/inacc-03.png"


def domains(rgba, measurements):
    h, w = rgba.shape[:2]
    wood = np.zeros((h, w), bool)
    for p in measurements["post_domains"]:
        wood |= polygon_mask(p, (0, 0, w, h))
    for p in measurements["post_cloth_occlusions"]:
        wood &= ~polygon_mask(p, (0, 0, w, h))
    for p in measurements["frame_domains"]:
        wood |= polygon_mask(p, (0, 0, w, h))
    support = authored_mask(rgba)
    return {"wood": wood & support, "bedding": support & ~wood}


def face_domains(rgba, measurements):
    h, w = rgba.shape[:2]
    support = authored_mask(rgba)
    post = np.zeros((h, w), bool)
    for p in measurements["post_domains"]:
        post |= polygon_mask(p, (0, 0, w, h))
    for p in measurements["post_cloth_occlusions"]:
        post &= ~polygon_mask(p, (0, 0, w, h))
    polygons = {
        "bedding_top": measurements["bedding_top"],
        **measurements["cloth_side_domains"],
        "rail_long": measurements["frame_domains"][0],
        "rail_end": measurements["frame_domains"][1],
    }
    raw = {k: polygon_mask(p, (0, 0, w, h)) for k, p in polygons.items()}
    rail = raw["rail_long"] | raw["rail_end"]
    masks = {
        k: v & support & ~post & (~rail if not k.startswith("rail_") else True)
        for k, v in raw.items()
    }
    masks["post"] = post & support
    masks["bedding_top"] &= ~(masks["cloth_long"] | masks["cloth_end"])
    masks["cloth_long"] &= ~masks["cloth_end"]
    masks["rail_long"] &= ~masks["rail_end"]
    return masks


def donor_report(uv, donors, allowed):
    h, w = allowed.shape
    sample = polygon_mask(uv, (0, 0, w, h))
    selected = donors[sample]
    wrong = int((~allowed.ravel()[selected]).sum())
    return {
        "samples": int(sample.sum()),
        "wrong_domain": wrong,
        "ok": bool(len(selected) and wrong == 0),
    }


def expected_face_domain(part, vertices, part_vertices):
    """Classify emitted planes from geometry, independently of material tags."""
    v = np.asarray(vertices, float)
    all_v = np.asarray(part_vertices, float)
    if part.startswith("post"):
        return "post"
    if part == "frame":
        return "rail"
    assert part == "bedding", part
    if np.ptp(v[:, 1]) < 1e-6:
        return (
            "bedding_top" if abs(v[0, 1] - all_v[:, 1].max()) < 1e-6 else "cloth_long"
        )
    footprint = v[:, [0, 2]]
    differences = footprint[:, None, :] - footprint[None, :, :]
    delta = differences.reshape(-1, 2)[
        np.linalg.norm(differences.reshape(-1, 2), axis=1).argmax()
    ]
    axis = np.array([68.0, 35.0])
    cosine = abs(delta @ axis) / (np.linalg.norm(delta) * np.linalg.norm(axis))
    return "cloth_long" if cosine > 0.9 else "cloth_end"


def post_heights_from_source(measurements):
    visible = []
    for cap, foot in zip(measurements["post_caps"], measurements["post_feet"]):
        if foot is not None:
            corner = min(cap, key=lambda p: (abs(p[0] - foot[0]), -p[1]))
            visible.append(float(foot[1] - corner[1]))
    return [
        float(np.median(visible))
        if foot is None
        else float(foot[1] - min(cap, key=lambda p: (abs(p[0] - foot[0]), -p[1]))[1])
        for cap, foot in zip(measurements["post_caps"], measurements["post_feet"])
    ]


def texture(rgba, support, fallback=None):
    h, w = support.shape
    ids = np.arange(h * w).reshape(h, w)
    points = np.argwhere(~support)
    donors, method = native_tile(
        points, support if fallback is None else fallback, rgba, rgba
    )
    ids[points[:, 0], points[:, 1]] = donors[:, 0] * w + donors[:, 1]
    out = rgba.reshape(-1, 4)[ids].copy()
    out[:, :, 3] = 255
    return out, ids, method


def face_report(uv, donors, roles, expected=None):
    """Local role transitions in an emitted face; arbitrary RGB detail is inert.

    A face belongs to one physical material part. This does not forbid colour
    boundaries, stripes or pillow/quilt patterns inside the bedding part.
    """
    h, w = roles.shape
    mask = polygon_mask(uv, (0, 0, w, h))
    labels = roles.reshape(-1)[donors]
    valid = mask & (labels != 0)
    wood = valid & (labels == 1)
    cloth = valid & (labels == 2)
    local = (
        (ndimage.maximum_filter(wood.astype(np.uint8), size=3) > 0)
        & (ndimage.maximum_filter(cloth.astype(np.uint8), size=3) > 0)
        & ndimage.binary_erosion(valid)
    )
    wrong = (
        0 if expected is None else int(np.count_nonzero(valid & (labels != expected)))
    )
    return {
        "samples": int(valid.sum()),
        "wood": int(wood.sum()),
        "bedding": int(cloth.sum()),
        "mixed_local_windows": int(local.sum()),
        "wrong_role": wrong,
        "ok": bool(valid.any() and not local.any() and wrong == 0),
    }


def base_faces(fit):
    base = np.asarray(fit["base"], float)
    c = base.mean(0)
    height = float(fit["height"])
    out = []
    for i, p in enumerate(base):
        q = base[(i + 1) % len(base)]
        edge = q - p
        n = np.array([edge[1], -edge[0]])
        if n @ ((p + q) / 2 - c) < 0:
            n = -n
        if n[1] < 0:
            p, q = 2 * c - p, 2 * c - q
        out.append(np.array([p, q, q - [0, height], p - [0, height]]))
    return out + [base - [0, height]]


def build(root=ROOT):
    root = Path(root)
    source = root / "game" / SOURCE
    rgba = np.array(Image.open(source).convert("RGBA"))
    measurements = json.loads((root / "game/data/bed_measurements.json").read_text())
    masks = domains(rgba, measurements)
    h, w = rgba.shape[:2]
    fits = json.loads((root / "game/data/interior.json").read_text())
    fit = fits[SOURCE]
    roles = np.zeros((h, w), np.uint8)
    for i, key in enumerate(("wood", "bedding"), 1):
        roles[masks[key]] = i
    identity = np.arange(h * w).reshape(h, w)
    # Prove the actual baseline and the look-alike controls before recording a gate.
    before = [face_report(uv, identity, roles) for uv in base_faces(fit)]
    assert all(not r["ok"] for r in before), before
    controls = {
        "authored_wood_grain": face_report(
            [[1, 28], [7, 28], [7, 45], [1, 45]], identity, roles, 1
        ),
        "authored_bedding_pattern": face_report(
            [[30, 21], [54, 21], [54, 36], [30, 36]], identity, roles, 2
        ),
        "unfixed_composite": before[0],
    }
    assert (
        controls["authored_wood_grain"]["ok"]
        and controls["authored_bedding_pattern"]["ok"]
    ), controls
    assert not controls["unfixed_composite"]["ok"]
    textures = {}
    face_masks = face_domains(rgba, measurements)
    for domain, support in face_masks.items():
        fallback = support
        if domain.startswith("rail_"):
            fallback = face_masks["rail_long"] | face_masks["rail_end"]
        elif domain == "bedding_top":
            fallback = support & polygon_mask(
                measurements["quilt_donor_domain"], (0, 0, w, h)
            )
        elif domain == "post":
            x, y, side = measurements["post_donor_square"]
            fallback = np.zeros_like(support)
            fallback[y : y + side, x : x + side] = True
            assert np.all(fallback <= support)
        elif domain in measurements["cloth_donor_squares"]:
            x, y, side = measurements["cloth_donor_squares"][domain]
            fallback = np.zeros_like(support)
            fallback[y : y + side, x : x + side] = True
            assert np.all(fallback <= support)
        out, ids, method = texture(rgba, support, fallback)
        path = f"assets/derived/bed-{domain.replace('_', '-')}.png"
        (root / "game" / path).parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(out).save(root / "game" / path)
        textures[domain] = {
            "path": path,
            "donors": ids.ravel().tolist(),
            "inferred": int((~support).sum()),
            "method": method,
        }
    # Source extrema provide the shared post height. Quilt and rail heights are
    # measured down the visible long edge, not from a desired world dimension.
    top = np.asarray(measurements["bedding_top"], float)
    post_heights = post_heights_from_source(measurements)
    contact_fit = compute_height(
        {
            "bedding_top": top.tolist(),
            "post_caps": measurements["post_caps"],
            "post_heights": post_heights,
        }
    )
    height = float(contact_fit["height"])
    left, front = top[3], top[2]
    x = float(measurements["long_edge_sample"]["x"])
    edge_y = float(
        left[1] + (front[1] - left[1]) * (x - left[0]) / (front[0] - left[0])
    )
    ground = edge_y + height
    levels = {
        key: round(ground - float(row), 4)
        for key, row in measurements["long_edge_sample"]["rows"].items()
    }
    # Adjacent last-cloth/first-rail pixel rows share the first rail boundary;
    # they are not a one-pixel air gap in the physical assembly.
    levels["bedding_bottom"] = levels["frame_top"]
    visible = []
    for cap, foot in zip(measurements["post_caps"], measurements["post_feet"]):
        if foot is not None:
            corner = min(cap, key=lambda p: (abs(p[0] - foot[0]), -p[1]))
            visible.append(float(foot[1] - corner[1]))
    post_heights = []
    for cap, foot in zip(measurements["post_caps"], measurements["post_feet"]):
        corner = (
            None
            if foot is None
            else min(cap, key=lambda p: (abs(p[0] - foot[0]), -p[1]))
        )
        post_heights.append(
            float(np.median(visible)) if foot is None else float(foot[1] - corner[1])
        )
    data = {
        "source": SOURCE,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "size": [w, h],
        "post_height": float(fit["height"]),
        "bedding_height": height,
        "contact_fit": contact_fit,
        "bedding_top": top.tolist(),
        "post_caps": measurements["post_caps"],
        "post_heights": post_heights,
        "levels": levels,
        "textures": textures,
    }
    return data, {"baseline_faces": before, "controls": controls, "levels": levels}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, default=ROOT)
    p.add_argument("--audit", type=Path)
    a = p.parse_args()
    data, audit = build(a.root)
    (a.root / "game/data/bed_parts.json").write_text(
        json.dumps(data, separators=(",", ":")) + "\n"
    )
    if a.audit:
        a.audit.write_text(json.dumps(audit, indent=2) + "\n")
    print(json.dumps(audit, indent=2))


if __name__ == "__main__":
    main()
