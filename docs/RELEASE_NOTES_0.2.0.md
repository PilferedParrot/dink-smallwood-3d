# Dink Smallwood 3D 0.2.0

Version 0.2.0 changes the project from the earlier raised-camera diorama into a
first-person 3D adaptation. Linux x86-64 and Windows x86-64 builds are included.

## Highlights

- Added a first-person renderer for imported maps, with modeled outdoor scenery,
  buildings, furniture, creatures, and projectiles.
- Added mouse and controller look, analog controller movement, jumping, sprinting,
  first-person melee, bow projectiles, and the original magic progression.
- Added controller navigation and controller-specific look settings.
- Added first-person save data, including camera orientation, and retained the
  campaign's inventory, quest, and script state.
- Added the original world map after it is received in the campaign.
- Extended automated campaign coverage from a new game through Ethel, AlkTree
  nuts, the return-home aftermath, Renton's letter, and Aunt Maria's map.

## Fixes included in this build

- Corrected imported screen-script offsets and a targeted source-script repair
  needed to release controls after Ethel's dialogue.
- Restored the intended open village-gate entrance and protected structural
  scenery and collision from disappearing after save/load.
- Added bounded recovery for edge arrivals that overlap 3D scenery.
- Improved state-specific fire, aftermath, and dialogue-camera presentation in
  the tested early campaign.

## Known limits

This remains a development release. The full campaign has not received a
continuous start-to-finish certification. Some characters and props share
stylized models, and later quests, natural campaign death, real-time audio and
timing, and native-GPU performance have not been certified. The Linux export
receives a local smoke check; Windows validation runs through Proton on Linux
and is not a native-Windows certification.

See [FIRST_PERSON.md](FIRST_PERSON.md) for implementation detail and the
campaign milestone reports for the exact test scope.
