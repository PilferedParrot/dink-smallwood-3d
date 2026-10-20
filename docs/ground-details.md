# Ground details

The source `lands/Details` directory mixes ground art with raised objects.
Its frame numbers do not encode surface orientation. Source pixels, retained
sequence hotspots/hardboxes (`game/data/sequences.json`) and authored uses
(`game/data/world.json`) give this inventory of all 41 frames:

| Sequence | Frames (each listed) | Representation | Source-art evidence |
| --- | --- | --- | --- |
| 89 | 1, 2, 3, 4 | Ground | Fissures in brown soil, with broken rims |
| 89 | 5, 6, 7, 8 | Ground | The corresponding fissures in blue stone |
| 89 | 9 | Ground | Dark opening and broken rim, used by `s1-hole` |
| 89 | 10 | Ground | Rectangular dug patch/open grave |
| 90 | 1, 2, 3, 4 | Ground | Loose bones, crossed bones and a spine |
| 90 | 5, 6 | Existing upright | Skull faces with visible eye sockets and jaws |
| 90 | 7, 8, 9, 10 | Existing upright | Raised thorn loops with shadows beneath |
| 90 | 11, 12, 13, 14, 15 | Ground | Thin loose thorn fragments without cast shadows |
| 91 | 1, 5 | Ground | Thin fallen sticks |
| 91 | 2, 3, 4 | Existing upright | Log trunks with cylindrical side faces and branch stubs |
| 92 | 1, 2, 3, 4 | Ground | Starfish, shells and sand-dollar scatter |
| 92 | 5, 6, 7, 8, 9, 10, 11 | Ground | Pebbles and scattered pebble patches |

These are 32 ground frames and 9 existing upright frames. “Ground” describes
the source image's surface: an opening, scatter or thin fallen fragment.
Visible raised loops, solid side faces and frontal skull faces retain their
previous representation. The rule is an authored semantic inventory rather
than an automatic image classifier.

The small thorns differ from the four bushes. Every placement of 90/11–13
has `hard=1` (passable); five of six are background/type 0. The type-1 use,
map 192/editor 5, runs `thorn.main`: `sp_touch_damage` and `sp_hitpoints`
(source lines 3–4, retained in `game/data/story.json`). This makes it a contact
hazard, with no movement or growth behavior that would imply a standing bush.
Unplaced frames 14–15 show the same isolated fragments. The bushes 7–10 have
raised loops, drawn shadows and predominantly hard-zero, live placements.
Hardness is corroborating evidence, not a test for visual orientation.

FreeDink 109.6 `src/game_engine.cpp:483–512` draws type-0 sprites into
`IOGFX_background`, adds hardness independently and instantiates type-1 sprites
as live objects. Lines 611–623 also paint backgrounds, while line 646 checks
hardness independently. Thus live/scripted status does not imply vertical
surface orientation. The [GNU FreeDink source mirror](https://github.com/gitGNU/gnu_freedink)
provides the engine's upstream provenance; the cited lines refer to 109.6.

`fp_world.gd` reuses `prop_solids.gd`'s existing flat-prop quad for every
ground-class instance, including source type 0. These instances are excluded
from background composition, so there is exactly one visible owner. The
source image, hotspot and size determine the plane and its camera-framing
rectangle. Ground shadow pixels stay in the image; the plane casts no new
shadow and adds no ray body. Its floor offset is the same as other flat props.
Entities, native hardness, scripts, touch damage and portal logic are preserved.
Raised details and real grass keep their previous keys and rendering, including
the existing background painter for their type-0 copies.

Five active scripted placements leave the standing interaction-body census.
These identities use `world.json`'s one-based sprite `index`:

| Screen:editor | Sequence/frame | Script | Source hard | Ground evidence |
| --- | --- | --- | --- | --- |
| 180:1 | 89/9 | `s6-hole2` | 0 | Crack opening |
| 192:5 | 90/12 | `thorn` | 1 | Loose thorn fragment |
| 209:4 | 89/9 | `s1-hole3` | 0 | Crack opening |
| 243:13 | 89/9 | `s6-hole` | 0 | Crack opening |
| 277:2 | 89/9 | `s1-hole` | 0 | Crack opening |

None of these scripts sets `sp_hard` (`story.json`). Hard zero still blocks
through the native source-hardbox path; hard one stays passable. The thorn
script still sets contact damage. Removing a standing ray target changes
neither movement hardness nor contact/portal execution. Map 132:1 is another
89/9 scripted opening, but its type 0 already excluded it from this active-body
census. The 145 decorative targets become 140; the thorn subset becomes 138
from 139 because 192:5 is one of those same five exclusions. The test asserts
the exact excluded identities, pictures and scripts as well as the totals.
There are six active scripted ground placements in total: 481:2 is beach
frame 92/1 (`s5-sec1`), source `hard=1`. It was an upright rock before this
change and was outside the decorative census. Its starfish/scatter artwork
now lies flat. `s5-sec1.hit` retains `sp_hard(...,1)` (source line 16), and
the bomb-hit path uses the source hardbox rather than a visual ray body.
The active-ground fixture includes this sixth identity and its hardness.

The live displayed frame determines entry into and exit from this class. Frame,
size, position and visibility changes follow the entity, without baking a stale
picture into terrain. Stock `s2-sec1`, `s2-sec3` and `s3-sec1` death procedures
(source lines 22–27, retained in `game/data/story.json`) turn trees into frame
89/10 on maps 307, 659 and 710. Those holes use the same flat surface immediately
and after save/load. Runtime-created ground frames follow the same rule.

The technical defect was the Details `frame >= 7` fallback to standing grass
(and standing rocks below 7). The development mistake was applying an unchecked
frame-number heuristic to a mixed artwork family. Live nodes also retained
their initial standing representation when scripts switched their picture;
static frame checks alone missed those source-script transitions. The earlier 18-frame branch
inventory included four raised thorn bushes; it was not a ground-art census.
`tests/ground_details_test.gd` exercises all 41 frames as active sprites both
with and without scripts, single ownership for authored uses, real grass as a look-alike control, the
three stock tree-to-hole scripts, save/load and all ground frames entering,
scaling, moving, hiding and returning to standing vegetation. Its unchanged-renderer failure
includes all 14 ground frames in that earlier 18-frame inventory.
