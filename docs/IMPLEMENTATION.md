# Architecture and provenance

The Godot host is an independent Apache-2.0 implementation. It renders imported
Dink bitmap frames as animated sprites in a 3D scene. It does not embed or link
GNU FreeDink's engine. The original campaign, images, and music are separate data
with their original licenses; see `licenses/` and `third_party/`.

The importer reads `Dink.dat`, `Map.dat`, `Hard.dat`, `Dink.ini`, BMPs and `dir.ff`
archives from a local FreeDink installation. Each map's 96 visible tiles are
stored in a binary structure containing **97** tile records. Sprite records
start at offset 8020; the screen record length is 31280 bytes. `Hard.dat` contains
800 collision masks, each stored as 51 by 51 bytes in x-major order.

The script compiler produces expression trees and procedure instructions in
JSON. The cooperative Godot VM owns variables and control flow; the game host
owns movement, dialogue, inventory, collision, audio, and combat. See
[DINKC_SUPPORT.md](DINKC_SUPPORT.md) and [DIALOGUE_CHANGES.md](DIALOGUE_CHANGES.md).

Behavior references used to verify data formats and scripting semantics:

- GNU FreeDink 109.6 source distribution: https://ftp.gnu.org/gnu/freedink/
- DinkC reference: https://dinkcreference.netlify.app/
- Original Dink.ini and Story sources in the installed FreeDink data package.

Tests cover compiler semantics, script context, modal controller navigation,
original map offsets, animation metadata, and game behavior. Imported screen
coverage is distinct from an end-to-end campaign playthrough.
