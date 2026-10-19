#!/usr/bin/env python3
"""G1: local donor support, Jacobians and runs against authored controls.

Images are exported by export_building_continuations.gd. Singleton padding is
retained; rank-deficient UVs are explicitly outside this continuation gate.
"""

import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

if __package__:
    from .building_continuations import authored_mask, nearest_provenance
else:
    from building_continuations import authored_mask, nearest_provenance


def local_metrics(points, ids, width):
    yy, xx = points.T
    values = ids[yy, xx]
    pos = {tuple(p): i for i, p in enumerate(points)}
    coords = np.stack((values % width, values // width), axis=1).astype(float)
    repeated = 0
    edge_count = 0
    singular = []
    support = []
    max_run = 1
    for axis in (0, 1):
        order = sorted(
            range(len(points)), key=lambda i: (points[i, 1 - axis], points[i, axis])
        )
        run = 1
        previous = None
        for i in order:
            if (
                previous is not None
                and points[i, 1 - axis] == points[previous, 1 - axis]
                and points[i, axis] == points[previous, axis] + 1
                and values[i] == values[previous]
            ):
                run += 1
            else:
                run = 1
            max_run = max(max_run, run)
            previous = i
    for i, (y, x) in enumerate(points):
        local = []
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                j = pos.get((y + dy, x + dx))
                if j is not None:
                    local.append(values[j])
        support.append(len(set(local)) / len(local))
        for dy, dx in [(0, 1), (1, 0)]:
            j = pos.get((y + dy, x + dx))
            if j is not None:
                edge_count += 1
                repeated += int(values[i] == values[j])
        a = pos.get((y, x + 1))
        b = pos.get((y + 1, x))
        if a is not None and b is not None:
            singular.append(
                np.linalg.svd(
                    np.stack((coords[a] - coords[i], coords[b] - coords[i]), axis=1),
                    compute_uv=False,
                ).tolist()
            )
    return {
        "distinct_support_min": min(support),
        "max_repeated_run": max_run,
        "repeated_edges": repeated,
        "edges": edge_count,
        "jacobian_min_singular": min((p[-1] for p in singular), default=None),
        "jacobian_samples": len(singular),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    paths = json.loads(args.images.read_text())
    cache = {}

    def source(key):
        if key not in cache:
            rgba = np.asarray(Image.open(paths[key]).convert("RGBA"))
            mask = authored_mask(rgba)
            digest = hashlib.sha256(mask.tobytes()).hexdigest()
            assert digest == manifest["source_support_sha256"][key], key
            cache[key] = (rgba, mask, nearest_provenance(mask))
        return cache[key]

    m = manifest
    records = []
    controls = {}
    failures = []
    for key, e in m["faces"].items():
        a, mask, old = source(e["source"])
        h, w = mask.shape
        x0, y0, rw, rh = e["rect"]
        valid = np.zeros((rh, rw), bool)
        valid[-y0 : h - y0, -x0 : w - x0] = mask
        target = np.zeros((rh, rw), bool)
        new = np.full((rh, rw), -1, np.int32)
        base = np.full_like(new, -1)
        base[-y0 : h - y0, -x0 : w - x0] = old
        for dst, donor in e["copies"]:
            y, x = divmod(dst, rw)
            target[y, x] = 1
            new[y, x] = donor
            da, dm, _ = source(e["donor_source"])
            dw = dm.shape[1]
            assert dm.flat[donor], (key, donor)
            assert not valid[y, x], (key, dst)
            if base[y, x] < 0:
                base[y, x] = old[(y + y0) % h, (x + x0) % w]
        labels, n = ndimage.label(target)
        for i in range(1, n + 1):
            p = np.argwhere(labels == i)
            b = local_metrics(p, base, w)
            f = local_metrics(p, new, w)
            bad = (
                f["distinct_support_min"] < 1
                or f["repeated_edges"]
                or (
                    f["jacobian_min_singular"] is not None
                    and f["jacobian_min_singular"] < 1 - 1e-8
                )
            )
            r = {
                "key": key,
                "component": i,
                "pixels": len(p),
                "baseline": b,
                "continued": f,
                "pass": not bool(bad),
            }
            records.append(r)
            if bad:
                failures.append(r)
        if e["source"] not in controls:
            interior = ndimage.binary_erosion(
                mask, structure=np.ones((3, 3), bool), iterations=1
            )
            ys, xs = np.nonzero(interior)
            if len(ys):
                y, x = int(ys[len(ys) // 2]), int(xs[len(xs) // 2])
                p = np.array(
                    [(y + dy, x + dx) for dy in range(-1, 2) for dx in range(-1, 2)]
                )
                identity = np.arange(h * w).reshape(h, w)
                controls[e["source"]] = {
                    "centre_yx": [y, x],
                    **local_metrics(p, identity, w),
                }
    # Negative controls include source panels that need no multi-texel repair.
    for source_key in paths:
        if source_key in controls:
            continue
        a, mask, _ = source(source_key)
        h, w = mask.shape
        interior = ndimage.binary_erosion(mask, structure=np.ones((3, 3), bool))
        ys, xs = np.nonzero(interior)
        if len(ys):
            y, x = int(ys[len(ys) // 2]), int(xs[len(xs) // 2])
            p = np.array(
                [(y + dy, x + dx) for dy in range(-1, 2) for dx in range(-1, 2)]
            )
            identity = np.arange(h * w).reshape(h, w)
            controls[source_key] = {
                "centre_yx": [y, x],
                **local_metrics(p, identity, w),
            }
    summary = {
        "components": len(records),
        "failures": len(failures),
        "baseline_red_components": sum(
            r["baseline"]["distinct_support_min"] < 1
            or r["baseline"]["repeated_edges"]
            or (
                r["baseline"]["jacobian_min_singular"] is not None
                and r["baseline"]["jacobian_min_singular"] < 1 - 1e-8
            )
            for r in records
        ),
        "controls": controls,
        "records": records,
        "excluded_rank1": len(m["excluded"]),
        "retained_singletons_in_canonical_maps": sum(
            e.get("retained_singletons", 0) for e in m["faces"].values()
        ),
    }
    args.out.write_text(json.dumps(summary) + "\n")
    print({k: v for k, v in summary.items() if k not in ("records", "controls")})
    print("authored controls", len(controls))
    assert not m["unresolved"], m["unresolved"]
    assert summary["baseline_red_components"] > 0
    assert not failures, (
        str(len(failures)) + " continued components fail native controls"
    )
    assert all(
        c["distinct_support_min"] == 1
        and c["max_repeated_run"] == 1
        and c["jacobian_min_singular"] >= 1 - 1e-8
        for c in controls.values()
    )


if __name__ == "__main__":
    main()
