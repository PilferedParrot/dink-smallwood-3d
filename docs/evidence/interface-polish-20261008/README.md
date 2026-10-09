# Interface polish — 2026-10-08

Local branch `codex/dink-ui-polish-20261008`, based on combined RC `cc381df`. This unit implements the lead’s calibrated findings7,8,9,16 plus accepted title, slider-focus and journal polish. It changes UI/history presentation; world fixes belong to the lead. Public game repository is not pushed.

| Finding | Result and verification |
|---|---|
| Modern HUD label boxes, doubled Life and misplaced values | Original engraved labels remain intact. FreeDink109.6 `src/status.cpp` and original stat-03 art locate stat digits atx81/y15,37,59, coinsx298/y57 and healthx284/y12. Outlined fitted values align with their rows; the lower-right inset holds EXP and level. No bitmap/font was added. |
| Settings dots do not identify state | Text buttons explicitly say On/Off. Actual Return toggles inversion and reduced camera movement in both directions; existing setting keys/signals remain intact. |
| Reticle vanishes against stone | Opaque cream symbol with a complete3px black outline. Sample measurements record contrast, with the text ruler’s irrelevant reticle font-size warning retained. |
| Instructions and chips crowd lower view | First gameplay input begins an eight-second real-time interval; hints fade in its final second. F1 recalls them for eight seconds. Weapon/empty-spell name chips hide with hints; equipped spell readiness remains outlined. Pause/Settings retains the full controller instructions. Menu instructions stay visible. |
| Saved title overflows by a few pixels | Title panel has more vertical space. Default1280×800 title with all five actions/Continue fits without a scrollbar;1920×1080 also checked. |
| Slider focus frame crosses track | Gold corner brackets frame the slider and leave its track/thumb clear. Keyboard/controller adjustment still works. |
| Journal lacks speakers | New `journal_log` string history prefixes known names. Raw `dialogue_log` remains unchanged for campaign/telemetry. Saves include journal history; old saves fall back to their unchanged unattributed lines. Unknown speakers are not invented. |

[Before/after comparison](before-after.jpg), [final1280 export](normal-1280.jpg), [final1920 export](normal-1920.jpg), [130% fixture](large-130.jpg), [narrow Astra integration judgment](integration.md), [measurements](measurements.json), [manifest](manifest.json). Contact sheets are navigation aids; full PNGs were inspected. Comparisons retain the combined RC1 review’s exact frames and the earlier saved-title overflow frame; states/camera positions differ and are not a pixel-diff claim.

Checks:11 focused tests passed in40.01s (`test_game_ui`, `test_fps`, `test_fps_opening_polish`, `test_nut_pickup`, `test_alktree_aftermath`), including actual controller toggle/slider callbacks, title-fit geometry, input-path F1 recall, named-history roundtrip/legacy load, and original campaign strings. After the UI-only real-time timer correction,5 UI checks passed in0.99s; final Linux export succeeds and logs/diff are checked.

The timer’s first revision used simulated frame time; a slow outdoor software capture extended its apparent duration. Final UI deadlines use monotonic real time. Final actual-input captures test initial hints → movement → hidden → F1 recalled → hidden. The engine test advances the deadline directly for deterministic expiration, explicitly skipping elapsed waiting; real exports supply the elapsed-time evidence.

All captures isolate XDG saves/settings/cache/logs, own their Xvfb display, use dummy audio and capped/throttled software GL. Normal exports start a new adventure and execute the opening dialogue before navigating/ saving through actual keys. The130% pig-farm fixture injects a prior staged save and settings, skips campaign/map startup and proves UI layout/input only. It does not certify ordinary outdoor progression.

Astra’s bounded integration judgment accepts the engraved HUD, value fit, toggle states, saved title, slider focus and journal/equipment layouts. It is not another calibrated/blind round. Captures do not certify real controller hardware, performance, audio, every texture/background, entire campaign or all numeric extremes. Fitted text in the original artwork caps enlargement for long/large values. Original stylised engravings remain; their patterned contrast is not claimed to meet every accessibility threshold. No observed residual default-size clipping in this scope;130% scrolling is intentional with heading/Back pinned.

Final contrast samples: reticle12.31:1 on the interior wall and10.98:1 outdoors (non-text threshold3:1); life count7.97:1, EXP count9.90:1. The EXP digit-only ink-height measurement17.6px at1080p is a borderline text-size flag retained in the measurement record; this is not an accessibility certification.

The UI-test wrapper now automatically isolates engine data/config/cache per test. Two engine-generated world-script UID sidecars remain untracked and were preserved outside this unit’s commit scope.
