# Neighbour startup load measurements — 2026-10-02

`tests/fps_perf.gd` loaded 439, 440 and 505 with the current screen's scripts
disabled. The first-person world still built its 5×5 block, including neighbour
startup predictions in the new checkout. Three repeats alternated the unchanged
`claude/dink-tenth-pass` checkout (`f7d02f1`) and `sol/neighbour-scripts` for
each screen. Every process had private XDG data/config/cache, Dummy audio,
Xvfb at 960×540, and `/dev/input` masked by bubblewrap. Each measured load
followed the probe's new-game setup. The raw result of every run is in
`neighbour-perf-raw.txt`.

| Screen | Old load ms: median (range) | New load ms: median (range) | Old/new frame p50 median ms |
| --- | ---: | ---: | ---: |
| 439 | 166.6 (154.7–283.6) | 151.6 (122.6–238.9) | 30.0 / 33.0 |
| 440 | 242.6 (130.9–442.4) | 235.4 (222.1–244.0) | 31.4 / 35.6 |
| 505 | 443.3 (436.7–718.3) | 313.9 (285.5–358.7) | 28.7 / 26.4 |

The machine was shared with other Godot jobs, and llvmpipe measures relative
software-renderer behavior only. The spread is large enough that 439 and 440
do not establish a load-time change. The measured 505 loads were lower in all
three pairs, but this probe does not isolate the sandbox from other scene and
asset-cache work. The frame medians likewise do not certify real GPU frame
time or player experience.
