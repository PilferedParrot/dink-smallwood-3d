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

The 39 shipped files, classified by content:

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

## Sounds FreeDink has no replacement for (silent, flagged)

The campaign data references these original files, and FreeDink ships no free
version. The original is **not** kept. The cue stays silent, which is what
FreeDink itself does.

* **Sound effects: 27 files, 28 slots.** `quack` (1), `pig1`–`pig4` (2–5),
  `select` (11), `picker` (13), `escape` (18), `sel2` (20), `sel3` (21),
  `spell1` (24), `caveent` (25, 32), `snarl1`–`snarl3` (26–28), `hurt1`,
  `hurt2` (29, 30), `attack1` (31), `level` (33), `splash` (35), `sword1` (36),
  `squish` (38), `steps` (40), `flyby` (42), `knock` (45), `drag1`, `drag2`
  (46, 47).
* **Music cues: 9 by name, plus the CD tracks with no file.** Screen music `100`,
  `101`, `102`, `103`, `107`, and `playmidi` `battle`, `bullythe`, `caveexpl`,
  `wanderer`. The CD-track cues (`1000+N`, see Observations) whose `N` has no
  shipped file are silent too: screen music `1008`, `1010`, `1016` and `playmidi`
  `1004`, `1006`, `1009`, `1011`, `1015`. `_play_music` leaves the current track
  playing, as before.

The v1.08 installer holds 13 more original files that no cue names directly:
`bird2`, `click`, `high1`, `ocean1`, `pop`, `splash.aif`, and the MIDIs `4`,
`6`, `9`, `10`, `11`, `16` and `neighbor`. They are not shipped, and FreeDink has
no replacement for them. The CD-track cues `1004` to `1016` reach `4`, `6`,
`9`, `10`, `11` and `16` through the mapping below, and find no file.

**Proposal:** keep these silent, as they are now. The audible gaps are the pig
grunts in the opening pigpen, Dink's hurt sounds, the sword hit, menu select and
level-up. Filling them with CC0 sounds is a separate step, and it needs Chris's
ear. freedink-data 1.08.20190120 is the newest release (ftp.gnu.org/gnu/freedink),
so there is no newer FreeDink replacement to take.

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

* `python3 tools/audio_provenance.py` passes: 39 files match
  `AUDIO-FILES.tsv` and the installed FreeDink data. Two negative controls
  fail as they should:
  * **The local v1.08 rework folder:** 49 files unlisted and 38 hash mismatches,
    one of them its own empty `lovin.ogg` render.
  * **The pre-fix `104.ogg`:** "0.0015 s of audio; the render is empty".
* The headless Godot import produces 39 audio resources, with no import errors.
* `tests/audio_cues_test.gd` runs the real game class headless. Through the
  game's own `_play_sound` and `_play_music`:
  * **Loaded:** all 39 shipped sounds.
  * **Played:** 21 sound slots, 9 of the 18 screen music ids (loaded through
    the game's own `load_map`) and 8 of the 17 `playmidi` names.
  * **Missing:** exactly the 27 FreeDink effect gaps, and the silent music ids
    listed above. With the old `104.ogg` swapped back in, the test fails.
  * **CD-track ids:** the test asserts each screen id's file (`1002` to `2.ogg`,
    `1005` to `5.ogg`, `1007` to `7.ogg`, `1012` to `12.ogg`, `1013` to
    `13.ogg`), and that a silent screen leaves the track playing. It fails on
    the code before the mapping.
* Per-file stats, from ffprobe and ffmpeg `ebur128=peak=true`:

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
