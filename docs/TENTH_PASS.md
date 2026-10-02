# The tenth pass: what changed

October 1, 2026. Branch `claude/dink-tenth-pass` (local, not pushed). One sheet: `docs/images/tenth-pass.jpg`, eight
cameras, the game before this pass (aa7388e) on the left and now on the right. The full record is in
`docs/DIRECTION.md`, the two "tenth pass" sections.

**What you will see**
1. **Trees stand whole from every side.** Nearly every tree, bush and bramble was a flat card facing south, because
   the old "wide sprites stay flat" rule measured the art's drawn shadow too. Looking east or west, the forest turned
   into slivers. Now only structures keep their plane: fences, walls, signs, the island's huts. Everything else turns to
   face you, as the people already did. Each still casts its shadow on the ground. Fire, grass, coins and holes cast
   none, because the original draws none for them.
2. **The next screen has its people and animals.** From Dink's yard the pigs stand in the pen next door, and the ducks
   and villagers of the neighbouring screens are where their screens put them. They stand still until you walk over.
3. **No doors on the backs of houses.** The saved house textures had doors painted onto their backs, and onto one
   wall of Ethel's house. The game now draws them as the original does.
4. **Bridges are bridges.** They were loose planks floating over the water. The decks now lie on the water as the
   original draws them, and the rope railings stand.
5. **The castle is solid.** Its walls and towers were tall flat pictures, slivers from the side. They now stand in 3D,
   built from their own sprites like the houses: walls with a walkway on top, round towers, the doors on their walls.
6. **Smaller fixes.** A villager or pig at a wall is no longer cut by it. The inn and its kin now order nearby barrels
   and grass as the original does.

**Where to look in the game:** walk east from Dink's house and turn round among the trees (376). Look at the pigpen from
the yard (439). Cross the rope bridge west of the village (404) and the long plank bridge in the east (448). Walk along
the castle wall by the knights (402) and into its courtyard (368).

**Still wrong**
- The castle's north gatehouse and a few corner and gate pieces are still flat cards, as are the island's huts.
- The next screen shows its editor layout: whatever its scripts would hide or move on arrival is still shown, and its
  people stand still. A GPT-6 Sol lane takes this from October 2: it will run each screen's startup scripts in a
  sandbox.
- Walking round a house, one small patch of a tree can jump in front of the wall as you cross the wall's line.
- A bridge's far railing lies flat on its deck.

**Checks:** 95 tests pass, 1 skipped (83 before the pass). Each fix has a test that failed on the old code. Loading
Dink's village screen takes about 102 ms, a few ms more than before the pass (the next screens' people). The castle
screen loads 4.5 ms slower and draws faster. These timings are approximate: rendered in software, on a shared machine.
