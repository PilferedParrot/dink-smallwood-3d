# Interior hard cells that stay invisible, as in the original

Generated from the native terrain census (tests/terrain_columns_test.gd, `blocked_cells_without_terrain`, tile-owned cells only) on the
terrain-tile-class build. A natively hard 10 px centre whose tile art is floor-class (paving, boards, grass, gravel, a bank lip), or fire
(FreeDink109.6 gfx_tiles.cpp:98-110), gets no terrain column: the original draws floor there too (tilesets 37 and 39 are cobble paving; screen 102's hard
bridge-edge cells stay wall-free, as in the original). Where a sprite hardbox also covers the cell, the sprite is the visible cause (second column). Sprite-only blocked
cells (no tile hardness) belong to the sprites, not to this list. No interior hard cell sits on tileset 8 (water).

Totals: floor-class, no sprite 5347 cells; floor-class with a sprite over it 1308; fire 2.

| screen | floor, no sprite | floor, sprite over it | fire |
|---|---|---|---|
| 3 | 7 | 3 | 0 |
| 33 | 2 | 2 | 0 |
| 34 | 3 | 12 | 0 |
| 35 | 0 | 24 | 0 |
| 66 | 21 | 0 | 0 |
| 70 | 223 | 127 | 0 |
| 73 | 339 | 4 | 0 |
| 74 | 277 | 0 | 0 |
| 85 | 5 | 0 | 2 |
| 86 | 20 | 0 | 0 |
| 102 | 264 | 136 | 0 |
| 105 | 247 | 0 | 0 |
| 106 | 289 | 0 | 0 |
| 134 | 205 | 284 | 0 |
| 137 | 208 | 0 | 0 |
| 138 | 218 | 0 | 0 |
| 169 | 330 | 0 | 0 |
| 170 | 158 | 0 | 0 |
| 195 | 2 | 2 | 0 |
| 196 | 10 | 17 | 0 |
| 202 | 400 | 0 | 0 |
| 225 | 2 | 2 | 0 |
| 226 | 2 | 2 | 0 |
| 260 | 220 | 18 | 0 |
| 514 | 292 | 0 | 0 |
| 515 | 227 | 0 | 0 |
| 546 | 248 | 0 | 0 |
| 547 | 157 | 0 | 0 |
| 577 | 58 | 125 | 0 |
| 578 | 237 | 66 | 0 |
| 579 | 135 | 475 | 0 |
| 609 | 216 | 9 | 0 |
| 610 | 325 | 0 | 0 |
