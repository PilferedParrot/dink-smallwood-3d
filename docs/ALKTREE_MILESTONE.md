# AlkTree nuts and the return-home aftermath

The following records the earlier AlkTree acceptance. The subsequent
[letter milestone](LETTER_MILESTONE.md) adds fire/grief presentation work, broader
Mother framing coverage, natural early nut-pickup handling, and a continuous route
through Aunt Maria's invitation and map.

**The continuous rendered Begin-adventure route passes in 2,642 commands.**
It earns the nut, completes the woods conversations and return-home aftermath,
then verifies save/load, pause/resume, and normal Quit. The actual Mother request
capture confirms the doorway visibility fix. This is a progression milestone;
fire/grief scene presentation still needs work.

Authoritative acceptance: `builds/playtests/alktree-complete/report.json` and
its independent source-dialogue, state, geometry, log, hash, and rendered review
at `builds/playtests/alktree-complete/review.json`. Screenshots and the earned
save are under `report.session/session-jfb4gmgs/` beside the report.

The existing Ethel baseline passed in 1,265 commands at
`builds/playtests/next-ethel/report.json`; its independent dialogue review is
`builds/playtests/next-ethel/review.json`.

## Original campaign behavior

The installed DinkC sources and imported world establish these requirements:

1. Finish Mother's complete AlkTree request after returning Quackers alive:
   `story=2`, `pig_story=1`, and `old_womans_duck=4`.
2. Exit through the north gate on map 408. `S1-GATE.c` hides the guard at
   story 2; the eastern and southern village fences remain solid. The first
   visit to map 376 runs the wizard's fifteen-line introduction. Travel through
   maps 377, 409 (outside the northern fence), 410, 442, and 474.
   Find the ordinary AlkTree on map 474, editor sprite 1 at `(428,109)`.
   Map 410 contains a different, vision-filtered actor with the same script;
   it is not the ordinary collectible tree.
3. Equip Fists and hit the tree through normal input. `S1-NTREE.c` creates
   a falling nut and attaches `s1-nut`. Follow its observed position and touch
   it with a free inventory slot. `S1-NUT.c` adds `item-nut` and sets
   `nuttree=1` and `story=3`.
4. Return through the woods. Map 410's `S1-BLS.c` reveals Milder and Lyna;
   `S1-BLOVE.c` delivers seven lines, completes their departures, releases
   Dink, and sets `nuttree=2`. Its final line retains the checkout's existing
   audited dialogue override, “Hhhmph, people!”
   Return to the home exterior. `S1-H1-O.c` delivers the two fire-discovery
   lines, then releases Dink to enter the house.
5. `S1-H1-S.c` delivers five interior grief lines and sets `story=4`, then
   walks the still-frozen player through the exit.
6. The exterior `S1-H1-O.c` delivers six neighbor lines on the live-duck path,
   fades, sets `story=5`, selects vision 2, fades back, unfreezes Dink, and
   finishes its task. The story flag alone is not cutscene completion.

## Confirmed host defects

Runtime nuts also failed to become collectible: the generic sprite-property
handler interpreted `sp_touch_damage(sprite, -1)` as a read. In this command,
`-1` enables the original touch procedure. The handler now accepts that value
for touch damage while retaining ordinary property queries. The live failed
save at `builds/playtests/alktree-live/nut-debug/adventure.json` retains the
nut with its script attached but no `touch_damage` property, with Dink standing
on it. A fresh process after the fix collected a newly struck nut through
normal input. `tests/nut_pickup_test.gd` separately verifies script startup,
actual movement/touch, item grant, quest state, disappearance, and notification.

The host previously checked map transitions only during ordinary player
movement and rejected frozen players. The original evacuation intentionally
keeps Dink frozen through its final `move_stop`, so it left him trapped inside
after all five grief lines.

Scripted player movement now checks transitions as it advances. This allows
the script to use the doorway while ordinary frozen input remains blocked.
The original DinkC source is unchanged.

A normal-step run then exposed entrance bounce: the delayed first move starts
inside the exit trigger after its cooldown, and an unconditional check sends
Dink back outside. Scripted doorway activation now requires approaching the
trigger center rather than moving away into the room. A normal-rate regression
covers this case before the accelerated original-script sequence. The rejected
live attempt is retained under `alktree-live/fixed-pickup/` with its failure
report; it observed only one of eleven grief/neighbor lines and is not a pass.

`tests/alktree_aftermath_test.gd` reproduces the original sequence with an
explicit `story=3` fixture, accelerated time, and test-mode dialogue. Before
the fix, six evacuation/aftermath assertions failed. The final focused test
checks all eleven interior/neighbor lines in order, the actual fade/vision/
unfreeze/task-ending calls, map 439, story 5, vision 2, finished tasks, and
movement through the input action after release. This fixture does not earn
the nut or replace continuous campaign acceptance.

## Mother's doorway presentation

The original request leaves Dink at the doorway with Mother behind the room's
wall/furniture sightline. For an obstructed Mother line at story 2, the FPS host
now selects a clear in-room camera position from bounded candidates. Physics
rays check that the viewpoint is clear and can see Mother. Dink's coordinates,
structural meshes, and collision bodies are unchanged. The camera returns when
the line ends, or when a reset/map/title transition cancels the conversation.
Reduced-motion settings retain the ordinary camera.

The focused test uses Mother's actual scripted `y=200` position and verifies
the blocked original sightline, clear temporary sightline, unchanged player
coordinates, and restored camera position/orientation. Lead visual review
accepted `builds/playtests/mother-visibility-fixture/mother-story2-live-position.png`:
Mother is visible above the dialogue panel. This is an explicit presentation
fixture. Lead review also accepted the actual continuous `home-alktree.png`:
Mother is clearly visible during the original nuts line.

Rendered review of the corrected earned-save aftermath confirms readable fire
and neighbor dialogue. The interior grief camera still faces a wall, and the
neighbors share generic models and speaker labels. These are remaining
presentation issues; the milestone does not certify finished scene direction.

## Review and scope

| Final check | Result |
| --- | --- |
| Fresh Begin adventure through aftermath | Pass, 2,642 commands; no scenario injection |
| Required post-Ethel dialogue | Six Mother lines, fifteen wizard lines, seven Milder/Lyna lines, two fire lines, five grief lines, six neighbor lines in order |
| Quest completion | Map 439, story 5, vision 2, nuttree 2, wizard_again 1, pig_story 1, live-duck state 4; controls released and no active script tasks |
| Save/load and pause/resume | Real movement before load and after resume; exact inventory/quest restoration; cottage and ten fence models/bodies retained |
| Fresh-process Continue | Pass against the final earned save, including camera, exact entity coordinates, inventory, quest/stats, and geometry |
| Defeat/restart | Pass using the explicitly synthetic one-health attacker, real damage/input, defeat-menu Begin again, opening dialogue, and restored movement |
| Full regression suite | **62 passed in 111.95 seconds** |

Final suite log:
`builds/playtests/alktree-acceptance-suite-v1ryfkbs/pytest.log`.
Cold Continue and defeat/restart:
`builds/playtests/alktree-restart/report.json`. Their rendered captures were
reviewed. Continue retains the campaign's earned life 9/10; the synthetic
restart restores the opening at 10/10. This does not certify a natural campaign
death route. The two known Mesa texture teardown diagnostics remain; the
independent acceptance review found no other engine errors.

The first route worker's map-410 route and the first presentation worker's
wall-thinning/yaw-bias proposal were rejected during lead review. The latter
was removed: its captures did not show Mother during dialogue. Neither is
acceptance evidence. The failed route explorations are bot/incomplete results.

The lead completed route integration after the workers' incomplete attempts.
Normal menu saves under `builds/playtests/alktree-live/` retain the earned
continuation chain. The final acceptance above reruns the whole route from
Begin adventure and does not depend on those debug continuations.

Requested delegation used two Luna workers at medium reasoning, then two Terra
workers at medium reasoning after review found inadequate results. An initial
inherited-model route worker was interrupted before implementation. The lead
reviewed proposals, implemented the host fixes and final route corrections,
and verified the integrated checkout and images. Worker token totals were not
exposed; none are estimated. No local Qwen requests were made.

Later quests, real-time audio/timing, and native GPU performance remain outside
this milestone. Launch the current checkout with `./play.sh`; packaged
executables are not automatically rebuilt.
