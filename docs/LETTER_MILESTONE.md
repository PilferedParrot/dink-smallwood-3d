# Renton's letter and Aunt Maria's map

**The continuous rendered Begin-adventure route passes in 3,011 commands.**
It extends the AlkTree aftermath through Renton's message, Aunt Maria's complete
invitation, and the enclosed world map, then verifies save/load, pause, and Quit.
The final regression suite passes 72 tests.

Authoritative evidence is `builds/playtests/letter-final/report.json` and its
independent `review.json`: original dialogue, state, finished scripts, structural
geometry, logs, unchanged source hashes, and selected rendered captures. The
earned save is under `report.session/session-n382e7vw/xdg/data/godot/app_userdata/`
`Dink Smallwood 3D/adventure.json` beside that report.

## Original campaign requirements

The installed `S1-GG.c`, `S1-GATE.c`, `S1-H1-S.c`, `S1-LTR.c`, and `BUTTON6.c`
establish the sequence:

1. At story 5, the north gate (map 408) selects vision 1 and exposes Renton,
   editor sprite 4 at `(451,108)`. Talk once. His script first moves Dink to
   `y=190`, then freezes him and sets `letter=1` before five dialogue lines.
   All five lines and released controls are required.
2. Return along the open gate lane to map 440, then map 439 and the home doorway.
   The home script creates the letter and starts `S1-LTR`. Its task attaches to
   pseudo-sprite 1000 so it can survive the later screen load.
3. `S1-LTR` sets story 6 and letter 2 before reading. Require seven invitation
   lines, Dink's two responses, and the original map hint. The script grants
   `s2-map=1`, fades, loads exterior map 439, fades back, unfreezes Dink, and ends.
   Early flags or the temporary control gap at screen load do not prove completion.
4. Open the original map with **M**, attempt movement while it is open, then close
   it with **M**. Save/load must retain `letter` and `s2-map` with the earlier quests.

The host now binds M to the original `BUTTON6` script and offers **Pause → World
map** for controller access. Before ownership, the original missing-map response
appears. Cutscenes and other modal menus cannot be replaced by a map press;
keyboard repeat cannot immediately toggle it closed. Escape and the map's Return
button also close it. The original dialogue and map artwork are unchanged.

## Fire and grief presentation

The home discovery has visible roof flames. The aftermath uses scorched materials
on the existing cottage, retaining its structural meshes and collision. Source
damage details have explicit models instead of generic rocks, and decorative
damage markers do not introduce collision bodies. State-specific treatment is
restricted to Dink's source house rather than nearby buildings.

The grief camera now finds a clear interior hearth view during both the doorway
line and the later `(203,151)` grief position. The fixture loads the actual
story-3, vision-1 sprites, including the non-colliding flames. The camera validates
its sightline, preserves Dink's coordinates, restores position/orientation after
dialogue and map/title cancellation, and respects reduced camera movement.
Mother's earlier story-2 visibility fix remains covered.

The new continuous run exposed Mother at `x=216.5835` instead of the earlier
`x=202`. A ray to her collider did not establish readable framing there. Story 2
now consistently uses bounded in-room camera candidates, including views from
the north. Both observed positions have rendered regression captures with Mother
above the dialogue panel; reduced motion and camera restoration still apply.

Aftermath labels use the source-backed Ethel, Neighbor, and Guard roles, including
animated sprites. Renton and Aunt Maria's letter also receive readable labels.
Character models remain stylized and partly shared; this is not completed scene art.
Ethel still uses a wizard-shaped placeholder, Mother is framed from behind, and
the letter prop remains generic. The scorched cottage keeps its intact silhouette
and original door. These are remaining presentation limitations.

## Debug evidence and review

- Baseline rerun: `builds/playtests/session-next-alktree/report.json`, pass in
  2,667 commands. Its independent `review.json` checks every required post-Ethel
  dialogue stage, the aftermath state, and engine errors.
- Guard prefix earned through normal Continue, walking, Talk, dialogue, and pause
  Save: `builds/playtests/letter-live/attempt1/`. The debug helper then used an
  incorrect live save-copy path; the retained save after session cleanup is valid.
- Letter suffix from that guard save: `builds/playtests/letter-live/attempt2/`,
  pass in 192 commands. Its source chain is recorded in `report.json`. The final
  earned save is `letter-map-closed/adventure.json` beneath that attempt directory.
- The earlier worker's `letter-continuation/debug-report.json` is an incomplete
  route attempt. Its `lead-review.json` corrects the false assertion that Continue
  reruns startup or resumes the exterior save inside the home. The bot crossed
  the doorway while walking; the saved map was 439 and Continue disables startup.

The runner now separates `letter_guard`, `letter_home`, and `letter_read` for
earned-save debugging. This does not replace continuous acceptance from Begin
adventure. Guard Talk must not be retried during his pre-dialogue repositioning;
doing so starts duplicate tasks. The eastern gate perimeter is solid, so return
south through the known open lane at `x=450` before turning west.

The first integrated `letter-complete` run was incomplete: a randomly falling nut
touched Dink and was collected before the runner saw it settle. The runner had
kept waiting for the already-removed sprite. It now accepts that natural pickup
only when the item, story/nut flags, and original pickup response all agree.
Two harness regressions cover successful early pickup and flags without an item.
That run's Mother capture also exposed a slightly different live X position that
needed additional camera coverage. It is retained as rejected acceptance evidence.

The final regression suite passes **72 tests in 118.80 seconds**. Its retained
log is `builds/playtests/letter-final-suite/pytest.log`. The earlier 70-test pass
predated the natural early-pickup regression and additional Mother framing fix.

Fresh-process Continue and isolated defeat/restart also pass at
`builds/playtests/letter-restart/report.json`, with independent review in that
directory's `review.json`. Continue matches the continuously earned save's exact
entity coordinates, camera, inventory, quests (including letter/map), stats, and
structural geometry. It preserves the earned life 9/10. The synthetic defeat
fixture uses normal damage and menu input, then verifies the original opening
and movement after Begin again at 10/10. Lead review accepted all three renders;
logs contain only the two known Mesa texture teardown diagnostics.

Three Luna workers proposed the bounded camera, world, and route changes. Two
Terra workers corrected presentation issues identified in lead review. The lead
implemented map input, integrated the changes, corrected route navigation, and
reviewed rendered evidence. Worker token totals were not exposed and are not
estimated; no local Qwen inference was used.

Later quests, real-time audio/timing, natural campaign death, and native GPU
performance remain unverified. Launch the current checkout with `./play.sh`;
exported executables are not automatically rebuilt.
