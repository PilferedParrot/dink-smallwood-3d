# Direction — September 24, 2026

This file supersedes the review process in `OPENING_REVIEW.md` and any
"no Sprite3D" rule in `FIRST_PERSON.md` / `IMPLEMENTATION.md`. Read it first.

## Chris's intent (canonical)

Turn the original *Dink Smallwood* into a **first-person shooter that keeps the
original art style and humor**, while removing the misogyny and bigotry of the
original. **It should be pleasant and funny for everyone to play.** Keep the
imported original title screen and menu. Build on the current project rather than
starting over.

## Diagnosis (Opus 5.5, from the captures and code)

The distance between the build and the intent is **structural, not incremental**.
Polishing the current structure will not close it.

1. **The art is replaced instead of reused.** `fp_world.gd` rebuilds every visible
   object as a generic Blender or primitive model ("a reinterpretation... not a
   recovery"). The original art survives only as some ground texture. So
   characters look nothing like the classic ones, and models are shared between
   different characters (Ethel has a beard). Hearts aren't heart-shaped, the save
   machine is wrong, objects are unrecognizable, and nothing has break animations.
   Every one of those complaints comes from one decision: drawing the world from
   new models instead of the original pixels.
2. **Collision is defined twice and the two definitions disagree.** Movement is
   blocked if *any* of these hits: original entity hardboxes (grown 4 px), original
   tile hardness masks, **or** a 0.24 m capsule overlapping any 3D decorative body
   (`fps_game.gd` `_blocked` → `_fps_capsule_blocked`). Invisible original hardness
   with no visible 3D counterpart = "trapped by open air." A 3D body placed away
   from the source hardbox also narrows gaps the original allowed. The
   `_fps_landing_recovery_offsets` search exists to paper over that mismatch.
3. **Each increment waited on Chris.** The human-acceptance gate made every fix
   wait for his playthrough and let unfinished work sit behind "pending." The agent
   must judge fidelity itself, against the original, before Chris sees anything.

## The structural change

**Derive the look and the solidity from the same original data.**

- **Characters, creatures and small props** (people, pigs, duck, barrels, pots,
  hearts, the save machine, bushes, trees): render the original sequence frames as
  camera-facing billboards. For directional sequences (1–4, 6–9), pick the frame
  from the angle between the camera and the actor's facing, as Doom does.
  Break/death/attack animations come directly from the original sequences.
- **Fences, walls and building facades:** place the original sprite pixels on quads
  or boxes with a **fixed** orientation along their footprint. Building sprites are
  drawn in 3/4 view: map the facade part of the sprite onto the front wall and the
  roof part onto the roof.
- **Ground:** use the original tile art everywhere, including the pigpen dirt.
- **Collision has one source:** the original hardboxes and tile hardness. Every
  hard region must have something visible at that spot. With billboards at the
  source positions this holds by construction. Tile hardness with no sprite (water
  edges, cliffs, forest walls) gets visible geometry generated from the mask.
  Decorative 3D bodies must never block movement on their own.
- **Content:** keep the humor, and rewrite the demeaning lines in the original
  voice through `tools/dialogue_overrides.json`, with a record of each change.

**Open risk, answered with a prototype and not by argument:** the sprites were
drawn from a raised 3/4 view, and at eye level they may look wrong. Build the
pigpen and village screens first, capture them next to the original, and judge
them. If it fails, raising the camera slightly or tilting the billboards are the
first fixes to try.

## Process

- Campaign expansion stays frozen until the opening meets this direction.
- The agent building it owns the visual judgment: side-by-side captures against
  the original at each step, with the defects it sees listed in writing. Chris is
  not the gate for each increment. He plays milestones, not steps.
- Automated input replays verify behavior, never appearance.

## Prototype result — September 24 (Opus 5.5)

`game/prototype/sprite_world_proto.gd` rebuilds the 5×5 screens around the pigpen
(map 407) from original data only. It does not touch the game.

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --audio-driver Dummy \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/sprite-proto-sept24" 407
```

Captures: `builds/sprite-proto-sept24/` (see `compare-pigpen.jpg` for original,
current build and prototype side by side).

**What worked:** the pigpen reads as Dink at eye level on the first try: the
original pigs, rail fence with yellow ties, rocks, grass tufts, trees and duck.
The 3/4-view risk turned out small for animals, props and trees. Techniques that
worked:
- Uniform 0.025 m per source pixel for ground **and** sprites, so fence segments
  meet the way they were drawn to. The game's 0.06 m ground scale spreads the
  world 2.4× wider than its art, which may be part of the "wide open and flat" complaint.
- Sprites anchored at their original hotspot (`dx`,`dy`), Y-axis billboards.
- Directional actors choose their frame from the camera angle (`_face_actors`).
- Type-0 background sprites painted into the ground image, like the original engine.
- Dithered black shadow pixels removed from upright sprites; they float at eye level.
- Fences drawn along the depth axis rebuilt from the side-view rail (seq 93 frame 1),
  turned 90°.

**Still open, in order:**
1. **Buildings.** A 3/4-view house drawn on one flat card looks like cardboard.
   Build a box on the hardbox footprint, map the facade band of the sprite onto
   the front wall and the roof band onto a roof mesh, and repeat or mirror for the
   sides. This is the main remaining piece of work.
2. Diagonal fence corners (seq 93 frames 2, 3, 5, 6): same rail rebuild, at 45°.
3. Soft blob shadows under actors to replace the removed dither.
4. Story state: the prototype shows every editor sprite, including the burned-house
   fire. In the game, the DinkC VM already hides sprites per story state; integrate
   through `fp_world.create_visual`/`update_visual`, not by duplicating the logic.
5. Collision from the same data (see above), then remove
   `_fps_landing_recovery_offsets`.

## Buildings — September 29 (Opus 5.5)

Item 1 above, done in the prototype for the four thatched houses of seq 63
(frames 1, 4, 6, 8: Dink's cottage and the Stonebrook houses on screens 439, 440,
469, 470, 409, 437). Evidence: `docs/images/facades-sept29.jpg`.

**Method (camera projection mapping, not a card and not a new model).** A house
sprite is a picture of a 3D house taken by the original camera. On the prototype's
1:1 ground that camera is the projection `screen = (X, Z - Y)`, an orthographic
view 45° down. All four sprites share it: their wall-base lines have slopes +0.48
and −0.50. `tools/facade_fit.py` recovers each house from its pixels:
- the footprint is the two wall-base lines, which on a 1:1 ground are the footprint
  itself;
- wall height and eave overhang come from fitting a rendered stone/thatch/air label
  map to the sprite;
- hip roofs are modelled as blocks, stacked for the two-tier home-04.

Roof pitch is read from the art. The label map can't see the ridge, and two
automatic criteria failed (see the tool's docstring). All four land at 42–48°.
The prototype builds each face with UV = the projection, which is exact on planes,
so the house reproduces its sprite from the original camera. Faces facing north
take the point-mirrored front face. The wall band the eave hid from the original
camera takes the stone below it, mirrored. Doors, windows and chimneys overlapping
a house are composited into its texture in the original draw order. Its dithered
shadow is painted into the ground.

```bash
/usr/bin/python3 tools/facade_fit.py   # -> game/prototype/facades.json
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --audio-driver Dummy \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/facades-sept29-407" 407
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --audio-driver Dummy \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/facades-sept29-470" 470
/usr/bin/python3 tools/facade_contact_sheet.py builds/facades-sept29-407 builds/facades-sept29-470 \
  --out docs/images/facades-sept29.jpg
```

The prototype now shows only vision-0 sprites (the editor's default story layer),
like the reference images. Story state is still item 4.

**Judgment.** From the original camera, screens 439, 469 and 470 match the source
reconstruction closely: the cottage, door, chimney, feed sack, shadow, fences and
river are where the original draws them. Mean |RGB| difference is 8.6–14.3. That
number is only a regression check, blind to every view but that one. At eye level
the houses read as the original stone-and-thatch cottages with their own doors and
windows. They are solid, not cardboard. The 3/4-view risk did not bite here either.

**Defects I see, in order:**
1. Chimneys (home-11/12) are composited flat onto the roof. At eye level they
   vanish. They need to be their own upright pieces standing on the roof.
2. home-04's skirt roof: the art's drooping thatch roll hangs lower than a flat
   eave, so a thatch band shows above the door at eye level. There are also small
   wing tips at the skirt ends from the original camera.
3. Roofs have zero thickness, so the rounded thatch roll at the eaves reads as a thin
   board from below.
4. Footprints are rhombi (56°/124° corners). This is the honest consequence of the
   1:1 ground, and it's barely visible at eye level.
5. **For the collision step (item 5):** a house's hardbox (e.g. home-01
   `[-129,-85,188,-1]`) is a rectangle behind the hotspot. The drawn walls extend
   about 90 px in front of it: the door of screen 439 stands at y=280, the hotspot is
   at 234. "Collision from hardboxes only" would let the player walk into the front
   walls. For buildings, collide with the fitted footprint, which is derived from
   the same original pixels.
6. Not done: the modular inn (seq 33 `outinn`, screens 472/473) and the cabin
   pieces. They need a panel-by-panel version of the same projection.

## Chimneys and the inn — September 29, second pass (Opus 5.5)

Buildings defects 1 and 6 above, with the same method: recover the geometry from the
original pixels under the original camera, texture it by projection, judge it from the
original camera and at eye level. Evidence: `docs/images/chimneys-inn-sept29.jpg`.

**Chimneys.** A chimney sprite (home-11, home-12) is a picture of an upright prism. Its
top face is horizontal, so under `screen = (X, Z - Y)` it shows its own footprint.
`tools/facade_fit.py` reads that face from the top outline, and it reads the foot: the
lowest stone pixel under the front edge. The prototype casts the view ray through the
foot into the house's fitted roof. Where it lands fixes the chimney's depth, and the top
face then fixes its height. The same ray test decides what a detail is: a foot that lands
on the roof means an upright piece, anything else is composited onto the walls as before.
The thatch ring and the dithered shadow at the chimney's foot lie on the roof, so they are
painted onto the roof texture.

Correction to the Sept 29 notes: only Dink's chimney (439) was composited onto its roof.
The two on 469 were ground cards hidden behind the house. That house is also placed on
screen 437 (y = 760), 437 was built first without them, and the duplicate check then
skipped 469's copy. Houses are now built in a pre-pass over the whole block, with details
gathered from every screen in world coordinates.

**The inn and its neighbour (kit buildings).** The inn is not one sprite. Its stone
ground floor and roof are seq 33 kit sprites, but its half-timbered upper storey and eave
are ground tiles (tilesets 34 and 35). The prototype used to paint that storey flat on the
ground and stand the kit pieces up as separate cards.
- `kit_canvas` rebuilds the building as the original camera saw it: per screen, its tiles
  and kit/door sprites in the original draw order, clipped as the engine clips them. Grass
  and water connected to the outside are cleared. The building is the largest connected
  component, and its pieces are listed explicitly, because two kit buildings share screen
  538.
- `kit_fit` models each building as two hip-roofed wings that share the outer front
  corner. Their union is exactly the L's roof: a hip at the outer corner and a valley
  inside. The upper storey is jettied over the stone floor, and the hip ends are steeper
  than the long slopes. Both show in the silhouette, and each was a structural change that
  the misfit located (IoU 0.92 → 0.94 → 0.97).
- Both buildings use the same kit pieces, so they share one kit geometry, fitted jointly:
  wall 284 px, stone storey 88, jetty 14, eave 20, pitch 45°, end pitch 1.7. Only the wing
  depths are per building. Fitted separately, they disagreed by 13% on wall height and
  2.6× on end pitch. The joint fit scores higher on both (inn 0.971, kit-538 0.966) than
  either separate fit did.
- Hanging signs sit on the walls in the original, but their hotspots are behind the drawn
  wall. A sprite whose visible foot (the bottom of its centre column) the view ray lands on
  the building is composited onto its walls. Barrels and benches standing in front keep
  their own billboards.
- The inn's tiles leave the ground, and the ground continues the row they interrupted.

```bash
/usr/bin/python3 tools/facade_fit.py
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --audio-driver Dummy \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/facades2-505" 505 \
  439 472 473 474 504 505 506 538 539
/usr/bin/python3 tools/facade_contact_sheet.py builds/facades2-407 builds/facades2-470 \
  builds/facades2-505 --out docs/images/chimneys-inn-sept29.jpg \
  --screens 439,469,472,474,505,506,538 \
  --eye 1:cottage-front,1:cottage-east,1:village-469,2:inn-southwest,2:inn-door,2:inn-south,2:inn-north,2:inn-northeast,2:inn-east,2:kit538-southwest
```

Headless runs use Mesa llvmpipe (the project uses the Compatibility renderer), not a GPU.
Each run takes about 7 s.

**Judgment.** At eye level the inn is one solid two-storey Tudor building. It has the stone
ground floor with its doors, the X-braced upper storey jettied over it, the hanging signs,
and a hipped shingle roof. It reads as the original inn, not as a row of cards. The house
south-east of it came out of the same fit unchanged. Chimneys stand upright on the ridges.
From the original camera the screens match the source reconstruction: mean |RGB| 11.0–14.8
on 439, 469, 472, 474, 505, 506 and 538 (538 was 17.0 before). That number is a regression
check only. The Sept 29 screens are unchanged (407 13.8, 439 13.9, 440 14.3, 469 11.0,
470 8.6).

**Defects I see, in order:**
1. Dormers are flat on the roof: they are baked into roof panels 13, 31 and 32. At eye
   level they barely show. They are the chimney problem again, but their pixels must first
   be separated from their panel.
2. The back of each kit building mirrors its front, so the signs and doors repeat on the
   back walls.
3. The jetty soffit is textured by projection from the band above it. It is plausible, not
   derived.
4. The chimney on 439 lost its thin cast shadow on the thatch. This shows only from the
   original camera.
5. Seq 33 kit buildings appear on 25 more screens (186–251, 385–388, 417–420, 465–467,
   497–499, 553–555, 585–587). Each needs a `KIT_BUILDINGS` entry today. Finding
   them automatically (connected components of kit pieces over the whole map) is the next
   step, then the joint fit covers them all.
6. For the collision step: a kit building's footprint is its fitted stone storey (blocks 0
   and 2), derived from the same pixels. Footprints are still rhombic (defect 4 above).

## Kit discovery, dormers and backs — September 29, third pass (Opus 5.5)

The five defects of the second pass, in the order the eye-level captures ranked them. The
25 unlisted seq 33 screens came first: their buildings still stood as cards, with the upper
storeys painted on the ground, which is the failure the buildings work set out to remove.
Evidence: `docs/images/kit-buildings-sept29.jpg` (original camera beside the source for eight
screens, then eye-level pairs, before on the left).

**Discovery (defect 5).** `tools/facade_fit.py` no longer lists kit buildings. It groups the
outdoor screens holding any kit piece into adjacent clusters, rebuilds each cluster as the
original camera saw it, and takes every connected component holding a seq 33 sprite as a
building. On the two hand-listed buildings this reproduces the old rects and members exactly
(only the signs, added later by `wall_details`, differ). There are seven buildings. The inn
is now `kit-537` and the old `kit-538` is `kit-570`, each named after the screen of its lowest
front corner. The others are `kit-251` (north), `kit-417` (west), `kit-498` (west Stonebrook)
and `kit-585`/`kit-587` (the square with the fountain).

`kit-417` is a zig-zag, not an L, so the fit now puts one hip-roofed arm on each straight run
of the front (`front_polyline`: the bottom of the silhouette splits at its convex and concave
corners). Where the front turns toward the camera, two arms share the front corner, as the L
did. Where it turns away, they share the back corner, so each reaches past the corner by the
other's depth. One kit geometry is fitted jointly to all seven: wall 296, stone storey 92,
jetty 16, eave 16, pitch 1.05, end pitch 1.4. Only the arm depths are per building.
Silhouette IoU is 0.959–0.971; the inn fell from 0.971 to 0.970 and kit-570 from 0.966 to
0.963. Six shared numbers fit seven buildings, one of them a shape the model had never seen.

The prototype now builds a kit building when any of its screens is in the block.

**Dormers (defect 1).** Each dormer panel (seq 33 frames 13, 31, 32) has a plain twin in the
kit, the same-size panel it differs from least: 12, 30 and 29. The two are identical except
where the dormer and its shadow are. A shadow keeps the plain roof's texture, darkened; the
dormer replaces it. Local normalised cross-correlation against the twin separates them. Two
earlier separations failed: a colour ratio, because the dormer's shingles are the roof's grey,
and a wood-and-glass colour mask, because the warm shingles pass it.

The dormer is a gabled prism: a vertical gable parallel to the wall below, running back until
the roof closes over it at the kit's pitch. So nothing behind the gable is fitted. Fitted one
by one, the three panels agreed within 4 px on width, cheek and rise, and chose their own
orientation: 13 faces down-right, 31 and 32 down-left. They are therefore fitted jointly: one
dormer, each panel with its own foot (IoU 0.79–0.80). The prototype lifts each dormer along
the view ray through its foot onto the roof, as it does the chimneys. On the roof, the panel
shows its twin wherever the dormer stood. That also removed the flattened dormers the north
slopes used to take from the mirrored south slopes.

**Backs (defect 2).** Faces the original camera never saw still take the mirrored front, but
from a back canvas. For kit buildings, each door panel (12 seq 33 frames, listed) shows its
door-less twin, which is always the window panel of the same wall slot, and door and sign
sprites are left off. Houses get the same: their doorways (seq 63 frames 2 and 3) and door
leaves (seqs 61, 62) stay off the back. The inn's back now has windows in the bays where the
front has doors, and Dink's cottage has one door, not two.

`wall_details` needed a second test once it ran on seven buildings. It had taken a tree
(tree-01 on 187 and on 472) and grass tufts as signs, because their foot rays land on the
building. A sign is drawn on the building, so most of its pixels lie on the building's own
mask. Over the seven buildings the numbers are:

| Sprites whose foot ray lands on a building | Share of pixels on the building's mask |
|---|---|
| Trees and other standing objects | 0–1% |
| Signs | 80–100% |

The threshold is 50%. The tree on 472 had raised that screen's number from 14.7 to 16.3.

**Soffit (defect 3): decided, not changed.** No pixel of the original shows a jetty's
underside, so any texture there is a convention. The projection samples the bottom band of the
upper storey, the bressumer and the foot of each stud. From below, that reads as joists under a
beam, which is how close-studded jetties are framed: each stud stands over a joist end.

**The 439 chimney's cast shadow (defect 4): still open, diagnosed.** The wedge is 91 pixels of
the chimney sprite, 88 of them over the house sprite. home-01's pitch (42°) is under the
camera's 45°, so the camera sees a sliver of the north slope. Every wedge pixel's view ray
lands on that slope (face 6, normal (−0.30, 0.74, −0.60)), which is textured from the mirrored
front. Painting those pixels into the back texture at their mirrored place changed nothing in
the render, which shows grass there. So the rendered geometry and the fitted faces disagree at
that edge. Next: a face-ID render from the original camera. The failed fix was reverted. This
shows only from the original camera.

```bash
/usr/bin/python3 tools/facade_fit.py
/usr/bin/python3 tools/kit_shots.py kit-498 tools/shots/kit-498.json   # the shot files are committed
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 --audio-driver Dummy \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/final-498" 498 \
  465 466 467 497 498 499 "$PWD/tools/shots/kit-498.json"
```

The other runs use the same command, with these centres and shot files:

| Centre | Shot file | Original-camera screens |
|---|---|---|
| 419 | `kit-419.json` | 385–388, 417–420 |
| 219 | `kit-219.json` | 186, 187, 218, 219, 251 |
| 586 | `kit-586.json` | 553–555, 585–587 |
| 505 | `dormers-505.json`, or `soffit-505.json` | 505 |
| 505 | none | 439, 472–474, 504–506, 538, 539 |
| 470 | `cottage-439.json` | 439 |
| 407 and 470 | none | the defaults |

The "before" images are the same runs with 2073182's `game/prototype/facades.json`. The
cottage's before image also used 2073182's prototype script.

**Judgment.** At eye level, every kit building on the map is a solid two-storey Tudor
building. The zig-zag on 417, the long L of west Stonebrook and the two small Ls round the
fountain were rows of cards before. The dormers stand up out of the roof line, with their
four-pane windows, and read from across a street. Backs no longer repeat their fronts' doors
and signs.

Through the original camera, the new screens match the source reconstruction: mean |RGB|
5.2–18.5 over the 25, which is a regression check only. The Sept 29 screens are unchanged:

| Screen | 407 | 439 | 440 | 469 | 470 | 472 | 473 | 474 | 504 | 505 | 506 | 538 | 539 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2073182 | 13.8 | 13.9 | 14.3 | 11.0 | 8.6 | 14.7 | 15.1 | 13.4 | 11.0 | 12.6 | 14.8 | 12.4 | 8.9 |
| Now | 13.8 | 13.9 | 14.3 | 11.0 | 8.6 | 14.7 | 14.7 | 13.3 | 11.0 | 12.6 | 14.6 | 12.4 | 8.9 |

**Defects I see, in order:**
1. The band the eave hides at the top of each upper storey is textured from the band below
   it, mirrored. At eye level it repeats as a chevron strip along every kit building's eave.
2. Other buildings are still cards:

   | Building | Where |
   |---|---|
   | The church (seq 60) | 187, 188 |
   | Log cabins (seq 59) | 251, 270, 274, 409, 440, 500, 501, 530 |
   | Thatched houses of seq 63 frames 5, 7 and 10, which are not in `HOUSES` | 318, 349, 350, 497, 500, 501, 537, 619, 734 |
3. Tilesets 36–39 are not in `game/assets/tiles`, so the courtyard of kit-417 (screens
   385–420) has no ground. The contact sheet and the prototype skip them alike.
4. The 439 chimney's cast shadow (above).
5. Each dormer's gable is fitted about 7 px wider than its drawn frame on one side.
6. For collision (item 5): unchanged. A kit building's footprint is its arms' stone storeys.

## Tiles, mirror-twin houses and the log cabin — September 29, fourth pass (Opus 5.5)

The defects of the third pass. Evidence: `docs/images/cabin-houses-tiles-sept29.jpg` (per screen:
source, before, after through the original camera; then eye-level pairs, before on the left).
One command now renders every building run and compares two sets of renders:

```bash
/usr/bin/python3 tools/facade_fit.py
/usr/bin/python3 tools/facade_regress.py render . tmp/after            # every run, ~2 min, llvmpipe
/usr/bin/python3 tools/facade_regress.py render <old checkout> tmp/before
/usr/bin/python3 tools/facade_regress.py table tmp/before tmp/after
/usr/bin/python3 tools/facade_regress.py sheet tmp/before tmp/after --out sheet.jpg --screens 270 --eye s270-6-near
```

`tools/kit_shots.py` also writes shots round a placed sprite (`screen:index`).

**Tilesets 36-39.** The importer globbed `*.bmp`, which is case-sensitive on Linux, and the original
ships `ts36.BMP` to `ts39.BMP`. It now matches the suffix in any case. Re-running the tile step
reproduces every existing tile byte for byte and adds these four. The courtyard of kit-417 has its
cobbles (385-420: mean |RGB| 8.3-18.0, from 16.2-32.2). The game loads the same sheets.
`S04.bmp` (20x20, short palette) and `cd.BMP` are still skipped. They are not tiles.

**Seq 63 frames 5 and 7** are frames 4 and 8 drawn mirrored (silhouette IoU 0.99 against the
mirrored twin; the lighting was re-rendered). One house drawn twice has one geometry, so each pair is
fitted jointly, each sprite with its own base lines. Fitted alone, home-05 chose a smaller upper
block whose roof fell 20 px short of the drawn peak. The joint fit raised home-04's own score
(0.592 to 0.605) and moved 440, 586 and 618 by +0.1; at the pixel the house is unchanged. Screens
497, 500, 501, 537 and 619 had these houses as cards; they are solid now.

**The log cabin (seq 59 frame 1)** is not a hip-roofed house: `gable_faces` builds a gabled block
(eaves and verges overhanging, long walls up to the roof's underside, gable pentagons at the ends).
Every fitted house shares the art's two wall directions to 0.001 (`wall_dirs`), so a building's
parts are placed in that frame and only their dimensions are fitted (`parts_score`: silhouette, wall
and roof IoU). The stone chimney defeated three fits: its sides lie inside the silhouette and its
stone and the logs share their colours, so only its foot and its top show against the air. It is
read from those, like the roof chimneys (`standing_chimney`): the foot's two base lines along the
wall directions give its footprint, the top face gives the top and, standing on the wall line, the
height. It is a frustum from one to the other. Faces carry their own texture coordinates (`polys`),
and the body's texture has the chimney cleared and filled from its own pixels (`occluders`,
`_add_uv_house`), so the gable wall behind it shows logs. The "log cabins" on 274, 409, 440, 500,
501 and 530 were cabin-03 windows and cabin-02 doors on houses; there are two cabins, on 251 and 270.

Seq 59 frames 2 and 3 on houses are composited onto their walls as before.

**Judgment.** At eye level the cabin is a log cabin with a tapering stone chimney against its
gable, from all four sides; it was a card that went edge-on from the east and west. The twin houses
stand like their twins. Through the original camera every Sept 29 screen is within +0.1 except two:

| Screen | Before | After | Why |
|---|---|---|---|
| 251 | 12.4 | 12.7 | tree-08 stands 3 px in front of the cabin's long wall; its flat billboard is half inside the wall |
| 497 | 16.7 | 17.0 | tree-04 west of home-07: its canopy is in front of the back roof in 3D, behind the house in 2D |
| 270 | 15.0 | 13.9 | the cabin |
| 500 / 537 / 619 | 12.1 / 13.0 / 13.4 | 11.4 / 12.5 / 13.1 | the twin houses |

**The church (seq 60 frame 1, 187-188)** is parts in the same frame (`church_parts`; built by a
Sonnet 5.5 subagent, judged here): the nave and the chancel are gable blocks, the chancel centred on
the nave's axis; the apse is a half cylinder as wide as the chancel with a half-cone roof; a square
tower on the ridge carries the spire; four buttresses stand against the south wall. Walls and roof
are told apart by warmth and brightness (`church_labels`). Its unseen half-apse mirrors across the
apse's axis, not through a point (`uv_polys(..., mirrors)`). Silhouette IoU 0.956. Two weaknesses:
`church_score` weights a fixed pixel window round the spire, fitted to this one sprite, and the
buttresses' height is read from the art and held (their tops lie inside the silhouette). The dark
square on the chancel's west gable is chrch-09, a window the level places on screen 187.

**The eave band (third pass, defect 1).** The band the eave hid now takes the wall one band further
down, shifted up, not the band just below it mirrored: that band carries the eave's own marks
(rafter holes on the cottages, the top rail on the kit buildings), and the mirror doubled them into
diamonds and chevrons. Walls under a jetty keep the mirror. The original camera cannot see the band,
so its numbers are unchanged; see the last rows of the evidence sheet.

**The 439 chimney's cast shadow (third pass, defect 4).** A face-ID render (prototype arg `faceid`:
each house face flat in its own colour) put 98 of the wedge's 169 pixels on face 6, the north slope's
sliver behind the ridge, 20 on the hips and 43 behind the chimney itself; 8 miss. So the geometry was
right. Face 6 is textured from the back canvas through the point mirror, and the foot was painted
only into the front canvas. Painting each pixel at its mirrored texel (the earlier attempt) lands, but
the sliver is seen at a grazing angle: neighbouring screen pixels sample texels ~10 px apart, and the
isolated painted texels vanish in the mipmaps. `_paint_unseen` paints every back texel whose point on
an unseen face projects onto a foot pixel. The wedge's error fell from 33.1 to 16.5.

Evidence: `docs/images/church-eaves-sept29.jpg`. Regression over every screen rendered since Sept 29
(`tools/facade_regress.py table`): 187 17.7 to 14.8, 188 13.5 to 12.0, 439 13.9 to 13.8; the rest as
in the table above.

**Defects I see, in order:**
1. home-10 (seq 63 frame 10, one house on 318, 349 and 350) is still a card: a two-storey core with
   a lower cross wing, the kit's arms-along-the-front model with an upper block.
2. At the acute corner of the rhombic footprint (56 degrees), a hip roof's eave sticks out as a
   thatch spike about half a metre long.
3. A tree billboard standing against a wall is cut by it (251, 497): the flat billboard stands at
   the trunk, not at the front of its canopy.
4. home-13, the tall chimney beside home-05 on 500, is composited flat onto the wall; it is a sprite
   of its own, so `roof_piece` can read it once a foot ray that misses the house means the ground.
5. The church's spire has no tower shaft (it fits at the grid's floor) and its buttresses are about
   5 px wider than drawn.

## Eave tips, trees against walls, home-13, home-10 — September 30, fifth pass (Opus 5.5)

Four of the fourth pass's defects. Evidence: `docs/images/tips-trees-chimney-sept30.jpg` (source,
e859386, now through the original camera; then eye-level pairs, e859386 on the left).

**Eave tips (d131a84).** A hip roof's eave, offset o from its walls, stands 2.1 o out at the
rhombic footprint's acute corners (52 degrees), the left and right tips on screen. From the original
camera those tips stood past the drawn roof (the "wing tips" of the first pass); at eye level they were
flat blades of thatch. The first fix rounded the eave (an overhang of width o all round, the roof
fanning up to the hip line). The blades went, but every house got worse from the original camera by
0.1-0.3. Four triangulations and texture rules gave the same numbers to the decimal. A changed-pixel map
showed why: rounding pulls each hip line in from the tip toward the arc, and the drawn roof keeps its
hip lines straight out toward the tip. It only stops short. So `clip_tips` keeps every plane and hip
line and cuts each block's two side tips with the vertical plane at the sprite's own extent in the
tip's row, read from the art, not tuned. No screen is worse (440 -0.2, 500 -0.2, 617/618 -0.1).

**Trees against walls (4a19be9).** A flat billboard (or a wide tree's fixed card) whose canopy overlaps
a house or parts building is cut where the plane through its trunk passes inside. The original's draw
order says which side of the building it belongs on. One drawn over the building (hotspot below the
building's) is moved along the view ray toward the camera by its half-width, and scaled to keep its size
on screen. Its trunk, and any collision, stays at the source position (`_flag_nudge`,
`_nudge_billboards`). 251 12.7 to 11.6. One drawn under the building (tree-04 on 497) is left:
moved away along the ray its trunk sinks below the ground (498 went +1.2 when tried). It needs a depth
offset in the sprite's shader, not a move.

**home-13 (ba949c1)**, the tall chimney beside home-05 on 500, is a sprite of its own: a rubble firebox
under a tapering stack, like the cabin's. `standing_piece` reads its foot from its bottom outline
along the wall directions and its top face as a roof chimney's; its axis is taken as vertical, which
fixes the height (163 px). The prototype stands it on the ground as the frustum between them
(`_add_ground_piece`). The house's own wall shows behind it.

**home-10 (seq 63 frame 10, one house on 318/349/350),** fitted by a Sonnet 5.5 subagent and judged
here. Evidence: `docs/images/home10-sept30.jpg`. Three hip-roofed blocks in the wall frame: a long
lower wing, a lower front wing crossing it, and the two-storey core. The zig-zag front is read by
`zigzag` with the art's slopes fixed. It is fitted jointly with home-09, its mirror twin, with a
depth-tested render (`render_z`) and shadow pixels left unread. Silhouette IoU 0.960, and 0.961 on the
twin. At eye level it went from a card to a solid stone house with a cross wing. From the original
camera, 350 went from 12.5 to 10.9, but 318 got worse, 10.1 to 10.2. The core's roof lands a few px
right of and below the drawn rounded top, and the old card was exact there. Held, not fitted: the
core's height is twice the wings' wall height, because its foot is hidden and height and depth trade
along the view ray. The wing pitch fitted 0.65, under the 0.8-1.1 read from the other houses'
art, and the core pitch is unresolved.

Regression over every screen rendered since Sept 29, against e859386: none worse except 318 (+0.2,
home-10's core roof). Against the Sept 29 baseline, 497 stays +0.3 (tree-04, drawn under the house).

**Defects I see, in order:**
1. home-10: the core roof sits a few px low from the original camera (318). The wing roofs, at pitch
   0.65, read flatter than the drawn thatch. The front wing's back end carries mirrored thatch.
2. A tree drawn under a building (497) is still cut by it: it needs a depth offset in the sprite's
   shader, not a move.
3. The church's spire has no tower shaft, and its buttresses are about 5 px wider than drawn.

## Home-10's roofs, thatch, trees under buildings, the tower shaft — September 30, sixth pass (Opus 5.5)

State at the time of writing (the pass is in progress; the last paragraph says what is left).

**home-10's roofs (d13c6c8, on the held 997ac24).** The wing pitch is read from the art as the other
houses' are: an overlay of 0.65, 0.85 and 1.05 puts the front wing's hip end, its one ridge end drawn
against contrast, on 1.05. Fitted freely it had gone to 0.65: flat slabs. The core's pitch is read from
the sprite's top 80 rows, where only the core's roof stands against the air. Screen 318 shows exactly
those rows. Silhouette IoU there, on both twins, peaks at 1.5 (1.25 fitted). The band along the core
roof's top edges that 318 showed is gone. 318 is still +0.14 against the card (10.08 to 10.22), spread
evenly over the roof's interior, not its edges. It is not mip blur: with mipmaps off it is unchanged
to three decimals. It is not diagnosed. The card was exact there, and 350 went 12.5 to 10.4.

**Thatch (block_faces `thick`, `bulge`).** Drawn thatch is convex and hangs a little at the eave. Each
hip slope now breaks halfway up its hip lines, raised by a bulge, and a thatch edge hangs from the eave
with the underside below it. One profile for this art's thatch, from the mean label score over every
house's sprite: 2 px hanging, 8 px bulge (0.6796, flat 0.6715). The first try raised the thickness
above the slopes, where the silhouette cannot tell it from a bulge. Read per house, the label score and
the original camera disagreed, so the profile is shared, as the kit's geometry is. d13c6c8 gives it to
home-10 only. The next commit gives it to every thatched house: at eye level the cottages' roofs are
full and rounded instead of boards. From the original camera, against the published state: 439 -0.34,
617 -0.35, 440/500/586/618 -0.1, but 619 +0.10 and 470 +0.08. Evidence: `docs/images/thatch-sept30.jpg`
and `docs/images/home10-roofs-sept30.jpg`.

All Godot runs now use `--audio-driver Dummy` (f838088): no sound may reach the default sink.

**The church's tower shaft.** The spire's fit scored the tower and the pyramid by outline only, and
its render sorted whole faces by mean depth, so the near roof slope hid the tower. The pyramid
swallowed the shaft (the tower's top at the grid's floor). Now the body is fitted as before and the
tower and spire are refined on their own (`church_spire_score`). In the spire window the tower's stone
and the spire's shingles count by label, depth-tested (`render_z`). Tower 30 px (was 23), top 7 px above
the ridge, spire 60 px (was 74). The shaft band matches the drawn one's width from the original camera.
At eye level the spire stands on a short dark shaft. 186-251 are unchanged to 0.05.

**Trees drawn under a building (`_push_back`).** A sprite the original draws under a building its
canopy overlaps keeps its place, and its depth is pushed away by its half-width in its own shader. Each
fragment's push is capped at 0.9 of its clearance above the ground along the view ray, so the trunk
never goes under the ground (moving it did). Control: with every push at 0 the images equal the plain
sprites' (mean |d| 0.000). It is the other half of the draw-order rule of the fifth pass. On today's
screens it changes 9-16 px at eye level and nothing from the original camera.

**Correction to the fourth and fifth passes:** the tree over home-07 on 497 is not tree-04 of 497
(drawn under the house). It is tree-04 of screen 528, whose trunk stands in front of the house, 40 px
below 497's edge. Its canopy reaches over the house. The source reconstruction draws only a screen's
own sprites, as the original engine did; the continuous world shows it, correctly in front. 497's
+0.3 against Sept 29 is that, not a cut tree.

Regression over every run, against the published state (a8fbd02 + package 5): 350 -2.0, 439 and
617 -0.3, 440/500/586/618 -0.1; worse: 318 +0.14 (home-10's core roof, above), 619 +0.10 and
470 +0.08 (the shared thatch profile, in its own commit).

**Next step (recommended):** the buildings are done. Every building on the map is a solid,
derived structure. The prototype is not the game. Integrate it, in this order:
1. Collision from one source: the original hardboxes and tile hardness, plus the fitted building
   footprints (the drawn walls stand ~90 px in front of the houses' hardboxes; Buildings defect 5).
   Then remove `_fps_landing_recovery_offsets` (item 5 above).
2. Story state through the DinkC VM's `fp_world.create_visual`/`update_visual`, not the prototype's
   vision-0 layer (item 4).
3. Build the game's world from the prototype's buildings and billboards, then have Chris play the
   opening.


## Collision from one source — September 30, seventh pass (Opus 5.5)

Step 1 of the sixth pass's next step. Evidence: `docs/images/collision-sept30.jpg` (per row: Dink
walks into a wall with W from 60 px out; a post marks where he stopped, seen from 70 px behind him;
8db1ff5 left, now right; the collision change beside them: kept grey, dropped red, added green).

**What the old collision was, measured.** Buildings defect 5 took home-01's hardbox, ~90 px behind
the drawn front wall, for the collision. 439 does not use it: most house sprites are not hard. The
map makers drew a house's hardness as a ring of custom tile masks round its picture.
`tools/collision_map.py --profile` walks into every wall of every fitted footprint on the map, at
points 5 px apart, from 80 px out. It leaves out approaches that meet a fence or a barrel first.

| | Front walls (1,779 approaches) | Back walls (1,916) |
|---|---|---|
| Original data: where the player stops | median 15 px in front of the drawn wall (10th percentile 2, 90th 32); 3% walk more than 80 px in | half walk more than 80 px in (kit buildings have no hardness on their backs); behind the houses, the ring stops him 45–80 px out in open ground |
| Now | median 4 px (the player's radius); 90% at 3–7 px | median 5 px; 77% at 3–7 px |

The rest are approaches that meet a building's other arm or a restored tile line within the last
few pixels. Before this pass the game also stopped the player on any 3D model
(`_fps_capsule_blocked`). The cottages were Blender models stretched over the unused hardbox, so
60 px behind Dink's cottage he stood inside it and could not move (sheet, second row).

**One source.** `tools/collision_map.py` writes `game/data/footprints.json`. Per screen it lists
the fitted footprints and the original hardness each replaces. A footprint is, per block, the hull
of the fitted faces' points on the ground: walls, the apse, buttresses, standing chimneys. Jettied
storeys and the tower are not on the ground. The hardness it replaces:
- the hardboxes of the building sprites, of the `/struct/` details drawn on them (doors, windows),
  of kit pieces, and of invisible (type 2) blockers standing on the picture (465, 585);
- a kit building's own tiles;
- the ring: custom tile masks on the building's picture (inside its outline), and custom hardness
  within one tile (50 px) that hangs off those and ends there. A custom mask that goes on beyond
  that or off the screen stays: the courtyard wall beside kit-417 on 385 and 388, forest edges,
  fences. A tile that loses its custom mask keeps its art's default mask (a river bank, a cliff
  edge).

The first core rule, any custom tile the outline touched, took the courtyard wall on 385 and 388,
which the outline grazes by one pixel. The overlays of all 57 screens with buildings were read to
settle the rule.

`game.gd` reads the file. A building's footprint, grown 4 px as every hardbox is, blocks movers,
missiles and lines of fire in place of that hardness while the building's entity is active.
`fps_game.gd` no longer blocks on 3D bodies, so `_fps_recover_landing_overlap` and its search are
gone. 3D bodies remain, for rays only.

**What stands where it blocks.** In the game, each fitted building replaces the Blender cottage
stretched over the hardbox. It is built from the fitted faces, each coloured by the sprite pixels
it covers from the original camera, and kit buildings in plain stone, plaster and shingle. That is
a stand-in: step 3 brings the prototype's projection-textured build. A door stands in the wall it
is drawn on. The porch that joined the old door to the old box is gone. A kit building's own tiles
leave the ground, as in the prototype, and the story fire stands on the fitted roof's east slopes.

```bash
/usr/bin/python3 tools/collision_map.py              # -> game/data/footprints.json (after facade_fit.py)
/usr/bin/python3 tools/collision_map.py --profile 439 505    # walk into every wall, old data and now
/usr/bin/python3 tools/collision_map.py --sheet tmp/collision 439 505   # overlays
/usr/bin/python3 tools/collision_sheet.py <8db1ff5 checkout> . --out docs/images/collision-sept30.jpg
```

**Verification.**
- `tests/fps_wall_test.gd` (new, real W input, screens loaded without scripts: scenario setup that
  skips progression). Eight walls on 439, 409, 440, 500, 537, 617, 505 and 538 all stop 4.0–4.3 px
  from the drawn wall. The doors of 439 and 409 lead in, and all four points behind Dink's cottage
  are open. Against 8db1ff5 the same test fails. At 538 the player walks through the inn and off
  the screen. Three approaches meet the old models' capsule before the wall. Behind the cottage,
  only 1 of 4 points is open.
- Every door on the map stays reachable: the free depth inside each trigger rect is 8–31 px (the
  inn's doors are the shallowest).
- `pytest`: 80 passed (79 before, plus the wall test). `tests/fps_stuck_test.gd` now checks that the
  pig-farm landing is walkable in the original data, that no recovery search remains, and that the
  pigpen fence still holds.
- The letter campaign (`tools/playtest.py --mode campaign --milestone letter --rendered
  --max-commands 5000`, from Begin adventure to Aunt Maria's letter and the map, with real input):
  PASS in 3,201 commands. 8db1ff5 passes it in 2,955; the difference is a second pass of the duck
  search. So the opening is still completable, and the route found no stuck player.
- Every Godot run used the Dummy audio driver (headless runs imply it). Renders used llvmpipe under
  xvfb, not the GPU.

**Judgment.** Where the player stops is now where the drawn building stands, from every side, on
every screen with a building. The eye-level sheet shows the change: the old post stood in the open
air in front of the cottages and 60 px behind them, stood inside the inn, or never moved, because
the player was inside a Blender cottage. Now it stands against the wall. The stand-in buildings are
the right shape and size, doors included, but they are flat-coloured. At 0.06 m per pixel a cottage
is 8–9 m to the ridge (3.5–3.8 m at the prototype's 0.025), which is step 3's scale question.

**Defects I see, in order:**
1. The buildings are stand-ins: flat colours per face, and kit buildings in fixed colours. Step 3's
   projection-textured build (the prototype's `_add_house`, `_add_uv_house`, `_prepare_kit`) belongs
   here.
2. The chimney sprites (home-11, 12, 13) are still drawn as rubble on the ground ("ruin"), behind
   the houses. The prototype stands them on the roofs.
3. The ring rule is a rule. It leaves custom hardness that reaches more than one tile from a
   building, or runs off the screen, as fences and walls. Screen 570 keeps a bush's hardbox and
   default-mask grass tiles ~60 px in front of kit-570's corner. Anything else the tile art's own
   masks hold (grass tiles with non-empty defaults beside buildings) stays as it was.
4. Neighbour screens' buildings have no ray bodies. As before, arrows can cross them from the next
   screen.
5. Outdoor hardness with nothing visible (water edges, cliffs, invisible gates) is unchanged. It
   still needs the geometry from the mask that step 3 calls for.

**Step 2 (story state) was not started.** The fitted buildings already go through
`create_visual`/`update_visual`: a building sprite the VM hides or kills stops drawing and stops
blocking, and Dink's cottage keeps its fire and ruin states. For everything else the step means the
billboards, and they are step 3.

**Next step (recommended):** step 3 with step 2 inside it. Build the game's world from the
prototype: its textured buildings in place of the stand-ins, and its billboards made through
`create_visual`/`update_visual` so the VM's story state drives them. Settle the scale (0.025 m per
pixel), then have Chris play the opening.


## The game's buildings, and the scale — September 30, eighth pass (Opus 5.5)

Step 3 of the sixth pass's next step, its building part: the seventh pass's flat-coloured stand-ins
are gone. Evidence: `docs/images/buildings-sept30.jpg`. Each row is one camera, placed in source
pixels, filmed in the old game with its Blender cottages (8db1ff5), in the game now, and in the
prototype. The first twelve rows are the seventh pass's walls, 74 px out (where the player stopped,
plus its 70 px step back) and 300 px out. The last six show the church, the log cabin, home-10,
kit-417 across the water from the north, a house by the fountain, and kit-417's front from the
walled street south of it (450). The old game drew that street as a dark room.

**One build, not two.** `scripts/sprite_buildings.gd` is the prototype's building code, moved out of
`prototype/sprite_world_proto.gd`, not copied. It covers the projection-textured faces, the thatch
profile, chimneys on roofs and beside houses, the cabin and the church (`polys`), kit buildings with
their dormers, and backs mirrored without their doors. It also holds the gathering: which sprites a
house draws onto itself. The prototype now calls it. Through the original camera, every screen of
`tools/facade_regress.py` is unchanged (±0.0), and its 199 renders differ by at most 0.022 of 255 in
the mean (sub-pixel edges). The game calls the same functions (`fp_world.gd`):
- A fitted house (`add_fitted_building`, `house_plan`): the sprites drawn over it are gathered as
  the prototype gathers them, over a 5×5 block round the screen, from the sprites drawn at the
  current story layer. Doors, windows and damage are composited onto its walls in the original draw
  order. Chimneys stand on its roof, or beside it (home-13). Those sprites keep their entities
  (warps, scripts, story state) but no model of their own (`house_part`). A scripted part without a
  warp, such as a door someone talks to, keeps an unseen body where it is drawn.
- Kit buildings (`add_kit_buildings`) are composed from the map's own tiles and kit sprites, with
  their dormers.
- Meshes and textures are cached per building and story layer, because the game rebuilds its scene
  on every screen change. Materials are unshaded, as in the prototype, because the light is baked
  into the art. They still cast the game's real-time shadows.
- Each building's mesh has its origin at its sprite's top-left, so it stands on exactly the
  footprint `tools/collision_map.py` derives from the same faces.
- Dink's cottage keeps its story states: flames on its east roof slopes at vision 1, and the charred
  tint at vision 2. The damage sprites of both layers are now on its walls and roof, not boxes
  floating beside it.

**The chimneys are no longer rubble.** home-11 and home-12 stand on their roofs and home-13 beside
its house. The game had drawn all three as a "ruin" heap behind the houses. The model key stays
`ruin` (tests/fps_fire_world_test.gd checks it), but nothing is drawn for it.

**The scale: 0.025 m per source pixel (was 0.06).** The player is Dink. His eye (EYE_HEIGHT,
1.65 m) must stand where Dink's eyes are in his sprite. The rest of the art must then come out at the
sizes it was drawn at, in the same unit. Heights come from the sprites' drawn pixels: from the top
of the drawn pixels to the hotspot, or, on a wall, a column's extent. The black shadow dither is
left out.

| Drawn | px | at 0.025 | at 0.06 |
|---|---|---|---|
| Dink standing (walk and idle, frame 1) | 68–71 | 1.7–1.8 m | 4.1–4.3 m |
| The player's eye (1.65 m), in Dink's pixels | | 66 px: 0.94 of his height, his eyes | 27.5 px: 0.39, his hip |
| Villagers (c5, c09) | 75–88 | 1.9–2.2 m | 4.5–5.3 m |
| Rail-fence post (fence-01) | 45 | 1.1 m | 2.7 m |
| Cottage wall to the eave (home-01, fitted) | 80 | 2.0 m | 4.8 m |
| Cottage ridge (home-01) | 140 | 3.5 m | 8.4 m |
| Kit ground storey (stone) | 92 | 2.3 m | 5.5 m |
| Door leaf, in the wall plane (seq 61/62) | 53–54 | 1.35 m | 3.2 m |
| Doorway with its frame (home-02/03) | 63–64 | 1.6 m | 3.8 m |

At 0.025 the eye stands at Dink's eyes, and fences, storeys and people come out at human sizes. The
door does not. The art draws doors at 0.77 of Dink's height, and the doorway frame at 0.9. That is
the art's cartoon proportion, and it is kept. A door is not stretched to 2 m. Choosing the scale
from the door (2 m for 54 px, 0.037) would put the eye at Dink's chest (45 px). At 0.06 the player
saw the world from Dink's hip, doors stood twice his eye height, and a cottage was a two-storey
house. The prototype's 0.025 was right, and the game now uses it.

Applied consistently:
- `fp_world.SCALE` is the one constant. `fps_game.gd`, `tests/fps_test.gd` and the screen size
  (`WIDTH`, `DEPTH`) read it. The interior mask grid and the wilderness had 0.06 written into their
  numbers; they now derive from SCALE.
- Game logic stays in source pixels: movement, collision, triggers and dialogue offsets.
- The arrow keeps its 21 m/s: it is a thing seen flying at eye level. At 0.025 it crosses a screen
  in 0.7 s. The game's 2D missiles move 180 px/s.
- The Blender models that stand in for sprites are sized to the sprite: people, animals, trees,
  barrels, chests, wells, signs, gravestones and fountains (`SPRITE_SIZED`). Each is as tall as its
  sprite stands above its hotspot, the way the prototype's billboards stand. They had been sized
  for 0.06, inconsistently: at 0.025 a duck would have been 1.63 m and a chest 1.6 m, while people
  (2.07 m) and oaks (6 m) happened to fit. `crate` is left out. It stands in for anything scripted or
  unknown (rakes leaning on walls, sacks), and a cube as tall as a leaning rake is a wall. Interior
  rooms keep their 3.6 m walls and ceiling, a room's height in metres.
- Two test fixtures had the old scale written into them, and both are fixed.
  `tests/fps_test.gd` placed its targets' entities at `y = 133.33` (4 m at 0.06), so
  `update_visual` moved the bodies to 1.7 m. `tests/fps_opening_polish_test.gd` gave a speaker the
  id of one of the room's walls without removing the wall's visual, so the framing aimed at a 3.6 m
  "head". At 0.06 the wall was far enough to stay under the 0.2 rad bound, and at 0.025 it was not.

**A roof piece's shadow on unseen faces.** Seen from behind at eye level, Dink's cottage had a dark
stripe running from ridge to eave on its north slope, in the prototype and the game alike. It was
the fifth pass's `_paint_unseen`. The chimney's cast shadow was painted onto the far slope wherever
that slope's points project onto the shadow's pixels. Along the grazing view rays, a few pixels
cover the whole slope. It is now painted only where the original camera sees that face: the ray's
first hit must be the face itself. The original camera's view is unchanged by construction (439:
13.4 before and after), and the stripe is gone.

**Verification.**
- Look first: the sheet above. From the seventh pass's camera positions, and wider, the game's
  buildings are the prototype's: the same cottages, doors, chimneys, thatch, inn, church, cabin and
  home-10. They differ in the game's lighting on everything else, its Blender stand-ins, and its
  lighter fog. No flat stand-in remains on a fitted building. The four `/Building/` sprites without a
  fit (build-01, 02, 03, 10) keep the Blender cottage.
- `pytest`: 80 passed, after the rebase onto 7a778e0, and again after the second and third
  rounds. `tests/fps_wall_test.gd` is among them:
  eight walls stop 4.3 px from the drawn wall, the doors of 439 and 409 lead in, and all four
  points behind Dink's cottage are open. The first run failed 3
  tests, on the two fixtures above.
- The letter campaign (`tools/playtest.py --mode campaign --milestone letter --rendered
  --max-commands 5000`) runs from Begin adventure to Aunt Maria's letter, with real input. It
  passes in 3,122 commands, in 3,823 after the second round and in 4,106 after the third (the duck
  search varies). The
  seventh pass took 3,201 and 8db1ff5 2,955, and collision is unchanged in source pixels. It found
  no stuck player.
- Frame time, `tests/fps_perf.gd` (written by a Sonnet subagent and checked here), same camera and
  same screen in each checkout, 300 frames after 30 of warm-up, three repeats. The screen is loaded
  with its scripts off (scenario setup). llvmpipe under xvfb, so the numbers are relative only.
  The runs are interleaved: repeat, then screen, then checkout. Medians follow, with the spread of
  the three repeats. The numbers are after the third round below (houses baked). The stand-in
  column is from the second round's run.

  | Screen, camera | Old game (8db1ff5) | Stand-ins (seventh pass) | Now |
  |---|---|---|---|
  | 439, the cottage: frame | 29.3 ms (29.3–29.4) | 27.0 | 27.7 (27.6–27.8) |
  | 440, the village: frame | 36.0 ms (35.9–36.0) | 33.5 | 32.5 (32.5–32.6) |
  | 505, the inn: frame | 43.8 ms (43.7–43.8) | 17.2 | 15.3 (15.3–15.4) |
  | 439: `load_map` | 29 ms (29–29) | 54 | 42 (41–42) |
  | 440: `load_map` | 42 ms (41–43) | 72 | 55 (54–57) |
  | 505: `load_map` | 47 ms (46–49) | 47 | 66 (64–66) |

  Frame time: the textured buildings cost what the stand-ins did (439 +0.7 ms, 440 and 505 less),
  and less than the Blender models everywhere. Loading is 13–19 ms over the old game's.
- Every Godot run used the Dummy audio driver. Headless runs imply it.

**Judgment.** In the game, at eye level, the buildings are the prototype's buildings. Dink's cottage
is stone and thatch, with its door where it was drawn and its chimney on the ridge. From behind it
is whole. The inn is one Tudor building, and the church, the cabin and home-10 are what the
prototype made of them. They are clearly better than the Blender cottages. Those were yellow boxes
on stretched hardboxes, and from behind the player stood inside them. At 0.025 the doors come to
Dink's shoulder, as drawn. The cottages are cottages: the eaves just above the eye, the ridge twice
the eye's height.

**Second round (the orchestrator's review of the sheet).**

*The kit-canvas stall.* The first build of a kit building composed its canvases in per-pixel
GDScript: the inn cost 3.7 s, profiled alone. The first round's game run measured 1.6 s for 505
because the new game had already built the inn. `_new_game` passes screens round 440, and its
`load_map` built kit-537 there, outside the timed load. The 1.6 s was kit-570, which 505's own
load built. Measured in the game, that explains the profile-vs-game gap.

The canvases depend only on the map and `facades.json`, so they are baked:
`tools/bake_kit_canvases.gd` runs `sprite_buildings.gd kit_canvases`, the same code, for all seven
kit buildings. It writes `game/data/kits/<name>-front.bin` and `-back.bin` (lossless WebP, 3.5 MB)
and a manifest holding `facades.json`'s SHA-256. Every image reads back byte-identical, or no
manifest is written. The game and the prototype load them, then fall back to composing when the
hash is stale. The export includes `data/kits/*`. The inn now loads in 17 ms. The prototype's kit
views are unchanged (worst eye-level mean |d| 0.02 of 255).

The houses then showed what was left. A house cost 170–190 ms, and a house with roof chimneys
0.8–1.5 s. Almost all of the chimney cost was the unseen-face painting, which ran the view ray
for every texel of every north-facing face. Two changes cut it:
- The texel scan is limited to the columns whose points land inside the chimney's sprite. The
  same texels pass.
- The face the original camera sees is read once per sprite pixel, through its centre.

Together they take the chimney painting from 1,264 to 191 ms (home-06) and from 606 to 83 ms
(home-01). The houses' hole fills run on the worker threads, taking a house's remaining build from
185 to about 110 ms. The original camera is ±0.0 on every screen of the regression. Eye level
changes only where the unseen-face painting did: the house on 501 loses the thatch-coloured smears
its chimneys had painted onto its back wall and roof (mean |d| 2.0 there), and the cottage its
stripe.

With those changes, 505 loaded in 141 ms (from 1.6 s; the old game took 48) and 440 in 277 ms (the
old game took 41). 440 still composed its houses' textures on arrival, about 110 ms each.

*Third round: the houses baked.* `tools/bake_houses.gd` bakes them the way the kits are baked.
- The game's own plan (`fp_world.house_plan`) runs with every outdoor screen as the current one,
  at every story layer its sprites use. Each house it gathers is keyed by the key the game already
  uses: the house plus the parts it draws (`bake_key`: the house's world key and the SHA-1 of its
  parts' signature).
- The tool stores `sprite_buildings.gd house_images` for each key: the filled body images, then
  one per roof piece and one per ground piece. That is the costly part, now split from the cheap
  mesh build.
- 31 houses, 2.4 MB, all read back byte-identical, with facades.json's SHA-256 in the manifest.
  The export includes `data/houses/*`. A stale bake, or a house drawn with other parts (a sprite
  the story removed), composes as before.
- The prototype composes as before. Its regression is unchanged: ±0.0 through the original
  camera, and at eye level identical to the second round.
- 440 now loads in 55 ms against the old game's 42, 505 in 66 against 47, and 439 in 42 against
  29. What remains is building meshes, textures and mipmaps from the loaded images, plus the
  scene's other entities.
- Generated assets in the repo: 3.5 MB of kit canvases and 2.4 MB of houses.

*kit-417 missing: `is_inside`.* The game took a screen with three or more `innwalls`/`stnwalls`
sprites for an interior. The original's own flag is the per-screen indoor flag of dink.dat
(world.json `indoor`, 74 screens). The engine uses it to keep the last outdoor screen for the map,
and every screen with interior wall sprites (`innwalls`) carries it. The count added 18 screens
that are flagged outdoor: kit-417's courtyard (385–388, 417, 420), the walled streets south of it
(449–452), 238, 244, 536, 625, 680–681 and 712–713. Every neighbour of each is an outdoor screen,
and their "walls" are the stonw and snak stone-wall pieces. `is_inside` is now the flag.
`tests/fps_test.gd` checks the result: exactly the flagged screens are interiors, Dink's house (1,
2) among them, and 386, 417 and 450 are outdoors. The sheet's last row shows the street before
(a dark room) and after (kit-417's front, as in the prototype). The interior tests (Dink's house:
Mother's visibility, the grief cameras, the hearth) pass.

**Defects I see, in order:**
1. Loads are 13–19 ms over the old game's (440: 55 against 42). Mesh, texture and mipmap
   creation for the baked images is the next cost, if it matters.
2. Everything that is not a building is still a Blender stand-in: fences are dark slabs, tools are
   crates, flames are cones, bushes are blobs. The walled streets' stone walls, now outdoors, are
   flat plaster boxes (the `wall` model), seen across the water on the sheet. This is step 3's
   other half: billboards made through `create_visual`/`update_visual`.
3. The game builds the screen and its eight neighbours. At 0.025 that is 45 × 30 m, and a
   building two screens away (kit-417 from 481) is not drawn, although the prototype's 5×5 draws
   it.
4. The drawn dither shadow of each building is not painted into the game's ground. The game's
   ground is tiles only, and background sprites are entities. The real-time shadow stands in for
   it.
5. Parts composited onto a house are fixed for the scene. A door the VM moves or animates stays as
   drawn until the screen reloads. Composited parts of a neighbour screen use the current screen's
   story layer, as every neighbour sprite already does.
6. The story fire's flame entities (fire1-0x) stand at their hotspots, not on the roof they are
   drawn on. `add_story_fire` puts its own flames on the roof.
7. The prototype's open building defects carry over: home-10's core roof sits a few px low (318),
   and the footprints are still rhombic.

## The props are their sprites, and the 5×5 block — September 30, ninth pass (Opus 5.5)

The eighth pass's defects 2 and 3. Evidence: `docs/images/props-sept30.jpg`. Each row is one camera,
in the game before this pass (fb244ac), in the game now, and in the prototype. The first nineteen rows
are the eighth pass's cameras. Then come the walled street south of kit-417, three of the prototype's
own pigpen and village shots (407, 439), and four new views of props that had stand-ins: tools leaning
on a house (440), boxes and a bush (499), the save machine (408), and the castle with two knights (402).
`docs/images/story-fire-sept30.jpg` shows Dink's cottage burning (vision 1), before and now.

**Everything that is not a building is its sprite.** `fp_world.make_entity` draws it as the
prototype's `_add_sprite` does (`add_billboard`):
- At its hotspot, 0.025 m per pixel times its `size`, unshaded, with the art's own light.
- The shadow dither is removed from the upright sprite (`clean_texture`, the prototype's `clean()`).
- Props, trees and actors are Y-axis billboards. Fences, outdoor stone walls, castle walls (`tower`)
  and any sprite over 100 px wide keep the orientation they were drawn in, facing the original viewer.
- A fence post column drawn along the depth axis is the side-view rail (seq 93 frame 1) turned 90°.
- Every frame, `update_visual` shows the frame the 2D game would show: the entity's animation, else its
  still frame. A directional actor (walk, idle or attack, directions 1–9) shows the frame drawn for its
  facing as seen from the camera (`update_billboard`, the prototype's `_face_actors`). So pigs, ducks,
  villagers, knights and the fire animate in their own frames. The Blender limbs and bobbing are gone
  for them.
- The ray body (aim, projectiles, dialogue cameras) is the sprite's width and drawn height; fences and
  walls keep theirs on the source hardbox. Movement is unchanged: it reads the source data only
  (`game.gd _blocked`).
- These keep their 3D build (`BUILT`): fitted and unfitted houses, bridges, doors, stairs, interior
  furniture, interior walls, and the arrow.

**Background sprites are painted into the ground** (`paint_background`), as the original engine and
the prototype do. That covers type 0 sprites that are not structures: rocks, grass, the walled street's
paving, the ground details. One with an upright twin at the same spot is left to the twin. A sprite the
story left as background (`editor_type` 3 or 5, a kill left lying) is painted too, as `load_map` types
it. The ground texture is cached by the list of sprites painted into it, so a story change to them
recomposes it on the next load. Sprites a kit building draws (`kit_member`, its
`members` in facades.json) get no model of their own, as in the prototype. The walled streets' plaster
boxes were these. A scripted piece without a warp (the talking door of 497, 505's s4-md3) keeps the
unseen body a house part keeps, so it can still be talked to and hit.

**The burning cottage** (vision 1): `add_story_fire`'s flames on the roof are the original fire
(seq 427, fire1), playing its ten frames (`story_flame`), not orange cones. The fire's hotspot lies
21 px below its drawn flames, where the raised view puts the ground under the roof. Anchored there,
the first build floated the flames above the roof (seen in the playtest's alktree-fire shot). On a
roof spot, the frame's bottom centre is now the anchor.

**The 5×5 block.** `build_ground` now builds the screen and its 24 neighbours, as the prototype does and
as `house_plan` already gathered. At 0.025 m/px a 3×3 block ended the world one screen (15 m) from the
screen's edge. The sheet shows the gain on 439 (village-east) and 472, where houses two screens away
now stand where the prototype has them. Neighbours still show no actors.

**Tests.** `tests/fps_test.gd` and `tests/fps_world_test.gd` asserted "no Sprite3D": the rule this file
supersedes. They now assert that sprites are drawn only as fp_world's depth-tested billboards, each the
`Model` of an entity (the 2D renderer's sprites must not leak in). fps_test also asserts that the
opening screens draw sprites, and that no sprite-drawn key keeps a stand-in model.
`tests/fps_capture.gd` takes `--vision=N` (scenario setup, for the fire sheet).
`tools/building_sheet.py` takes `--old-label`, `--only-inline` and `--props`, and has the new views.

**Verification.**
- Looked at first: every row of the sheet. The fences, pigs, trees, bushes, barrels, boxes, the rake on
  Ethel's wall, the save machine, the castle, the knights and the stone walls are the prototype's, from
  the same cameras. No stand-in remains on the sheet except the arrow, bridges and the four unfitted
  `/Building/` cottages, none of which are in view.
- `pytest`: 81 passed, 1 skipped, with every change in (`.venv/bin/python -m pytest -q tests`, run
  with the input devices hidden).
- No timings. The GPUs were shared tonight, and every render was llvmpipe under xvfb. The cost of
  `clean_texture` on a sprite's first use, and of the 16 extra neighbour screens, is not measured.
- Every Godot run used the Dummy audio driver.
- The letter campaign (`tools/playtest.py --mode campaign --milestone letter --rendered
  --max-commands 5000`) runs from Begin adventure to Aunt Maria's letter, with real input. It passes
  in 3,686 commands, and in 3,045 after the background and roof-flame fixes. fb244ac, run alongside
  the first under the same conditions, passes in 3,666. That last run came before the scripted kit
  pieces got their bodies (above); after that change, pytest and the wall, world and reload tests
  pass again. It found no stuck player.
- `tools/playtest.py --rendered` opens its Godot window on the session's own display: it has no Xvfb
  of its own. Run it under `xvfb-run`, and with the machine's input devices hidden (`bwrap --dev-bind
  / / --tmpfs /dev/input --tmpfs /tmp --unshare-net xvfb-run -a ...`). The first three runs tonight
  went to the desktop. Each stopped at a pause menu that opened in the middle of a walk or a wait,
  at a different place each time: input from the desktop reached the game window. They were
  harness faults ("inconclusive"), not game failures, and are not counted.

**Judgment.** At eye level the props are now Dink's own: the rail fences with their yellow ties, the
pigs, the trees, the bushes, the barrels, the rake on Ethel's wall, the boxes and the save machine. The
stone walls of the walled streets and the castle are the drawn stones, not plaster boxes. From the same
cameras, the game and the prototype now differ mainly in the lighting, the fog, the procedural grass
blades and the viewmodel. The Blender stand-ins read as a different game. These read as Dink.

**Defects I see, in order:**
1. The procedural grass blades (`add_grass`) still cover the original tile art on every outdoor
   screen. The original and the prototype have none. The structural change says "the original tile
   art everywhere". This is the largest remaining difference on the sheet.
2. Neighbour screens draw no actors. 407's pigs are missing from 439's view of the pen
   (pen-from-south), as before.
3. The story fire's source flames (fire1, eighth pass defect 6) stand at their hotspots. They are now
   tall animated fire sprites on the ground in front of the cottage, more visible than the cones were.
4. Structures drawn as one wide fixed card read as cardboard up close: the well by the save machine
   (408), and the castle walls seen obliquely. The prototype does the same. They need the houses'
   treatment, fitted to stand in 3D.
5. The prototype moves or depth-pushes billboards whose canopy overlaps a building (`_flag_nudge`,
   `_push_back`). That is not ported, though no case shows on the sheet. (Ported October 1: see the
   last section.)
6. Billboards cast no shadow and have no blob shadow under them (the prototype's open item 3). Fixed
   cards do cast one.
7. At 74 px, the game draws a door on walls where the prototype draws none: 439's back, 409's front,
   440's back. It did so before this pass too, and it was not investigated.
8. Bridges and the four unfitted `/Building/` cottages keep their Blender models. Interiors keep their
   box walls and Blender furniture.
9. Not measured: the load cost of `clean_texture` on a sprite's first use, and of the 16 extra
   neighbour screens.

**Next step:** measure `load_map` and frame time for 439, 440 and 505 with `tests/fps_perf.gd`, on a
quiet machine, before and after this pass. If the 5×5 block costs too much, bake the cleaned sprite
textures as the kits are baked. Then remove the procedural grass blades (defect 1), and port
`_flag_nudge`/`_push_back` (defect 5).

**Addendum, the same evening: the grass blades are gone** (defect 1 above). `add_grass` scattered 300
dark green blade meshes per outdoor screen over the tile art. Neither the original nor the prototype
has them. The function, its call in `add_ground` and the dead `"grass"` stand-in case in
`primitive_model` are removed. Nothing else read them: no setting, density table or test. The tests'
geometry count still counts MultiMeshInstance3D, which is harmless. The original grass is the map's
own: its tiles, and its grass sprites (`/grass/`, `lands/details`), which the pass above already draws
as billboards or paints into the ground. Evidence: `docs/images/grass-sept30.jpg`. It shows the twelve
rows of the sheet above where grass shows: the eighth pass's 300 px views and the extra building views,
407's pen, 439's pen and village, and 472. Each row has three columns: 9784925 with the blades, the
game now, and the prototype. The ground is now the tile art, as in the prototype. What still differs is
the game's real-time light and shadow, its sky and fog, and the viewmodel. `pytest`: 81 passed,
1 skipped; fps_test and fps_world_test (644 screens) pass. Rendered under
`bwrap --dev-bind / / --tmpfs /dev/input --tmpfs /tmp --unshare-net`, with xvfb-run for each capture.

**Addendum: the story fire stands on the roof** (defect 3 above; the eighth pass's defect 6). The map's
own fire sprites (fire1-0x and the small fire2-4 pieces on 439 at vision 1) were drawn over the cottage.
Their que (1000, 950) sets the original's draw order after the house. Their hotspots lie 21 px below
the drawn flames, on the ground, so in 3D they stood in front of the house as tall flames.
`place_on_surface` now places any sprite that is drawn after a fitted house and whose foot (the centre
of its lowest drawn row) projects onto it. The rule is the chimneys' (`sprite_buildings.gd claim` and
`ray_hit`): the original camera's view ray through the foot meets the house where the sprite stands.
The sprite is anchored there by its foot. It is one rule, with nothing tuned per screen. A sprite in
front of the walls projects below their base, so the ray misses and it keeps its hotspot. With the
source flames on the roof, `add_story_fire`'s own roof flames on a fitted house were a second set, and
an invented one. They are removed: the map's set is kept. The state meta and the fallback flames for an
unfitted house are kept. Evidence: `docs/images/story-fire-roof-sept30.jpg`, 8878d0e beside the game
now, at vision 1, from three cameras. The flames now burn along the thatch, as the original draws them,
and none stands on the ground. `pytest`: 81 passed, 1 skipped. fps_fire_world_test,
fps_grief_presentation_test, fps_test and fps_world_test pass.

## Trees against buildings, in the game — October 1 (Sonnet 5.5 subagent)

The ninth pass's defect 5: the prototype's `_flag_nudge` and `_push_back`, ported to the game
(`fp_world.gd` `depth_rule`, `settle_depth`, `DEPTH_SHADER`). Branch `claude/trees-under-buildings` on dfe0788;
local, not pushed. Evidence: `docs/images/trees-buildings-oct1.jpg` (built by `tools/trees_sheet.py`).

**What was predicted before any change** (and held or not): pytest 81 passed, 1 skipped plus the new tests (held:
83 passed, 1 skipped); the push-at-0 picture equals the plain sprites' (held, below); screens with no flagged
sprite are unchanged to the pixel at every camera (held: 407, 408, 470, 505, 586 from the original camera, 0 px);
trunks and bodies stay where the source puts them (held by construction: only the shader's depth moves); the
frame time does not change (not distinguishable, below). Not predicted, found by looking: the rule needed a
camera side, a below-ground rule and a shadow twin (below).

**The rule.** A sprite (not an actor, not a fence or structure) whose hotspot lies within its half-width of a
fitted house's wall footprint (the convex hull of the wall faces' feet, `sprite_buildings.gd hull_of`) takes a
depth shift of that half-width in its own shader. Over the house (the original draws it after: its que, else its
y, above the house's hotspot): pulled toward the camera, so the walls cannot cut it. Under: pushed away, so the
house hides its canopy; each fragment's push capped at 0.9 of its clearance above the ground along the view ray,
a pull at 0.9 of its distance from the camera. The map has 34 such sprites on 15 screens (28 over, 6 under):
trees on 251 (tree-08), 496/497 and 498/530 (tree-04, under) and 528 (tree-04, over), and barrels, boxes, tools,
grass and a bush against houses on 274, 409, 439, 440, 501, 532, 537, 617, 734. Kit buildings (the inn) have
no footprint in the list, as in the prototype.

**Two changes from the prototype's mechanism, and why.**
1. The nudge is the same depth shift with the sign reversed, not a move and a rescale. Moved along the view
   ray and scaled to keep its size, a flat card gives the same picture and a different depth; here the depth is
   written directly. Nothing moves, so there is no per-frame, camera-dependent update (`update_visual` rewrites
   node positions every frame), the trunk and the ray body stay put, and a player standing next to the tree
   (within its half-width of the camera) cannot flip its scale.
2. The side depends on the camera. The ninth pass's note held that the prototype's rule is the original's draw
   order. That order is the y of a camera that looks north; the game's camera looks every way. The first port
   (the prototype's sign, whatever the camera) pulled the two conifers that stand south of the 251 cabin onto its
   back wall when seen from the north (the sheet's third row is the same camera now). Now the side is the
   original's from the side of the nearest wall's plane the original camera is on, and reversed from the other
   side, where the house stands between the camera and the tree. From the original camera this is the
   prototype's rule exactly (the plane test is multiplied by the original camera's own side). Tried and dropped:
   comparing the trunk's depth with the house's hotspot along the view. The hotspot lies on the front wall, so
   a tree beside that wall changes side with the lateral offset (251 from the north-west). A sprite inside the
   footprint, or ordered by a que, keeps the original's order from every camera. The planes' flip is a hard
   switch, as the draw order is; walking round a house a tree changes side where the camera crosses the wall's
   plane. I did not smooth it: a blend over the half-width would also soften the original camera's own result.

**Two things the sprite needs so that only the buildings' order moves.**
- A fragment below the ground (the rows an art draws under its hotspot) is not shifted: pulled, those rows came
  into view over the grass (190 px at the foot of one tree on 497).
- A card that casts a shadow (the fixed, wide ones) casts it from a plain shadow-only twin child, because the
  shadow pass runs the same shader and a shifted depth moved the shadow on the ground (8,000 px at 251).
  `tests/fps_test.gd` and `fps_world_test.gd` accept the `ShadowTwin` child.

**Verification.**
- `pytest`: 83 passed, 1 skipped (the baseline in a scratch worktree at dfe0788: 81 passed, 1 skipped; the two new
  tests are `tests/test_fps_trees.py`). Run with the input devices hidden, under xvfb, no Wayland.
- Classification: the game's flags (a loaded scene, headless) equal an independent reading of the map data
  written in the test from the prototype's rule: the same 34 sprites, the same signs and half-widths, and nothing
  flagged on the quiet screens 407, 408, 470, 505, 586.
- Control (`tests/fps_trees_test.gd`): with every reach at 0 the shader's picture equals the plain sprites'. Over
  the eight cameras: exactly 0 on four of them; at most 2 px over 3/255 on the others, mean |d| at most 0.0004
  (an edge texel, the shader's own billboard matrix against Godot's). The prototype's figure was 0.000.
- The control cannot only pass. The draw-order check (R equals the houses-hidden picture on the sprite's pixels
  when over; the house hides the canopy where it shows, the rest whole, when under) is run on wrong rules too,
  and they go red: sides swapped, 25,402 / 17,984 px (251 over), 4,767 (528), 3,346 / 2,462 (497 under); the
  original's side held from every camera, 3,853 / 7,095 (251 from behind), 4,407 (497 from behind); the push without
  its ground cap, 644 / 245 px (497); and, by mutating `fp_world.gd` and running the tests, the side flipped
  (classification test red), no cap, no shadow twin, camera-blind and no below-ground rule (each red; the
  no-below-ground-rule mutation stayed green until I added the "sprite alone" check, which found the first
  version of the test blind to it). The noise of the instrument is 0 px between two renders of one scene; the viewmodel sways, so the test
  hides it.
- From the original camera (`tests/fps_capture.gd --batch`, orthographic, 45 degrees, fog off), mean |RGB|
  difference from the source reconstruction (`tools/facade_contact_sheet.py reference`), before and now:
  251 22.49 to 22.16 (-0.335, 3,777 px changed), 440 -0.046, 734 -0.022, 530 -0.001, 528 and 497 0.000 (0 px). The
  five screens where nothing is flagged (407, 408, 470, 505, 586) are 0 px changed. The number is blind to eye level.
- Frame time (approximate: xvfb, llvmpipe, the machine shared; relative only): `tests/fps_perf.gd`, six
  interleaved pairs on 251 (153, 520) and on 439 (505, 340), 300 frames each. Median of the runs' p50: 251 15.27
  ms before, 15.23 now; 439 15.28 before, 15.65 now. The probe's frame pacing sits at about 15 ms and the p95 spikes
  (to 28 ms) hit both builds at random, so a cost under a millisecond could not show: read it as "no cost the probe
  can see". `load_map` on 439, eight interleaved runs: median 98.4 ms before, 98.3 ms now (the first port, without
  the bounding-box reject, read +7 ms).
- Every Godot run was `--audio-driver Dummy`, under `xvfb-run` with `WAYLAND_DISPLAY` unset: nothing on the
  desktop and nothing to the speakers.

**What I saw** (the sheet: each row eye level before, now, the original camera now, the source). 251 from the
south-west and from the south: before, the tree-08 card (three conifers) is cut into slivers by the cabin's
walls; now the conifers stand whole in front of the wall, as in the source picture, and from the original camera
the cabin has its tree. 251 from behind the cabin: unchanged (0 px): the cabin hides them. 528 and 497: no
visible change (0 and 2 px): there the plain card did not pass through the walls from these cameras. 530 (a tree
under home-01, from the north-east): the canopy now goes behind the house's corner. 440 and 734: the barrels,
the tool and the stack of boxes stand whole against the walls instead of sunk into them.

**Defects I see, in order:**
1. Actors are left to the walls' hardness (their frames change with the camera and they move). A villager or
   pig standing against a wall can still be cut by it.
2. The side flips as the camera crosses a wall's plane: a tree can change sides in one frame where the plane
   passes through the view of both it and the house. Not seen as a defect on the sheet, not walked.
3. Wide cards are fixed cards: seen edge-on they are slivers, with or without the rule (the 251 trees from the
   east). Unchanged.
4. A shifted sprite also sorts against other sprites within its half-width of it. No visible case found.
5. The kit buildings (the inn) have no footprint in the list, as in the prototype.
6. The probe could not see a frame cost; a machine free of other work should measure it.

**Re-run:** `../../../.venv/bin/python -m pytest -q tests/test_fps_trees.py` (from the worktree root, inside
`env -u WAYLAND_DISPLAY bwrap --dev-bind / / --tmpfs /dev/input --unshare-net xvfb-run -a -s "-screen 0 1920x1080x24"`);
the control alone: `xvfb-run -a $GODOT --audio-driver Dummy --path game --script ../tests/fps_trees_test.gd -- --render`
(prints each camera's push-at-0 line and the wrong controls' counts); the sheet:
`/usr/bin/python3 tools/trees_sheet.py <checkout at dfe0788>`.


## Trees from every side, the neighbours' people, and no doors on the backs — October 1, tenth pass, first half (Opus 5.5 lead, Sonnet 5.5 units)

The open defects, taken in the order a player sees them. Evidence: `docs/images/tenth-pass-m1.jpg`, each row one
camera, the game before this pass (aa7388e) and now. The units' own sheets are `docs/images/doors-oct1.jpg` (with
the prototype and the original's picture), `docs/images/neighbours-oct1.jpg` and `docs/images/billboards-oct1.jpg`.
`tools/view_sheet.py` renders any views file in several checkouts, one column each; `tests/fps_capture.gd --batch`
now redraws every sprite for each view, as the game does every frame (an actor showed the frame chosen for the
load-time camera in every view before).

**Trees stood edge-on from the side** (the October 1 section's defect 3, and the ninth pass's 4). A card kept the
orientation it was drawn in if its art was over 100 px wide. The ninth pass meant that for structures, but an art's
width includes its shadow dither: tree-01 is 128 px, tree-02 204, tree-03 169, tree-04 249. So nearly every tree
outdoors (about 650), the bushes, the brambles, the well, the save machine, and the knights and dragons over 100 px
were fixed cards facing south, and looking east or west the forest was a field of slivers. Two measures from the art
were tried first and failed: the hardbox's aspect (tree-01's is 94 × 36, a bush's 122 × 37, a fence's 175 × 23) and
the straightness of the drawn bottom edge (tree-01's cone is as straight as a stone wall's: 0.047 of its height
against 0.005-0.048 for the walls). What a sprite depicts is in the original's own data: its folder and file. So a card
keeps its drawn plane only if it is a structure (`fp_world.is_structure`): a fence, a wall, a castle wall, a sign (a
board: thin edge-on is right) or one of the island's round huts. The island's art is classified by its file in
`model_key` (isle-01..06 huts, 07..12 rail fences, 13..18 spears), as the landmark and garden art already were by
frame. Everything else is a Y-axis billboard whatever its width, as the ninth pass intended. Looking north, a
Y-billboard faces +Z exactly as the card did, so the sprites' own pixels are unchanged there and through the original
camera. A billboard has no plane of its own to cast a shadow with, and before this every tree cast one as a card: each
billboard now casts its silhouette from a shadow-only twin turned to face the sun (the existing `ShadowTwin`; a shifted
fixed card's twin stays a plain +Z card). The props and actors that cast none before now do: the prototype's open item 3.
`tests/fps_cards_test.gd`: every card of every outdoor screen is fixed exactly when an independent reading of its art's
path says it is a structure. The old rule gets 996 of 2,909 cards wrong, and the plausible fix "measure the width
without the dither" 702. A tree-04 is 243 px wide from the east, west and north as from the south (0 px from the side
before), and still casts a shadow.

**The neighbour screens drew no people or animals** (the ninth pass's defect 2). The 5×5 block drew a neighbour's
scenery and skipped its actors, so beyond the screen you stood on the world was empty: from Dink's yard the pen on 407
had no pigs. A neighbour now shows what its own screen loads on arrival, before its scripts run. The body of
`load_map`'s editor-sprite loop is one function, `game.gd editor_entity` (the story's editor state, persistence 2-8
with its return time, the vision filter, the still frame), which `load_map` and the neighbour build both call. So
neighbours now also honour persistence as arrival does. Their actors stand where the editor put them, in their editor
frame, with no body, and `fp_world.face_neighbours()` turns each to the frame drawn for its facing as seen from the
camera every frame, as the current screen's actors are turned. Their brains run only on their own screen, as in the
original. The vision is the current screen's, as for all neighbour sprites (a known limit: the original sets it per
screen from the screen's script). `tests/fps_neighbours_test.gd`: which actors (against an independent reading of
world.json), which frame from four sides, and each pig in the picture (render noise 0). It was red on the unmodified
code, with `face_neighbours` a no-op, with the vision filter dropped (406 showed 14 ducks, not 8) and with the per-frame
call removed. Every non-actor neighbour node is byte-identical before and after.

**The door on the backs of houses** (the ninth pass's defect 7: at 74 px the game drew a door on 439's back, 440's
back and 409's front, where the prototype draws none). It was in the house bake. Under the headless (dummy) renderer
a texture's `get_image()` returns the texture's own stored Image, and `house_images` painted the doors and windows into
it. Every later composition of the same sprite started from a canvas that already held them: its door-less back
mirrored a door, and the second house drawn with home-06 on 409 (the map places it twice, 1 px apart) took the first
one's doors and the cuts in its thatch. `tools/bake_houses.gd` runs headless, so the bake carried them. The game under
GL composes correctly (with the bake moved aside it drew no door, as the prototype). `sprite_buildings.gd image()` now
returns a private copy, and the houses are re-baked: 45 of 75 images change, the same 31 houses; the kit canvases re-bake
byte-identical. `tests/fps_bake_test.gd` composes every house twice in one headless run and checks both against the
bake: on aa7388e 17 houses came out different the second time and 9 differed from the bake; now 0 and 0. Through the
original camera the game is nearer the original's picture: mean |RGB| on 409 21.77 to 21.42, 439 22.56 to 22.50, 440
unchanged.

<!-- C: actors against walls, filled at merge -->

**Verification.**
- Looked at first: every row of the three unit sheets and the combined one. From the side the trees, the well and the
  save machine stand whole; looking north the sprites are the same pictures; fences and castle walls are unchanged;
  the pigs stand in 407's pen seen from 439 and 408, and 374's ducks from 406; the backs are plain stone, as in the
  prototype; 409 through the original camera matches the original's picture.
- `pytest`, with the units merged: 91 passed, 1 skipped (aa7388e: 83 passed, 1 skipped).
- Frame time and loading (approximate: llvmpipe under xvfb, the machine shared with the units' renders; relative only):
  `tests/fps_perf.gd`, four interleaved pairs, aa7388e against the merge, 300 frames. Median of p50: 439 (505, 340)
  16.0 ms before, 17.6 now; 376 (120, 250) 17.1 before, 17.6 now. The spreads are 3-8 ms, so a cost under about 1.5 ms
  cannot be told from the noise. `load_map` median 439 94.8 ms before, 114 now (one run of 187), 376 104 and 104. The
  scene on 439 has 1,089 nodes, from 830 (the neighbours' actors and the shadow twins). Unit A measured the neighbours'
  actors at about 5 ms of load; `editor_entity`'s deep copy is 3.2 ms of it, and a shallow copy for neighbours would save
  about 2.
- Every Godot run: xvfb with WAYLAND_DISPLAY unset and the input devices hidden (bwrap), or headless; the Dummy audio
  driver.
