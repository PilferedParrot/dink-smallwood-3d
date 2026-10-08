# Interface verification — 2026-10-07

As of 2026-10-07: this unit restores the original wooden title logo, stone status bar, equipment chest, marble and vines. Dink lead Claude Opus 5.5 accepted the direction and boundaries. GPT-6 Astra reviewed the plan, integrated presentation and two new lower-world conditions; a separate blind Astra played the export for 25 decisions. The lead integrates this local branch into the one build Chris plays; this unit does not publish or install a separate player build.

- [Before/after](before-after.jpg): title, HUD, dialogue, equipment, pause and settings at 1280×800. Original build is base `43f6eec` (0.3.0), exported separately.
- [Widescreen](widescreen.jpg): normal opening/menu input at 1920×1080. Expand aspect removes the old96-pixel pillarboxes: old left-strip mean RGB was `(0,0,0)`; the new strip contains scene pixels.
- [130% text](text-130.jpg), [85% text](text-85.jpg): title, settings and keyboard navigation to the lower controls/Done. Scroll overflow is intentional; heading and primary action remain visible on entry. These geometry captures precede the final music-step correction; the final settings frame in the before/after sheet shows55%, matching the audio default.
- [Blind player](blind-player.jpg): first-time review before its fixes. Raw report, input log, full PNGs and contrast measurements remain under `builds/interface-evidence/blind-review/`.
- [Pickup fixture](pickup-fixture.jpg): explicit staged map407 save, injected feed/heart, fixed camera, frozen surrounding actors, skipped campaign/map startup. Original heart main/touch execute. Actual W input approaches the visible pickup, collects it and saves life10 after starting at5. Astra accepted the dock's visibility in this view; the heart's foreshortening/held-bag overlap remain world/viewmodel limits.
- [Manifest](manifest.json): final and blind export hashes, selected model/effort and verification scope. Provider token totals were unavailable and were not estimated.

## Findings and decisions

| Finding | Decision / actual verification |
|---|---|
| Generic interface unlike Dink | Original artwork reused at its intended proportions, direct labels, state-specific hints; Astra judged it recognizably Dink. No new font/art asset. |
| Bow appeared as a red potion | Audited fallback icons against original campaign registrations; bow is `item-w08`, feed `item-w02`. Exact-icon regression and exported frames checked. |
| Enlarged-text menus entered below heading/Return | Reset scrolling after layout/deferred focus; regression checks and actual pause/settings frames show both. |
| Journal Esc Back resumed gameplay | Preserve parent menu; existing pause/title/resume signals route cancel. Actual journal→Esc→pause captured. Standalone equipment/pause still resume with matching cues. |
| Toast lost contrast over tan wall (~3.2:1 in blind review) | Solid dark backing and border. Actual map/gear feedback frames inspected; no broad accessibility certification inferred. |
| Sliders lacked values / music default rounded55→60 | Numeric readouts, explicit slider focus, music step5% preserves55% default. Controller/default/readout checks pass. |
| Title advertised controller-only cues | Keyboard/mouse default; switch on actual input. Gamepad navigation remains tested. |
| Zero magic cost falsely displayed Ready | Align recharge text with casting guard; show no-spell/recharge/ready and magic controls when equipped. |
| Location lost in new HUD | Restored compact location label above scene. |
| E aimed at Mother initially selected fireplace | Queued to Dink lead with blind frames07–09. Target/range cue and selection behavior require gameplay/world integration; no stuck-player claim. |

## Checks and limits

Final isolated run: **13 passed** (`test_game_ui.py`, `test_fps.py`, `test_fps_opening_polish.py`, `test_fps_grief_presentation.py`, `test_playtest_restart.py`). Additional isolated UI/FPS checks passed after aspect changes; final music/default UI checks also passed. `git diff --check`, Python compilation and Linux release export succeeded. The older FPS test wrapper inherited the default XDG directory; it now isolates data/config/cache, and final checks were rerun with isolated outer paths as well. All exported playtests/reviewer profiles were isolated throughout.

Full frames and logs live in `builds/interface-evidence/`. Normal opening/menu captures exercise exported keyboard input. Rendering is software, throttled30FPS, nice10, six-core affinity with two llvmpipe threads; it does not certify GPU performance. Camera/text-size fixtures are distinguished from ordinary progression. A held mouse press executed the real feed use script, confirmed by saved `item-pig:1` locals (`basehit528`, `dir8`, `mholdx328`, `mholdy260`, runtime `junk92`). Astra accepted the staged feed view's dock geometry. Grain appearance remains inconclusive; we do not claim that the before/after grain pixels prove successful scattering.

Whole-frame OCR missed readable marble text and sometimes merged words. Those are harness false negatives. Final captures disable that unreliable gate and have their actual page images inspected. Brief synthetic clicks also disappeared between frames in the polled attack path; the capture tool now holds mouse input through frames. Fixture generation exits successfully but emits existing dummy-renderer resource-teardown warnings; the actual export logs have no script/runtime errors.

The blind rubric is Pinelle, Wong & Stach, *Heuristic Evaluation for Games: Usability Principles for Video Game Design*, CHI2008, [DOI10.1145/1357054.1357282](https://doi.org/10.1145/1357054.1357282), read from the local research PDF. Its ten heuristics assess usability, not artwork, entertainment or story. No research PDF is shipped. Every recorded interface issue was fixed or queued with its reason; no whole-game/ordinary-outdoor-progression, audio, hardware-controller or all-angle certification is claimed.

To reproduce captures, use `tools/ui_capture.py` with the export and an output folder. `--no-page-assertions` requires visual confirmation of each intended page. `tools/ui_fixture.gd` creates explicitly staged feed/pickup saves; pass `--pickup` for a heart, then give the export capture an explicit `--save-source`. Do not point tests or fixtures at the player's profile.
