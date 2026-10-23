#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Passage bottlenecks of the live mover against the original's raw hitmap (unit 3, check G1).

For each screen: the raw map is Hard.dat tiles plus the raw hardboxes of the editor layer (what FreeDink's
live_screen.cpp writes into the hitmap); the live map is the game's own `_blocked` for the player, dumped by
tests/clearance_mask_dump.gd. Every pair of raw edge-opening runs is connected by a widest path (the largest minimum
Euclidean distance to a blocked cell); a pair is NARROWER when the live bottleneck is below the raw one.
The widest-path and portal routines are adapted from tools/triage_passages.py of codex/dink-triage (9c06b5b, GPT-6 Luna).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy import ndimage

from collision_map import hardbox, rect_mask, tile_mask

ROOT = Path(__file__).resolve().parents[1]
SCREENS = (2, 3, 408, 409, 439)
X_ORIGIN = 20


def runs(free: np.ndarray) -> list[tuple[int, int]]:
    edges = np.flatnonzero(np.diff(np.pad(free.astype(np.int8), (1, 1))))
    return [(int(a), int(b)) for a, b in zip(edges[::2], edges[1::2])]


def edge_portals(blocked: np.ndarray) -> list[dict]:
    height, width = blocked.shape
    sides = (("north", ~blocked[0, :], lambda p: p), ("south", ~blocked[-1, :], lambda p: (height - 1) * width + p),
             ("west", ~blocked[:, 0], lambda p: p * width), ("east", ~blocked[:, -1], lambda p: p * width + width - 1))
    result = []
    for side, free, index in sides:
        for a, b in runs(free):
            result.append({"id": len(result), "side": side, "interval": [a, b], "indices": [index(p) for p in range(a, b)]})
    return result


def widest_paths(blocked: np.ndarray, portals: list[dict]) -> list[list[float]]:
    """Maximum over paths of the minimum EDT radius between every portal pair (union-find from the widest cell down)."""
    height, width = blocked.shape
    free = ~blocked
    clearance = ndimage.distance_transform_edt(free).ravel()
    flat_free = free.ravel()
    count = height * width
    active = np.zeros(count, bool)
    parent = np.arange(count, dtype=np.int32)
    size = np.ones(count, dtype=np.int32)
    bits = [0] * count
    portal_at = [0] * count
    for portal in portals:
        for i in portal["indices"]:
            if flat_free[i]:
                portal_at[i] |= 1 << portal["id"]
    radius = [[0.0] * len(portals) for _ in portals]

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = int(parent[i])
        return i

    def note(left: int, right: int, value: float) -> None:
        while left:
            a = (left & -left).bit_length() - 1
            left &= left - 1
            others = right & ~(1 << a)
            while others:
                b = (others & -others).bit_length() - 1
                others &= others - 1
                if radius[a][b] == 0.0:
                    radius[a][b] = radius[b][a] = value

    order = np.flatnonzero(flat_free)
    order = order[np.argsort(clearance[order], kind="stable")[::-1]]
    for raw_index in order:
        i = int(raw_index)
        value = float(clearance[i])
        active[i] = True
        bits[i] = portal_at[i]
        note(bits[i], bits[i], value)
        y, x = divmod(i, width)
        for neighbour in (((i - 1,) if x else ()) + ((i + 1,) if x + 1 < width else ()) +
                          ((i - width,) if y else ()) + ((i + width,) if y + 1 < height else ())):
            if not active[neighbour]:
                continue
            a, b = root(i), root(neighbour)
            if a == b:
                continue
            note(bits[a], bits[b], value)
            if size[a] < size[b]:
                a, b = b, a
            parent[b] = a
            size[a] += size[b]
            bits[a] |= bits[b]
    return radius


def raw_blocked(world: dict, sequences: dict, number: int) -> np.ndarray:
    """Hard.dat tiles + the raw hardboxes of vision-0, hard-0, non-warp sprites, as a 400 x 600 bool (x 20..619)."""
    mask, _ = tile_mask(world, number)
    boxes = [hardbox(sequences, e) for e in world["screens"][str(number)]["sprites"]
             if int(e.get("vision", 0)) == 0 and int(e.get("hard", 1)) == 0 and e.get("warp") is None]
    return (mask | rect_mask(boxes, 0))[:, 20:620]


def compare(raw: np.ndarray, live: np.ndarray) -> dict:
    portals = edge_portals(raw)
    raw_r, live_r = widest_paths(raw, portals), widest_paths(live, portals)
    pairs = []
    for a in range(len(portals)):
        for b in range(a + 1, len(portals)):
            r, v = round(raw_r[a][b], 4), round(live_r[a][b], 4)
            if r == 0 and v == 0:
                continue
            kind = "closed" if r > 0 and v == 0 else "opened" if r == 0 else "narrower" if v < r - 1e-6 else "wider" if v > r + 1e-6 else "same"
            pairs.append({"portals": [a, b], "raw": r, "live": v, "lost_px": round(r - v, 4), "kind": kind})
    connected = [p for p in pairs if p["raw"] > 0]
    return {"raw_blocked_px": int(raw.sum()), "live_blocked_px": int(live.sum()),
            "raw_blocked_live_free_px": int((raw & ~live).sum()), "raw_free_live_blocked_px": int((~raw & live).sum()),
            "connected_pairs": len(connected),
            "narrower": sum(p["kind"] == "narrower" for p in connected), "closed": sum(p["kind"] == "closed" for p in connected),
            "wider": sum(p["kind"] == "wider" for p in connected), "same": sum(p["kind"] == "same" for p in connected),
            "max_lost_px": max((p["lost_px"] for p in connected), default=0.0),
            "min_median_raw": [float(np.min([p["raw"] for p in connected])), float(np.median([p["raw"] for p in connected]))] if connected else None,
            "min_median_live": [float(np.min([p["live"] for p in connected])), float(np.median([p["live"] for p in connected]))] if connected else None,
            "pairs": pairs}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", type=Path, required=True, help="directory of live-<screen>.bin dumps")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--screens", type=int, nargs="*", default=list(SCREENS))
    args = parser.parse_args()
    world = json.loads((ROOT / "game/data/world.json").read_text())
    sequences = json.loads((ROOT / "game/data/sequences.json").read_text())["sequences"]
    result = {}
    for n in args.screens:
        live = np.frombuffer((args.live / f"live-{n}.bin").read_bytes(), np.uint8).reshape(400, 600).astype(bool)
        result[str(n)] = compare(raw_blocked(world, sequences, n), live)
        r = result[str(n)]
        print(n, {k: r[k] for k in ("connected_pairs", "narrower", "closed", "wider", "same", "max_lost_px",
                                    "raw_blocked_live_free_px", "raw_free_live_blocked_px", "min_median_raw", "min_median_live")})
    args.out.write_text(json.dumps(result, indent=1) + "\n")


if __name__ == "__main__":
    main()
