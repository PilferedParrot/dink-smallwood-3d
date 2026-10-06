# FreeDink audio source materials

This directory contains the upstream materials needed to modify the FreeDink
audio replacements distributed in `game/assets/sound`.  It was selected from
`freedink-data-1.08.20190120`, not copied as a full data archive.

- `src/5.mid`, `src/7.mid`, `src/12.mid`, `src/18.mid`, `src/104.mid`, and
  `src/105.mid` contain the editable sources for the GPL music replacements.
- The other `src/` directories correspond only to replacement audio files
  shipped by this project.
- `dink/Sound/` contains the original Dink MIDI and effect inputs that this
  project converts or distributes.

`README-REPLACEMENTS.txt` preserves the upstream author, attribution, and
per-file licensing information.  `COPYING` is the GPL-3.0-or-later text used
by the GPL replacement materials.  Original Dink data licensing is retained
in `licenses/FREEDINK-DATA-COPYRIGHT.txt`.

Upstream links to distributed audio have been materialized as regular files so
the source bundle is usable independently on Linux and Windows.

## `src/lovin.mid`: the source video is not redistributed

Upstream ships `src/lovin.mid/Lovin-sLR6RFybiTg.mp4`, the YouTube video from
which FreeDink made `lovin.ogg` (the recipe is under `lovin.mid` in
`README-REPLACEMENTS.txt`). Since 2026-10-06 this project keeps the video's
audio and no longer distributes the video itself.

- Work: "Lovin'" by Gachopin, Copyright (C) 2007, 2012 Gachopin.
- Source: <https://www.youtube.com/watch?v=sLR6RFybiTg>, uploaded 2012-12-08
  by the composer's own channel, gachopin (`@GachopinMusic`).
- License: CC BY 3.0, <https://creativecommons.org/licenses/by/3.0/>, as
  upstream recorded it on retrieval (2014-07-12). On 2026-10-06 YouTube's
  license field for the video still read "Creative Commons Attribution license
  (reuse allowed)".

Why the video was removed: its picture is one still image for the whole
183 seconds. It shows a photograph of a guitarist under the title and the
composer's name, with the watermark "UPLOAD MP3S AT MP32TUBE.COM" of an
MP3-to-YouTube upload service. The composer owns the music. Nothing
establishes who owns the photograph, and a Creative Commons grant covers only
what its licensor holds. The game never used the picture.

What is kept:

- `Lovin-sLR6RFybiTg.m4a` is the video's AAC audio track, copied without
  re-encoding. This is upstream's first conversion step (`-codec:audio copy`),
  kept in an MP4 container:

  ```
  ffmpeg -i Lovin-sLR6RFybiTg.mp4 -map 0:a:0 -c:a copy -map_metadata -1 \
    -map_chapters -1 -fflags +bitexact -flags:a +bitexact Lovin-sLR6RFybiTg.m4a
  ```

  All 7,882 AAC packets match the video's (ffmpeg `framemd5`), the decoded
  audio is identical (MD5 `f277e920eb570e92166e059809d63183`), and the command
  reproduces the file byte for byte (SHA-256
  `0a7dffae6d065d67326486eaae25031a7f0ba00c718b0113b2c90a3be0745a29`).
- `lovin.ogg` is upstream's Ogg Vorbis conversion, unchanged, and is the file
  shipped as `game/assets/sound/lovin.ogg`. Its duration equals the video
  audio's to the microsecond (183.019683 s).

The removed video was 3,069,665 bytes, SHA-256
`67effd6f45162b223c30dde62ded690a2dc7bf732f6d96dec93c75ac4abf7f05`. It is
byte-identical to the copy in Debian's `freedink-data` source package
(1.08.20140901-1 onward). It remains in this repository's history before this
change.
