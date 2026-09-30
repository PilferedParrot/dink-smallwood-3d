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
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 \
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
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 \
  --path game -s res://prototype/sprite_world_proto.gd -- "$PWD/builds/facades-sept29-407" 407
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 \
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
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 \
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
xvfb-run -a -s "-screen 0 1920x1080x24" ~/.local/bin/Godot_v4.6.1-stable_linux.x86_64 \
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
