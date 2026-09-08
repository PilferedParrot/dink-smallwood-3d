# Opening adventure verification — September 7, 2026

The opening adventure passes a continuous rendered campaign run using normal
inputs, with isolated saves. This is an opening milestone, not a finished game
or a complete campaign certification.

## Changes

- Added `--mode campaign` to the existing playtest runner and a bounded route in
  `tools/playtest_campaign.py`. It starts through the title menu and exercises
  normal dialogue, movement, equipment selection, transitions, and DinkC scripts.
- Added read-only campaign/UI telemetry, bounded wait/menu commands, action and
  response traces, retained isolated saves, and expected menu-exit handling.
- Fixed an actual entrance defect: `fp_world.gd` added solid collision to fence
  artwork with Dink's non-solid `hard=1` flag. Those sections now show an open
  entrance. Solid `hard=0` fences and their projectile collision remain intact.
- Fixed structural deduplication during save/load: replacement walls, cottages,
  and towers are now suppressed only when an actual live original still exists.
  Previously a stale fingerprint removed their models and colliders after load.
- Added focused gate and repeated structural reload regressions alongside the
  existing pigpen fence and embedded-arrival recovery regression. Campaign
  telemetry also compares structural model/body counts before and after loading.
- Headless mouse look now rejects unsupported capture instead of claiming a
  successful turn. The bridge's idle polling no longer leaves a SceneTreeTimer
  alive when exiting through the menu.

## Verified evidence

The final acceptance report is `builds/playtests/opening-complete/report.json`: **480 actions, pass**.
Its independent assertion/log/hash review is `builds/playtests/opening-complete/review.json`.
The session and screenshots are in
`builds/playtests/opening-complete/report.session/session-c1jcemyu/`.
All 18 interior wall models and their colliders remain after loading; Astra
inspected the matching `before-save.png` and `save-reload.png` renders.
It adds structural geometry assertions and before/after load screenshots to the
normal-input route. Earlier runs `campaign-full4` (477 actions) and
`opening-verified` (478 actions) passed their state/input assertions, but Astra's
screenshot review found missing walls after reload. Those earlier results are
superseded for save/load visual correctness by the final run.

| Check | Observed result |
| --- | --- |
| Title → Begin adventure | Normal focused-button input, new isolated profile |
| Opening conversation | All three original lines; `story=1`; controls released |
| Feed pickup | Walking to the sack grants `item-pig`; original touch script runs |
| Cottage → farm | Normal door/edge transitions: 1 → 439 → 407 |
| Pig feeding and Milder | Equipment menu and use input; all dialogue/scripts complete; `pig_story=1`; controls released |
| Return home | 407 → 439 → 1; normal talk with moving Mother, fed-pigs choice and both completion lines |
| Save/load | Save through pause UI, move away, load through UI; position, inventory, `pig_story`, structural models and colliders restored |
| Pause/resume | Pause page stays open; attempted movement has zero displacement; resuming restores movement |
| Exit | Pause → Title screen → Quit; process exit code 0 |

The retained save is inside the session's `xdg/data/godot/app_userdata/Dink
Smallwood 3D/` directory, separate from the player's profile. For example, the
earlier state/input pass stores map 1, `pig_story=1`, position `(222.107,183.409)`, and
Fists/Bow/Pig feed. Movement after saving changes position to `(218.892,197.035)`;
loading restores the saved position exactly. The pause movement attempt retains
the saved position, and movement after resuming reaches `(218.892,197.035)`.

Astra inspected rendered title, opening conversation, feed pickup, farm/feeding,
actual Milder dialogue, home conversation, and pause screenshots. A separate
focused render at `builds/playtests/gate-visual/session-orp4gb72/open-gate.png`
shows the restored entrance. That focused setup is visual/collision evidence,
not campaign-completion evidence.

Validation: the final full pytest suite passed **40 tests in 53.44 seconds**,
including the new repeated structural reload test. The isolated
engine smoke test exited 0 with `SMOKE PASS`; logs are in
`builds/playtests/opening-smoke/godot.log`.

## Failures and their classification

- **Game defect, fixed:** the non-solid entrance fence acquired a solid 3D
  collider. Normal campaign movement stopped at map407 `(110,381.25)` even
  though the source fence and terrain allow passage. The solid fence at x320
  remains a negative control.
- **Game defect, fixed:** save/load rebuilt structural visuals while retaining
  stale deduplication fingerprints. State assertions passed but screenshots
  showed missing walls. The renderer now tracks live originals; focused repeated
  loads and the campaign compare actual structural models/colliders.
- **Bot mistakes, corrected:** retaining a fictitious position after several
  live movement probes, aiming at blocked waypoints, confusing a door's arrival
  point with its entrance, expecting the wrong completion wording, and aiming
  at Mother's original position after she moved. These did not establish game
  bugs. Earlier reports labeled some failures `game suspected`; this review
  supersedes those labels where the traces demonstrate bot errors.
- **Harness defect, fixed:** headless mouse look returned success without
  rotation. Full route acceptance uses rendered/captured mouse input.
- **Harness cleanup, fixed:** an idle SceneTreeTimer caused an ObjectDB shutdown
  warning. Normal title Quit now exits without that warning.
- **Remaining renderer diagnostics:** two 349,524-byte GL texture teardown
  errors reproduce under Mesa/llvmpipe even in a direct title-only game launch.
  Xvfb also reports input-method/V-sync limitations. These are retained in logs;
  the passing route has no GDScript errors and exits 0. Their relevance to native
  GPU play has not been established.

## Local model usage

The bounded Qwen mobility probe completed three requests: 155, 189, and 204
server-reported tokens, **548 total**, with **10.858 seconds** total inference
latency. The endpoint identified `Qwen3-Coder-Next-UD-Q4_K_XL.gguf`. Its report is
`builds/playtests/opening-qwen-final/report.json`. A prior endpoint attempt was
refused, and another attempt hit a bridge parse error during editing; neither
produced a completed model response. This was focused mobility/menu evidence,
not full campaign evidence. The owned local server was stopped after use.

## Remaining scope and player-facing limitations

The opening remains visually rough: feed uses the generic fist view and glowing
effect, and Milder can speak outside the player's view while dialogue captures
controls. Some close-up scenery is oversized. These do not prevent the verified
opening progression. Later quests, death/restart, fresh-process Continue,
real-time timing/audio, and native GPU performance were not certified here.

Run the updated checkout with `./play.sh`. Existing packaged executables were
not rebuilt. See [NEXT_SESSION.md](NEXT_SESSION.md) for the proposed continuation
and decisions to review.
