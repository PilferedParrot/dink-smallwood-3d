# Dink Smallwood 3D 0.3.3 (work in progress)

This release carries the story further and makes the game easier to read and to
control. It is still a work in progress.

## What changed

- **The story route now reaches Terris.** The whole route from a new game, played
  with the real controls and the original scripts, gets as far as Terris.
- **Talk picks its target as the original does.** Pressing Talk addresses the
  person the original game would pick, by the same box rule, instead of whoever a
  ray happens to hit. Characters who have nothing to say to you stay silent, as in
  the original.
- **Text up to 200%, and a plain font.** The text size now goes to 200%, and an
  optional plain font is available for reading. Every menu, plaque and speech card
  was checked at 100%, 150% and 200% in both fonts.
- **Speech and menus show whole lines.** A line of speech, a heading or a button is
  never cut through at the top or bottom of its box. Long text scrolls a whole line
  at a time, and every line can be reached. The aiming point steps aside only while
  speech or help is actually drawn over it.
- **Sprint can be a toggle, and attacking can repeat while held.** Both are
  options in Controls; the defaults keep the old behaviour. The hints name the keys
  you have set.
- **The well is solid.** The well in the village is built from its own drawing: a
  wooden frame, a roof, a rim and a dark shaft, and you can no longer walk through it.
- **Ceilings.** Interior ceilings and the beams that support them are built from
  the original room art.
- **Flat ground details stay flat.** Things the original painted onto the ground
  (fissures, loose bones, shells, pebbles) lie on the floor instead of standing up
  as upright cut-outs.
- **Beds have sides.** A bed is built from its drawing as a frame, bedding and four
  posts, so it has sides and corners that match what you see.
- **Terrain walls match where you can walk.** Walls in caves and similar rooms are
  built from the same hard-ground map the game uses for movement, so a wall you see
  is a wall you bump into, and open floor is open.
- **Script fixes.** A script that runs from a different character now keeps its own
  variables, scripts of a screen you leave are cancelled as the original does, and
  items and spells run in the right owner's script after a screen rebuilds.

## Known issues

- Some caves that have no hand-built version look unbuilt: the walls are flat brown
  columns, and grey void shows at open edges.
- There are some invisible walls where hard ground is read as water or grass.
- Background art that shows standing objects lies flat.
- A cloth wedge shows at the foot end of the bed.
- 22 furniture pieces have collision that doesn't match their drawing (offsets up to
  55 pixels).
- Two places have surfaces at the same depth that can flicker: a bed post in one
  house and a chapel wall.
- The all-screens test needs a longer time limit than it has.

If something is wrong where you are standing, press F9 and send the report.
