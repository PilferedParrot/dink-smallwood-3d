# Local playtesting pilot

The pilot separates repeatable execution from model judgment. Ordinary Python
and Godot code run inputs, collect state, and check outcomes. Local Qwen can
choose bounded follow-up actions from structured observations. Astra reviews
implementation, plans further tests, and interprets rendered screenshots.
See the project [delegation policy](../AGENTS.md).

No MCP plugin, cloud API, training run, or new Python dependency is required.
Godot 4.6.1 and Python are already used by the project. Set `GODOT` if the engine
is not on PATH or at the existing local fallback location.

## What the pilot checks

- Actual player inputs and camera-relative movement in the first-person host.
- Whether a blocked direction still permits another direction of movement.
- Opening and closing the pause menu through input events.
- Attempting movement with the menu open, then moving after resuming.
- Compact state including position/map, control inhibition, menu state, and
  nearby collision probes.
- Rendered screenshot capture for Astra, or explicit rejection in headless mode.

The controller lives in [tools/playtest.py](../tools/playtest.py); its Godot host
is [tests/playtest_session.gd](../tests/playtest_session.gd). Each session has an
owned process, bounded requests, atomic command/response files, and isolated
player data. It pauses scene processing between commands; movement tests verify
that model latency does not move the player. Timers configured to process while
paused can still run, so this is not a universal campaign clock or a real-time
performance test.

Scenario setup deliberately selects a map and starting position and skips that
map's startup scripts. The host does not enable `test_mode`, which would bypass
normal dialogue handling. These are focused movement/menu checks; they do not
certify reaching the location through the campaign or completing its quests.

## Running without a model

From the repository root:

```sh
python3 tools/playtest.py --report builds/playtests/smoke/report.json
xvfb-run -a python3 tools/playtest.py --rendered --report builds/playtests/visual/report.json
```

The first command performs headless checks. The second runs a real renderer on
a virtual display and collects a screenshot. Reports identify artifact paths.
Xvfb can use software rendering, so its performance is not a GPU benchmark.
Neither command should disturb the player's save/settings profile or require
the player to navigate menus manually.

The Python `PlaytestSession` interface also supports `observe()`,
`hold(action, frames)`, `look(dx, dy)`, `pause()`, and `screenshot()` for bounded
external workers. Use it as a context manager to close the owned process even
when a test raises an exception.

## Local Qwen

[tools/playtest_qwen.py](../tools/playtest_qwen.py) uses the existing local
OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1/chat/completions`. It does
not install, download, or automatically start a model. The local pilot model is
Qwen3-Coder-Next, served by llama.cpp; server-reported model and usage fields are
recorded with the results.

With the local endpoint running:

```sh
python3 tools/playtest_qwen.py --report builds/playtests/qwen/report.json
```

`--screen`, `--x`, and `--y` select the focused starting scenario. `--rendered`
adds screenshot capture and requires a display (use `xvfb-run -a` if desired).
The default is the ordinary southern pigpen approach at `(407, 320, 390)`.
`--max-actions` bounds game commands; `--timeout` bounds each model request.
Only choices among remaining probes use Qwen. The final single remaining probe
and fixed menu checks use ordinary code.

The action contract is narrow: the model proposes an allowed input; Python
validates it, executes it, and determines the result from observed state. The
model receives compact observations and coverage history. It cannot execute
arbitrary shell commands or declare its own success. Invalid responses,
unavailable inference, and exhausted budgets must remain inconclusive.

Prefer the model-free smoke test for established regressions. Reserve local
Qwen for selecting probes or interpreting text evidence. A model request per
frame wastes resources and introduces needless timing problems.

## Interpreting results

Standing against the southern pigpen fence on map 407 is a negative control:
forward movement stops, while strafing and retreat can still work. Do not infer
a stuck-player defect from a single blocked direction. Check control flags,
menu/dialogue state, the attempted inputs, and the actual position changes.

An all-direction blockage, an intentional cutscene freeze, a failed bridge
request, and an agent that did not complete its probes are different outcomes.
Reports must preserve that distinction. A focused test pass is not evidence
that the entire pig farm or campaign is bug-free.

## Verified September 7 pilot

A different northward entry, from map 439 at `x=400`, reproduced the reported
kind of trap: arrival at `(400,390)` on map 407 overlapped a decorative rock's
3D collider. All four keyboard directions failed, while pause/resume still
worked. Jumping could escape. Without the player's recorded position, this
cannot establish that it was the exact incident reported.

The first-person host now checks overlapping edge arrivals after map/load and
can move them at most 32 source units laterally to a clear point. It checks the
original collision along the adjustment and retains the pigpen fence and
projectile colliders. This is bounded edge recovery, not general unsticking
anywhere in the campaign.

The new `tests/fps_stuck_test.gd` regression drives keyboard inputs and also
checks loading an embedded save. Running it against the pre-fix FPS script
failed the landing, escape, and save-recovery assertions. Its setup uses the
existing test-mode dialogue shortcut; the external session bridge does not.

The completed local-Qwen pilot used three requests totaling 548 reported tokens
(155, 189, 204), with about 11.4 seconds of inference latency. The runner checked
all four directions, menu opening, attempted movement while paused, closing the
menu, and subsequent movement. This measures one short scenario, not general
autonomous exploration. The report and retained engine logs are under
`builds/playtests/qwen/`; rendered captures are under `builds/playtests/visual/`.

Tests should retain a reproducible setup, inputs, before/after state, engine
logs, and any rendered captures. A future replay/recording path for ordinary
human play would help locate incidents for which no saved position exists.

## Next coverage to add

Extend the same controller with full opening-quest traversal, save/reload,
death/restart, equipment use, and longer exploration. Enable startup scripts for
campaign tests and advance dialogue through normal controls. Add real-time runs
separately for timing, audio, and performance. Keep changes evidence-driven;
never bypass a fence or weaken an assertion merely to make the bot succeed.

## Opening campaign mode

The same runner now has `--mode campaign`. It boots the real title screen,
selects **Begin adventure** through menu input, and drives mouse look, walking,
equipment selection, dialogue, map transitions, and the original quest scripts.
Campaign setup does not replace the map, inject items, enable `test_mode`, or
skip startup scripts. Read-only state guides the bot and supports assertions;
all progression occurs through normal inputs.

```sh
xvfb-run -a python3 tools/playtest.py --mode campaign --rendered \
  --report builds/playtests/opening/report.json
```

Use a rendered session for this route. Godot's headless display does not capture
the mouse, so mouse-look is explicitly rejected there instead of falsely
reporting a successful turn. Headless focused movement/menu scenarios remain
available with the original default mode.

Each session retains `trace.jsonl`, `godot.log`, selected PNG screenshots, and an
`xdg/` copy of its isolated saves/settings. The campaign report retains action
observations and named checkpoints even when traversal is incomplete. Test
saves do not use the player's profile. Command budgets bound exploration, and
normal menu Quit is checked separately from harness process cleanup.

The bridge also exposes `navigation_grid()`: a read-only, five-source-unit
collision grid of the current map, including original hardness and the 3D player
capsule. It does not advance physics or alter campaign state. Route planning can
use this snapshot to choose walking waypoints; actual progression still uses
the normal input commands. A solid-fence regression checks that planning does
not turn blocked geometry into a traversable route.

Fresh-process Continue and a bounded defeat/restart check use an earned save:

```sh
xvfb-run -a python3 tools/playtest_restart.py --rendered \
  --campaign-report builds/playtests/opening-polished/report.json \
  --report builds/playtests/restart/report.json
```

`--save` can instead name a retained `adventure.json`. Only that save is copied
into a new isolated profile; its source is left untouched. Continue is selected
through the real title UI and checked against source position, camera,
inventory, and quest/stat values. A campaign report additionally supplies
expected structural geometry. Defeat uses an explicit synthetic one-health
attacker fixture, then normal menu input, the opening conversation, and movement
after restarting; this is not evidence of a naturally reached campaign death.

A stalled waypoint is a bot/incomplete result unless further evidence identifies
a game defect. Do not infer completion from an empty dialogue panel between
delayed script lines; require the quest's completion state and released controls.
The runner still advances a paused scene in bounded steps: its successful route
is not a real-time performance, audio, or full-game completion certification.

The September 7 opening milestone and failure classification are recorded in
[OPENING_MILESTONE.md](OPENING_MILESTONE.md). A proposed continuation prompt is
in [NEXT_SESSION.md](NEXT_SESSION.md).

## AlkTree campaign mode

```sh
xvfb-run -a python3 tools/playtest.py --mode campaign --milestone alktree \
  --rendered --max-commands 5000 \
  --report builds/playtests/alktree/report.json
```

This extends the Ethel prefix through the north gate, the wizard introduction,
the ordinary nut tree on map 474, Milder and Lyna, the home fire, and the
neighbors' aftermath. Fists are selected through Equipment. The runner waits
for the spawned nut to land, then follows its observed position through normal
movement. Required dialogue and released controls distinguish completion from
early quest-flag updates. Save/reload and cold Continue also compare `nuttree`
and `wizard_again`.

The route uses source-backed gate access and collision-grid-derived paths
around scenery. The village's solid perimeter cannot be crossed directly from
maps 440/441 into the southern woods. A blocked route or an obstructed random
nut landing remains an incomplete bot result, not an automatic game defect.

For debugging, `Campaign` separates `alktree_depart`, `alktree_woods`,
`alktree_pickup`, `alktree_return`, and `alktree_home`. An earned pause-menu save
can be copied into a fresh isolated `PlaytestSession(save_source=...)`, followed
by real Continue input and the appropriate remaining phase. Retain the source
save/report chain and label the earned prefix. These continuations help debug;
final acceptance still starts continuously from Begin adventure.

See [ALKTREE_MILESTONE.md](ALKTREE_MILESTONE.md) for results, source prerequisites,
host fixes, rendered limitations, and retained evidence.

## Letter and enclosed map campaign mode

```sh
xvfb-run -a python3 tools/playtest.py --mode campaign --milestone letter \
  --rendered --max-commands 5000 \
  --report builds/playtests/letter/report.json
```

This extends the continuous AlkTree prefix through Renton's five-line conversation,
Aunt Maria's complete invitation, and the map grant. It requires the final exterior
state, released controls, and finished script tasks. The route opens the original
map with M, verifies that movement is blocked while it is open, and closes it with
M before the normal save/reload, pause, and Quit checks. Cold Continue additionally
compares `letter` and `s2-map` with the earlier quest and inventory state.

`letter_guard`, `letter_home`, and `letter_read` support earned-save phase debugging.
Start `letter_guard` on the completed story-5 exterior. Continue preserves a save's
map with startup scripts disabled; walking through the home doorway is a new map
transition. Retain every source-save/report link when resuming a later phase, and
use fresh Begin adventure for final continuous acceptance.

Renton's script moves Dink before it displays dialogue, so send Talk once and wait.
Repeated Talk during that delay can create duplicate tasks. For the return route,
walk south through the open gate lane at `x=450`, then west near `y=375`; the eastern
perimeter is solid. See [LETTER_MILESTONE.md](LETTER_MILESTONE.md) for source-backed
acceptance conditions and the fire/grief presentation changes.
