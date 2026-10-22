# Terrain columns: what stands where the map is hard

Interior screens (the 74 `indoor` screens) stand a visible column on natively hard ground so that nothing blocks the player invisibly.

**Which cells.** A 10 px cell gets a column when its tile's art depicts a raised surface (rock, cliff face, solid dark) and ANY of its pixels
is hard in the effective tile mask; the rectangles are then clipped to the exact 1 px mask (`fp_world.gd` `terrain_wall_cells`,
`terrain_wall_rects`). hard.dat draws rims 1-3 px thick, which a centre sample misses. Tile art decides, never colour: paving, boards, grass,
gravel and grass-bank lips stay as flat as the original draws them, as do water (FreeDink 109.6 `gfx_tiles.cpp:87-93`, tileset 8) and fire
(`:98-110`, tileset 19). The table is `game/data/terrain_tile_classes.json`, read from the tiles themselves (`docs/terrain-tile-classes/*.png`,
`tools/terrain_tile_classes.py --check` fails when an interior tile is unclassed). Hard cells that stay invisible are listed in
`terrain-invisible-hard.md`.

**Bodies behind a rim.** A boulder or rock band is a rim in hard.dat, which alone is a ragged shell. A non-hard region of the screen that holds no
floor-class pixel is not walkable floor, so the rim encloses it; its raised-class pixels are drawn (`game/data/terrain_fill.json`,
`tools/terrain_fill.py`), never collided.

**Faces.** Caves show the room's own rock (the ceiling donor, `interior_ceiling.gd`), projected on the world axes. Other rooms show their own tile
picture extruded by the original's camera, screen = (X, Z - Y) (`tools/facade_fit.py`): a point Y up a face shows the art Y px behind it, into the
solid, so texels keep one source pixel per face pixel. A fitted room's corners keep its stone. An interior's open edge is black: the original draws
nothing past its 600x400 screen.

**Census.** `tests/terrain_columns_test.gd` reads the emitted MultiMesh transforms of all 644 screens; `tools/terrain_columns.py` is the
independent oracle (class table plus raw masks, no colour). `tests/test_terrain_columns.py` holds the controls: 102 stays wall-free, a look-alike
rock that wears the old blue/green guess stands, paving the old guess kept does not.
