# Dink Smallwood 3D 0.3.3 (work in progress)

This release carries the story much further and makes the game easier to read and to
control. It is still a work in progress.

## What changed

- **The story goes on to Terris.** Played with the real controls and the original
  scripts, the game now gets from the start past the cave and Bonca, over the toll
  bridge and into Terris. In 0.3.2 it stopped before the cave, because pushing the
  rock that opens it did nothing.
- **Pushing works as in the original.** Rocks and other pushable things move when
  you push them.
- **Indoor rooms connect.** Walking off the edge of a cave or indoor room takes you
  into the next one, as in the original.
- **Speech no longer freezes you.** Characters talk while you keep moving, as in the
  original, unless a scene stops you on purpose. Timed speech stays up long enough
  to read, and the new option "Speech waits for me" keeps each line until you
  dismiss it.
- **Talk picks the same target as the original.** Pressing Talk addresses whoever
  the original game would, by the original's rule, so furniture or a scroll lying on
  a table can no longer get in the way.
- **Your own keys.** Every action can be remapped to keys, mouse buttons or a
  controller on the new Controls page, and the hints name the keys you chose.
- **Text up to 200%, and a plain font.** The text size goes to 200%, and an optional
  plain font is easier to read. Every menu, plaque and speech box was checked at
  100%, 150% and 200% in both fonts.
- **Whole lines.** When text stops, no line of speech, heading or button is cut
  through at the edge of its box, and every line can be scrolled to. The aiming
  mark is hidden only while speech or help is drawn over it.
- **Sprint can be a toggle, and attack can repeat while held.** Both are options;
  the defaults keep the old behaviour. (The original attacks only on a fresh press.)
- **Furniture collision matches the furniture.** Shelves, tables and the like block
  you where they are drawn; the wizard's bookshelf no longer stands in front of him.
- **The well is a real well.** It is built from its own drawing (posts, a pitched
  thatch roof, a stone rim and an open shaft) instead of a flat picture that turns to
  face you.
- **Beds have sides, and houses have end walls and ceilings.** Beds, cottage end
  walls and chimney bases, and interior ceilings are built from the original art.
  Caves and stone rooms get rock or stone overhead instead of wooden beams.
- **Ground details lie flat.** Cracks and holes, grave marks, shells and pebbles that
  the original paints on the ground lie on the floor instead of standing up.
- **Walls you see are walls.** In caves and similar rooms, no visible wall covers
  ground you can walk on any more.
- **Script fixes.** When a script redraws the screen, the screen's other scripts stop
  as in the original, while items, spells and their timers keep running.

## Known issues

- Some caves that have no hand-built version look unbuilt: their walls are flat
  brown columns, and grey void shows at open edges.
- Some ground blocks you with no visible wall, mostly where the map reads it as
  water or grass.
- Background art that shows standing objects (such as some rocks and props) lies
  flat on the ground.
- A cloth wedge shows at the foot end of the beds.
- 22 pieces of furniture (some chairs, stairs and tables) still block a little away
  from where they are drawn, by up to 55 pixels.
- Two places have surfaces at the same depth that may flicker: a bed post in one
  house and a chapel wall.

If something is wrong where you are standing, press F9 and send the report.
