#!/usr/bin/env python3
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
"""Tile classes for indoor terrain walls: which tile art depicts a raised surface.

A natively hard cell gets a visible terrain column iff the tile under it depicts a raised surface
(rock, cliff face, solid dark). Floor-class art (paving, boards, grass, gravel, a grass bank's lip)
stays invisible-hard as in the original, as do water and fire. The classes were read from the tiles
themselves (docs/terrain-tile-classes/*.png, the sheets this tool writes), not from a colour rule.

Citations. FreeDink 109.6 gfx_tiles.cpp:87-93 animates tileset 8 (full indices 896-1023) as water and
:98-110 tileset 19 (2304-2431) as fire. Tileset 8 holds no tile under an interior screen at all; on
tileset 19 the flame tiles are fire and its grass-bank tiles are floor-class lips. Colour is not used.

Usage:
    python3 tools/terrain_tile_classes.py --write      # game/data/terrain_tile_classes.json + sheets
    python3 tools/terrain_tile_classes.py --check      # every tile of every interior screen is classed
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game/data/terrain_tile_classes.json"
SHEETS = ROOT / "docs/terrain-tile-classes"

WATER_RANGE = (896, 1023)  # FreeDink tileset 8; gfx_tiles.cpp:87-93
FIRE_RANGE = (2304, 2431)  # FreeDink tileset 19; gfx_tiles.cpp:98-110 (animation range, not the art class)

# Each entry: (class, note, tile indices). Order is the contact-sheet order.
GROUPS = [
    ("floor", "tileset 1 wooden boards", [6, 7, 18, 19]),
    ("dark", "tileset 1 solid black: the unlit outside of a room", [30, 31, 42, 43]),
    ("floor", "tileset 1 grass", [40, 41]),
    ("floor", "tileset 5 grass with a thin rubble lip, and plain grass", [514, 515, 538, 562, 574]),
    ("raised", "tileset 5 brown cliff face", [526, 527]),
    ("fire", "tileset 19 flames (FreeDink animates all of tileset 19 as fire; these are the flame art)",
     [2306, 2307, 2310, 2311, 2312, 2313, 2318, 2319, 2322, 2325, 2329, 2330, 2331, 2332, 2334, 2335, 2336,
      2337, 2341, 2342, 2343, 2344, 2354, 2355, 2356]),
    ("floor", "tileset 19 grass bank and hedge lip along the fire field (seen in place on 85 and 86)",
     [2323, 2324, 2328, 2333, 2340, 2345, 2357, 2366, 2367, 2368, 2369]),
    ("floor", "tileset 37 blue cobble paving", [4608, 4609, 4610, 4611, 4612, 4613, 4620, 4621, 4622, 4623, 4624,
                                               4625, 4632, 4633, 4634, 4635, 4644, 4645, 4646, 4647]),
    ("floor", "tileset 39 olive cobble paving", [4864, 4865, 4866, 4867, 4868, 4869, 4876, 4877, 4878, 4879, 4880,
                                                 4881, 4888, 4889, 4890, 4891, 4900, 4901, 4902, 4903]),
    ("floor", "tileset 40 pure gravel floor (no rock in the tile)", [5046, 5047, 5058, 5059]),
    ("raised", "tileset 40 cave rock and rock rims (rock in the tile, with or without floor beside it)",
     [4992, 4993, 4994, 4995, 4996, 4997, 4998, 4999, 5000, 5001, 5004, 5005, 5006, 5007, 5008, 5009, 5010,
      5011, 5012, 5013, 5016, 5017, 5018, 5019, 5020, 5021, 5022, 5023, 5024, 5025, 5028, 5029, 5030, 5031,
      5032, 5033, 5034, 5035, 5036, 5037, 5040, 5041, 5042, 5043, 5044, 5045, 5052, 5053, 5054, 5055, 5056,
      5057]),
]


def classes() -> dict[int, str]:
    table: dict[int, str] = {}
    for cls, _, tiles in GROUPS:
        for t in tiles:
            assert t not in table, t
            table[t] = cls
    return table


def interior_tiles(world: dict) -> set[int]:
    return {int(t["tile"]) for s in world["screens"].values() if s.get("indoor") for t in s["tiles"][:96]}


def build() -> dict:
    table = classes()
    out = {"schema": "terrain-tile-classes-1",
           "water_index_range": list(WATER_RANGE), "fire_index_range": list(FIRE_RANGE),
           "classes": {c: sorted(t for t, k in table.items() if k == c) for c in ("raised", "dark", "floor", "fire")},
           "notes": {c: [n, tiles] for c, n, tiles in GROUPS}}
    return out


def write_sheets(world: dict) -> None:
    from PIL import Image, ImageDraw
    SHEETS.mkdir(parents=True, exist_ok=True)
    table = classes()
    atlas: dict[int, Image.Image] = {}
    for cls in ("raised", "dark", "floor", "fire"):
        tiles = sorted(t for t, k in table.items() if k == cls)
        per, size = 10, 80
        rows = (len(tiles) + per - 1) // per
        sheet = Image.new("RGB", (per * size, rows * (size + 12)))
        draw = ImageDraw.Draw(sheet)
        for i, t in enumerate(tiles):
            s, c = divmod(t, 128)
            if s + 1 not in atlas:
                atlas[s + 1] = Image.open(ROOT / f"game/assets/tiles/ts{s + 1:02d}.png").convert("RGB")
            tile = atlas[s + 1].crop(((c % 12) * 50, (c // 12) * 50, (c % 12) * 50 + 50, (c // 12) * 50 + 50))
            x, y = (i % per) * size, (i // per) * (size + 12)
            sheet.paste(tile.resize((size, size), Image.NEAREST), (x, y + 12))
            draw.text((x + 2, y), str(t), fill=(255, 255, 0))
        sheet.save(SHEETS / f"{cls}.png", optimize=True)


def check(world: dict) -> list[int]:
    return sorted(interior_tiles(world) - set(classes()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    world = json.loads((ROOT / "game/data/world.json").read_text())
    if args.write:
        DATA.write_text(json.dumps(build(), indent=1, sort_keys=True) + "\n")
        write_sheets(world)
    missing = check(world)
    if missing:
        print("unclassed interior tiles:", missing)
        return 1
    print("every interior tile is classed:", len(interior_tiles(world)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
