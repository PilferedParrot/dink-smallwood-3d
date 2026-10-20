#!/usr/bin/env python3
"""Contacts between the emitted bed's convex prism components.

Vertex API: mapping part name -> iterable of emitted (x, y, z) triples. A
triangle soup is accepted; duplicate vertices are harmless. All dimensions are
in emitter/world units. XZ convex hulls are used deliberately: this checks
support envelopes, not concave holes or exact mesh connectivity.
"""

from __future__ import annotations
import json
import math
from pathlib import Path
from typing import Iterable, Mapping, Sequence

POINT_EPS = 1e-7
AREA_EPS = 1e-6
Y_EPS = 1e-7


def hull(points):
    pts = sorted(set((float(p[0]), float(p[1])) for p in points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo = []
    for p in pts:
        while len(lo) > 1 and cross(lo[-2], lo[-1], p) <= POINT_EPS:
            lo.pop()
        lo.append(p)
    hi = []
    for p in reversed(pts):
        while len(hi) > 1 and cross(hi[-2], hi[-1], p) <= POINT_EPS:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def polygon_area(poly):
    if len(poly) < 3:
        return 0.0
    return abs(
        sum(
            poly[i][0] * poly[(i + 1) % len(poly)][1]
            - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly))
        )
        / 2
    )


def intersect_convex(subject, clip):
    """Sutherland-Hodgman clipping; returns projected intersection polygon."""
    out = list(subject)
    if len(out) < 3 or len(clip) < 3:
        return []
    signed = sum(
        clip[i][0] * clip[(i + 1) % len(clip)][1]
        - clip[(i + 1) % len(clip)][0] * clip[i][1]
        for i in range(len(clip))
    )
    orient = 1.0 if signed >= 0 else -1.0
    for i, a in enumerate(clip):
        b = clip[(i + 1) % len(clip)]

        def side(p):
            return orient * (
                (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
            )

        inp, out = out, []
        if not inp:
            break
        prev = inp[-1]
        sp = side(prev)
        for cur in inp:
            sc = side(cur)
            if (sc >= -POINT_EPS) != (sp >= -POINT_EPS):
                den = sp - sc
                if abs(den) > 1e-30:
                    t = sp / den
                    out.append(
                        (
                            prev[0] + t * (cur[0] - prev[0]),
                            prev[1] + t * (cur[1] - prev[1]),
                        )
                    )
            if sc >= -POINT_EPS:
                out.append(cur)
            prev, sp = cur, sc
    return out


def contact_report(parts: Mapping[str, Iterable[Sequence[float]]]):
    """Report all required pair contacts from actual emitted vertices.

    Required names: frame, bedding, post0..post3. Each flattened triangle
    vertex contributes to both its XZ footprint and its Y min/max interval.
    Contact passes only when projected overlap has positive area and the Y
    intervals overlap or touch within Y_EPS.
    """
    geom = {}
    for name, vertices in parts.items():
        verts = [tuple(map(float, v[:3])) for v in vertices]
        if not verts:
            raise ValueError(f"part {name} has no vertices")
        geom[name] = {
            "hull_xz": hull((v[0], v[2]) for v in verts),
            "y_interval": [min(v[1] for v in verts), max(v[1] for v in verts)],
        }
    pairs = [("frame", f"post{i}") for i in range(4)]
    pairs += [("bedding", f"post{i}") for i in range(4)]
    pairs += [("bedding", "frame")]
    results = []
    for a, b in pairs:
        if a not in geom or b not in geom:
            results.append({"pair": [a, b], "pass": False, "reason": "missing part"})
            continue
        ga, gb = geom[a], geom[b]
        overlap = intersect_convex(ga["hull_xz"], gb["hull_xz"])
        area = polygon_area(overlap)
        ya, yb = ga["y_interval"], gb["y_interval"]
        gap = max(ya[0] - yb[1], yb[0] - ya[1], 0.0)
        results.append(
            {
                "pair": [a, b],
                "projected_overlap_area": area,
                "vertical_gap": gap,
                "pass": area > AREA_EPS and gap <= Y_EPS,
            }
        )
    return {
        "pass": all(r["pass"] for r in results),
        "tolerances": {
            "point": POINT_EPS,
            "area_positive": AREA_EPS,
            "vertical_touch": Y_EPS,
        },
        "parts": geom,
        "pairs": results,
    }


def vertical_slice(poly, x):
    zs = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        if min(a[0], b[0]) - POINT_EPS <= x <= max(a[0], b[0]) + POINT_EPS:
            if abs(b[0] - a[0]) <= POINT_EPS:
                if abs(x - a[0]) <= POINT_EPS:
                    zs.extend((a[1], b[1]))
            else:
                t = (x - a[0]) / (b[0] - a[0])
                if -POINT_EPS <= t <= 1 + POINT_EPS:
                    zs.append(a[1] + t * (b[1] - a[1]))
    return (min(zs), max(zs)) if zs else None


def compute_height(parts):
    """Intersect analytic post scanline intervals for matched bed corners."""
    bed = parts["bedding_top"]
    mapping = [3, 0, 1, 2]
    intervals = []
    for i, corner_index in enumerate(mapping):
        x, source_z = bed[corner_index]
        # Post polygon's source vertical coordinate is shifted by its height;
        # corner world Z is source_z + common bed height.
        lo, hi = vertical_slice(hull(parts["post_caps"][i]), x)
        lo += parts["post_heights"][i]
        hi += parts["post_heights"][i]
        intervals.append([lo - source_z, hi - source_z])
    lower = max(i[0] for i in intervals)
    upper = min(i[1] for i in intervals)
    if lower > upper:
        raise ValueError(f"no common height interval: {intervals}")
    return {
        "per_corner_intervals": intervals,
        "common_interval": [lower, upper],
        "height": (lower + upper) / 2,
    }
