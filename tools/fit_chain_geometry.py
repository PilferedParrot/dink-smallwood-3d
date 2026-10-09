"""Fit cdoor-06's right chain to its own opaque pixels before rendering in Godot.

The source view is an orthographic projection of (world x, world z - world height).
This program reconstructs the same tubular triangles as castle_doors.gd and samples
their projected coverage at source resolution. It needs numpy, scipy and Pillow.
Run with one BLAS thread: OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1.
"""
import argparse
import json
import math
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.optimize import differential_evolution

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game/assets/graphics/struct/Castle/cdoor-06.png"
START_SOURCE = np.array([48.0, 19.0])
END_SOURCE = np.array([124.0, 147.0])
SPAN = float(np.linalg.norm(END_SOURCE - START_SOURCE))
SOURCE_NORMAL = np.array([-128.0, 76.0]) / SPAN
SHAPE = (192, 149)
SCALE = 4


@lru_cache(maxsize=1)
def source_anchors():
    """Read sprite placement and the fitted castle face, independently of a mesh probe."""
    world = json.loads((ROOT / "game/data/world.json").read_text())
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    screen = 80
    origin = np.array([((screen - 1) % 32) * 600.0 - 20.0,
                       ((screen - 1) // 32) * 400.0])
    sprites = world["screens"][str(screen)]["sprites"]

    def placed(filename):
        for sprite in sprites:
            frame = sequences[str(sprite["seq"])]["frames"][sprite["frame"] - 1]
            if frame["path"].endswith(filename):
                return origin + [sprite["x"] - frame["dx"],
                                 sprite["y"] - frame["dy"]]
        raise ValueError(filename)

    door_at = placed("cdoor-06.png")
    castle_at = placed("castl-05.png")
    fit = json.loads((ROOT / "game/prototype/facades.json").read_text())["_walls"]
    poly = fit["assets/graphics/struct/Castle/castl-05.png"]["parts"][0]["poly"]
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] -
               poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
    anchor_x = door_at[0] + 50.0 - castle_at[0]
    edges = []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        dx = q[0] - p[0]
        if dx and min(p[0], q[0]) <= anchor_x <= max(p[0], q[0]) and -dx * np.sign(area) > 0:
            edges.append((castle_at + p, castle_at + q))
    assert len(edges) == 1, edges
    a, b = edges[0]
    start_x = door_at[0] + START_SOURCE[0]
    wall_z = a[1] + (start_x - a[0]) * (b[1] - a[1]) / (b[0] - a[0])
    height = wall_z - (door_at[1] + START_SOURCE[1])
    start = np.array([start_x, height + .4, wall_z])
    end = np.array([door_at[0] + END_SOURCE[0], .4, door_at[1] + END_SOURCE[1]])
    return door_at, start, end


def source_mask():
    a = np.asarray(Image.open(SOURCE).convert("RGBA"))
    y, x = np.indices(SHAPE)
    distance = (-(x - 48) * 128 + (y - 19) * 76) / SPAN
    domain = (y >= 55) & (y < 109) & (x >= 65) & (x < 125) & (abs(distance) < 6)
    return (a[:, :, 3] > 127) & domain, domain


def _project(center, tangent, major, minor, wire, tilt, parity):
    lateral = np.cross(tangent, [0.0, 1.0, 0.0])
    lateral /= np.linalg.norm(lateral)
    front = lateral + np.cross(tangent, lateral)
    front /= np.linalg.norm(front)
    depth = np.cross(tangent, front)
    angle = math.radians(tilt) * (1 if parity else -1)
    side = front * math.cos(angle) + depth * math.sin(angle)
    binormal = np.cross(tangent, side)
    theta = np.arange(16) * 2 * math.pi / 16
    phi = np.arange(8) * 2 * math.pi / 8
    ct, st = np.cos(theta), np.sin(theta)
    cp, sp = np.cos(phi), np.sin(phi)
    around = center + tangent[None, :] * (major * ct[:, None]) + side[None, :] * (minor * st[:, None])
    radial = tangent[None, :] * (ct[:, None] / major) + side[None, :] * (st[:, None] / minor)
    radial /= np.linalg.norm(radial, axis=1)[:, None]
    return around[:, None, :] + wire * (radial[:, None, :] * cp[None, :, None] +
                                        binormal[None, None, :] * sp[None, :, None])


def projected_mask(profile, scale=SCALE):
    """Rasterize the same 16x8 tube quads at native source resolution."""
    door_at, start, end = source_anchors()
    major = float(profile["major_radius_px"])
    minor = float(profile["minor_radius_px"])
    wire = float(profile["wire_radius_px"])
    tilt = float(profile["plane_tilt_deg"])
    offset = float(profile["center_offset_px"])
    phase = float(profile["phase_px"])
    count = int(profile["right_link_count"])
    direction = end - start

    def path(u):
        warped = u + phase / SPAN * math.sin(math.pi * u)
        p = start + warped * direction
        shift = offset * math.sin(math.pi * u) * SOURCE_NORMAL
        return p + np.array([shift[0], 0.0, shift[1]])

    image = Image.new("L", (SHAPE[1] * scale, SHAPE[0] * scale), 0)
    draw = ImageDraw.Draw(image)
    for j, u in enumerate(np.linspace(0.0, 1.0, count)):
        center = path(float(u))
        tangent = path(min(1.0, float(u) + .001)) - path(max(0.0, float(u) - .001))
        tangent /= np.linalg.norm(tangent)
        points = _project(center, tangent, major, minor, wire, tilt, j % 2)
        uv = np.stack([points[:, :, 0] - door_at[0],
                       points[:, :, 2] - points[:, :, 1] - door_at[1] + .4], axis=2) * scale
        for i in range(16):
            nxt = (i + 1) % 16
            for k in range(8):
                nxtk = (k + 1) % 8
                draw.polygon([tuple(uv[i, k]), tuple(uv[nxt, k]),
                              tuple(uv[nxt, nxtk]), tuple(uv[i, nxtk])], fill=255)
    return np.asarray(image.resize((SHAPE[1], SHAPE[0]), Image.Resampling.BOX)) / 255.0


def rasterize_actual_triangles(vertices, door_top_left, scale=SCALE):
    """Rasterize the loaded Godot mesh probe's triangle vertices, independent of fit parameters."""
    assert len(vertices) % 3 == 0
    image = Image.new("L", (SHAPE[1] * scale, SHAPE[0] * scale), 0)
    draw = ImageDraw.Draw(image)
    for first in range(0, len(vertices), 3):
        triangle = [((vertices[i][0] - door_top_left[0]) * scale,
                     (vertices[i][1] - door_top_left[1] + .4) * scale)
                    for i in range(first, first + 3)]
        draw.polygon(triangle, fill=255)
    return np.asarray(image.resize((SHAPE[1], SHAPE[0]), Image.Resampling.BOX)) / 255.0


def mask_stats(coverage, domain):
    binary = (coverage >= .5) & domain
    envelope = np.zeros_like(binary)
    for y in range(55, 109):
        xs = np.flatnonzero(binary[y])
        if len(xs):
            envelope[y, xs.min():xs.max() + 1] = True
    holes = ndi.binary_fill_holes(binary) & ~binary
    labels, count = ndi.label(holes)
    areas = np.bincount(labels.ravel())[1:]
    return {"pixels": int(binary.sum()), "envelope_pixels": int(envelope.sum()),
            "occupancy": float(binary.sum() / max(1, envelope.sum())),
            "hole_areas": sorted((int(x) for x in areas if x), reverse=True),
            "hole_count": int(count)}


def compare_masks(coverage, source=None, domain=None):
    if source is None or domain is None:
        source, domain = source_mask()
    predicted = (coverage >= .5) & domain
    intersection = (predicted & source).sum()
    union = (predicted | source).sum()
    center_errors = []
    width_errors = []
    for y in range(55, 109):
        a = np.flatnonzero(source[y])
        b = np.flatnonzero(predicted[y])
        if len(a) and len(b):
            center_errors.append(abs((a.min() + a.max()) - (b.min() + b.max())) / 2)
            width_errors.append(abs((a.max() - a.min()) - (b.max() - b.min())))
    return {"mesh": mask_stats(coverage, domain),
            "source": mask_stats(source.astype(float), domain),
            "iou": float(intersection / max(1, union)),
            "median_row_center_error_px": float(np.median(center_errors)),
            "median_row_width_error_px": float(np.median(width_errors))}


def _occupancy(binary, domain):
    selected = binary & domain
    envelope_count = 0
    for y in range(55, 109):
        xs = np.flatnonzero(selected[y])
        if len(xs):
            envelope_count += int(xs.max() - xs.min() + 1)
    return float(selected.sum() / max(1, envelope_count))


def _training_loss(coverage, source, domain, training, wanted_occupancy):
    selected = domain & training
    target = source & selected
    background = selected & ~source
    missed = float(np.mean(1.0 - coverage[target]))
    false = float(np.mean(coverage[background]))
    # The sparse openings get equal weight to iron; raw IoU alone favors a solid strip.
    balanced = .5 * (missed + false)
    row_error = []
    for y in np.flatnonzero(np.any(selected, axis=1)):
        xs = np.flatnonzero(target[y])
        predicted = np.flatnonzero((coverage[y] >= .5) & selected[y])
        if len(xs) and len(predicted):
            row_error.append((abs((xs.min() + xs.max()) - (predicted.min() + predicted.max())) / 12.0 +
                              abs((xs.max() - xs.min()) - (predicted.max() - predicted.min())) / 8.0))
    align = float(np.mean(row_error)) if row_error else 2.0
    occupied = _occupancy(coverage >= .5, selected)
    return balanced + .08 * align + .25 * abs(occupied - wanted_occupancy)


def fit(maxiter=35, popsize=6, seed=20261008):
    source, domain = source_mask()
    y, _ = np.indices(SHAPE)
    training = (y < 91) | (y >= 103)
    holdout = (y >= 91) & (y < 103)
    wanted_train = _occupancy(source, domain & training)
    wanted_holdout = _occupancy(source, domain & holdout)
    bounds = [(3.4, 5.1), (1.8, 3.7), (.65, 1.8), (8.0, 48.0), (-3.5, 1.0), (-4.0, 4.0)]
    runs = []
    for count in (18, 19, 20, 21):
        def loss(values):
            major, minor, wire, tilt, offset, phase = values
            if minor - wire < .15 or major - wire < 1.5:
                return 2.0 + abs(minor - wire)
            p = {"major_radius_px": major, "minor_radius_px": minor,
                 "wire_radius_px": wire, "plane_tilt_deg": tilt,
                 "center_offset_px": offset, "phase_px": phase,
                 "right_link_count": count}
            return _training_loss(projected_mask(p, scale=2), source, domain, training, wanted_train)

        result = differential_evolution(loss, bounds, seed=seed + count, maxiter=maxiter,
                                        popsize=popsize, polish=False, workers=1,
                                        updating="immediate", tol=.001)
        profile = dict(zip(("major_radius_px", "minor_radius_px", "wire_radius_px",
                            "plane_tilt_deg", "center_offset_px", "phase_px"),
                           (float(x) for x in result.x)))
        profile["right_link_count"] = count
        coverage = projected_mask(profile)
        report = {"profile": profile, "train_loss": float(result.fun),
                  "holdout_loss": _training_loss(coverage, source, domain, holdout, wanted_holdout),
                  "all_stats": mask_stats(coverage, domain),
                  "source_stats": mask_stats(source.astype(float), domain)}
        runs.append(report)
        print(json.dumps({"count": count, "train": report["train_loss"],
                          "holdout": report["holdout_loss"],
                          "stats": report["all_stats"]}), flush=True)
    # Select on training loss only; the held-out rows remain a genuine check.
    return min(runs, key=lambda run: run["train_loss"]), runs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maxiter", type=int, default=35)
    parser.add_argument("--popsize", type=int, default=6)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "tmp/row8/chains/fit")
    args = parser.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    best, runs = fit(args.maxiter, args.popsize)
    (args.out_dir / "fit-report.json").write_text(json.dumps({"selected": best, "runs": runs}, indent=2) + "\n")
    Image.fromarray((projected_mask(best["profile"]) * 255).astype("uint8")).save(args.out_dir / "fitted-projection.png")
    print("SELECTED", json.dumps(best), flush=True)


if __name__ == "__main__":
    main()
