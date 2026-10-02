# Neighbour startup prediction: comparison fixed before implementation

2026-10-02. The original game starts the incoming screen's `main`, filters its
editor sprites using the resulting `&vision`, then starts each loaded editor
sprite's `main`. A neighbour should show the visible state at the first point a
player could inspect that screen. The predictor's cut is the first `wait`,
`say_stop*`, `move_stop`, `freeze`, menu/choice, fade, warp or other blocking host
command in **each procedure**. Its earlier property changes count; commands
after that point do not. Spawned script mains run by `sp_script` use the same cut.
The live game is not paused or altered by prediction.

## Cases and oracle

Enumerate all 570 outdoor maps (`world.json`'s `indoor == false`) in numeric
order. For each, compare a real `load_map(n, true)` after deferred editor mains
have run with the prediction from the same pre-load state. Record the vision and
every visible sprite's source editor index or created ordinal, active/nodraw,
position, pseq/pframe and seq/frame. Exclude sprite 1 (the player). Run four
explicit *scenario setups* that skip story progression:

1. Fresh game: globals and editor state after `_new_game()`.
2. Post-letter: fresh game plus `story=5`, `nuttree=1`,
   `old_womans_duck=4`.
3. Burning house: fresh game plus `story=4`, `old_womans_duck=4`;
   screen 439's startup should select vision 1 before its first dialogue.
4. Duck search: fresh game plus `story=1`, `old_womans_duck=1`;
   force `random(4,1)` to 1 in both oracle and predictor for the deterministic
   control of screen 440. In production the preview draws from a private RNG
   and records the startup draws for that visit. On entry, only matching
   startup draws are replayed; later script calls keep normal random behavior.

For each state and screen, restore the input state before the real load, rather
than carrying mutations from the preceding screen. If a real script continues
after the predictor's cut, label the resulting mismatch `post-cut` rather than
claiming prediction agrees. If timing or another host action prevents a stable
real snapshot, label it `inconclusive`. Report an agreement count for each state,
with every mismatch mapped to a cause and named screen. The oracle exercises the
real `load_map` path; the setup and random override are explicit shortcuts.

The old editor-only neighbour state is the negative control. It must disagree
with real startup on 440 in the forced duck-search case (vision 2 and the duck),
408 with `story=1` when `s1-gate` creates the girl, and at least one sprite
property case among 410, 414, 497, 505 or 536. Record actual results before
using any of them as a positive predictor claim. Also compare a snapshot of
live globals, editor state, inventory, entities, music and UI immediately before
and after building a whole 5x5 neighbour block; all must be identical.

Measure `load_map` (scripts off) for 439, 440 and 505 with `tests/fps_perf.gd`
before and after, same camera and 300 frames, interleaving the old and new
checkout for each screen and repeat. Under Xvfb/llvmpipe this is a relative
comparison only. Capture three or four boundaries with actual visible
disagreement using `tools/view_sheet.py` at <=1700 px and inspect the pixels.

Every Godot process has private XDG data/config/cache directories and Dummy
audio. Rendered probes use Xvfb under a bubblewrap `/dev/input` mask; logic
probes use `--headless`. This keeps the player's save/settings/log and desktop
unaffected. A headless state comparison does not establish the rendered result.

## Result — 2026-10-02

`neighbour_script_sandbox.gd` runs the incoming screen main, constructs its
editor sprites with the resulting vision, and then runs their mains. Its VM,
globals, script locals, editor state, inventory, entities and random generator
are private. Blocking commands stop only their calling procedure. The current
screen's predicted immediate startup supplies the story state from which its
neighbours are built. The 5×5 renderer uses those results for ground painting,
fitted building parts and upright sprites. A cached preview's random calls are
replayed on that screen's actual startup when its input state still matches.

The original editor-only neighbour is red on the planned controls: on 440 it
omits duck vision 2 and `s1-oldd`; on 408 it omits the girl made by `s1-gate`;
on 505 the `1gold` entity's `frame` remains 1 instead of becoming 4. The gold
case establishes an entity-property difference, not a visible frame change:
its `pframe` stays 1 and the renderer can still show that frame.

The [per-screen survey](evidence/neighbour-startup-survey.jsonl) records every
outdoor screen in every scenario (2,280 rows), including each predicted and
actual vision, visible count and any difference. These setups are explicit
shortcuts around campaign progression; the oracle itself calls real
`load_map(n, true)` and lets the deferred mains run.

| Scenario | Exact agreement | Post-cut or elapsed motion difference | Active-task inconclusive | Agreement at a cut, future state uncertain | Unclassified |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fresh game | 547 | 7 | 15 | 1 | 0 |
| Post-letter fixture | 546 | 7 | 16 | 1 | 0 |
| Burning-house fixture | 546 | 8 | 15 | 1 | 0 |
| Duck-search fixture | 547 | 7 | 15 | 1 | 0 |

The different-state rows are 376 (the wizard moves), 404 (bridge script past
its cut), 408 (the girl moves), 439 in the burning-house setup (cutscene actors
move), and 634, 665, 697 and 727 (fish mains continue after the sandbox's
freeze cut). Screen 251 agrees at the cut but could change later. The other
inconclusive rows have live tasks still running when the oracle takes its
snapshot. The sandbox emitted no unsupported-command uncertainty for these
setups. No unclassified mismatch remains.

The standalone 2,280-load survey exits successfully and writes all rows, then
Godot prints an `ObjectDB instances leaked at exit` warning. A five-screen
smoke run does not print it. The cause of that harness exit warning has not
been established; it is separate from the per-screen agreement result.

The full-block isolation probe found no changes to the live VM state, editor
state, inventory, entities, current screen, music or UI. A separate test walked
across 439→440 with a real W-key event after changing the private preview seed
to a control that would hide the duck on a new roll: the entry kept vision 2
and the previewed duck. This is a scenario setup for the quest flag, then the
actual movement input path.

The [rendered sheet](images/neighbour-startup-oct2.jpg) shows three boundaries
at 1600 px width: duck from 439, gate girl from 409, and the burning-house
appearance from 471. The roof shows dark scorch with small orange highlights;
this still does not establish prominent active flames. The captures used the
same view in the old and new checkout, Xvfb and Dummy audio. The
[search views](evidence/neighbour-views-search.json) use `story=1`,
`old_womans_duck=1`, preview seed 3; the
[fire view](evidence/neighbour-views-fire.json) uses `story=4`,
`old_womans_duck=4`, preview seed 1701. Both are scenario setups. Astra inspected
the sheet: the intended changes are visible, and no other visual regression is
obvious in these views. The [load probe](evidence/neighbour-perf.md) and its
[raw runs](evidence/neighbour-perf-raw.txt) cover 439, 440 and 505.
The [check record](evidence/neighbour-tests.md) gives the exact full-suite
results: 95 passed, 1 skipped on the unchanged base, and 98 passed, 1 skipped
on the final branch. Its profile note records the first broad runs' XDG
isolation mistake and the final isolated rerun.

The preview is a snapshot for a block build. A story flag changed while the
player remains on the same map appears in neighbours on the next block build;
it does not rebuild the existing block immediately. Scripts that depend on
the player's future arrival position or continue past the documented cut may
also diverge from their preview. Those cases need a separate follow-up if they
become visible in play.
