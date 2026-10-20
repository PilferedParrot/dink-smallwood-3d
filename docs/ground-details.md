# Ground details

The source `lands/Details` directory mixes ground art with raised objects.
An authored per-frame inventory controls rendering. It is a representation
policy, with explicit ambiguous cases, rather than a complete pixel classifier.
Sequence hotspots/hardboxes live in `game/data/sequences.json`; authored uses
and retained script source lines are in `world.json` and `story.json`.

| Sequence | Frames (each listed) | Active representation | Evidence / limit |
| --- | --- | --- | --- |
| 89 | 1,2,3,4 | Ground | Fissures and broken rims in brown soil |
| 89 | 5,6,7,8 | Ground | Corresponding fissures in blue stone |
| 89 | 9 | Ground | Dark opening/radial rim; source cave portals |
| 89 | 10 | Ground | Rectangular opening/hatch; map 85/editor 1 has a warp to 254 |
| 90 | 1,2,3,4 | Ground | Loose bones/spine; partial shadow rule disagrees on1 (weak outline dither) |
| 90 | 5,6 | Existing upright | Frontal skull faces; shadow-only rule is undecidable |
| 90 | 7,8,9,10 | Existing upright | Raised thorn loops; detached base shadow |
| 90 | 11,12,13,14,15 | Ground | Thin fragments; rule disagrees on11/12 (outline dither), retained judgment |
| 91 | 1 | Existing upright | Substantial base shadow, independently noticed in pixel inspection |
| 91 | 2,3,4 | Existing upright | Log trunks, side faces and base shadow |
| 91 | 5 | Ground | Unshadowed fork; orientation remains ambiguous, retained judgment |
| 92 | 1,2,3 | Ground | Starfish/shell/sand-dollar scatter |
| 92 | 4 | Existing upright | Conch with base cast shadow; active rendering retains it |
| 92 | 5,6,7,8,9,10,11 | Ground | Pebbles and scattered pebble patches |

This gives 30 ground frames and 11 upright-category frames. Source type 0 keeps
its existing background-painter contract, including when its image depicts a
raised thing. All 29 authored conch placements are type 0 and therefore remain
painted on the floor as before; seven of eight fores01 placements are type 0.
The one active fores01 stands. This broader type 0 representation limitation
is separate from choosing the active-frame class; no two-frame painter
exception is introduced. The source type, hardness and scripts are unchanged.

## Partial independent pixel evidence

`tools/detail_pixels.py:measure` consumes only RGBA pixels, with no filename,
sequence, inventory or implementation classification. It reuses the existing
`tools/facade_fit.py:is_dither` convention: opaque near-black pixels (RGB sum
below 10) with no orthogonally adjacent near-black pixel are isolated shadow
candidates. It removes candidates to measure body bbox, fill and aspect.
A base-shadow cue needs at least 4 candidate pixels, at least half below their
column's body-bottom envelope, and a lower candidate centroid than body
centroid. Otherwise the result is **undecidable**, never proof of flatness.

The rule independently flags conch04 and fores01, all four raised thorns and
all three logs. It cannot resolve the skulls or fores05. It also flags weak
outline dither on bone01 and thorn11/12; those disagreements are retained as
known limits, not silently changed into successful classifications. Source
context and inspection still decide those policy rows. A cast shadow is
height evidence, but does not uniquely recover an object's orientation from
one 2D projection.

A proposed stronger rule added a shadow/body area threshold 0.1 or a compact
vertical silhouette (height>=width and fill>=0.5). It was rejected after an
out-of-sample check, selected before measurement: all 29 pre-existing flat
prop fits against 4 whole barrel round/box fits. It falsely called 13 flat
frames upright. No tuned revision of that failed classifier is used.

The native test is honestly an inventory/geometry **consistency** test. A
separate pixel check verifies the two independently reviewed cast-shadow
counterexamples against their actual rendered plane state; it can fail even
when implementation and inventory agree. Pure tests exercise the positive
shadow controls, declared abstentions and shadow-removal sensitivity. Neither
that partial instrument nor a headless consistency check certifies all art.

## Rendering and source behavior

Every ground-category instance uses the existing flat-prop quad, including
type 0, and is excluded from background composition: one visible owner. Source
pixels, hotspot and size determine its footprint and camera rectangle. Source
shadow pixels remain in the image; these planes cast no extra shadow and add
no ray body. Other type 0 objects retain the painter; upright active frames
retain their prior sprite/shadow representation.

The five departures from the standing decorative-body census are source
180:1(89/9,s6-hole2,hard 0),192:5(90/12,thorn,hard 1),209:4(89/9,s1-hole3,hard 0),
243:13(89/9,s6-hole,hard 0),277:2(89/9,s1-hole,hard 0). None of those five scripts
has a hit, talk or push procedure or forwarding call to one. Regression checks
assert those absent handlers so a future source addition requires revisiting
the target policy. Hard0 holes retain native source-hardbox movement blocking;
hard 1 thorn remains passable with contact damage. Thorn.main source 3–4 sets
touch damage 15 and hitpoints 0. No script in these five changes sp_hard.

The holes use touch procedures: s1-hole source 9–25 includes a life guard and
transition to map 131; s1-hole3 source 11–29 transitions to 198; s6-hole source
11–29 to 182; s6-hole2 source 11–29 to 166. Their preload/touch-damage setup is
in source 3–4. Their task attachment to pseudo-sprite 1000 during transition
changes task ownership, not ray interaction. Source entities are preserved.

A sixth active scripted ground placement,481:2(92/1,s5-sec1,hard 1), was a rock
outside that decorative census. Its bomb-only hit secret uses native brain 17
source-hardbox dispatch, separately tested with the flat visual; source 16
retains sp_hard 1. The six active-ground identities and five decorative
exclusions are checked separately, not inferred from totals.

Live displayed-frame/scale/position/visibility changes follow ground instances.
Stock s2-sec1, s2-sec3 and s3-sec1 death procedures(source 22–27) turn trees into
89/10 on maps307,659,710; native tests execute these and check isolated
save/load. These direct script/bomb fixtures skip earning their progression.

FreeDink 109.6 `src/game_engine.cpp:483–512` independently draws type 0 background,
adds hardness and instantiates type 1; 611–623 also paint backgrounds and 646
checks hardness separately. The [GNU source mirror](https://github.com/gitGNU/gnu_freedink)
provides provenance. Neither active/scripted status nor hardness is an image
orientation test.

The original technical defect was Details' frame threshold routing mixed art
to standing rocks/grass, plus live nodes retaining their old standing class
when scripts replaced their frame. The development cause was an unvalidated
numerical heuristic and static-only evidence. A second mistake grouped the
conch and shadowed twig by family/semantic description while overlooking their
base shadows. The initial consistency oracle could not catch that shared
mistake; independent pixel counterexamples now can, with the stated limits.
