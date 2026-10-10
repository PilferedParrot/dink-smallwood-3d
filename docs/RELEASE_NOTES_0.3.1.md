# Dink Smallwood 3D 0.3.1 (work in progress)

This is a work-in-progress release. It makes the things you walk around solid, rebuilds
Dink's house from the original art, and brings back the original game's interface. It
still has many problems: the known issues are listed below, in the words of the person
who played it.

## What changed since 0.3.0

- **Props and fences are solid.** The sack of pig feed, the pie, barrels, crates, chests,
  bags and bottles stand in 3D, each fitted from its own original sprite, instead of
  flat pictures. The rail fences are solid posts and rails, joined at the corners.
- **Dink's house is built from the original art**: stone walls, a brick hearth with its
  fire, the round table with the pie on it, and the quilted beds. The neighbours' rooms
  too. Indoors, no outdoor sky shows past the doorway; the corridor ends in a door.
- **The original interface**: the Dink Smallwood logo, the stone status bar with the
  original item pictures, the item chest, and the original game's dark menus. Text
  contrast is much higher, sliders show their values, toggles say On or Off, and the
  control hints fade after first use (F1 shows them again).
- **North-south bridges have standing railings**, and the drawbridge chains are iron links.
- **Fixes**: walking east from screen 376 into 377 near its south edge no longer traps you
  against a tree; grain bags by the inn no longer merge into one shape; the round table
  is round; a chimney no longer disappears into the wall.

## Known issues

Reported after playing this build (October 10, 2026):

- You can still get stuck in an open area of the map.
- Some trees are drawn half as 3D models.
- Some text takes up far too much of the screen, and some text is repeated on the same
  screen.
- You have no body. Walking around, you are only a raised fist, a bow or a feed bag, and
  your shadow is only that too.
- You have to get too close to barrels to break them.
- The save machine is a flat picture that turns to face you as you walk around it.
- Milder can be hard to see when he appears.
- The corridor from the room to the door in Dink's house is too long and narrow to look
  real.

Also known: the well is still a flat picture; the cottages' end walls show stretched
texture; the beds' sides are smeared; the ceilings are untextured; there is no key
remapping; the first-person bow and hand are untextured.

The Linux export receives a local check. Windows validation runs through Proton on Linux
and is not a native-Windows certification. The Windows executable is not code-signed.

See [DIRECTION.md](DIRECTION.md) for the full record and [RELEASE_NOTES_0.3.0.md](RELEASE_NOTES_0.3.0.md)
for the previous release.
