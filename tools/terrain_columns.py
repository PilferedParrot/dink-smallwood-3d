#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Source-data oracle for indoor terrain columns.

The source art chooses 10-pixel cells from the raw tile atlas. The centre must
be hard in the effective native tile mask. Phase A covers each chosen square;
phase B keeps only hard pixels in those squares. This module reads neither the
production terrain builder nor its selection metadata.

Native report coordinates are source pixels: x in [20, 620), y in [0, 400).
Rectangles and horizontal runs use half-open ends. Coverage arrays are [y, x]
with x rebased to [0, 600).
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from collision_map import tile_mask

WIDTH, HEIGHT = 600, 400
X_ORIGIN = 20
CELL = 10


def _effective_hard(world: dict, footprints: dict, screen: int) -> np.ndarray:
    fp = footprints.get(str(screen), {})
    hard, _ = tile_mask(world, screen, fp.get("revert", ()), fp.get("clear", ()))
    return hard[:, X_ORIGIN:X_ORIGIN + WIDTH]


def expected_cells(world: dict, screen: int, footprints: dict | None = None,
                   atlas_dir: Path | None = None) -> list[tuple[int, int]]:
    """Select native source-pixel centres, without reading native report cells."""
    source = world["screens"][str(screen)]
    if not source.get("indoor", False):
        return []
    hard = _effective_hard(world, footprints or {}, screen)
    atlas_dir = ROOT / "game/assets/tiles" if atlas_dir is None else Path(atlas_dir)
    sheets: dict[int, np.ndarray] = {}
    selected = []
    for y in range(CELL // 2, HEIGHT, CELL):
        for x in range(X_ORIGIN + CELL // 2, X_ORIGIN + WIDTH, CELL):
            if not hard[y, x - X_ORIGIN]:
                continue
            tile_index = (y // 50) * 12 + ((x - X_ORIGIN) // 50)
            tile_id = int(source["tiles"][tile_index]["tile"])
            sheet, atlas_cell = divmod(tile_id, 128)
            sheet += 1
            if sheet not in sheets:
                sheets[sheet] = np.asarray(
                    Image.open(atlas_dir / f"ts{sheet:02d}.png").convert("RGB"))
            rgb = sheets[sheet][(atlas_cell // 12) * 50 + y % 50,
                                (atlas_cell % 12) * 50 + (x - X_ORIGIN) % 50]
            r, g, b = (int(value) for value in rgb)
            if (b > 1.1 * r and b > .85 * g) or g > 1.12 * r:
                continue
            selected.append((x, y))
    return selected


def expected_coverage(world: dict, footprints: dict, screen: int,
                      phase: str, atlas_dir: Path | None = None) -> np.ndarray:
    """Return the full pixel mask for phase A or phase B."""
    if phase not in ("A", "B"):
        raise ValueError(f"phase must be A or B, got {phase!r}")
    out = _cell_coverage(expected_cells(world, screen, footprints, atlas_dir))
    if phase == "B":
        out &= _effective_hard(world, footprints, screen)
    return out


def _cell_coverage(cells: list[tuple[int, int]]) -> np.ndarray:
    out = np.zeros((HEIGHT, WIDTH), dtype=bool)
    for x, y in cells:
        out[y - CELL // 2:y + CELL // 2,
            x - X_ORIGIN - CELL // 2:x - X_ORIGIN + CELL // 2] = True
    return out


def rasterize_rects(rects: list) -> np.ndarray:
    """Rasterize emitted native rectangles at source pixel centres."""
    out = np.zeros((HEIGHT, WIDTH), dtype=bool)
    for rect in rects:
        if len(rect) != 4:
            raise ValueError(f"rectangle needs [x,y,width,height]: {rect!r}")
        x, y, width, height = map(float, rect)
        if not np.isfinite([x, y, width, height]).all() or width <= 0 or height <= 0:
            raise ValueError(f"invalid rectangle: {rect!r}")
        if x < X_ORIGIN or y < 0 or x + width > X_ORIGIN + WIDTH or y + height > HEIGHT:
            raise ValueError(f"rectangle outside screen: {rect!r}")
        x0 = max(0, int(np.ceil(x - X_ORIGIN - .5)))
        x1 = min(WIDTH, int(np.ceil(x + width - X_ORIGIN - .5)))
        y0 = max(0, int(np.ceil(y - .5)))
        y1 = min(HEIGHT, int(np.ceil(y + height - .5)))
        if x1 > x0 and y1 > y0:
            out[y0:y1, x0:x1] = True
    return out


def rasterize_runs(runs: list) -> np.ndarray:
    out = np.zeros((HEIGHT, WIDTH), dtype=bool)
    for run in runs:
        if len(run) != 3:
            raise ValueError(f"run needs [y,x0,x1]: {run!r}")
        y, x0, x1 = map(int, run)
        if not (0 <= y < HEIGHT and X_ORIGIN <= x0 <= x1 <= X_ORIGIN + WIDTH):
            raise ValueError(f"run outside screen: {run!r}")
        out[y, x0 - X_ORIGIN:x1 - X_ORIGIN] = True
    return out


def runs(mask: np.ndarray) -> list[list[int]]:
    """Lossless horizontal encoding in native source coordinates."""
    result = []
    for y in range(HEIGHT):
        row = np.pad(mask[y].astype(np.int8), (1, 1))
        edges = np.flatnonzero(np.diff(row))
        result.extend([y, int(a) + X_ORIGIN, int(b) + X_ORIGIN]
                      for a, b in zip(edges[::2], edges[1::2]))
    return result


def check_report(report: dict, world: dict, footprints: dict,
                 phase: str, atlas_dir: Path | None = None) -> dict:
    """Compare actual emitted geometry and native facts with the source oracle.

    Every discrepant pixel is represented by a lossless run. The visual-cause
    inventory is only produced when native visual runs are supplied; it lists
    blocked pixels outside both those runs and the emitted terrain geometry.
    """
    if report.get("schema") != "terrain-columns-1":
        raise ValueError(f"unexpected report schema: {report.get('schema')!r}")
    if phase not in ("A", "B"):
        raise ValueError(f"phase must be A or B, got {phase!r}")
    result = {"schema": "terrain-columns-oracle-1", "phase": phase,
              "failures": list(report.get("failures", [])), "screens": []}
    for record in report["screens"]:
        number = int(record["screen"])
        source_indoor = bool(world["screens"][str(number)].get("indoor", False))
        cells = expected_cells(world, number, footprints, atlas_dir)
        a_coverage = _cell_coverage(cells)
        b_coverage = a_coverage & _effective_hard(world, footprints, number)
        expected = a_coverage if phase == "A" else b_coverage
        actual = rasterize_rects(record["rects"])
        reported_cells = {tuple(map(int, cell)) for cell in record["cells"]}
        expected_cell_set = set(cells)
        missing = expected & ~actual
        extra = actual & ~expected
        clipped = sorted((x, y) for x, y in cells
                         if (a_coverage[y - 5:y + 5, x - X_ORIGIN - 5:x - X_ORIGIN + 5]
                             & ~b_coverage[y - 5:y + 5, x - X_ORIGIN - 5:x - X_ORIGIN + 5]).any())
        finding = {
            "screen": number, "expected_cells": len(cells),
            "missing_cells": [list(p) for p in sorted(expected_cell_set - reported_cells)],
            "extra_cells": [list(p) for p in sorted(reported_cells - expected_cell_set)],
            "clipped_cells_from_A_to_B": [list(p) for p in clipped],
            "expected_pixels": int(expected.sum()), "actual_pixels": int(actual.sum()),
            "missing_pixels": int(missing.sum()), "extra_pixels": int(extra.sum()),
            "missing_runs": runs(missing), "extra_runs": runs(extra),
            "sprite_perturbation_equal": record.get("sprite_perturbation_equal"),
            "errors": [],
        }
        if bool(record["indoor"]) != source_indoor:
            finding["errors"].append("native indoor flag differs from world source")
        if record.get("sprite_perturbation_equal") is not True:
            finding["errors"].append("sprite perturbation equality was not proved")
        if "native_coverage_violations" in record:
            violations = record["native_coverage_violations"]
            finding["native_coverage_violations"] = violations
            if phase == "B" and violations:
                finding["errors"].append("native recorder found emitted pixels walkable")
        if "blocked_cells_without_terrain" in record:
            finding["blocked_cells_without_terrain"] = record["blocked_cells_without_terrain"]
        if "blocked_runs" in record:
            native_blocked = rasterize_runs(record["blocked_runs"])
            walkable = actual & ~native_blocked
            finding["walkable_overlap_pixels"] = int(walkable.sum())
            finding["walkable_overlap_runs"] = runs(walkable)
            if "visual_runs" in record:
                visible = rasterize_runs(record["visual_runs"])
                unseen_blocked = native_blocked & ~(visible | actual)
                finding["blocked_without_visible_cause_pixels"] = int(unseen_blocked.sum())
                finding["blocked_without_visible_cause_runs"] = runs(unseen_blocked)
        elif "visual_runs" in record:
            finding["errors"].append("visual_runs supplied without blocked_runs")
        if finding["missing_cells"] or finding["extra_cells"]:
            finding["errors"].append("selected cells differ from source oracle")
        if finding["missing_pixels"] or finding["extra_pixels"]:
            finding["errors"].append("emitted geometry differs from source oracle")
        if phase == "B" and finding.get("walkable_overlap_pixels", 0):
            finding["errors"].append("emitted geometry overlaps native walkable pixels")
        result["screens"].append(finding)
    result["ok"] = not result["failures"] and all(not s["errors"] for s in result["screens"])
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="native terrain-columns-1 JSON")
    parser.add_argument("--phase", choices=("A", "B"),
                        default=os.environ.get("DINK_TERRAIN_PHASE", "B"))
    parser.add_argument("--world", type=Path, default=ROOT / "game/data/world.json")
    parser.add_argument("--footprints", type=Path, default=ROOT / "game/data/footprints.json")
    parser.add_argument("--output", type=Path, help="write oracle JSON here instead of stdout")
    args = parser.parse_args(argv)
    report = json.loads(args.report.read_text())
    world = json.loads(args.world.read_text())
    footprints = json.loads(args.footprints.read_text())["screens"]
    result = check_report(report, world, footprints, args.phase)
    encoded = json.dumps(result, separators=(",", ":"), sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded)
    else:
        sys.stdout.write(encoded)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
