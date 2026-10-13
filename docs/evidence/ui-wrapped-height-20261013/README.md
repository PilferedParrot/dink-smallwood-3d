# Notification plaque height diagnosis — 2026-10-13

The gold-bordered, almost empty card in the Linux and Windows `--capture` frames is `GameUI.toast_backing`, displaying the starter-bow notification. It is not the opening dialogue panel: `--capture` sets `test_mode`, and the FPS dialogue host records/advances blocking lines without displaying their card in that mode. Cancelling an opening dialogue card therefore cannot explain this captured plaque. A rendered Linux source probe measured its rectangle as 819.2 × 1309 pixels at (230.4, 65), despite its current combined minimum being only 33 × 51 pixels and its Label minimum being 1 × 31 pixels. The viewport was 1280 × 800.

The notification can be laid out while the UI has almost no available width during early startup. The wrapped Label temporarily demands a very tall container. Once width settles, the minimum height falls, but the top-level PanelContainer keeps its already enlarged size. Waiting for a process frame before starting the new-game fixture gives a 51-pixel plaque instead. The capture fixture starts immediately and exposes this ordering.

The technical cause is missing height ownership for a top-level wrapped notification. The reasoning cause is an oversight: UI checks asserted notification visibility/contrast, but did not measure its backing after text or width changes, and did not inspect early-startup capture output. RC4's dialogue sizing change covered the speech panel only. Treating a smaller content minimum as automatic container shrinking was the mistaken assumption; an anchored top-level container needs explicit height sizing.

## Prior art

Godot's [Control documentation](https://docs.godotengine.org/en/4.6/classes/class_control.html#class-control-method-reset-size) describes resetting a control to its combined minimum. [Label documentation](https://docs.godotengine.org/en/4.6/classes/class_label.html#class-label-property-autowrap-mode) explains the width-dependent wrapped height. Godot's [existing PanelContainer shrink report](https://github.com/godotengine/godot/issues/100626) independently records a related grow-without-shrink case; it is supporting prior art, not evidence of this game's state. The fix uses the native size/offset contract, retains the anchored notification width, and assigns height from the current combined minimum.

The scoped OpenAlex query for game UI heuristics found “Game User-Interface Guidelines: Creating a set of Usability Design Guidelines for the FPS Game User-Interface” and “Usable Usability Heuristics for Game Developers”; neither supplies a Godot layout mechanism. The repository's accepted `docs/INTERFACE_DIRECTION.md`, existing UI controller/feedback checks, and engine documentation are the applicable sources here. No new artwork, layout framework, or dependency is needed in the game.

## Reachability and input evidence

Local evidence is in `tmp/rc5-card-pack/`; no temporary artifacts are committed. `baseline-verified/steps.json` and its individually named PNGs record a replay of the existing exported Linux build at 1280 × 800, using actual X11 keyboard input and an isolated profile, Dummy audio and llvmpipe.

- Title → Begin adventure → Mother's “Dink, would you go feed the pigs?” → Escape: the dialogue remains on screen. Blocking dialogue deliberately ignores pause, so the requested pause/title and pause/load paths *during that line* are unavailable to the player.
- Three actual Enter presses complete the authored opening. Escape then opens pause; Down/Enter saves normally. Seven more Down presses select Title screen. The saved title is visible, and Down/Enter begins a fresh adventure. Its three opening lines again complete normally.
- Escape/Down/Down/Enter selects Load saved adventure. The saved game returns with normal HUD and no oversized plaque.

The observed startup bow notification is a thin strip on the normal input path. These runs establish those paths only, not absence of the defect in every possible state. The early-capture fixture reaches the stretched state reproducibly. The input-driven regression also covers a live notification → pause → title → fresh new game, and text replacement and resizing; it labels its source-dialogue bypass explicitly.

Two initial export harness attempts were inconclusive: one acted during startup, and one used OCR segmentation that missed Continue against its textured focused button. They are preserved in `baseline/` and `baseline-input/`, classified as harness failures, and were reported to the lead. The completed baseline run uses sparse-text OCR for Continue. A final-export attempt showed that this remains unreliable; its `fixed-input/` frames are also classified as a harness failure. The completed final-export run in `fixed-input-verified/` waits for each of the three authored line texts and sends one Enter per verified line. It preserves every waiting frame rather than overwriting evidence.

## Wrapped container inventory

`game_ui.gd` has these owners:

| Wrapped content | Container and existing layout owner |
| --- | --- |
| Gameplay/menu control hint Label | `hint_backing`; `_process` assigns top and bottom offsets from content every frame |
| Notification Label | `toast_backing`; missing height owner, fixed by assigning its current combined minimum height |
| Dialogue Label / choice Buttons | `panel` with `menu_scroll` and `column`; `_fit_dialogue_panel` assigns content height up to the 35% cap |
| Menu heading, menu Labels and Buttons, equipment selected-name Label | `panel` with pinned chrome and `menu_scroll`; `_layout_for` assigns the designed menu rectangle and the body scrolls |
| Modal notification feedback | `modal_feedback`; its Label clips one line, does not wrap, and occupies the heading row |

Menus intentionally occupy their designed menu area; shrinking them to bare content minimum would remove scrolling space. The regression checks their height is unchanged after long journal content and equipment descriptions. Hints, speech/choices, and notifications are checked after width and text-size changes. Existing `cancel_speech` closes dialogue and its underlay; the input replay gives no basis for adding a new VM cancellation mechanism.

## Verification

- Before the fix, the startup pixel regression failed on `eb90e43`: the contiguous gold border ran from y=65 to the bottom of the 800-pixel frame. The rendered source probe independently measured the full retained height as 1309 pixels. The original two-test run was one failure / one pass in 124.86 seconds; `tmp/rc5-card-pack/red.log` preserves it.
- The original focused set passed all 9 tests in 23.20 seconds. The blind Claude review `review-20261013T080449-22aaaf53` agreed with the cause and fix and requested stronger instruments. Geometry now compares plaque height to line metrics plus theme margins rather than to the production sizing expression. The pixel test finds four complete gold border edges without fixed coordinates, then bounds height by glyph ink, font whitespace and the notification's own margins.
- Linux export succeeds. Its inspected `capture-fixed-export.png` shows the plaque at y=65..115, a 51-pixel height, with the world and HUD exposed. Export SHA-256: `16a0435801f7f9223b40f9141085aab8b3be5be19efac032fb6dbd14ff65954b`.
- `fixed-input-verified/steps.json` and PNGs complete the same normal-input save/title/restart/load flow on the fixed export. They also confirm Escape leaves the blocking opening dialogue on screen.
- The tightened final pixel regression is red on the historical `eb90e43` UI: no complete four-edge plaque rectangle fits inside the frame (1 failed in 8.11 seconds). `tmp/rc5-card-pack/tightened-red-eb90e43.log` preserves this run. The historical project copies the unchanged scripts and replaces only `game_ui.gd` with `git show eb90e43:game/scripts/game_ui.gd`; assets/data/imports are reused locally.
- Final full suite: **202 passed in 1763.40 seconds (29:23)**, with `DINK_REQUIRE_GODOT=1`, isolated native profiles and software rendering. Both tightened regressions passed in that suite. Log: `tmp/rc5-card-pack/full-suite.log`. The named service `dink-card-suite-20261013T0810` ended inactive with `Result=success` and `ExecMainStatus=0`; no job remains running. `git diff --check` passes. No push or publication occurred.

The height owner updates once per UI process. A width/text change can leave one layout frame using the preceding wrap metrics before container layout settles; these tests wait six process frames, and the capture check uses the game's actual capture timing. They verify settled geometry and startup capture, not the absence of every transient frame. The geometry fixture intentionally bypasses story dialogue; normal progression is evidenced by the separate exported replay. Notifications are bounded by their content; dialogue/choices have the existing 35% cap. Arbitrarily long notification text is not newly truncated or given a dialogue scroll panel by this fix.
