# Audio: the GNU FreeDink set only (2026-09-30)

Chris, 2026-09-30: "swap the audio for freedink's replacements".

The concern was that Dink 3D ships original Dink Smallwood v1.08 audio. RTsoft's
2008 free data release (zlib license, `licenses/FREEDINK-DATA-COPYRIGHT.txt`)
left out the sounds it did not own. The FreeDink data README says: "The original
game contained sounds that were not owned by RTsoft and hence could not be
released under a free license." GNU FreeDink replaced some of them with free
files and left the rest silent.

## Result

* **This repository and every published release have only ever shipped the
  FreeDink set.** No original non-free or unclear audio file was committed or
  released (see the exposure report below). Nothing had to be swapped.
* **One FreeDink file was broken, and is now fixed.** `104.ogg` (Stonebrook, the
  first-person start music) was a 1.45 ms render of FreeDink's `104.mid`, which
  plays as silence. That file shipped in v0.1.0 and v0.2.0. It now plays FreeDink's
  Schubert Serenade arrangement, 293.9 s long.
* **The original v1.08 audio exists only in the local main checkout.** It is an
  uncommitted and unpublished opening rework from September 8 to 11. It holds all
  88 original v1.08 files, rendered where they are MIDI. That checkout's
  `docs/OPENING_SOURCE_AUDIO.md`, `NOTICE` and `README.md` describe that rework,
  not this repository. This branch does not touch the rework. What happens to it
  is Chris's decision.
* **The 27 effects FreeDink leaves silent are filled** (2026-09-30, Chris: "why
  have a silent sound effect?"). The sources are CC0, public domain and CC BY 3.0
  recordings, plus one sound we synthesize. `tools/build_sfx.py` builds them, and
  each one has its own row, source and license. See "Filled" below.
* **`playsound` speed now follows the engine.** DinkC passes an absolute rate in
  Hz, and the game had divided it by 22050 for every file. See "playsound speed"
  below.
* **Guards.** `tools/audio_provenance.py` pins every shipped file to its FreeDink
  source by hash. `tests/test_audio_provenance.py` and
  `tools/package_release.py` both run it, so a tree containing original audio
  fails the tests and cannot be packaged.

## Inventory of what the game loads

Code path: `game/scripts/game.gd` loads only `res://assets/sound/`.
* **Numbered sounds:** `_load_sound_slots` reads the `load_sound` registry in
  `START.c` (49 slots). `_play_sound` plays a slot, or does nothing if the slot
  has no file.
* **Music:** `_play_music` looks up `<name>.ogg`, then `<name>.wav`, from
  `playmidi` calls and the screen music ids.
* **Nothing else:** nothing loads audio at runtime from a Dink install. The export
  presets ship `game/` whole: all resources plus `data/*.json`.

The 39 FreeDink files, classified by content (the 27 fills are listed under
"Filled"):

| Class | Files | How identified |
|---|---|---|
| FreeDink replacement, copied | 21 effects (all except `secret.wav`) and 5 music files (`1`, `5`, `106`, `denube`, `lovin`) | SHA-256 identical to `/usr/share/games/dink/dink/Sound` (freedink-data 1.08.20190120) |
| FreeDink replacement, MIDI rendered | `7`, `12`, `13`, `18`, `104`, `105` | Decoded PCM identical to a fresh FluidSynth + FluidR3_GM render of the FreeDink MIDI. The original MIDIs render to different lengths, for example 105: 253.9 s (FreeDink) vs 259.0 s (original) |
| Original Dink data that FreeDink keeps (zlib) | `1003`, `2`, `dance`, `insper`, `lively`, `love` (rendered MIDI) and `secret.wav` | The FreeDink copyright file lists these as covered by RTsoft's release. The MIDI bytes are identical in both sets |
| Original, non-free or unclear | none | |

Per-file hashes, sources, licenses and credits are in `licenses/AUDIO-FILES.tsv`.

## The 104.ogg repair

FreeDink's `104.mid` was written by Rosegarden in 2008. It keeps MIDI running
status across meta events. SMF 1.0 says "Sysex events and meta-events cancel
any running status", so FluidSynth 2.3.4 misreads the rest of the track. Its
debug log shows `alloc metadata, len = 16257`, and it renders nothing.
`tools/import_assets.py` now writes every channel event with its own status
byte before rendering (`midi_with_explicit_status`). This is lossless:
* **The other 11 FreeDink MIDIs** render PCM-identical to the committed files.
* **All 16 MIDIs under `third_party/`** keep identical event lists (tested).

Only `104.ogg` changed. The source MIDI is unchanged; it is still FreeDink's file.

## Sounds FreeDink has no replacement for (filled, source per file)

The campaign data references 27 original effect files that FreeDink ships no
free version of. The originals are **not** used. Until 2026-09-30 these cues
were silent, as they are in FreeDink. Now each one plays a free sound built by
`tools/build_sfx.py`:

* **Sound effects: 27 files, 28 slots, all filled.** `quack` (1), `pig1`–`pig4`
  (2–5), `select` (11), `picker` (13), `escape` (18), `sel2` (20), `sel3` (21),
  `spell1` (24), `caveent` (25, 32), `snarl1`–`snarl3` (26–28), `hurt1`,
  `hurt2` (29, 30), `attack1` (31), `level` (33), `splash` (35), `sword1` (36),
  `squish` (38), `steps` (40), `flyby` (42), `knock` (45), `drag1`, `drag2`
  (46, 47).
* **Music cues are still silent (out of scope; Chris composes).** 9 by name, plus
  the CD tracks with no file. Screen music `100`, `101`, `102`, `103`, `107`, and
  `playmidi` `battle`, `bullythe`, `caveexpl`, `wanderer`. The CD-track cues
  (`1000+N`, see Observations) whose `N` has no shipped file are silent too:
  screen music `1008`, `1010`, `1016` and `playmidi` `1004`, `1006`, `1009`,
  `1011`, `1015`. `_play_music` leaves the current track playing, as before.

The v1.08 installer holds 13 more original files that no cue names directly:
`bird2`, `click`, `high1`, `ocean1`, `pop`, `splash.aif`, and the MIDIs `4`,
`6`, `9`, `10`, `11`, `16` and `neighbor`. They are not shipped, and FreeDink has
no replacement for them. The CD-track cues `1004` to `1016` reach `4`, `6`,
`9`, `10`, `11` and `16` through the mapping below, and find no file.
freedink-data 1.08.20190120 is the newest release (ftp.gnu.org/gnu/freedink), so
there is no newer FreeDink replacement to take.

### Filled

**Sources.** Only CC0, public domain and CC BY 3.0 files were used. The shipped
audio already includes CC BY 3.0 and CC BY-SA 3.0 files.
* **Where from:** Kenney.nl packs, OpenGameArt entries and Wikimedia Commons
  files. None of these needs an account.
* **License check:** each license was read on the source's own page (the OGA
  "License(s)" field, the Commons file's wikitext license tag, and the Kenney
  asset page plus the pack's `License.txt`), not from a search listing.
* **Pinned:** every download is pinned by SHA-256 in `tools/build_sfx.py`.
* **Credits:** `licenses/AUDIO-FILES.tsv` gives each file's credit: the source
  page, author, license and our edit. `NOTICE` names the CC BY authors.
* **Own work:** `flyby.wav` is synthesized, so it is our own work (Apache-2.0).
  It is a fireball's roar moving past the listener. Its swell and pitch drop come
  from the distance (1/r), the propagation delay (Doppler) and air damping.
  Nobody drew them. The test suite rebuilds it byte for byte.

**Format: the v1.08 file's sample rate.** The originals are 8000, 11025, 12500
or 22050 Hz, and all 20 FreeDink replacements we measured keep their original's
rate. A script's `playsound` speed is a playback rate in Hz (next section). So a
file at the original's rate plays at the speed each script was written for.
Each file's content sounds natural at its own rate, so the in-game pitch follows
from the script. For example, a size-100 pig grunts at 13000 Hz, 1.6 times its
file's rate (GNU FreeDink 109.6 `src/brain_pig.cpp:64-88`), as the original did.

**Where register mattered, it was measured.** For `hurt1`, the original's
register was read from its spectral centroid and pitch. Its callers play it at
1.5 to 2 times its rate, so the source was slowed to 0.56 like tape. That puts
it near the original's pitch and length at the file's rate: f0 about 260 Hz
against 212, and 2.2 s against 2.4.

**Loudness.** Loudness is the maximum momentary loudness, EBU R128 M over 400 ms,
with short files padded to 0.4 s.
* **Target:** the v1.08 file's measured value plus −0.35 dB. That offset is the
  median gap between FreeDink's 20 replacements and the originals they replace;
  the gaps range from −8.6 to +5.3 dB.
* **Clamp:** the target is kept inside the range the shipped FreeDink effects
  span, −29.0 to −10.2 LUFS.
* **Peaks:** peaks above −1 dBTP are limited (look-ahead 1.5 ms, release 20 ms),
  by at most 6 dB.
* **Shortfalls:** files more than 0.5 dB under their target are marked \* in
  the table. Three percussive sources could not get near it within that limit:
  `knock` is 6.9 dB under, `sel2` 4.5 dB and `picker` 3.1 dB. `sword1`,
  `splash`, `escape` and `pig4` are 0.7 to 1.0 dB under. The original
  `knock` clipped (true peak +2.2 dBTP). We did not clip to match it.
* **Neighbours:** every fill but one sits inside the level range of the shipped
  FreeDink effects. The exception is `picker`, a 38 ms click at −32.1. The
  original `picker` (−30.6) was also quieter than any shipped effect.
* **Measured only:** the originals were used for their rate, length and level.
  No original waveform was used, and none is in this repository.

**Heard only by measurement so far.** No sound was played during this work.
Chris judges them on headphones.

| file | slot | role | source | license | Hz | s (v1.08) | max M LUFS (target) | int. LUFS | true peak dBTP |
|---|---:|---|---|---|---:|---:|---:|---:|---:|
| `quack.wav` | 1 | duck hit (s7-duck); duck brain | [Ducks snatching (Ravenhof park, Torhout)](https://commons.wikimedia.org/wiki/File:Ducks_snatching.ogg), Bert76 | CC0-1.0 | 22050 | 1.00 (1.13) | -17.8 (-17.8) | -19.4 | -6.4 |
| `pig1.wav` | 2 | pig grunt (engine pig brain, at 13000 Hz for a size-100 pig) | [Pig SFX Pack, pig_idle](https://opengameart.org/content/pig-sfx-pack), Vinrax | CC-BY-3.0 | 8000 | 0.75 (0.77) | -20.0 (-20.0) | -21.2 | -1.0 |
| `pig2.wav` | 3 | pig grunt (engine pig brain) | [Pig grunt (a farm pig)](https://commons.wikimedia.org/wiki/File:Pig_grunt_-_Erdie.ogg), erdie (freesound.org/people/Erdie) | CC-BY-3.0 | 8000 | 0.66 (0.88) | -22.9 (-22.9) | -24.2 | -12.0 |
| `pig3.wav` | 4 | pig grunt (engine pig brain) | [Pig SFX Pack, pig_idle3](https://opengameart.org/content/pig-sfx-pack), Vinrax | CC-BY-3.0 | 8000 | 0.28 (0.38) | -28.1 (-28.2) | -30.5 | -7.3 |
| `pig4.wav` | 5 | pig grunt (engine pig brain) | [Pig SFX Pack, pig_idle4](https://opengameart.org/content/pig-sfx-pack), Vinrax | CC-BY-3.0 | 8000 | 0.87 (0.78) | -20.5 (-19.8) * | -21.9 | -1.1 |
| `select.wav` | 11 | menu cursor move (engine: inventory and choice menus) | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.13 (0.58) | -23.5 (-23.6) | -23.5 | -2.5 |
| `picker.wav` | 13 | experience counter tick (engine), pig-feed item | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.04 (0.21) | -32.1 (-29.0) * | -32.1 | -1.5 |
| `escape.wav` | 18 | game menu and inventory open/close | [RPG Audio](https://kenney.nl/assets/rpg-audio), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.56 (0.83) | -16.0 (-15.2) * | -17.6 | -1.1 |
| `sel2.wav` | 20 | title menu button hover | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.10 (0.43) | -22.3 (-17.8) * | -22.3 | -1.0 |
| `sel3.wav` | 21 | title menu choice; warp (at 8000 Hz) | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.53 (0.87) | -15.2 (-15.2) | -17.6 | -4.2 |
| `spell1.wav` | 24 | spell cast (wizards, magic items, bosses) | [Magic spell SFX, magical_1](https://opengameart.org/content/magic-spell-sfx), JaggedStone | CC0-1.0 | 22050 | 1.59 (1.56) | -10.3 (-10.2) | -12.3 | -1.4 |
| `caveent.wav` | 25, 32 | a monster roaring deep in the cave (s1-cave, s1-caves noise) | [CC0 deep monster roar](https://opengameart.org/content/cc0-deep-monster-roar), trazzz123 | CC0-1.0 | 11025 | 6.62 (6.62) | -12.6 (-12.5) | -15.0 | -1.5 |
| `snarl1.wav` | 26 | monster snarl (no current caller) | [Cat hissing](https://commons.wikimedia.org/wiki/File:Cat_hissing_-_Zabuhailo.wav), Zabuhailo (freesound.org/people/Zabuhailo) | CC0-1.0 | 22050 | 1.64 (1.64) | -13.8 (-13.8) | -16.3 | -1.4 |
| `snarl2.wav` | 27 | monster attack snarl (goblins, slayers) | [Dog snarl, grunt, grumble](https://opengameart.org/content/dog-snarl-grunt-grumble), qubodup | CC0-1.0 | 22050 | 0.66 (0.78) | -29.0 (-29.0) | -31.5 | -15.5 |
| `snarl3.wav` | 28 | monster attack snarl (goblins, slayers) | [Bear growls (U.S. Fish & Wildlife Service recordings)](https://opengameart.org/content/bear-growls), AntumDeluge | CC0-1.0 | 22050 | 1.07 (1.97) | -25.2 (-25.2) | -27.1 | -18.7 |
| `hurt1.wav` | 29 | monster hit (boncas, slimes, cave monster; called at 1.5-2x) | [15 monster grunt/pain/death sounds](https://opengameart.org/content/15-monster-gruntpaindeath-sounds), Michel Baradari | CC-BY-3.0 | 11025 | 2.19 (2.40) | -16.9 (-16.9) | -19.7 | -6.1 |
| `hurt2.wav` | 30 | pillbug hit | [Piglet squeal 01](https://commons.wikimedia.org/wiki/File:618483_foleyhaven_piglet-squeal-01.flac), Foleyhaven (freesound.org/people/Foleyhaven) | CC0-1.0 | 22050 | 1.41 (1.29) | -20.5 (-20.6) | -23.1 | -8.2 |
| `attack1.wav` | 31 | monster attack (boncas, cave monster, dragon, boss) | [Big scary troll sounds, troll-roars](https://opengameart.org/content/big-scary-troll-sounds), Darsycho | CC0-1.0 | 11025 | 1.20 (1.30) | -16.4 (-16.4) | -20.4 | -8.0 |
| `level.wav` | 33 | level up | [Music Jingles](https://kenney.nl/assets/music-jingles), Kenney (kenney.nl) | CC0-1.0 | 22050 | 0.80 (1.67) | -12.7 (-12.8) | -14.7 | -3.6 |
| `splash.wav` | 35 | fish splashing; boat launch | [Water Splash (Yo Frankie!)](https://opengameart.org/content/water-splash-yo-frankie), Blender Foundation | CC-BY-3.0 | 22050 | 3.03 (2.67) | -15.7 (-14.8) * | -18.5 | -1.1 |
| `sword1.wav` | 36 | sword enemies' attack | [20 sword sound effects, clashes](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes), StarNinjas | CC0-1.0 | 22050 | 0.48 (0.76) | -14.8 (-13.8) * | -17.4 | -1.1 |
| `squish.wav` | 38 | slime touch and hit | [8 wet squish, slurp impacts](https://opengameart.org/content/8-wet-squish-slurp-impacts), Independent.nu (Johannes Pinter) | CC0-1.0 | 22050 | 0.42 (0.42) | -15.9 (-15.8) | -17.5 | -1.5 |
| `steps.wav` | 40 | footsteps (s3-1st) | [RPG Audio](https://kenney.nl/assets/rpg-audio), Kenney (kenney.nl) | CC0-1.0 | 22050 | 1.57 (1.79) | -21.7 (-21.6) | -25.2 | -1.4 |
| `flyby.wav` | 42 | fireball flying past (s4-h1p, s2-fgate, s8-da) | synthesized (`synth_flyby`) | Apache-2.0 | 22050 | 0.60 (0.60) | -22.9 (-23.0) | -23.5 | -4.5 |
| `knock.wav` | 45 | knocking on a door (s2-mdoor) | [Knocking on wood or door](https://commons.wikimedia.org/wiki/File:Knocking_on_wood_or_door.ogg), stephan (pdsounds.org) | public domain | 12500 | 0.72 (0.68) | -17.1 (-10.2) * | -18.4 | -1.4 |
| `drag1.wav` | 46 | dragon hit; s5-fguy | [Lion roaring (a captive lion, Tamil Nadu)](https://commons.wikimedia.org/wiki/File:Lion_raring-sound1TamilNadu178.ogg), த*உழவன் (Wikimedia Commons) | public domain | 22050 | 1.30 (1.26) | -14.1 (-14.0) | -15.7 | -9.9 |
| `drag2.wav` | 47 | dragon attack | [American alligator bellows](https://commons.wikimedia.org/wiki/File:27alligator2bellow.ogg), U.S. Fish and Wildlife Service | public domain | 22050 | 3.20 (3.10) | -11.8 (-11.8) | -15.0 | -1.8 |

The table's lengths are the shipped file's; the v1.08 original's is in
parentheses. "Engine" roles are FreeDink engine calls that this game does not
make yet, so those files load but are not triggered: `pig1`–`pig4`
(`brain_pig.cpp`), `select` (`inventory.cpp`, `game_choice.cpp`) and the
experience-counter `picker` ticks (`status.cpp`). `snarl1` and `caveent`'s slot
25 have no caller in FreeDink either; slot 32 plays `caveent`.

## playsound speed (fixed 2026-09-30)

DinkC's `playsound(sound, min_speed, rand_speed_to_add, sprite, repeat)` passes
a playback rate in Hz, whatever rate the file was written at. GNU FreeDink 109.6
`src/sfx.cpp:637-653`:
* `play_freq = min + rand() % plus`;
* the sample then advances `play_freq / hw_freq` per output frame.

The game had divided every speed by 22050, so an 8000 Hz file called at 8000
played at 0.36. It also ignored `rand_speed_to_add`. `Game._play_sound_hz` now
uses speed / the file's own rate, plus the random add.

**What changes in the existing FreeDink set.** The 22050 Hz files play exactly as
before when called at a fixed speed. The four 8000 Hz files now play as FreeDink
plays them:
* `swing` from the weapon scripts at 8000 Hz: pitch 1.0 (was 0.36).
* `burn` at 8000: 1.0 (was 0.36); at 22050: 2.76 (was 1.0).
* `sword2` from 14 pickup scripts at 22050: 2.76 (was 1.0).
* `wscream`'s `12050 + rand(10000)` now varies.

`tests/audio_cues_test.gd` checks the rule through the game's own DinkC binding
(`swing` at 8000 → 1.0, `sword2` at 22050 → 2.756, `pig1` at 13000 + 800 →
1.625 to 1.725, and more). Under the old rule it fails: "playsound(8, 8000, 0)
on swing.wav plays at pitch 0.36281, want 1.00000".

## CD-track music ids (fixed 2026-09-30)

Screen music uses the CD-track form `1000+N` (`1002`, `1005`, `1007`, `1012`,
`1013`, `1016`, ...), and `_play_music` used to look for `1007.ogg`. So `2`, `5`,
`7`, `12`, `13` and `18` shipped and never played. The original engine has no CD
player. Its rule, from GNU FreeDink 109.6 (`git.savannah.gnu.org/cgit/freedink.git`,
tag `v109.6`; the same lines are on master):

* `src/game_engine.cpp:334-339`, a screen's music: `if (g_dmod.map.music[*pplayer_map] > 1000)`
  ... `sprintf(midi_filename, "%d.mid", g_dmod.map.music[*pplayer_map] - 1000);`
  `PlayMidi(midi_filename);`. Comment at 335: "Try to play a CD track
  (unsupported) - fall back to MIDI". At or below 1000 it plays `<id>.mid`
  (343-344); `0` and `-1` play nothing (329, 333).
* `src/dinkc_bindings.cpp:1264-1278`, DinkC `playmidi`: for `regm > 1000` it plays
  `"%d.mid"` of `regm - 1000` (1271-1273), then plays the name as written
  (1278). The comment at 1275 says "necessary for START.c:playmidi("1003.mid")".
  The name as written therefore wins when its file exists.
* `src/bgm.cpp:137-142`: when the file is in no directory, `PlayMidi` logs
  "doesn't exist in any dir" and returns 0. `Mix_HaltMusic` (152) has not run, so
  the current track keeps playing.
* `src/bgm.cpp:95-102` tries `N.ogg` before `N.mid`; this game ships `.ogg`.

`Game.music_candidates` implements that. A screen's `1000+N` tries `N`; `playmidi`
tries the name as written, then `N`. `1000` itself is `1000`. The dedupe of a
track already playing (`bgm.cpp:87-92`) now compares the resolved track, so
screen `1007` and `playmidi("7")` are one track. Nothing that played before
changed: `1`, `104`, `105`, `106`, `denube`, `lovin`, `insper`, `dance`, `love`
and `1003` resolve as they did.

Result: screen music `1002`, `1005`, `1007`, `1012`, `1013` now plays `2`, `5`, `7`,
`12`, `13` (60 screens), and `playmidi` `1005.mid` and `1018` play `5` and `18`.
`1008`, `1010` and `1016` (42 screens) map to `8`, `10`, `16`, which no set
ships, so they stay silent. This changes what the player hears: the six files are
FreeDink renders at −24 to −46.5 LUFS (see Loudness spread), next to `104`
at −29.8 LUFS.

## Observations

* **Loudness spread.** This predates the swap. The FluidSynth renders measure
  −23 to −46.5 LUFS integrated. The recorded tracks (`1`, `106`, `denube`,
  `lovin`) measure −12.6 to −21 LUFS. The repaired `104` measures −29.8 LUFS,
  inside the render range and next to `13` (−28.8) and `105` (−33.3). No gain was
  changed. A loudness pass is a listening decision.

## Verification (no audio played)

Every Godot run used `--headless`, which sets the Dummy driver, or
`--audio-driver Dummy`. The session also pointed PulseAudio and PipeWire at a
dead socket. `tests/test_fps_fire_world.py` now passes `--audio-driver Dummy`
in its rendered (xvfb) mode. Before this change, that mode started Godot's
default audio driver.

* `python3 tools/audio_provenance.py` passes: 66 files match
  `AUDIO-FILES.tsv` and the installed FreeDink data (39 FreeDink files and the
  27 fills). The negative controls fail as they should:
  * **The 27 v1.08 originals copied over the fills:** all 27 fail
    ("sha256 differs"), and 20 of them also fail the fill format rule (8-bit or
    stereo).
  * **The local v1.08 rework folder:** 49 files unlisted and 38 hash mismatches,
    one of them its own empty `lovin.ogg` render.
  * **The pre-fix `104.ogg`:** "0.0015 s of audio; the render is empty".
* The headless Godot import produces 66 audio resources, with no import errors.
  The 27 new `.import` files carry the same parameters as FreeDink's.
* `tests/audio_cues_test.gd` runs the real game class headless. Through the
  game's own `_play_sound` and `_play_music`:
  * **Loaded:** all 66 shipped sounds.
  * **Played:** all 49 sound slots, 9 of the 18 screen music ids (loaded through
    the game's own `load_map`) and 8 of the 17 `playmidi` names.
  * **Missing:** no sound slot; only the silent music ids listed above. With the
    old `104.ogg` swapped back in, the test fails.
  * **playsound speed:** see "playsound speed" above.
  * **CD-track ids:** the test asserts each screen id's file (`1002` to `2.ogg`,
    `1005` to `5.ogg`, `1007` to `7.ogg`, `1012` to `12.ogg`, `1013` to
    `13.ogg`), and that a silent screen leaves the track playing. It fails on
    the code before the mapping.
* Per-file stats of the FreeDink files, from ffprobe and ffmpeg
  `ebur128=peak=true` (the fills are in the "Filled" table):

| file | codec | rate Hz | ch | duration s | integrated LUFS | true peak dBTP |
|---|---|---:|---:|---:|---:|---:|
| 1.ogg | vorbis | 44100 | 2 | 301.166 | -16.0 | -0.3 |
| 1003.ogg | vorbis | 44100 | 2 | 34.393 | -24.6 | -11.5 |
| 104.ogg | vorbis | 44100 | 2 | 293.864 | -29.8 | -16.7 |
| 105.ogg | vorbis | 44100 | 2 | 253.925 | -33.3 | -17.1 |
| 106.ogg | vorbis | 44100 | 2 | 192.000 | -19.7 | -0.1 |
| 12.ogg | vorbis | 44100 | 2 | 29.504 | -43.9 | -27.4 |
| 13.ogg | vorbis | 44100 | 2 | 282.452 | -28.8 | -16.0 |
| 18.ogg | vorbis | 44100 | 2 | 180.685 | -46.5 | -29.7 |
| 2.ogg | vorbis | 44100 | 2 | 88.606 | -32.5 | -17.5 |
| 5.ogg | vorbis | 44100 | 2 | 86.157 | -31.9 | -19.9 |
| 7.ogg | vorbis | 44100 | 2 | 105.011 | -24.1 | -10.9 |
| arrow.wav | pcm s16 | 22050 | 1 | 0.263 | -70.0 | 0.3 |
| axe.wav | pcm s16 | 22050 | 1 | 0.260 | -70.0 | -1.9 |
| bhit.wav | pcm s16 | 22050 | 1 | 0.539 | -12.2 | 0.3 |
| bird1.wav | pcm u8 | 22050 | 2 | 2.068 | -25.6 | -14.4 |
| bow1.wav | pcm s16 | 22050 | 1 | 0.351 | -70.0 | -1.2 |
| burn.wav | pcm s16 | 8000 | 1 | 2.735 | -23.0 | -6.8 |
| dance.ogg | vorbis | 44100 | 2 | 26.417 | -23.0 | -9.6 |
| denube.ogg | vorbis | 44100 | 1 | 177.450 | -21.0 | -0.1 |
| fire.wav | pcm s16 | 22050 | 1 | 7.824 | -31.4 | -8.4 |
| gold.wav | pcm s16 | 22050 | 1 | 0.185 | -70.0 | -4.7 |
| grunt1.wav | pcm s16 | 22050 | 1 | 0.372 | -70.0 | -1.3 |
| grunt2.wav | pcm s16 | 22050 | 1 | 0.419 | -15.5 | 0.0 |
| high2.wav | pcm s16 | 22050 | 2 | 4.075 | -22.7 | -11.5 |
| insper.ogg | vorbis | 44100 | 2 | 67.135 | -32.3 | -17.4 |
| intro.wav | pcm s16 | 44100 | 1 | 0.000 | -70.0 | -inf |
| lively.ogg | vorbis | 44100 | 2 | 68.979 | -29.4 | -9.8 |
| love.ogg | vorbis | 44100 | 2 | 45.838 | -35.5 | -21.4 |
| lovin.ogg | vorbis | 44100 | 2 | 183.020 | -12.6 | 0.4 |
| nono.wav | pcm s16 | 22050 | 2 | 0.644 | -16.6 | -0.1 |
| open.wav | pcm s16 | 8000 | 1 | 0.328 | -70.0 | -4.7 |
| punch.wav | pcm s16 | 22050 | 1 | 0.196 | -70.0 | -0.2 |
| save.wav | pcm s16 | 22050 | 1 | 1.330 | -24.5 | -10.2 |
| secret.wav | pcm s16 | 22050 | 2 | 1.408 | -13.0 | -3.7 |
| sel1.wav | pcm s16 | 22050 | 1 | 0.960 | -24.2 | -3.2 |
| stairs.wav | pcm s16 | 22050 | 1 | 0.990 | -29.7 | -7.4 |
| swing.wav | pcm s16 | 8000 | 1 | 0.133 | -70.0 | -2.7 |
| sword2.wav | pcm s16 | 8000 | 1 | 0.384 | -70.0 | -0.8 |
| wscream.wav | pcm s16 | 22050 | 1 | 0.690 | -15.1 | -10.9 |
| 104.ogg before the fix | vorbis | 44100 | 2 | 0.0015 | -70.0 | -89.7 |

A reading of −70.0 LUFS is the EBU R128 gate. Files shorter than one 400 ms
block have no integrated value, so read their true peak instead. `intro.wav` is
FreeDink's deliberate one-frame silence.

## Exposure report (facts only; nothing was changed)

**(a) Repository history.** No original non-free or unclear audio was ever
committed.
* **Scope:** all 7,787 objects reachable from every ref. The remote has `main`,
  `v0.1.0` and `v0.2.0`.
* **Method:** each object's git blob hash was checked against the 88 original
  v1.08 files and the 88 files of the local rework.
* **Matches:** only the 7 files FreeDink itself ships under RTsoft's zlib grant:
  six MIDIs in `third_party/freedink-audio-source/dink/Sound/` and
  `game/assets/sound/secret.wav`.
* **Sound history:** one commit ever touched `game/assets/sound`, `caedad9`
  (2026-09-06, tag v0.1.0).
* **Nothing else:** no audio exists outside `game/assets/sound` and
  `third_party/freedink-audio-source`. The installer, `builds/` and
  `OPENING_SOURCE_AUDIO.md` were never committed.

**(b) Published releases.** No original-only sound is present.
* **Assets:** v0.1.0 (published 2026-09-07 03:14Z) and v0.2.0
  (2026-09-08 01:30Z), Linux and Windows. All four zips match the release
  `SHA256SUMS` and the local `builds/` copies.
* **Packs:** each executable embeds a Godot 4.6.1 pack (format v3) with exactly
  39 sounds, all of them FreeDink files.
* **Content classes:** 32 FreeDink, 7 shared, 0 original-only, 0 unknown.
  * **Method:** `tools/audit_release_audio.py` compares against both
    reference sets by content: 8 windows per file, decoded QOA or PCM, and raw
    Vorbis packets.
  * **Controls:** a positive control (the originals imported by Godot) all
    classify as ORIGINAL. Negative controls also pass.
  * **Independent check:** listing the pack paths, and byte-window probes of
    `1.ogg`, `105.ogg` and `106.ogg`, agree.
* **Loose files:** the zips hold `third_party/freedink-audio-source`, 58 audio
  files. All are FreeDink files, shared files or FreeDink source material.
* **Defect:** both releases carry the silent `104.ogg`.

**(c) What a clean remedy needs.**
* **No rewrite or withdrawal:** nothing non-free was published, so history and
  releases need no change for audio.
* **New release assets:** building from this branch fixes the silent Stonebrook
  music and carries the per-file attribution table. The released zips already
  include `licenses/AUDIO-REPLACEMENTS.txt` and the license texts.
* **The real hazard is local:** the uncommitted rework in the main checkout.
  Committing it as it stands would publish 81 non-free or unclear files. The new
  test and the packaging gate now refuse that tree. What to do with the rework is
  Chris's decision.
