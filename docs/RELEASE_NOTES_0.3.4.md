# Dink Smallwood 3D 0.3.4 (work in progress)

This release fixes saving, makes the caves look like caves, and fixes a duck that could stop
coming back. It is still a work in progress.

## What changed

- **Save slots say what they are.** The save machine, the load list, the pause menu and Continue on
  the title page show each slot as the original does: "Slot 3 - 1:23 - Level 4" or "Slot 2 - Empty".
  Each slot is its own save, so saving into one slot no longer overwrites the others, and loading
  an empty slot no longer loads another one. Continue opens the list with your latest save
  selected; Save picks the first empty slot. Your existing save becomes slot 1.
- **Caves look like caves.** Cave walls are built from the cave's own rock art instead of flat
  brown posts, they stand where the original blocks your way (including the thin rock edges it
  missed before), and the openings out of a cave are black.
- **The duck comes and goes as in the original.** A screen's chance events (such as whether the
  old woman's duck is there) are rolled afresh on each visit, as in the original. Before, the first
  roll could stick until something else in the game changed. What you see of the next screen
  before you enter it still matches what you find there.
- **Cave walls build faster.** On the slowest screen, building the walls takes about 0.04 s instead
  of 0.2 s.

## Known issues

- Characters, monsters, trees and many props are flat pictures that turn to face you, rather
  than solid 3D objects.
- Small animals on the ground, such as the duck, drop out of view below the screen when you walk
  up to them, at about 1.2 m.
- Up close, pictures and some models show large square pixels.
- Some passages are narrower than in the original, because the game keeps you a little away from
  everything you could bump into.
- Some characters' pictures poke through walls when they stand next to them.
- Some bones and graves that the original draws on cave rock are now hidden inside the rock.
- Some caves still show rough, stepped edges where the rock meets the floor.
- In some rooms, two surfaces at the same depth can flicker.
- Background art that shows standing objects (such as some rocks and props) lies flat on the
  ground.
- A cloth wedge shows at the foot end of the beds.
- 22 pieces of furniture (some chairs, stairs and tables) still block a little away from where
  they are drawn, by up to 55 pixels.
- Some ground blocks you with no visible wall where the original also shows none.

If something is wrong where you are standing, press F9 and send the report.
