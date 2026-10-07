# Dink Smallwood 3D 0.3.0

Version 0.3.0 rebuilds the world's scenery from the original artwork. Houses, the
church, the castle, bridges, huts, trees and props now stand in 3D as the
original sprites show them, instead of as stand-in models. Linux x86-64 and
Windows x86-64 builds are included.

## Highlights

- Houses, the log cabin, the church and the inn are built in 3D from their
  original sprites. Each is fitted from the picture's own pixels: footprint,
  wall height, eaves, thatch, chimneys and dormers. The back of a house has no
  door.
- The castle stands in 3D: its walls, towers, gatehouse and corners, with doors
  set in their walls and the drawbridge lying on the ground.
- The island's round huts are solid round huts, not flat cards.
- Bridges are decks on the water. On the east-west rope bridges the railings
  stand, and arrows hit the deck.
- Props, trees, bushes and people are the original sprites, drawn upright from
  every side. Trees no longer turn edge-on to a sliver, and people and animals
  settle against walls instead of being cut by them. The ground is the tile art;
  the procedural grass blades are gone.
- The people and animals of the neighbouring screens are drawn, and show what
  their scripts set when you arrive.
- Collision follows the fitted building footprints.
- Stacked and doubled trees are fixed. Two tree pictures each hold two trees; each
  now stands on its own foot. An object the map repeats on both sides of a
  screen's edge is built once.
- Walking round a tree against a wall, the canopy dissolves in over a few steps
  instead of jumping in front of the wall.
- Sound: the Stonebrook start music plays (it was silent in 0.1.0 and 0.2.0),
  screen music follows the original engine's CD-track rules, and the 27 sound
  effects that GNU FreeDink leaves silent are filled with free sounds. Shipped
  audio is pinned by hash to the FreeDink set.

[docs/M3.md](M3.md) is the one-page list of what the last stretch changed, with a
before-and-after sheet. The full record, with evidence images, is in
[DIRECTION.md](DIRECTION.md).

## Fixes included in this build

- `playsound` speed follows the engine: DinkC passes an absolute rate in Hz, and
  the game had divided it for every file.
- The coincident-copy rule leaves fixed cards alone, so fences, structures and
  castle pieces a few pixels apart are no longer merged.
- Castle doors sit in their walls and the drawbridge leaf lies on the ground.
- The source bundle for the music no longer includes the still-picture YouTube
  video that came with the "Lovin'" recording. Its audio (CC BY 3.0, Gachopin) is
  kept as an AAC file; the game's own audio is unchanged. The picture's rights are
  not established, and the game never used it.

## Known limits

This remains a development release. The full campaign has not received a
continuous start-to-finish certification, and later quests, natural campaign
death, real-time audio and timing, and native-GPU performance have not been
certified.

Things you may notice in the scenery:

- Seen from the east or west, the island huts are narrow eggs with a stretched,
  partly doubled picture on their flanks, and a seam runs down each back.
- The side-flip dissolve is a fine stipple. Standing exactly on a wall's line
  leaves the tree half-stippled.
- The gatehouse's vaulted tops are a flat picture, and its hidden faces streak
  on thin edges.
- The north-south bridges' ropes lie flat on the planks.
- The drawbridge's chains are pale straps where the art draws dark iron links.
- Through the original's own camera, a few screens (270, for one) show trees
  standing behind a cabin roof where the original drew them over it, and the 3D
  shadows fall in new places.

The Linux export receives a local smoke check. Windows validation runs through
Proton on Linux and is not a native-Windows certification. The Windows
executable is not code-signed, so Windows may ask you to confirm that you want
to run it.

See [FIRST_PERSON.md](FIRST_PERSON.md) for implementation detail, [M3.md](M3.md)
for this release's changes and [RELEASE_NOTES_0.2.0.md](RELEASE_NOTES_0.2.0.md)
for the previous release.
