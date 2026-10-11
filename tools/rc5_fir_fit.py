#!/usr/bin/env python3
"""Measure source fir parts and the complete original fir for RC5.

Run with the project's Python environment. This reads source art only; it does
not decide scene ownership. SourceFir.parts makes that decision at runtime.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SEQUENCES = ROOT / "game/data/sequences.json"
OUTPUT = ROOT / "game/prototype/rc5_firs.json"
SCALE = 0.025


def measure(path: str, row0: int = 0, row1: int | None = None) -> dict:
    art = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
    if row1 is None:
        row1 = len(art)
    crop = art[row0:row1]
    # Exactly fp_world.sprite_foot's alpha and nonblack thresholds on 8-bit art.
    drawn = (crop[:, :, 3] > 127) & (crop[:, :, :3].astype(np.int32).sum(axis=2) >= 11)
    yy, xx = np.where(drawn)
    if not len(yy):
        raise ValueError(f"No nonblack crown pixels: {path} rows {row0}:{row1}")
    bottom = int(yy.max())
    foot_x = float(np.where(drawn[bottom])[0].mean() + 0.5)
    return {
        "rows": [row0, row1],
        "source_foot_px": [foot_x, bottom + 1],
        "crown_bbox_px": [int(xx.min()), int(yy.min()), int(xx.max() + 1), bottom + 1],
        "crown_height_px": bottom + 1 - int(yy.min()),
        "image_size_px": [int(crop.shape[1]), int(crop.shape[0])],
    }


def runs(row: np.ndarray) -> list[tuple[int, int]]:
    """Half-open horizontal nonblack runs in one source-art row."""
    xs = np.flatnonzero(row)
    if not len(xs):
        return []
    cuts = np.flatnonzero(np.diff(xs) > 1)
    starts = np.r_[0, cuts + 1]
    ends = np.r_[cuts, len(xs) - 1]
    return [(int(xs[a]), int(xs[b]) + 1) for a, b in zip(starts, ends)]


def measure_strip8(path: str, whole: dict) -> tuple[list[dict], dict]:
    """Four crown fragments from their apexes, including the periodic edge pair.

    Frame 8 has no feet in its 95px-high picture. The two middle apexes touch
    its top; one more crown crosses the image's left/right periodic boundary.
    Infer each absent foot from the original frame-1 apex-to-foot offset, not
    from the strip's cut bottom or the generic source hotspot.
    """
    art = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
    assert art.shape[:2] == (95, 200), art.shape
    drawn = (art[:, :, 3] > 127) & (art[:, :, :3].astype(np.int32).sum(axis=2) >= 11)
    top_runs = runs(drawn[0])
    assert top_runs == [(37, 42), (120, 126)], top_runs
    edge_row = next(y for y in range(art.shape[0]) if drawn[y, 0] or drawn[y, -1])
    assert edge_row == 12, edge_row
    left_edge = runs(drawn[edge_row, :20])
    right_edge = runs(drawn[edge_row, 180:])
    assert left_edge == [(0, 3)] and right_edge == [(19, 20)], (left_edge, right_edge)
    template = np.asarray(Image.open(ROOT / "game" / whole["path"]).convert("RGBA"))
    top = (template[0, :, 3] > 127) & (template[0, :, :3].astype(np.int32).sum(axis=1) >= 11)
    assert runs(top) == [(78, 84)], runs(top)
    template_apex_x = float(np.flatnonzero(top).mean() + 0.5)
    delta_x = float(whole["source_foot_px"][0]) - template_apex_x
    delta_y = float(whole["source_foot_px"][1])
    assert (template_apex_x, delta_x, delta_y) == (81.0, 2.5, 176.0)
    width = art.shape[1]
    # The x=199 pixel belongs to the crown whose complementary apex pixels
    # start at x=0 in the next 200px source repeat.
    edge_apex_x = float(np.mean([x + 0.5 for x in (-1, 0, 1, 2)]))
    mid_apex = [float(np.mean(np.arange(a, b) + 0.5)) for a, b in top_runs]
    apexes = [(edge_apex_x, float(edge_row)), (mid_apex[0], 0.0),
              (mid_apex[1], 0.0), (edge_apex_x + width, float(edge_row))]
    assert apexes == [(1.0, 12.0), (39.5, 0.0), (123.0, 0.0), (201.0, 12.0)]
    # Pixel ownership windows are the exact rounded midplanes between apexes.
    # Each source pixel belongs to one crown, even where silhouettes overlap.
    mids = [int(round((apexes[i][0] + apexes[i + 1][0]) / 2.0)) for i in range(3)]
    windows = [(a, b) for a, b in zip([0, *mids], [*mids, width])]
    assert windows == [(0, 20), (20, 81), (81, 162), (162, 200)]
    pieces = []
    for index, ((apex_x, apex_y), (x0, x1)) in enumerate(zip(apexes, windows)):
        y0 = int(apex_y)
        crop = drawn[y0:, x0:x1]
        yy, xx = np.where(crop)
        assert len(xx), index
        pieces.append({
            "rows": [y0, art.shape[0]], "source_window_x_px": [x0, x1],
            "source_apex_px": [apex_x, apex_y],
            "source_foot_in_full_art_px": [apex_x + delta_x, apex_y + delta_y],
            "uniform_scale": 1.0,
            "source_visible_bbox_px": [x0 + int(xx.min()), y0 + int(yy.min()),
                                       x0 + int(xx.max()) + 1, y0 + int(yy.max()) + 1],
            "source_visible_nonblack_pixels": int(len(xx)),
            "foot_below_picture_bottom_px": apex_y + delta_y - art.shape[0],
        })
    assert pieces[0]["source_foot_in_full_art_px"][0] + width == pieces[3]["source_foot_in_full_art_px"][0]
    evidence = {"image_size_px": [width, art.shape[0]],
                "template_top_apex_x_px": template_apex_x,
                "template_apex_to_foot_px": [delta_x, delta_y],
                "source_top_apex_runs_px": [list(run) for run in top_runs],
                "periodic_edge_first_row": edge_row,
                "periodic_edge_apex_pixel_centers_px": [-0.5, 0.5, 1.5, 2.5],
                "source_apexes_px": [list(x) for x in apexes],
                "partition_midplanes_x_px": mids,
                "scale_basis": "source and original template apexes are 5-6 pixels wide at source pixel resolution; retain one source pixel per template pixel, no anisotropic fit",
                "foot_basis": "original seq32/frame1 measured nonblack foot minus its top-row apex center; strip bottom row is a cut line, not a root"}
    return pieces, evidence


def main() -> None:
    frames = json.loads(SEQUENCES.read_text())["sequences"]["32"]["frames"]
    template = frames[0]
    template_path = template["path"]
    whole = measure(template_path)
    whole["path"] = template_path
    parts: dict[str, list[dict]] = {}
    hashes = {"sequences.json": hashlib.sha256(SEQUENCES.read_bytes()).hexdigest()}
    for frame in (9, 10):
        source = frames[frame - 1]
        path = source["path"]
        art = np.asarray(Image.open(ROOT / "game" / path).convert("RGBA"))
        occupied = np.where((art[:, :, 3] > 127).any(axis=1))[0]
        breaks = np.where(np.diff(occupied) > 3)[0]
        if len(breaks) != 1:
            raise ValueError(f"Expected exactly two source crowns: {path}")
        cuts = [(int(occupied[0]), int(occupied[breaks[0]] + 1)),
                (int(occupied[breaks[0] + 1]), int(occupied[-1] + 1))]
        measured = []
        for row0, row1 in cuts:
            part = measure(path, row0, row1)
            part["source_foot_in_full_art_px"] = [part["source_foot_px"][0],
                                                  row0 + part["source_foot_px"][1]]
            part["uniform_scale"] = part["crown_height_px"] / whole["crown_height_px"]
            measured.append(part)
        parts[path] = measured
        hashes[path] = hashlib.sha256((ROOT / "game" / path).read_bytes()).hexdigest()
    strip_path = frames[7]["path"]
    parts[strip_path], strip_evidence = measure_strip8(strip_path, whole)
    hashes[strip_path] = hashlib.sha256((ROOT / "game" / strip_path).read_bytes()).hexdigest()
    hashes[template_path] = hashlib.sha256((ROOT / "game" / template_path).read_bytes()).hexdigest()
    output = {
        "schema": "rc5-whole-fir-fit-1",
        "method": "alpha>127 and RGB sum>=11; 9/10 bottom-row foot and crown-height scale unchanged; 8 feet inferred from measured periodic/top apexes plus original whole-fir apex-to-foot offset",
        "world_units_per_source_px": SCALE,
        "template": {"path": template_path, "seq": 32, "frame": 1,
                     "frame_hotspot_px": [template["dx"], template["dy"]], **whole},
        "source_parts": parts,
        "source08_apex_evidence": strip_evidence,
        "source_sha256": hashes,
    }
    OUTPUT.write_text(json.dumps(output, indent=2) + "\n")
    print(f"Wrote {OUTPUT}; complete fir {template_path}, height {whole['crown_height_px']} px")


if __name__ == "__main__":
    main()
