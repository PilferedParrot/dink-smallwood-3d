# RC5 terrain category source-art report

This report splits the current census `water_cliff_edge` category by exact atlas pixels. It distinguishes blue water art, non-blue shore/ground art from the water sheets, and rock/cliff atlas art. All are painted flat on the current outdoor ground plane. This is a source-texture classification, not a claim that the pixels form raised terrain.

## Current phase and denominators

The input is the RC5 current census `docs/rc5/census-rc5-current.json.gz` (phase `RC5`), paired with `docs/rc5/native-rc5-current.json.gz`, `game/data/world.json`, and `game/data/footprints.json`. The category is looked up by its name in the census `categories` list; the code does not assume a numeric category index. Its exact `classification_runs` contain **1,123,319 full hard pixels** across the current outdoor screens. The current static-warp reachability graph has **377,828 reachable boundary pixels** in this category. These are different denominators: full category mask versus reachable-space boundary.

The cited historical figure 880,441 is not substituted for the current result: no matching phase/artifact or denominator was supplied for it. Against the current full-hard denominator it is lower by 242,878 pixels. This report pins the RC5 phase and input hashes below so the comparison is explicit.

| Class (disjoint) | Full hard pixels | Reachable boundary pixels |
|---|---:|---:|
| Blue water source pixels | 89,719 | 7,938 |
| Painted flat relief (rock/cliff atlas) | 737,294 | 122,734 |
| Painted flat shore / other ground in water sheets | 296,306 | 247,156 |
| Uncertain source pixels | 0 | 0 |
| **Total `water_cliff_edge`** | **1,123,319** | **377,828** |

The two totals reconcile exactly. `Uncertain=0` means every current category pixel mapped to an inspected water or cliff-family tile and passed one of the explicit pixel classes; it does not mean that any pixel's appearance or geometry was rendered and verified.

## Atlas-family census

Counts are source pixels within the disjoint category-5 runs. “Full” is the entire current category mask; “reachable” is its intersection with the exact static-warp reachable-space boundary. Atlas family is `tsNN = floor(tile_id / 128) + 1`.

| Atlas | Water full | Shore/ground full | Relief full | Water reachable | Shore/ground reachable | Relief reachable |
|---|---:|---:|---:|---:|---:|---:|
| ts02 | 0 | 0 | 114,905 | 0 | 0 | 13,047 |
| ts03 | 0 | 0 | 23,595 | 0 | 0 | 4,813 |
| ts04 | 0 | 0 | 11,010 | 0 | 0 | 2,519 |
| ts05 | 0 | 0 | 126,514 | 0 | 0 | 22,034 |
| ts06 | 0 | 0 | 53,175 | 0 | 0 | 20,326 |
| ts07 | 0 | 0 | 9,384 | 0 | 0 | 4,890 |
| ts08 | 58,951 | 183,652 | 0 | 6,158 | 151,547 | 0 |
| ts14 | 20,156 | 80,865 | 0 | 888 | 70,104 | 0 |
| ts15 | 9,860 | 31,789 | 0 | 807 | 25,505 | 0 |
| ts16 | 752 | 0 | 0 | 85 | 0 | 0 |
| ts24 | 0 | 0 | 61,191 | 0 | 0 | 2,103 |
| ts25 | 0 | 0 | 30,174 | 0 | 0 | 11,532 |
| ts26 | 0 | 0 | 28,637 | 0 | 0 | 0 |
| ts29 | 0 | 0 | 168,095 | 0 | 0 | 21,653 |
| ts30 | 0 | 0 | 107,581 | 0 | 0 | 19,174 |
| ts31 | 0 | 0 | 1,243 | 0 | 0 | 341 |
| ts32 | 0 | 0 | 1,790 | 0 | 0 | 302 |
| **Total** | **89,719** | **296,306** | **737,294** | **7,938** | **247,156** | **122,734** |

The large reachable `ts08/14/15` shore counts are the reason the entire category should not be described as water. Those pixels are on the ground plane and are non-blue shore/ground colors in the source tile art. The ts02 and ts05 components previously selected for capture are within flat relief on the same plane. Root's planned captures may still assess how this reads at eye level; no rendering was run for this report.

## Source hardness: default and custom tile masks

Source tile ownership is retained separately from the pixel-art class. Default-hard masks account for 508,305 relief pixels, 296,306 shore/ground pixels, and 1,380 water pixels (805,991 total). Per-screen custom-hard masks account for 228,989 relief pixels and 88,339 water pixels (317,328 total). These sum to the full category denominator; current category-5 shore pixels are all default-hard. Reachable-boundary source ownership is: default-hard 107,449 relief + 247,156 shore/ground + 1,231 water = 355,836; custom-hard 15,285 relief + 6,707 water = 21,992.

## Classification and reachability method

The tool reads each exact `classification_runs` row and looks up the original source pixel at the matching 50×50 tile cell. It classifies pixels using the already inspected source atlas families and conservative color rules used by the census:

- `ts08`, `ts14`, `ts15`, and `ts16` are water families. A pixel is blue water only when `b > 1.1*r` and `b > 0.85*g`; other pixels in these families remain a distinct shore/ground class.
- `ts02`, `ts03`, `ts04`, `ts05`, `ts06`, `ts07`, `ts24`, `ts25`, `ts26`, `ts29`, `ts30`, `ts31`, and `ts32` are inspected relief families. Non-grass pixels (`g <= 1.12*r` or `g <= 1.12*b`) count as flat relief. Grass-colored and other unrecognized pixels remain uncertain.

The exact current static reachability is rebuilt from `classification_runs`, the native warp inventory, indoor collision data, and footprints. The resulting boundary sum must equal the census aggregate (377,828) or the tool fails. Source tile-family counts and tile-ID counts are serialized in the JSON output; water/default/custom intersections are not inferred from RGB alone.

`fp_world.gd`'s outdoor ground is a `PlaneMesh`. The `add_terrain_walls()` function exits for outdoor screens, so this category does not mean outdoor 10-pixel raised wall cells. Separate kit structures and sprite models are outside this texture classification.

## Reproduction and inputs

```sh
/usr/bin/python3 tools/rc5_terrain_report.py --world game/data/world.json --footprints game/data/footprints.json --census docs/rc5/census-rc5-current.json.gz --inventory docs/rc5/native-rc5-current.json.gz --out tmp/rc5-terrain-report/current.json
```

The generated report contains the full per-tile ID and per-screen details. Input SHA-256:

| Input | SHA-256 |
|---|---|
| `game/data/world.json` | `3e643839d6c287f757d9a65ccd773f1d4313de645ab944c54700e1a88a011be1` |
| `game/data/footprints.json` | `dfe1548b35112dc67dc39ff8e5f679b30a7548e23e6046022ff4e4073eab33a1` |
| `docs/rc5/census-rc5-current.json.gz` | `e1b8ef736164f4057d0468d4360f00b76c79c584fdf1db74f86b7c79539c0cbf` |
| `docs/rc5/native-rc5-current.json.gz` | `8fb0965e955cea5ce5e649bd434b9caf7fce7bdc67e8d4fcdabfbdeb505b8756` |
