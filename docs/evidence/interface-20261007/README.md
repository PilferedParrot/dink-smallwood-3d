# Interface verification — 2026-10-07

As of 2026-10-07: this unit restores the original wooden title logo, stone status bar, equipment chest, dark choice-panel texture and vines. Dink lead Claude Opus 5.5 accepted the direction and boundaries. GPT-6 Astra reviewed the plan, integrated presentation and two new lower-world conditions; a separate blind Astra played the export for 25 decisions. The lead integrates this local branch into the one build Chris plays; this unit does not publish or install a separate player build.

- [Before/after](before-after.jpg): title, HUD, dialogue, equipment, pause and settings at 1280×800. Original build is base `43f6eec` (0.3.0), exported separately.
- [Widescreen](widescreen.jpg): normal opening/menu input at 1920×1080. Expand aspect removes the old96-pixel pillarboxes: old left-strip mean RGB was `(0,0,0)`; the new strip contains scene pixels.
- [130% text](text-130.jpg), [85% text](text-85.jpg): title, settings and keyboard navigation to the lower controls/Done. Scroll overflow is intentional; heading and primary action remain visible on entry. These are final settings geometry frames, including pinned headings and the55% music default. The manifest distinguishes their export hash from the last HUD-only label-fit correction.
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

The lead's accepted widescreen follow-up is verified: the actual FPS camera uses `KEEP_HEIGHT`. An isolated engine regression resizes1280×800→1920×1080, confirms unchanged vertical projection and wider horizontal projection, then restores the window; **1 passed**. HUD anchors at both resolutions were inspected in the export frames.

Whole-frame OCR missed readable textured text and sometimes merged words. Those are harness false negatives. Final captures disable that unreliable gate and have their actual page images inspected. Brief synthetic clicks also disappeared between frames in the polled attack path; the capture tool now holds mouse input through frames. Fixture generation exits successfully but emits existing dummy-renderer resource-teardown warnings; the actual export logs have no script/runtime errors.

The blind rubric is Pinelle, Wong & Stach, *Heuristic Evaluation for Games: Usability Principles for Video Game Design*, CHI2008, [DOI10.1145/1357054.1357282](https://doi.org/10.1145/1357054.1357282), read from the local research PDF. Its ten heuristics assess usability, not artwork, entertainment or story. No research PDF is shipped. Every recorded interface issue was fixed or queued with its reason; no whole-game/ordinary-outdoor-progression, audio, hardware-controller or all-angle certification is claimed.

To reproduce captures, use `tools/ui_capture.py` with the export and an output folder. `--no-page-assertions` requires visual confirmation of each intended page. `tools/ui_fixture.gd` creates explicitly staged feed/pickup saves; pass `--pickup` for a heart, then give the export capture an explicit `--save-source`. Do not point tests or fixtures at the player's profile.

## Accepted follow-up and fresh frame panel

Four fresh independent lenses reviewed nine full1280×800 export frames without source or peer findings. These are a frame panel, distinct from the earlier actual-input blind player round. Reports: [first-time player](first-time-player.md), [visual critic](visual-critic.md), [accessibility](accessibility.md), [Chris proxy](chris-proxy.md). Model labels inside reports are self-reports; the manifest records the requested worker model/effort.

| Panel finding (including repeated findings) | Decision |
|---|---|
| Gameplay Esc hint2.96:1 against hand (blocks play) | Fixed: opaque dark plaque; actual exported measurement recorded in contrast.json. |
| Baked Attack/Defense/Magic/Life labels near4.2:1 | Fixed: dark plaques and readable cream labels; ornaments/art remain outside exact label regions. Dynamic numeric values also gained backing after a4.44:1 life-number measurement. |
| Small HUD tags/numbers, equipment E and footer | Fixed: HUD14/15 native font units, E18, footer20; text-size setting still deliberately supports85%, which is not certified as meeting every minimum-size reference. |
| Small release version | Fixed:18 instead of16. |
| Generic flat buttons around original art | Fixed: original chest recess used as a texture style with a separate visible focus border; no new bitmap/font. The final follow-up composition is checked in actual export frames. |
| Visible scene texture through dialogue/settings/journal | Fixed: opaque panel underlay beneath original dark dither. |
| Vines stop midway through actions; title right vine clipped | Fixed: intentional small header ornaments on modal sides, removed from original-black title. Proportions preserved. |
| Equipment controller(Select) wraps alone | Fixed: Equipment bindings start their own line. |
| Slider footer gives no adjustment cue | Fixed: settings footer explicitly says Left/right Adjust. |
| Raw mouse sensitivity0.0020 | Fixed:1.00× relative to the actual default; stored value unchanged. |
| Journal has no speaker attribution (all three content/style lenses) | Queued to gameplay lead: saved history contains plain rendered strings; UI cannot recover missing speakers honestly. Existing saves remain compatible. This is polish, not a blocker. |

The follow-up also checks saved-feedback→settings (no stale message), focus on equipment Back, full Pig feed name, and map feedback. Page headings and primary return/continue actions are pinned while content scrolls. Capture fixtures explicitly skip progression; they do not certify campaign scripting.

Measured follow-up samples: [contrast.json](contrast.json), with actual crop geometry and limits. Settings control text is17.66:1 at85%/130%, gameplay EscPause15.54:1, Defense and life numeric14.39:1. These clear the sampled defect; they do not certify every font/glyph/background. The final backing/header-only revision passes5 UI tests; the preceding full follow-up run passes13 focused tests in60.60s. Original engine reference inspected: GNU FreeDink109.6 `src/game_choice_renderer.cpp`, `inventory.cpp`, and original `Story/START.c`; no engine source was copied.

Boundary evidence includes a harness correction: the original three-Tab “equipment-back-focused” filename actually selects Bow after cycling. It is not evidence of a Back failure. The corrected one-Tab sequence is in `release-equipment-back/`; the engine test also focuses the fixed Back explicitly.

[Bounded Astra integration review](integration.md) accepts the original-material buttons, opaque reading surfaces, visible focus and layouts. The lead directly checked the later small header ornaments/numeric backing, then constrained enlarged HUD labels to their existing value columns and abbreviated the EXP tag to keep its numbers visible. Tiny toggle-state indicators remain a polish item for the combined RC's already planned input review; their on/off recognition was not demonstrated in this frame pass.

[130% equipment/Back and HUD](equipment-130.jpg): corrected one-Tab actual-input capture confirms visible fixed Back, full Pig feed name and Enter returning to gameplay. The final enlarged HUD keeps Defense separate from its value and the full EXP count visible.
