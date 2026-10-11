# RC5 reachable-boundary residue report

This static report decomposes reachable vision-0 `nothing` boundary pixels by their source. It does not certify campaign progression, eye-level appearance, or whether a rendered scene feels blocked. The census boundary mask is taken from exact `reachable_unowned_components` runs; sprite hardboxes use the native inventory rectangles grown by four source pixels. Flat hard type-0 art is removed as a union before source attribution so overlapping bodies are not counted twice.

## Reproduction

The CLI takes all source inputs explicitly and accepts `.json` or `.json.gz` for census, inventory, and output:

```sh
/usr/bin/python3 tools/rc5_residue.py --world game/data/world.json --footprints game/data/footprints.json --census docs/rc5/census-rc4-base.json.gz --inventory docs/rc5/native-rc4-base.json.gz --out /tmp/rc5-residue-base.json.gz
/usr/bin/python3 tools/rc5_residue.py --world game/data/world.json --footprints game/data/footprints.json --census docs/rc5/census-rc5-current.json.gz --inventory docs/rc5/native-rc5-current.json.gz --out /tmp/rc5-residue-current.json.gz
```

The census and inventory inputs must be matching phases with the same 570 outdoor screens. The report records SHA-256 hashes of each exact input. `--out` may be plain JSON or deterministic gzip JSON. No path under `tmp/` is assumed by the tool.

## Baseline and current totals

| Census | Reachable `nothing` boundary | Flat type-0 union | Residual | Default tile | Custom tile | Sprite hardbox union | Source union | Source-only | Overlap | Unattributed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| RC4 baseline | 246,852 | 6,622 | 240,230 | 191,949 | 43,777 | 4,604 | 240,230 | 240,130 | 100 | 0 |
| RC5 current | 243,472 | 6,581 | 236,891 | 191,893 | 40,544 | 4,617 | 236,891 | 236,728 | 163 | 0 |

For each phase, mutually exclusive membership masks reconcile to the residual. Baseline has 191,948 default-only, 43,678 custom-only, 4,504 sprite-only, 1 default+sprite, and 99 custom+sprite pixels. Current has 191,892 default-only, 40,382 custom-only, 4,454 sprite-only, 1 default+sprite, and 162 custom+sprite. The pairwise matrix is inclusive, so its row totals intentionally overlap; source union and exclusive membership classes do not.

The atlas-family cross-tab (`tsNN = floor(tile_id / 128) + 1`) is retained in the JSON output as exact disjoint source-owner pixel counts. Selected large families:

| Family | Baseline default/custom | Current default/custom |
|---|---:|---:|
| ts02 | 64,005 / 1,285 | 63,974 / 1,146 |
| ts05 | 63,959 / 410 | 63,959 / 410 |
| ts01 | 0 / 30,489 | 0 / 27,647 |
| ts16 | 0 / 3,360 | 0 / 3,134 |

The residual perimeter is a location cross-tab at playable x=20, x=619, y=0, and y=399; it does not introduce a fifth hardness source. Baseline unique perimeter population is 3,641 pixels (x20 524, x619 463, y0 976, y399 1,686; 8 corners). Current is 3,594 (524, 461, 969, 1,648; 8 corners). The JSON includes source-membership classes on each strip and on their deduplicated union.

The flat-hard-type-0 census covers 1,083 outdoor type-0 entries; 143 are vision-0 hard-0 including six warp triggers. There are 137 nonwarp entries, of which 126 are painted flat ground pictures across 25 source art paths and 11 are nonflat objects. No supplementary authored vision layers contain hard-0 type-0 placements. The flat union removes 6,622 pixels in baseline and 6,581 in current; per-art placement, overlap incidence, union, and positive hits are serialized in the report.

## Current residue capture ranks

The largest individual residual components are screen 145 (774 px, `[20,0,620,175]`), screen 145 (550 px, `[45,24,595,25]`), screen 208 (472 px, `[245,302,620,400]`), screen 420 (400 px, `[370,0,371,400]`), and screen 145 (350 px, `[595,25,596,375]`). These rank components, not whole-screen totals. The largest aggregate residual screens are 145 (3,142 px), 210 (2,531), 215 (2,499), 212 (2,472), and 217 (2,459). The tool emits both rankings, plus largest whole-boundary components and screens, so the reader can select render captures without conflating component and screen aggregates.

## How to interpret the source masks

`fp_world.gd` composites the selected 96 tile images and background art into a 600×400 texture, then places it on a `PlaneMesh`. Its `add_terrain_walls()` function returns immediately for outdoor screens (`if not interior: return`), so its later 10-pixel cube stamping branch is dungeon-only. Outdoor ts02/ts05 hard masks therefore lie on the flat ground plane in the current renderer; separate kit buildings and sprite models can still stand above the plane. This is a renderer-code finding, not an eye-level visual judgment. The census classifies exact source tile families and source masks, not whether the texture reads visually as grass or rock. Scene captures remain pending; inspect the largest current ts02 and ts05 default-hard components from two opposing side views and one top view, with cameras outside both the mask and component, before claiming a player-visible cause.

Current high-priority components for capture are the largest residual components listed above. Their aim points are `(320,0)` on 145, `(320,24)` on 145, `(432,399)` on 208, `(370,200)` on 420, and `(595,200)` on 145; aim coordinates lie on component pixels, so move each camera outside the component before taking the opposing views.

The current reachable default-hard component scan ranks ts02's top tied examples at screen 253 bbox `[33,306,79,307]`, screen 273 `[533,206,579,207]`, screen 276 `[133,306,179,307]`, screen 306 `[383,106,429,107]`, and screen 309 `[33,156,79,157]` (each 46 pixels). For ts05, screen 180 `[535,157,585,158]` is 50 pixels; screen 181 has five equally sized examples at x `[35,85]`, `[135,185]`, `[235,285]`, `[335,385]`, `[435,485]`, and `[535,585]`, y `[157,158]`. These are one-row strips under 4-connectivity. Candidate ground-projection aims are screen 253 `(56,306)` and screen 180 `(560,157)`. For each, opposing side-view camera ground points can start at y offsets −26 and +28; a top-view position can start at (+49,−46) relative to the aim. These are preliminary outside-component locations only: verify the final camera's ground projection against both the exact mask and component before capturing.

## A report-class bug and its cause

The earlier analysis encoded three source memberships into a multi-bit integer and then applied a Boolean pixel-domain mask to the encoded values. That truncated higher membership bits (custom tile and sprite), so exact class cross-tabs lost valid classes even though separately computed unions remained correct. The promoted implementation selects encoded values by the Boolean domain (`encoded[domain]`) and never bitwise-ANDs the integer codes with that domain. A synthetic test checks the high bits, disjoint population totals, overlap union, and edge cross-tab.

The code error came from a reasoning oversight: a Boolean mask is safe to apply to a pixel array but is not a safe operation on a packed membership code. The assumption that “masking after encoding only clears out-of-domain pixels” was misapplied because the Boolean `1` also clears bit values `2` and `4`. The fix preserves the membership representation and restricts counting to the domain. A separate earlier reporting error treated total hardbox area as boundary overlap; this report computes intersection against the exact reachable boundary before removal and reports the art-path union to avoid double-counting overlapping owners.

## Input artifact hashes

Hashes identify the source snapshot used for reproducibility. The exact hashes are also embedded in generated reports.

| Input | SHA-256 |
|---|---|
| `game/data/world.json` | `3e643839d6c287f757d9a65ccd773f1d4313de645ab944c54700e1a88a011be1` |
| `game/data/footprints.json` | `dfe1548b35112dc67dc39ff8e5f679b30a7548e23e6046022ff4e4073eab33a1` |
| Baseline census JSON.GZ | `285a3cb60f54090fc8e492bbb85da56a6e50016931343deaee3f1f684db271be` |
| Current census JSON.GZ | `e1b8ef736164f4057d0468d4360f00b76c79c584fdf1db74f86b7c79539c0cbf` |
| Baseline native inventory JSON | `fd9b7a20f1626193c5d9fdfe6aa76d37d14d3a9355f653eacae57dd316d54fa6` |
| Current native inventory JSON | `8fb0965e955cea5ce5e649bd434b9caf7fce7bdc67e8d4fcdabfbdeb505b8756` |

Native inventories are supplied as compressed artifacts alongside the census in `docs/rc5/`.
