#!/usr/bin/env python3
"""Native-pixel continuation of unsupported fitted-building texture strips.

Copies authored patches; never blends/paints colours. See docs/DIRECTION.md.
The input polygons/masks are exported from the frozen constructor, not inferred
from a screenshot. Local donor provenance is retained to audit edge extrusion.
"""

from __future__ import annotations
import argparse, hashlib, json, math
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage, signal

ROOT = Path(__file__).resolve().parents[1]


def polygon_key(source: str, uv) -> str:
    return (
        source
        + "|"
        + ";".join(
            f"{x:.2f},{y:.2f}"
            for x, y in sorted((float(p[0]), float(p[1])) for p in uv)
        )
    )


def polygon_mask(uv, rect):
    x0, y0, w, h = rect
    yy, xx = np.mgrid[y0 : y0 + h, x0 : x0 + w]
    xx = xx + 0.5
    yy = yy + 0.5
    p = np.asarray(uv, float)
    inside = np.zeros((h, w), bool)
    # Exactly the emitter's triangle fan, including non-affine hut quads.
    for i in range(1, len(p) - 1):
        tri = p[[0, i, i + 1]]
        a, b = tri[1] - tri[0], tri[2] - tri[0]
        if abs(a[0] * b[1] - a[1] * b[0]) < 1e-8:
            continue
        signs = []
        for a, b in zip(tri, np.roll(tri, -1, axis=0)):
            signs.append((b[0] - a[0]) * (yy - a[1]) - (b[1] - a[1]) * (xx - a[0]))
        c = np.array(signs)
        inside |= np.all(c >= -1e-7, axis=0) | np.all(c <= 1e-7, axis=0)
    return inside


def authored_mask(rgba):
    a = rgba[:, :, 3] >= 128
    black = a & (rgba[:, :, :3].astype(np.int32).sum(2) <= 10)
    neighbours = ndimage.convolve(
        black.astype(np.uint8),
        np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]]),
        mode="constant",
    )
    return a & ~(black & (neighbours == 0))


def nearest_provenance(support):
    """Exactly the emitter's row-major, four-neighbour multi-source BFS."""
    h, w = support.shape
    ids = np.full(h * w, -1, np.int32)
    source = np.flatnonzero(support.ravel())
    ids[source] = source
    q = deque(source.tolist())
    while q:
        p = q.popleft()
        x = p % w
        for n in (p - 1 if x else -1, p + 1 if x < w - 1 else -1, p - w, p + w):
            if 0 <= n < h * w and ids[n] < 0:
                ids[n] = ids[p]
                q.append(n)
    return ids.reshape(h, w)


def tangent_uv(pts, uv):
    p = np.asarray(pts, float)
    u = np.asarray(uv, float)
    P = np.stack([p[1] - p[0], p[2] - p[0]], axis=1)
    Q = np.stack([u[1] - u[0], u[2] - u[0]], axis=1)
    n = np.cross(P[:, 0], P[:, 1])
    d = np.cross(n, [0.0, 1.0, 0.0])
    if np.linalg.norm(d) < 1e-10:
        d = P[:, 0]
    t = Q @ np.linalg.pinv(P) @ d
    if t[0] < 0 or (abs(t[0]) < 1e-10 and t[1] < 0):
        t = -t
    return t / max(np.linalg.norm(t), 1e-20)


def _choose_patch(points, valid, rgba, tangent, target_rgba=None):
    if target_rgba is None:
        target_rgba = rgba
    """Find a rigid translated donor for this entire target shape."""
    y0, x0 = points.min(0)
    y1, x1 = points.max(0) + 1
    shape = np.zeros((y1 - y0, x1 - x0), np.float64)
    shape[points[:, 0] - y0, points[:, 1] - x0] = 1
    if shape.shape[0] > valid.shape[0] or shape.shape[1] > valid.shape[1]:
        return None
    # Search the preferred one-dimensional native tangent before expanding to
    # the whole atlas. This is exactly the same candidate preference as below,
    # but avoids scanning every kit pixel once per singleton shadow hole.
    if abs(tangent[0]) > 1e-10:
        dx = np.arange(-x0, valid.shape[1] - x1 + 1)
        expected = dx * tangent[1] / tangent[0]
        line = np.unique(
            np.concatenate(
                [
                    np.stack((np.floor(expected).astype(int), dx), axis=1),
                    np.stack((np.ceil(expected).astype(int), dx), axis=1),
                ]
            ),
            axis=0,
        )
        line = line[
            (np.abs(line[:, 0] - line[:, 1] * tangent[1] / tangent[0]) <= 0.5)
            & (line[:, 0] >= -y0)
            & (line[:, 0] <= valid.shape[0] - y1)
        ]
    else:
        dy = np.arange(-y0, valid.shape[0] - y1 + 1)
        line = np.stack((dy, np.zeros_like(dy)), axis=1)
    feasible = []
    batch_size = max(1, min(256, 1000000 // len(points)))
    for at in range(0, len(line), batch_size):
        shifts = line[at : at + batch_size]
        p = points[None, :, :] + shifts[:, None, :]
        feasible.extend(shifts[valid[p[:, :, 0], p[:, :, 1]].all(1)])
    if len(feasible):
        shifts = np.asarray(feasible)
    else:
        if len(points) <= 8:
            height = valid.shape[0] - shape.shape[0] + 1
            width = valid.shape[1] - shape.shape[1] + 1
            possible = np.ones((height, width), bool)
            for py, px in points - [y0, x0]:
                possible &= valid[py : py + height, px : px + width]
            candidates = np.argwhere(possible)
        else:
            hits = signal.fftconvolve(
                valid.astype(float), shape[::-1, ::-1], mode="valid"
            )
            candidates = np.argwhere(hits > len(points) - 0.25)
        if not len(candidates):
            return None
        shifts = candidates - [y0, x0]
    # Only immutable authored neighbours determine the seam error. No cut or
    # blend reaches into the source art. A source translation preserves rank.
    members = set(map(tuple, points.tolist()))
    boundary = []
    for y, x in points:
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if (
                (ny, nx) not in members
                and 0 <= ny < valid.shape[0]
                and 0 <= nx < valid.shape[1]
                and valid[ny, nx]
            ):
                boundary.append((ny, nx))
    boundary = np.unique(np.asarray(boundary, dtype=int).reshape(-1, 2), axis=0)
    scores = []
    if len(boundary):
        target = target_rgba[boundary[:, 0], boundary[:, 1], :3].astype(float)
        # Evaluate the same exhaustive boundary SSD in bounded NumPy batches;
        # Python per-candidate loops are expensive on the large kit canvases.
        for at in range(0, len(shifts), 256):
            batch = shifts[at : at + 256]
            donor = boundary[None, :, :] + batch[:, None, :]
            inside = (
                (donor[:, :, 0] >= 0)
                & (donor[:, :, 1] >= 0)
                & (donor[:, :, 0] < valid.shape[0])
                & (donor[:, :, 1] < valid.shape[1])
            )
            yy = np.clip(donor[:, :, 0], 0, valid.shape[0] - 1)
            xx = np.clip(donor[:, :, 1], 0, valid.shape[1] - 1)
            good = inside & valid[yy, xx]
            error = np.square(rgba[yy, xx, :3].astype(float) - target[None, :, :]).sum(
                2
            )
            counts = good.sum(1)
            sums = np.where(good, error, 0).sum(1)
            means = np.divide(
                sums, 3 * counts, out=np.full(len(batch), np.inf), where=counts > 0
            )
            scores.extend(
                (float(e), int(dy * dy + dx * dx), int(dy), int(dx))
                for e, (dy, dx) in zip(means, batch)
            )
    else:
        scores = [(0.0, int(dy * dy + dx * dx), int(dy), int(dx)) for dy, dx in shifts]
    _, _, dy, dx = min(scores)
    return np.array([dy, dx])


def native_tile(points, valid, rgba, target_rgba):
    """Largest authored square, repeated without shearing patch joins.

    Three texels is the minimum period preserving distinct IDs in every 3x3
    audit window. The selected square is nearest the missing component; phase
    alone is selected by immutable-boundary colour error.
    """
    integral = np.pad(valid.astype(np.int32), ((1, 0), (1, 0))).cumsum(0).cumsum(1)

    def squares(size):
        return (
            integral[size:, size:]
            - integral[:-size, size:]
            - integral[size:, :-size]
            + integral[:-size, :-size]
            == size * size
        )

    lo = 0
    hi = min(valid.shape) + 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if squares(mid).any():
            lo = mid
        else:
            hi = mid
    if lo < 3:
        raise ValueError("material has no authored 3x3 native tile")
    origins = np.argwhere(squares(lo))
    distances = np.square(origins + (lo - 1) / 2 - points.mean(0)).sum(1)
    origin = origins[np.argmin(distances)]
    members = set(map(tuple, points.tolist()))
    boundary = []
    for y, x in points:
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if (
                (ny, nx) not in members
                and 0 <= ny < valid.shape[0]
                and 0 <= nx < valid.shape[1]
                and valid[ny, nx]
            ):
                boundary.append((ny, nx))
    boundary = np.unique(np.asarray(boundary, dtype=int).reshape(-1, 2), axis=0)
    best = None
    for py in range(lo):
        for px in range(lo):
            phase = np.array([py, px])
            donors = origin + (boundary - phase) % lo
            error = (
                float(
                    np.square(
                        rgba[donors[:, 0], donors[:, 1], :3].astype(float)
                        - target_rgba[boundary[:, 0], boundary[:, 1], :3]
                    ).mean()
                )
                if len(boundary)
                else 0.0
            )
            score = (error, py, px)
            if best is None or score < best[0]:
                best = (score, phase)
    phase = best[1]
    donors = origin + (points - phase) % lo
    return donors, {
        "kind": "periodic_native_square",
        "origin_yx": origin.tolist(),
        "size": lo,
        "phase_yx": phase.tolist(),
    }


def patch_map(target, valid, rgba, tangent, fallback_valid=None, target_rgba=None):
    """Cover unsupported components with native-scale authored translations."""
    labels, n = ndimage.label(target)
    copies = []
    patches = []

    def place(points, component):
        pool = valid
        offset = _choose_patch(points, pool, rgba, tangent, target_rgba)
        if offset is None and fallback_valid is not None:
            pool = fallback_valid
            offset = _choose_patch(points, pool, rgba, tangent, target_rgba)
        if offset is None:
            donor, description = native_tile(
                points, pool, rgba, target_rgba if target_rgba is not None else rgba
            )
        else:
            donor = points + offset
            description = {"kind": "translation", "offset_yx": offset.tolist()}
        assert pool[donor[:, 0], donor[:, 1]].all()
        patch_id = len(patches)
        patches.append(dict(description, component=component, pixels=len(points)))
        copies.extend(
            (int(y), int(x), int(sy), int(sx), patch_id)
            for (y, x), (sy, sx) in zip(points, donor)
        )

    for component in range(1, n + 1):
        place(np.argwhere(labels == component), component)
    return copies, patches


def plan_face(
    source, pts, uv, rgba, pool_uvs=None, key=None, donor_rgba=None, domain_uvs=None
):
    if donor_rgba is None:
        donor_rgba = rgba
    assert rgba.shape == donor_rgba.shape
    uv = np.asarray(uv, float)
    domain = domain_uvs or [uv]
    all_uv = np.concatenate(domain)
    lo = np.floor(all_uv.min(0)).astype(int)
    hi = np.ceil(all_uv.max(0)).astype(int)
    if np.linalg.matrix_rank(uv[1:] - uv[0], tol=1e-8) < 2:
        return None
    # Retain native atlas dimensions whenever all UVs are inside: identical
    # normalization and texel centres keep authored pixels numerically stable.
    h, w = rgba.shape[:2]
    x0 = min(0, int(lo[0]))
    y0 = min(0, int(lo[1]))
    x1 = max(w, int(hi[0]))
    y1 = max(h, int(hi[1]))
    rect = [x0, y0, x1 - x0, y1 - y0]
    face = np.zeros((rect[3], rect[2]), bool)
    for member_uv in domain:
        face |= polygon_mask(member_uv, rect)
    padded = np.zeros((rect[3], rect[2], 4), np.uint8)
    padded[-y0 : h - y0, -x0 : w - x0] = rgba
    authored = np.zeros(face.shape, bool)
    authored[-y0 : h - y0, -x0 : w - x0] = authored_mask(rgba)
    target = face & ~authored
    # A singleton has no internal repeated run or two-dimensional Jacobian.
    # Keep its existing nearest padding: it is already a green G1 region, and
    # recolouring these isolated dither holes changes the art unnecessarily.
    components, count = ndimage.label(target)
    sizes = np.bincount(components.ravel())
    retained_singletons = int(np.count_nonzero(sizes[1:] == 1))
    target &= sizes[components] > 1
    if not target.any():
        return None
    donor_padded = np.zeros_like(padded)
    donor_padded[-y0 : h - y0, -x0 : w - x0] = donor_rgba
    donor_authored = np.zeros(face.shape, bool)
    donor_authored[-y0 : h - y0, -x0 : w - x0] = authored_mask(donor_rgba)
    valid = face & donor_authored
    pool = valid.copy()
    for member_uv in pool_uvs or []:
        pool |= polygon_mask(member_uv, rect) & donor_authored
    if not pool.any():
        return {
            "key": key or polygon_key(source, uv),
            "unresolved": "material group has no authored donor",
            "source": source,
            "pts": pts,
            "uv": uv.tolist(),
            "unsupported": int(target.sum()),
        }
    copies, patches = patch_map(
        target, valid, donor_padded, tangent_uv(pts, uv), pool, padded
    )
    packed = []
    for y, x, sy, sx, patch in copies:
        packed.append([y * rect[2] + x, (sy + y0) * w + (sx + x0)])
    return {
        "key": key or polygon_key(source, uv),
        "source": source,
        "rect": rect,
        "source_size": [w, h],
        "copies": packed,
        "patches": patches,
        "retained_singletons": retained_singletons,
        "unsupported": int(target.sum()),
        "pts": pts,
        "uv": uv.tolist(),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("polygons", type=Path)
    ap.add_argument("--images", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    data = json.loads(args.polygons.read_text())
    images = {}
    faces = {}
    unresolved = []
    excluded = []
    aliases = {}
    hut_plans = {}
    if args.images:
        data["images"] = json.loads(args.images.read_text())
    fits = json.loads((ROOT / "game/prototype/facades.json").read_text())
    for f in data["polygons"]:
        path = f["source"].split("#")[0]
        if f.get("group", "").endswith("|polys") and path in fits:
            p = np.asarray(f["pts"], float)
            c = p.mean(0)
            options = []
            for original in fits[path]["faces"]:
                q = np.asarray(original["pts"], float)
                n = np.cross(q[1] - q[0], q[2] - q[0])
                length = np.linalg.norm(n)
                if length < 1e-12:
                    continue
                error = float(np.abs((p - q[0]) @ (n / length)).max())
                # Geometry matching only: source fit vertices have 0.01px precision.
                distance = float(np.linalg.norm(c - q.mean(0)))
                options.append(
                    (error, distance, int(original["block"]), int(original["label"]))
                )
            error, _, block, label = min(options)
            if error > 0.02:
                raise ValueError(
                    f"Cannot match explicit polygon to source material plane: {path} {error}"
                )
            f["group"] = f["source"] + f"|block{block}-label{label}"
    groups = {}
    for f in data["polygons"]:
        groups.setdefault(f.get("group", f["source"]), []).append(f["uv"])
    for i, f in enumerate(data["polygons"]):
        source = f["source"]
        image = Path(data["images"][source])
        if source not in images:
            images[source] = np.asarray(Image.open(image).convert("RGBA"))
        key = f.get("key") or polygon_key(source, f["uv"])
        if np.linalg.matrix_rank(np.array(f["uv"])[1:] - f["uv"][0], tol=1e-8) < 2:
            excluded.append(dict(f, reason="rank-deficient UV parameterisation"))
            continue
        if key in faces or key in aliases:
            continue
        is_hut = "|hutrow" in f.get("group", "")
        if is_hut and source in hut_plans:
            canonical = hut_plans[source]
            if canonical is not None:
                aliases[key] = canonical
            continue
        donor_source = (
            source[:-1] + "1"
            if source.startswith("kit:") and source.endswith("#0")
            else source
        )
        if donor_source not in images:
            images[donor_source] = np.asarray(
                Image.open(data["images"][donor_source]).convert("RGBA")
            )
        domain = (
            [
                q["uv"]
                for q in data["polygons"]
                if q["source"] == source
                and "|hutrow" in q.get("group", "")
                and np.linalg.matrix_rank(np.array(q["uv"])[1:] - q["uv"][0], tol=1e-8)
                >= 2
            ]
            if is_hut
            else None
        )
        planned = plan_face(
            source,
            f["pts"],
            f["uv"],
            images[source],
            domain or groups[f.get("group", source)],
            key,
            images[donor_source],
            domain,
        )
        if is_hut:
            hut_plans[source] = key if planned and "unresolved" not in planned else None
        if planned is None:
            continue
        if "unresolved" in planned:
            unresolved.append(planned)
            continue
        planned["donor_source"] = donor_source
        if is_hut:
            planned["atlas_key"] = source
        faces[key] = planned
        if i % 100 == 0:
            print(i, "polygons,", len(faces), "continued", flush=True)
    out = {
        "format": 1,
        "facades_sha256": hashlib.sha256(
            (ROOT / "game/prototype/facades.json").read_bytes()
        ).hexdigest(),
        "source_support_sha256": {
            k: hashlib.sha256(authored_mask(v).tobytes()).hexdigest()
            for k, v in images.items()
        },
        "faces": faces,
        "aliases": aliases,
        "unresolved": unresolved,
        "excluded": excluded,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_suffix(args.out.suffix + ".tmp")
    temporary.write_text(json.dumps(out, separators=(",", ":")) + "\n")
    temporary.replace(args.out)
    print(len(faces), "continued polygons,", len(unresolved), "unresolved")


if __name__ == "__main__":
    main()
