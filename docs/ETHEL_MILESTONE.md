# Ethel quest session — September 7, 2026

**The full rendered Begin-adventure route passes: 1,262 commands**, including
Ethel's request, Quackers returning alive, Ethel's acknowledgment, all six lines
of Mother's next request, save/load, pause/resume, and normal menu Quit. This is
a campaign milestone, not full-game completion. Mother's model remains obscured
by doorway scenery during the new conversation; her dialogue is readable.

Authoritative acceptance: `builds/playtests/ethel-complete/report.json` and
its independent state, dialogue-order, log, screenshot, and hash review at
`builds/playtests/ethel-complete/review.json`. Rendered captures and the earned
save are in `builds/playtests/ethel-complete/report.session/session-u9_10c8c/`.

```sh
xvfb-run -a python3 tools/playtest.py --mode campaign --milestone ethel \
  --rendered --max-commands 3500 --report builds/playtests/ethel/report.json
```

## Campaign prerequisites

The installed original DinkC sources establish this route:

1. Feed the pigs and finish Mother's fed-pigs conversation.
2. Visit Ethel on interior map 2, choose **Ask after her pet**, then
   **Agree whole heartedly**. `S1-H2-O.c` sets `old_womans_duck=1`.
3. Search maps 440 and 441. Their original `FINDDUCK.c` script rolls on map
   entry; a successful roll selects vision 2 and reveals Quackers.
4. Talk to the live duck and choose **Yell at it**. `S1-OLDD.c` sends him home
   alive and sets `old_womans_duck=2`. The gentler first choice does not advance
   the original quest.
5. Reenter Ethel's house. Her startup acknowledges the duck and sets the state
   to 4; the interior startup selects the returned duck's vision.
6. Return home with `pig_story=1`. Mother's **startup** sets `story=2` and asks
   for AlkTree nuts. This is automatic dialogue, not a new talk-menu choice.
   Completion requires the final “You're a dear” line and released controls;
   the early `story=2` assignment alone is insufficient evidence.

## Game changes

- Fixed the Map.dat screen-script offset: 30240, immediately after the complete
  sprite table, instead of 30204. Updated only screen-level script fields in the
  existing imported world; 76 nonempty scripts now match the installed source.
  Leading NUL bytes remain empty C strings. The residual `indduck` bytes on map
  409 are cleared data, not a script to repair or run.
- Run a screen's immediate startup instructions before filtering editor sprites
  by vision. Normal transitions reset vision for the incoming map; save
  reconstruction retains saved vision and skips startup.
- Preserve visuals created by screen scripts and start only editor-sprite main
  procedures in the deferred startup pass. Runtime sprites already start their
  scripts through `sp_script`; starting them twice duplicates behavior.
- Repair the exact premature closing brace in the original `S1-H2-O.c` source.
  It had stranded the final unfreeze commands in an unused top-level block,
  leaving Dink frozen after either agreement. The compiler records this one
  script-specific repair, preserves source line numbers and dialogue overrides,
  and keeps the original unfreeze commands inside `talk`. Other top-level code
  is unaffected. The original compiled script fails all four release assertions
  in the focused regression; the repaired script passes both agreement paths.
- Pig feed has a visible labeled sack, use motion, and non-solid grain geometry
  for the original short-lived seed effect. The original item script still
  decides whether feeding advances the quest.
- NPC dialogue frames the actual speaker when its line begins, including
  vertical aim, and labels opening characters by name. Queued lines do not move
  the camera early, and Dink's own lines keep the current view.

## Verification

| Final check | Evidence |
| --- | --- |
| New title → Begin adventure | Fresh isolated profile, `test_mode=false`, startup scripts enabled |
| Ethel request | Original two choices; `old_womans_duck=1`; controls released |
| Duck return alive | Original talk and departure; `old_womans_duck=2`; controls released |
| Ethel acknowledgment | Original house-entry dialogue; `old_womans_duck=4` |
| Mother return-home conversation | All six original lines observed in order; `story=2`; controls released |
| Save/load | Position, inventory, three quest flags, 18 wall models and 18 wall bodies preserved |
| Pause/resume and Quit | Paused movement blocked, resumed movement works, normal Quit exits 0 |
| Cold Continue | Earned Ethel save restored in a fresh process with exact original entity coordinates, camera, inventory, stats/quests, and geometry |
| Bounded death/restart | Explicit fixture begins at life 1; the first gameplay input advances damage to life 0; Begin again completes the opening and restores movement at life 10 |

- Baseline opening: `builds/playtests/next-opening/report.json`, pass, 480 actions.
- Polished opening: `builds/playtests/opening-polished/report.json`, pass,
  475 actions. Rendered review confirms Milder is now in view and identified;
  before/after-load house walls remain intact. A later adjustment keeps the
  feed label fully inside the viewport.
- Full regression suite: **55 passed in 145.21 seconds**.
  Isolated artifacts: `builds/playtests/suite-acceptance-14iy26la/pytest.log`.
  After the final cold-coordinate comparison and death-fixture timing correction,
  both focused restart tests passed again in 25.56 seconds.
- Isolated engine smoke: `builds/playtests/ethel-smoke-v_eti7ms/godot.log`,
  `SMOKE PASS`.
- Focused feed renders: `builds/playtests/opening-polish-fixture/`.
  These use explicit presentation fixtures, not earned campaign progression.
- Final rendered cold Continue and synthetic death/restart:
  `builds/playtests/ethel-restart-settled/report.json`, pass. Continue compares the
  earned save's position, orientation, inventory, quest/stats, and structural
  geometry. Death uses an explicitly synthetic one-health touch attacker, then
  normal defeat-menu input, opening dialogue, and post-restart movement.
  Earlier `ethel-restart/report.json` failed only because its comparison mixed
  saved double-precision coordinates with the float32 collision view. The final
  comparison reads original entity coordinates; it does not loosen an epsilon.

The first combined suite ran while new tests were being finished and reported
three test failures. After fixing the fixture timing/assertions and adding
queued-speaker checks, the complete suite above passed.

## Failure classification and limits

The missing screen scripts, late vision filtering, and Ethel's stranded unfreeze
commands were game defects.
The early Ethel runner failures on maps 440 and 409 were direct walking routes
through scenery, classified as bot/incomplete; they do not establish a trapped
player. The first worker's nonexistent AlkTree talk choice was corrected from
the original source before it could count as acceptance evidence.

The early `builds/playtests/ethel-debug/report.json` continuation reported
`ok=true` prematurely. Lead review rejected its home checkpoint: `story=2` had
changed, but none of Mother's six lines had run. The independent rejection is
`builds/playtests/ethel-debug/review.json`. The runner now requires those lines
in order, across delayed startup and the five-line telemetry window, followed
by released controls. Focused regressions reject an early flag-only result.

Later campaign scripts are restored but later quests remain unverified. The
bounded runner is not a real-time audio/performance test. Synthetic death
coverage does not certify naturally reaching death in the campaign. Previously
documented Mesa texture teardown diagnostics remain outside this milestone.
Mother's new dialogue is readable but the doorway blocks her model in the
retained `home-alktree.png` capture. Ethel still shares a generic character model.
These visual limitations remain for the next session; this report certifies
the listed progression and input checks, not finished presentation.

## Delegation and launch

Three bounded workers were requested on Luna at medium reasoning for
presentation/import, restart coverage, and initial route implementation. Route
debugging was escalated to Terra at medium reasoning after repeated navigation
failures. Astra reviewed and corrected proposed changes, interpreted rendered
evidence, and ran the combined verification. This runtime did not expose worker
token totals; none are estimated. No local Qwen requests were made this session.

Launch the checkout with `./play.sh`. Packaged executables were not rebuilt.
