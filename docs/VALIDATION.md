# Validation of development release 0.1.0

Test environment: Linux x86-64, Godot 4.6.1, Python 3.14. Rendered screenshots
were inspected using Godot's OpenGL compatibility renderer through Xvfb.

The automated suite passes 20 tests. It covers:

- DinkC expression/control flow parsing, explicit source repairs, and all 381
  campaign scripts (936 procedures).
- Immutable VM control flow, nested labels/gotos, concurrent sprite contexts,
  conditional choice IDs, script cancellation, persistent script attachments,
  and VM save state.
- Original binary map offsets, per-frame sprite metadata, animation aliases,
  collision masks, and audio source/attribution paths.
- Controller navigation and activation of the actual menu, plus text scaling.
- The opening conversation, touching the pig-feed sack, pickup persistence,
  the original home-to-village exit, sword animation/equipment changes, and
  repeated save/load without increasing weapon stats.
- Loading all 644 imported screens.
- Combat brains, melee and projectile damage, defense, source/target contexts,
  enemy touch/attack callbacks, bombs, magic recharge, and level-up choices.

This demonstrates the stated behaviors, not a complete campaign playthrough.
The adaptation's AI, timing, and sprite presentation are independently implemented;
frame-for-frame equivalence with FreeDink has not been established. Characters
and scenery are original rendered frames placed in a 3D diorama. The camera changes
elevation; it does not expose newly modeled backs or sides of those objects.

FreeDink's installed sound package contains 22 effect files and 17 music tracks
(after MIDI rendering). Original scripts reference additional historical audio
names absent from the freely licensed package; those calls are silent. The project
does not substitute unlicensed original recordings.

Linux and Windows executables are exported from identical source and data. Linux
receives an exported-executable smoke check. The Windows export is not tested on
Windows in this Linux environment.
