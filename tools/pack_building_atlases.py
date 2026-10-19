#!/usr/bin/env python3
"""Share compatible face repairs; crop split atlases without changing donors."""

import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

if __package__:
    from .building_continuations import authored_mask, polygon_mask
else:
    from building_continuations import authored_mask, polygon_mask


def mip_bytes(width, height):
    total = 0
    while True:
        total += width * height * 4
        if width == height == 1:
            return total
        width = max(1, width // 2)
        height = max(1, height // 2)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--polygons", type=Path, required=True)
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--margin", type=int, default=8)
    args = ap.parse_args()
    data = json.loads(args.manifest.read_text())
    polygons = json.loads(args.polygons.read_text())["polygons"]
    by_key = {p["key"]: p for p in polygons}
    paths = json.loads(args.images.read_text())
    images = {}
    groups = {}
    native_aliases = {}
    excluded = {p["key"] for p in data["excluded"]}
    hut_domains = {}
    for p in polygons:
        if "|hutrow" in p["group"] and p["key"] not in excluded:
            hut_domains.setdefault(p["source"], []).append(p)

    def image(source):
        if source not in images:
            a = np.asarray(Image.open(paths[source]).convert("RGBA"))
            images[source] = authored_mask(a)
        return images[source]

    def details(source, domain):
        support = image(source)
        height, width = support.shape
        all_uv = np.concatenate([p["uv"] for p in domain])
        lo = np.floor(all_uv.min(0)).astype(int)
        hi = np.ceil(all_uv.max(0)).astype(int)
        x0 = min(0, int(lo[0]))
        y0 = min(0, int(lo[1]))
        w = max(width, int(hi[0])) - x0
        h = max(height, int(hi[1])) - y0
        face = np.zeros((h, w), bool)
        for p in domain:
            face |= polygon_mask(p["uv"], [x0, y0, w, h])
        author = np.zeros_like(face)
        author[-y0 : height - y0, -x0 : width - x0] = support
        labels, n = ndimage.label(face & ~author)
        sizes = np.bincount(labels.ravel())
        keep = (sizes[labels] == 1) & (labels != 0)
        protected = {(int(y) + y0, int(x) + x0) for y, x in np.argwhere(keep)}
        sensitive = False
        for p in domain:
            xyz = np.array(p["pts"]) * p["point_scale"] / 0.025
            screen = np.stack(
                (xyz[:, 0], (xyz[:, 2] - xyz[:, 1]) / np.sqrt(2)), axis=1
            ) * (1280 / 600)
            P = np.stack((screen[1] - screen[0], screen[2] - screen[0]), axis=1)
            Q = np.stack(
                (np.array(p["uv"][1]) - p["uv"][0], np.array(p["uv"][2]) - p["uv"][0]),
                axis=1,
            )
            if np.linalg.matrix_rank(P, tol=1e-8) < 2:
                continue
            rho = np.linalg.svd(Q @ np.linalg.inv(P), compute_uv=False)[0]
            sensitive |= bool(rho >= 1 - 32 * np.finfo(np.float32).eps)
        return all_uv, protected, sensitive

    def add(source, key, mapping, domain, donor_source):
        uv, protected, sensitive = details(source, domain)
        pool = groups.setdefault(source, [])
        conflicts = []
        for group in pool:
            clash = (
                any(
                    p in group["map"] and group["map"][p] != d
                    for p, d in mapping.items()
                )
                or bool(set(mapping) & group["protected"])
                or bool(protected & set(group["map"]))
            )
            if not clash:
                break
            conflicts.append(group["id"])
        else:
            group = {
                "id": source + "@" + str(len(pool)),
                "source": source,
                "donor_source": donor_source,
                "map": {},
                "protected": set(),
                "members": [],
                "uv": [],
                "sensitive": False,
                "conflicts": conflicts,
            }
            pool.append(group)
        group["map"].update(mapping)
        group["protected"] |= protected
        group["members"].append(key)
        group["uv"].append(uv)
        group["sensitive"] |= sensitive
        return group["id"]

    # Existing donor maps are immutable: sharing changes neither assignments nor G1.
    for key, e in data["faces"].items():
        x0, y0, w, h = e["rect"]
        mapping = {
            (int(dst) // w + y0, int(dst) % w + x0): int(donor)
            for dst, donor in e["copies"]
        }
        domain = (
            hut_domains[e["source"]] if e["source"] in hut_domains else [by_key[key]]
        )
        e["atlas_id"] = add(e["source"], key, mapping, domain, e["donor_source"])
    # Reuse those atlases for unchanged faces too, unless their retained holes
    # conflict. An empty group reuses the original texture, without another copy.
    repaired = set(data["faces"]) | set(data.get("aliases", {}))
    for p in polygons:
        key = p["key"]
        source = p["source"]
        if key in repaired or key in excluded or source not in groups:
            continue
        donor = (
            source[:-1] + "1"
            if source.startswith("kit:") and source.endswith("#0")
            else source
        )
        native_aliases[key] = add(source, key, {}, [p], donor)
    atlases = {}
    private = 0
    sensitive_count = 0
    for source, pool in groups.items():
        height, width = image(source).shape
        for group in pool:
            uv = np.concatenate(group["uv"])
            m = args.margin
            if not group["map"]:
                rect = [0, 0, width, height]
            elif group["sensitive"]:
                # Original-camera mip sampling is tied to the original atlas
                # dimensions. Preserve that lattice for these shared groups.
                lo = np.minimum(np.floor(uv.min(0)), [0, 0]).astype(int)
                hi = np.maximum(np.ceil(uv.max(0)), [width, height]).astype(int)
                rect = [int(lo[0]), int(lo[1]), int(hi[0] - lo[0]), int(hi[1] - lo[1])]
                sensitive_count += 1
            else:
                lo = (np.floor((uv.min(0) - m) / m) * m).astype(int)
                hi = (np.ceil((uv.max(0) + m) / m) * m).astype(int)
                rect = [int(lo[0]), int(lo[1]), int(hi[0] - lo[0]), int(hi[1] - lo[1])]
            x0, y0, w, h = rect
            copies = [
                [(y - y0) * w + x - x0, donor]
                for (y, x), donor in sorted(group["map"].items())
            ]
            assert all(0 <= dst < w * h for dst, donor in copies)
            atlases[group["id"]] = {
                "atlas_key": group["id"],
                "source": source,
                "donor_source": group["donor_source"],
                "source_size": [width, height],
                "rect": rect,
                "copies": copies,
                "members": group["members"],
                "conflicts_with": group["conflicts"],
                "source_order": int(source.rsplit("#", 1)[1]),
                "native_mip_lattice": group["sensitive"],
            }
            private += int(len(group["members"]) == 1 and bool(group["conflicts"]))
    data["atlases"] = atlases
    data["atlas_aliases"] = native_aliases
    for e in data["faces"].values():
        a = atlases[e["atlas_id"]]
        aw = a["rect"][2]
        ax, ay = a["rect"][:2]
        actual = {
            ((dst // aw) + ay, (dst % aw) + ax): donor for dst, donor in a["copies"]
        }
        x0, y0, w, h = e["rect"]
        assert all(
            actual[(dst // w + y0, dst % w + x0)] == donor for dst, donor in e["copies"]
        )
    data["atlas_statistics"] = {
        "repaired_faces": len(data["faces"]),
        "atlas_groups": len(atlases),
        "unchanged_face_aliases": len(native_aliases),
        "private_conflicting_faces": private,
        "native_mip_groups": sensitive_count,
        "predicted_mip_bytes": sum(
            mip_bytes(a["rect"][2], a["rect"][3]) for a in atlases.values()
        ),
        "filter_margin_native_pixels": args.margin,
    }
    temporary = args.manifest.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    temporary.replace(args.manifest)
    print(json.dumps(data["atlas_statistics"]))


if __name__ == "__main__":
    main()
