# Fitted south-exit script coordinate audit (2026-10-10)

Sources read: `game/data/world.json` editor records, `game/data/sequences.json` source hardboxes, `game/data/interior.json` wall fits, and the complete compiled AST in `game/data/story.json`. The fitted south-exit screens found from these records are 1, 2, 34, 38, 65, 66 and 68. Their directly placed screen/sprite scripts name 25 scripts; two names (`box-e`, `s2-barp`) have no compiled AST. Following literal `sp_script` and `external` references adds nine scripts, for 32 compiled scripts audited. Dynamic script-name construction is outside this static audit.

There are **zero `sp_x` or `sp_y` getter calls** in the 32 compiled scripts, so there are no reads compared against original doorway-band constants to change. The four setters are:

| Script | Procedure / line | Calls | Destination already selected | Mapping decision |
| --- | --- | --- | --- | --- |
| `s1-ltr` | `main` 37–38 | `sp_x(1,362)`, `sp_y(1,303)` | `player_map=439` at line 36 | Outdoor screen; leave live values unchanged. |
| `s2-bar` | `main` 105–106 | `sp_x(1,320)`, `sp_y(1,373)` | `player_map=498` at line 104 | Outdoor screen; leave 373 unchanged despite its numerical overlap with an interior band. |

The raw outdoor editor warps into these fitted rooms are: 409/editor 16 → screen 2 at (312,373); 439/editor 13 → screen 1 at (323,390); 497/editor 12 → screen 66 at (319,387); 497/editor 15 → screen 68 at (317,355); 498/editor 10 → screen 34 at (317,355); and 532/editor 11 → screen 65 at (317,343). All old-band arrivals lie inside their destination aperture. Screen 65's y=343 is already on the room side and must stay unchanged. Screen 38 has no corresponding raw incoming editor warp in the map records inspected.

Literal vertical `move`/`move_stop` goals for player 1 in a fitted exit's old 352–400 band are `s1-h1-m/main:28` north to 370; `s1-h1-s/main:22` south to 398 and `main:34` north to 370; `s2-bar/main:90` south to 385; and transitively attached `s2-ryan3/main:14` north to 375. The runtime move adapter must use the player's current x and current screen, so a numerical y in this range maps only when the player occupies that screen's actual doorway aperture. The screen 1 burning-home evacuation uses the 398 goal; the existing `test_alktree_aftermath.py` runs that original script.

The error being corrected has two causes. The physical cause is an arrival at source y=390 behind a closed leaf now drawn at y=352. The design cause was validating the new outward portal without checking inbound positions and script goals against that same source-derived plane. The adapter changes live player coordinates and leaves raw editor warps, compiled script constants, and `sp_y` getters' live return values intact.
