# Worldwide outdoor hard type-0 sprites painted flat

Read-only census from the source editor maps, native renderer dispatch inventory and the existing RC5 hardness baseline. No production files or baseline census were changed.

**Denominator reconciliation:** the baseline says 246,852 reachable vision-0 `nothing`-boundary pixels. Summing exact `reachable_unowned_components` runs independently across all 570 outdoor screens also gives **246,852**.

Across those 570 outdoor screens are 1,083 type-0 entries total. Of them, 143 vision-0 entries have hard=0, including 6 warp triggers that the baseline correctly excludes from hardbox solidity ({'assets/graphics/lands/Details/crack-10.png': 6}). That leaves 137 non-warp source hardboxes. Native dispatch classifies 126 as painted-flat `ground_picture` (25 exact source art paths); another 11 type-0 hard sources across 6 paths dispatch as built geometry, so they are not included in painted-flat totals. Those nonflat hardboxes overlap 0 of the reachable-nothing boundary pixels.

The union of grown source hardboxes for those **126 painted-flat hard type-0 sprites** intersects **6,622 unique reachable nothing-boundary pixels**, or **2.6826%** of 246,852. Per-owner intersections sum to 6,637; 15 hits are overlap and are removed from the union. Summing within-art-path unions gives 6,637, with 15 cross-family overlap beyond the global union.

Exact painted-flat source-art families (the per-family union column may overlap across rows):

| Outdoor placements | Screens | Grown hardbox px | Owner-hit px | Family union px | Source art path |
|---:|---:|---:|---:|---:|---|
| 90 | 1 | 17920 | 3958 | 3958 | `assets/graphics/Animals/Duck/death/dkh1x-01.png` |
| 1 | 1 | 1305 | 144 | 144 | `assets/graphics/Bonuses/Barrels/barel-01.png` |
| 1 | 1 | 160 | 32 | 32 | `assets/graphics/Items/Tools/tool-14.png` |
| 1 | 1 | 2640 | 136 | 136 | `assets/graphics/Items/grain/bag-09.png` |
| 2 | 2 | 5280 | 201 | 201 | `assets/graphics/Items/grain/bag-12.png` |
| 1 | 1 | 1092 | 0 | 0 | `assets/graphics/lands/Details/crack-01.png` |
| 1 | 1 | 2278 | 0 | 0 | `assets/graphics/lands/Details/crack-02.png` |
| 1 | 1 | 2573 | 0 | 0 | `assets/graphics/lands/Details/crack-03.png` |
| 1 | 1 | 5618 | 0 | 0 | `assets/graphics/lands/Details/crack-04.png` |
| 1 | 1 | 3542 | 242 | 242 | `assets/graphics/lands/Details/fores-04.png` |
| 1 | 1 | 1980 | 59 | 59 | `assets/graphics/lands/Fence/fence-04.png` |
| 4 | 2 | 648 | 37 | 37 | `assets/graphics/lands/Grass/grass-02.png` |
| 1 | 1 | 2376 | 60 | 60 | `assets/graphics/lands/Rocks/rock-02.png` |
| 1 | 1 | 180 | 0 | 0 | `assets/graphics/lands/Rocks/rocks-04.png` |
| 1 | 1 | 180 | 0 | 0 | `assets/graphics/lands/Rocks/rocks-08.png` |
| 2 | 2 | 11700 | 166 | 166 | `assets/graphics/lands/Shrubs/bush-01.png` |
| 1 | 1 | 4242 | 232 | 232 | `assets/graphics/lands/Shrubs/bush-02.png` |
| 1 | 1 | 4081 | 205 | 205 | `assets/graphics/lands/Shrubs/bush-03.png` |
| 6 | 5 | 5945 | 0 | 0 | `assets/graphics/lands/Trees/tree-02.png` |
| 1 | 1 | 1209 | 99 | 99 | `assets/graphics/lands/Trees/tree-03.png` |
| 1 | 1 | 7622 | 482 | 482 | `assets/graphics/lands/Trees/tree-08.png` |
| 1 | 1 | 928 | 41 | 41 | `assets/graphics/lands/Trees/tree-09.png` |
| 2 | 2 | 4800 | 265 | 265 | `assets/graphics/lands/Trees/tree-11.png` |
| 2 | 2 | 5346 | 224 | 224 | `assets/graphics/lands/Trees/tree-12.png` |
| 1 | 1 | 2340 | 54 | 54 | `assets/graphics/lands/Trees/tree-13.png` |

Nonzero authored vision layers contain 3 type-0 sprites (visions {1: 3}); none have hard=0. Their entries are [(409, 34, 1, 'assets/graphics/Items/Tools/tool-06.png'), (533, 21, 1, 'assets/graphics/struct/Details/Damage/hole-02.png'), (533, 23, 1, 'assets/graphics/struct/Details/Damage/hole-03.png')]. They are supplementary inventory, not part of the vision-0 reachability denominator.

**Caveats:** reachability is the baseline static vision-0 4-connected source-free component plus authored static vision-0 warps, not a campaign playthrough. Pixel overlap does not certify that a source hardbox is legible at eye level. Exact per-screen union reconciliation is in `primary_by_screen.json`; rerun `/usr/bin/python3 tmp/rc5-hard-type0/census.py` to reproduce.
