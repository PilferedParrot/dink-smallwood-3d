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
