# Fir eye-height source-art census (2026-10-11)

This is a report-only comparison of the existing complete tree-01 firs and the RC5 completed tree-09/10 parts. It changes no collision, scene ownership, or rendering. [The full per-screen and per-owner data](../../tmp/rc5-fir-eye/census.json) records all 570 outdoor screens, including zero rows. The [native older-tree inventory](../../tmp/rc5-fir-eye/existing-native.json) and [native completed-part inventory](../../tmp/rc5-fir-support/native.json) supplied actual 5×5 seam visibility; the final static-warp [reachability masks](../../tmp/rc5-evidence/reach-masks.npz) supplied integer-pixel player locations.

**Metric.** The complete source tree-01 art has measured physical foot `(83.5,176)` px. At a 1.65 m eye height, 66 source pixels above that foot, row 110 has nonblack visible pixels x=40–120 (74 occupied pixel centers, with transparent gaps). Relative to the foot, its leftmost and rightmost occupied centers are -43 and +37 px. Each tree's yaw-independent disk uses the larger **43 px radius**, multiplied by its uniform source scale. The adjacent row109 spans -40 to +36 px; row110 is the conservative choice at the half-pixel eye-row boundary. Nonblack means alpha>127 and RGB sum≥11, matching `fp_world.sprite_foot`. A point is counted when its integer source coordinate lies within that disk and the exact mask marks it statically reachable for the loaded screen. Every same-screen overlap is counted once.

This **cannot establish that the camera is inside a 3D crown**. These objects are `BILLBOARD_FIXED_Y` cards that face the camera. A radius around the measured foot is a conservative proximity screen for possible eye-level canopy occupation, not the actual alpha silhouette at a given yaw, a volume, or a rendering/occlusion result. It also cannot prove frame clipping or player experience. The masks are static integer-cell reachability, not fractional movement or dynamic story state.

## What is compared

| Source-art cohort | Native static authored | Shown in ≥1 real 5×5 scene | Eye-row radius | Meaning |
|---|---:|---:|---:|---|
| Existing complete tree-01 fir, seq32/frame1 | 207 | 199 | 43 px | Already standing in RC4; its legacy `model_key` is `oak_tree` despite the conical fir picture. |
| RC5 whole tree-01 at source tree-09/10 parts | 123 placements / 246 parts | 165 parts | 43 px × uniform scale | One complete original fir per retained source part; 92 valid unsupported roots have the authorized frame-1 hardbox collider, 73 other shown roots do not gain that collider. One shown root normalizes to absent screen798. |
| Existing tree-02 broadleaf oak control | 89 | 79 | 17 px at its thin eye-row slice | Its legacy `model_key` is `pine_tree`; it is **excluded** from the fir union. |

The source-tree-01 foot is 2.5 px right and 18 px below its metadata hotspot `(81,158)`; counting from the hotspot would shift the disks. Tree-02's measured physical foot is `(121.5,264)` versus metadata hotspot `(116,190)`. The older static source cohort was selected with native `editor_entity`, `model_key`, and `seam_parts` in every real outdoor 5×5 block. The same native inventory run against the isolated RC4 archive produced a [byte-identical result](../../tmp/rc5-fir-eye/existing-baseline-native.json) (SHA-256 `bab78ca687534a4ce0967efdd86ecd915f93c8df19e0043157f510172aa17ffb`), so these existing-tree ownership counts are an actual baseline comparison. Other frames3–7 were inventoried but excluded from this fir-art comparison.

## Reachable eye locations

| Count of distinct outdoor source cells | Baseline before RC5 geometry | Final after RC5 geometry |
|---|---:|---:|
| Reachable anywhere | 100,397,252 | 100,212,087 |
| Within existing complete tree-01 fir disks | 282,967 | 282,967 |
| Within completed fir disks | 427,556 | 262,755 |
| Within both cohorts (overlap) | 1,324 | 1,324 |
| Within either fir cohort (union) | 709,199 | 544,398 |
| Broadleaf tree-02 control, excluded from union | 40,587 | 40,587 |

The completed-fir count falls by 164,801 reachable cells after the full wall/fir collision change. This is a mask comparison, not an attribution of every removed cell to one fir: stone walls and other reachability changes are in the final mask. Only two screens have nonzero fir-cohort overlap: screen209 has 1,226 final cells and screen366 has 98. There are 67 screens with a final reachable completed-fir disk, 74 with an existing complete-fir disk, and 127 with either. The final topology has 530 outdoor screens with reached free cells; the full inventory has 570 outdoor screens.

**Hardbox geometry.** The original complete frame-1 hardbox relative to its *physical* foot is west -50.5, north -31, east +43.5, south +5 px. The source movement rule's 4 px band makes those -54.5, -35, +47.5, +9. A radius-43 disk extends 8 px farther north and 34 px farther south; it does not extend past the grown west/east limits. For a completed source trim, its *old* tree-09/10 source hardbox is a different rectangle, often far from a part's physical foot. The JSON records both raw source and frame-1 template hardboxes per owner, their directional extents/band gaps, and before/after reachable disk counts. These are geometric comparisons only: `hard=1` boxes, replaced boxes, and boxes not installed for supported roots are not movement solids. The final `after_reachable` mask decides actual static standability.

For reference, per-owner disk incidences sum to 264,322 final reached cells for the completed cohort and 285,679 for the existing tree-01 cohort. These **sums duplicate cells** where owner disks overlap; the union counts in the table are the distinct-cell numbers. Of those incidences, 192,384 completed-fir incidences lie outside each owner's hypothetical frame-1 hardbox grown by4px. That number also duplicates inter-owner overlaps and does not identify a new collision fix.

## Screen251 old camera and natural screen283

The old capture pose `(260,500)` is **outside screen251's 0–399 logical playfield**, so it is excluded from the screen251 mask row. Its natural normalized destination is screen283 at `(260,100)`. In a screen251 scene and in a screen283 scene, native seam ownership shows the same completed source part: source screen283 editor5, list index4, part1 of `tree-09.png`, source rows200–377. Its complete tree-01 physical foot is screen283 `(240.5,93)` (global `[15820.5, 3293.0]`), **20.718 px** from the normalized eye, inside the 43 px disk. The exact final mask marks `(283,260,100)` before/after reachable and before/after **not hard**. This is a scene-only neighbor visual while loaded on251, with no local `HitBody`; the support inventory says this root already had baseline support and received no new frame-1 collision rectangle. The old source tree-09 hardbox at this part's physical foot has relative y -142 to -68 px, far north of the eye's +7 px. The complete frame-1 geometric band would reach +9 px south, but no new fir box was installed here. This is a strong 2D close-canopy proxy and **not a claim of collision occupancy or rendered occlusion**. The relocated pose `(100,520)` is 143.1 source px from that root (3.577 m), outside its proxy disk.

## Per-screen counts where either fir cohort has a nonzero before/after eye disk

All values are distinct reachable integer cells for that screen's own real 5×5 scene visibility. `Existing` means tree-01 fir art only; tree-02 oak is separate above. The complete [JSON table](../../tmp/rc5-fir-eye/census.json) includes all 570 outdoor screens and provenance for every owner.

| Screen | Existing before | Completed before | Overlap before | Fir union before | Existing after | Completed after | Overlap after | Fir union after |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 144 | 0 | 12,904 | 0 | 12,904 | 0 | 10,489 | 0 | 10,489 |
| 176 | 0 | 16,940 | 0 | 16,940 | 0 | 7,058 | 0 | 7,058 |
| 177 | 0 | 5,621 | 0 | 5,621 | 0 | 5,621 | 0 | 5,621 |
| 178 | 18 | 0 | 0 | 18 | 18 | 0 | 0 | 18 |
| 179 | 17 | 0 | 0 | 17 | 17 | 0 | 0 | 17 |
| 180 | 91 | 0 | 0 | 91 | 91 | 0 | 0 | 91 |
| 181 | 1,884 | 0 | 0 | 1,884 | 1,884 | 0 | 0 | 1,884 |
| 182 | 4,622 | 0 | 0 | 4,622 | 4,622 | 0 | 0 | 4,622 |
| 183 | 11,952 | 0 | 0 | 11,952 | 11,952 | 0 | 0 | 11,952 |
| 184 | 6,078 | 1,715 | 0 | 7,793 | 6,078 | 1,715 | 0 | 7,793 |
| 186 | 6,076 | 0 | 0 | 6,076 | 6,076 | 0 | 0 | 6,076 |
| 187 | 5,824 | 0 | 0 | 5,824 | 5,824 | 0 | 0 | 5,824 |
| 188 | 0 | 6,052 | 0 | 6,052 | 0 | 3,497 | 0 | 3,497 |
| 208 | 0 | 15,370 | 0 | 15,370 | 0 | 5,953 | 0 | 5,953 |
| 209 | 6,698 | 5,101 | 1,226 | 10,573 | 6,698 | 5,101 | 1,226 | 10,573 |
| 210 | 6,670 | 0 | 0 | 6,670 | 6,670 | 0 | 0 | 6,670 |
| 211 | 6,075 | 0 | 0 | 6,075 | 6,075 | 0 | 0 | 6,075 |
| 212 | 2,818 | 0 | 0 | 2,818 | 2,818 | 0 | 0 | 2,818 |
| 213 | 8,626 | 0 | 0 | 8,626 | 8,626 | 0 | 0 | 8,626 |
| 214 | 9,180 | 0 | 0 | 9,180 | 9,180 | 0 | 0 | 9,180 |
| 215 | 7,183 | 0 | 0 | 7,183 | 7,183 | 0 | 0 | 7,183 |
| 216 | 7,248 | 0 | 0 | 7,248 | 7,248 | 0 | 0 | 7,248 |
| 217 | 2,250 | 0 | 0 | 2,250 | 2,250 | 0 | 0 | 2,250 |
| 218 | 1,926 | 16,920 | 0 | 18,846 | 1,926 | 9,236 | 0 | 11,162 |
| 219 | 1,442 | 0 | 0 | 1,442 | 1,442 | 0 | 0 | 1,442 |
| 220 | 0 | 3,202 | 0 | 3,202 | 0 | 3,202 | 0 | 3,202 |
| 221 | 0 | 1,286 | 0 | 1,286 | 0 | 244 | 0 | 244 |
| 237 | 0 | 5,201 | 0 | 5,201 | 0 | 3,023 | 0 | 3,023 |
| 238 | 5,127 | 4,671 | 0 | 9,798 | 5,127 | 2,408 | 0 | 7,535 |
| 239 | 0 | 6,446 | 0 | 6,446 | 0 | 1,833 | 0 | 1,833 |
| 241 | 8,049 | 1,578 | 0 | 9,627 | 8,049 | 1,578 | 0 | 9,627 |
| 242 | 7,266 | 0 | 0 | 7,266 | 7,266 | 0 | 0 | 7,266 |
| 243 | 2,760 | 0 | 0 | 2,760 | 2,760 | 0 | 0 | 2,760 |
| 244 | 894 | 0 | 0 | 894 | 894 | 0 | 0 | 894 |
| 246 | 721 | 0 | 0 | 721 | 721 | 0 | 0 | 721 |
| 247 | 721 | 0 | 0 | 721 | 721 | 0 | 0 | 721 |
| 248 | 3,088 | 0 | 0 | 3,088 | 3,088 | 0 | 0 | 3,088 |
| 249 | 1,043 | 0 | 0 | 1,043 | 1,043 | 0 | 0 | 1,043 |
| 250 | 0 | 5,994 | 0 | 5,994 | 0 | 5,994 | 0 | 5,994 |
| 252 | 0 | 3,945 | 0 | 3,945 | 0 | 3,945 | 0 | 3,945 |
| 253 | 0 | 14,085 | 0 | 14,085 | 0 | 9,642 | 0 | 9,642 |
| 269 | 0 | 6,209 | 0 | 6,209 | 0 | 3,745 | 0 | 3,745 |
| 270 | 0 | 15,076 | 0 | 15,076 | 0 | 11,683 | 0 | 11,683 |
| 271 | 0 | 9,939 | 0 | 9,939 | 0 | 9,797 | 0 | 9,797 |
| 273 | 0 | 6,191 | 0 | 6,191 | 0 | 1,717 | 0 | 1,717 |
| 276 | 4,844 | 0 | 0 | 4,844 | 4,844 | 0 | 0 | 4,844 |
| 278 | 2,105 | 0 | 0 | 2,105 | 2,105 | 0 | 0 | 2,105 |
| 279 | 0 | 4,451 | 0 | 4,451 | 0 | 1,896 | 0 | 1,896 |
| 282 | 0 | 8,314 | 0 | 8,314 | 0 | 3,463 | 0 | 3,463 |
| 283 | 2,422 | 12,249 | 0 | 14,671 | 2,422 | 7,415 | 0 | 9,837 |
| 284 | 0 | 3,251 | 0 | 3,251 | 0 | 1,375 | 0 | 1,375 |
| 285 | 0 | 170 | 0 | 170 | 0 | 170 | 0 | 170 |
| 288 | 0 | 2,334 | 0 | 2,334 | 0 | 2,334 | 0 | 2,334 |
| 301 | 0 | 7,945 | 0 | 7,945 | 0 | 3,521 | 0 | 3,521 |
| 303 | 0 | 5,808 | 0 | 5,808 | 0 | 3,434 | 0 | 3,434 |
| 305 | 0 | 7,726 | 0 | 7,726 | 0 | 3,134 | 0 | 3,134 |
| 311 | 0 | 8,981 | 0 | 8,981 | 0 | 3,826 | 0 | 3,826 |
| 314 | 0 | 13,396 | 0 | 13,396 | 0 | 5,374 | 0 | 5,374 |
| 315 | 0 | 12,842 | 0 | 12,842 | 0 | 7,732 | 0 | 7,732 |
| 316 | 0 | 6,490 | 0 | 6,490 | 0 | 2,750 | 0 | 2,750 |
| 320 | 0 | 1,005 | 0 | 1,005 | 0 | 1,005 | 0 | 1,005 |
| 333 | 0 | 4,408 | 0 | 4,408 | 0 | 4,290 | 0 | 4,290 |
| 334 | 0 | 4,889 | 0 | 4,889 | 0 | 398 | 0 | 398 |
| 335 | 0 | 7,016 | 0 | 7,016 | 0 | 4,657 | 0 | 4,657 |
| 337 | 0 | 5,254 | 0 | 5,254 | 0 | 5,136 | 0 | 5,136 |
| 340 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 343 | 0 | 7,481 | 0 | 7,481 | 0 | 4,926 | 0 | 4,926 |
| 344 | 0 | 4,889 | 0 | 4,889 | 0 | 398 | 0 | 398 |
| 346 | 3,414 | 7,726 | 0 | 11,140 | 3,414 | 3,134 | 0 | 6,548 |
| 347 | 0 | 8,902 | 0 | 8,902 | 0 | 3,792 | 0 | 3,792 |
| 348 | 0 | 6,490 | 0 | 6,490 | 0 | 2,750 | 0 | 2,750 |
| 364 | 0 | 7,537 | 0 | 7,537 | 0 | 5,286 | 0 | 5,286 |
| 365 | 0 | 7,142 | 0 | 7,142 | 0 | 4,958 | 0 | 4,958 |
| 366 | 4,826 | 8,395 | 98 | 13,123 | 4,826 | 8,135 | 98 | 12,863 |
| 367 | 0 | 4,997 | 0 | 4,997 | 0 | 4,893 | 0 | 4,893 |
| 372 | 929 | 0 | 0 | 929 | 929 | 0 | 0 | 929 |
| 375 | 0 | 3,945 | 0 | 3,945 | 0 | 3,945 | 0 | 3,945 |
| 376 | 12,110 | 9,916 | 0 | 22,026 | 12,110 | 9,670 | 0 | 21,780 |
| 377 | 6,912 | 0 | 0 | 6,912 | 6,912 | 0 | 0 | 6,912 |
| 378 | 2,070 | 4,585 | 0 | 6,655 | 2,070 | 2,184 | 0 | 4,254 |
| 379 | 1,165 | 3,310 | 0 | 4,475 | 1,165 | 3,310 | 0 | 4,475 |
| 380 | 45 | 929 | 0 | 974 | 45 | 929 | 0 | 974 |
| 395 | 0 | 7,726 | 0 | 7,726 | 0 | 3,134 | 0 | 3,134 |
| 398 | 18 | 0 | 0 | 18 | 18 | 0 | 0 | 18 |
| 409 | 2,262 | 0 | 0 | 2,262 | 2,262 | 0 | 0 | 2,262 |
| 411 | 244 | 0 | 0 | 244 | 244 | 0 | 0 | 244 |
| 426 | 0 | 3,785 | 0 | 3,785 | 0 | 3,785 | 0 | 3,785 |
| 427 | 0 | 3,721 | 0 | 3,721 | 0 | 1,509 | 0 | 1,509 |
| 441 | 1,475 | 0 | 0 | 1,475 | 1,475 | 0 | 0 | 1,475 |
| 442 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 443 | 2,178 | 0 | 0 | 2,178 | 2,178 | 0 | 0 | 2,178 |
| 468 | 150 | 0 | 0 | 150 | 150 | 0 | 0 | 150 |
| 472 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 473 | 2,290 | 0 | 0 | 2,290 | 2,290 | 0 | 0 | 2,290 |
| 495 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 500 | 2,121 | 0 | 0 | 2,121 | 2,121 | 0 | 0 | 2,121 |
| 502 | 10,026 | 0 | 0 | 10,026 | 10,026 | 0 | 0 | 10,026 |
| 503 | 13,482 | 0 | 0 | 13,482 | 13,482 | 0 | 0 | 13,482 |
| 521 | 4,325 | 0 | 0 | 4,325 | 4,325 | 0 | 0 | 4,325 |
| 524 | 2,417 | 0 | 0 | 2,417 | 2,417 | 0 | 0 | 2,417 |
| 535 | 7,038 | 0 | 0 | 7,038 | 7,038 | 0 | 0 | 7,038 |
| 560 | 0 | 1,809 | 0 | 1,809 | 0 | 1,383 | 0 | 1,383 |
| 566 | 4,267 | 0 | 0 | 4,267 | 4,267 | 0 | 0 | 4,267 |
| 584 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 592 | 5,906 | 4,812 | 0 | 10,718 | 5,906 | 4,812 | 0 | 10,718 |
| 593 | 2,346 | 0 | 0 | 2,346 | 2,346 | 0 | 0 | 2,346 |
| 598 | 916 | 0 | 0 | 916 | 916 | 0 | 0 | 916 |
| 600 | 0 | 1,720 | 0 | 1,720 | 0 | 1,720 | 0 | 1,720 |
| 601 | 0 | 3,434 | 0 | 3,434 | 0 | 3,434 | 0 | 3,434 |
| 620 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 624 | 1,348 | 0 | 0 | 1,348 | 1,348 | 0 | 0 | 1,348 |
| 625 | 76 | 0 | 0 | 76 | 76 | 0 | 0 | 76 |
| 626 | 4,844 | 0 | 0 | 4,844 | 4,844 | 0 | 0 | 4,844 |
| 631 | 842 | 0 | 0 | 842 | 842 | 0 | 0 | 842 |
| 632 | 10,352 | 3,399 | 0 | 13,751 | 10,352 | 3,399 | 0 | 13,751 |
| 633 | 0 | 2,675 | 0 | 2,675 | 0 | 2,675 | 0 | 2,675 |
| 656 | 2,422 | 0 | 0 | 2,422 | 2,422 | 0 | 0 | 2,422 |
| 659 | 11,719 | 0 | 0 | 11,719 | 11,719 | 0 | 0 | 11,719 |
| 664 | 916 | 0 | 0 | 916 | 916 | 0 | 0 | 916 |
| 713 | 902 | 0 | 0 | 902 | 902 | 0 | 0 | 902 |
| 716 | 4,844 | 0 | 0 | 4,844 | 4,844 | 0 | 0 | 4,844 |
| 735 | 0 | 4,980 | 0 | 4,980 | 0 | 2,312 | 0 | 2,312 |
| 736 | 0 | 8,314 | 0 | 8,314 | 0 | 3,463 | 0 | 3,463 |
| 745 | 1,520 | 0 | 0 | 1,520 | 1,520 | 0 | 0 | 1,520 |
| 766 | 0 | 3,558 | 0 | 3,558 | 0 | 1,327 | 0 | 1,327 |
| 767 | 0 | 4,451 | 0 | 4,451 | 0 | 1,896 | 0 | 1,896 |
| 768 | 0 | 5,953 | 0 | 5,953 | 0 | 205 | 0 | 205 |

Reproduce the native inventory with Godot4.6.1 headless Dummy and an isolated profile: `nice -n 10 godot --headless --audio-driver Dummy --path game --script res://../tmp/rc5-fir-eye/existing_inventory.gd` with OMP/BLAS/MKL=1 and LP_NUM_THREADS≤6. Then run `nice -n 10 uvx --offline --with pillow --with numpy python tools/rc5_fir_eye_census.py`. This reads the existing source assets, native inventories and final masks; it does not boot campaign scripts or render. Input SHA-256 hashes are embedded in `census.json`.
