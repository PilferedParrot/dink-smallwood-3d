# Dink Smallwood 3D 0.3.2 (work in progress)

This release answers most of what Chris reported after playing 0.3.1. The game is
still a work in progress.

## What changed

- **No more trapped crossings.** Walking from one screen to the next keeps Dink where
  he is instead of dropping him at a fixed spot, which could be inside something
  solid. Every edge of all 570 outdoor screens was walked: nowhere leaves Dink unable
  to move.
- **Stone walls are solid.** On the 18 screens with stone walls, the walls are built
  from the original wall art as solid walls you can walk around. You can no longer
  walk through a wall that is drawn there.
- **Whole trees.** Firs that the original drew cut off at a screen or forest edge
  are now whole firs standing on their own trunks, built from the original fir art.
  A fir you can see is a fir you bump into.
- **Save machines work from every side.** Walking up to a save machine and pressing
  E now always offers to save. In 0.3.1 it could say "Move closer" from some sides.
- **Talking and hitting** use what you can see: walls and buildings block them,
  invisible blocking does not. Everything you can talk to or hit can be reached.
- **Dink casts his own shadow**, from his original animated body.
- **Barrels break at the original's reach.**
- **Milder can be seen when he appears**, and the speaker in a conversation turns
  to face you.
- **The house's front room** is the size the original draws, not a long corridor.
- **Text takes less of the screen** and is no longer shown twice at once.
- **Buildings draw the same on every launch.** A few house kits drew the same dormer
  twice; that is fixed.
- **F9 saves a report** (a screenshot, Dink's position and the last few seconds of
  input) on your computer, so a problem can be found exactly where you saw it.
  Nothing is sent anywhere.

## Known issues

- Rocks and cliffs outdoors are painted flat on the ground but still block you, as
  they do in the original. This is the next thing to fix.
- You can walk into a fir's lower branches, and open forest ground is a picture of
  treetops painted flat.
- Looking down, Dink has a shadow but no body; the fist and bow are plain models.
- Some interface panels, textures and the house ceiling are still rough.
- In the grief scene the camera stays where you were standing, and you can't walk
  around during it, as in the original.
- Timed speech can cover the top of the status bar until the line ends.
- F9's replay starts from the moment you pressed it; it does not rewind.

If something is wrong where you are standing, press F9 and send the report.
