# Neighbour startup checks — 2026-10-02

Rendered runs used Xvfb with `/dev/input` masked by bubblewrap and Dummy
audio. The standalone neighbour probes used private XDG data/config/cache.
The **final full suite** was also launched with private XDG roots around the
whole pytest process, covering older test wrappers that do not set them.

- Unchanged `f7d02f1` checkout: `.venv/bin/python -m pytest -q tests` under
  bubblewrap/Xvfb: **95 passed, 1 skipped in 358.18 s**.
- `sol/neighbour-scripts` checkout after the background-frame correction:
  the first full suite: **98 passed, 1 skipped in 550.15 s**. It inherited XDG
  for some older wrappers; see the profile note below.
- Final rerun with outer private XDG roots
  (`/tmp/dink-neighbour-suite-xiKmkX`): **98 passed, 1 skipped in 575.12 s**.
- `tests/test_fps_neighbor_startup.py` and
  `tests/test_fps_neighbor_crossing.py`: **2 passed in 29.78 s** in a focused
  run. The first checks the editor-only red controls and full 5×5 build's
  live-state isolation. The second presses the W key to cross 439→440 with a
  scenario setup for the duck quest, confirming preview random replay.
- `tests/fps_neighbor_startup_survey.gd` directly under headless Godot:
  **570 outdoor screens × 4 story setups, exit 0, no unclassified mismatch**.
  The per-screen record is `neighbour-startup-survey.jsonl`. The standalone
  full survey printed an `ObjectDB instances leaked at exit` warning after
  its pass line; the five-screen smoke run did not. Its cause is unresolved.
- `tools/view_sheet.py` captured the same three boundaries in `f7d02f1` and
  the final checkout. The final search rows were pixel-identical to the
  previous render after the last frame-key correction; the combined final
  sheet was opened and inspected at its 1600 × 1368 resolution.

The survey is a headless state comparison. The sheet samples visible output;
the W-key test exercises one real boundary crossing. These checks do not prove
that every animated or future post-cut state is visually correct.

**Profile note.** The initial baseline and broad suite were run without an
outer XDG override. Several older wrappers inherited the player's Godot data
directory, contrary to the plan. A read-only check found the player's
`settings.json` still dated September 7 and no `adventure.json` there; Godot
log files were written/rotated around 01:02–01:04 CDT on October 2. Those
logs were left untouched. This is a harness isolation error, not a game
failure. After the private-XDG rerun, a second metadata check found the
player settings and those log timestamps unchanged, with no adventure save
present in that profile.
