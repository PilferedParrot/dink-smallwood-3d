# Script instances and event re-entry

The original's script instance is not one coroutine per event. A sprite can
receive PUSH, talk, hit or touch while its script is waiting for text or a timer.
The new event starts at that procedure in the existing instance; its previous
continuation is replaced, and its script locals remain.

## Source derivation

Primary specification: GNU FreeDink 109.6, the pinned release source, read
2026-10-19. Paths below are relative to its `src/`; the public source index is
[Debian Sources](https://sources.debian.org/src/freedink/109.6-1/src/).
The implementation derives the behavior independently; engine code is not copied.

- `brain_keyboard.cpp:54–85`, specifically line78, dispatches PUSH by locating
  the procedure on the sprite's existing script, then running that script.
  `brain_keyboard.cpp:253–261` and `live_sprite.cpp:146–186` allow held contact
  to dispatch again after the push animation. Repeated authored speech is
  therefore expected; suppressing repeat PUSH is not the fix.
- `dinkc.cpp:402–470` saves the existing instance's instruction position, scans
  from the start, and leaves it at the selected procedure, resetting control
  levels and a pending move. A missing procedure restores the original position.
  There is no new interpreter stack or new instance in this lookup.
- `dinkc.cpp:1115–1196` executes that same instruction position until yielding.
  `dinkc_bindings.cpp:906–912` replaces returning callbacks before registering
  a new wait. `dinkc_bindings.cpp:766–818` does the same for stop-speech;
  `dinkc.cpp:1085–1111` removes prior timer and speech-return callbacks.
  The source does not categorically delete all callbacks inside `locate`:
  it overwrites the instruction cursor, and the next blocking operation
  replaces its return callback. An old event's previous tail is not preserved.
- `dinkc.cpp:2540–2571` implements external by loading a **new** script instance
  attached to the caller's sprite, setting its return owner and running it.
  Same sprite and same filename do not make this the existing event instance.
  `dinkc_bindings.cpp:1237–1249` likewise loads a new instance for spawn.

## Host mapping

DinkVM's normal entry identifies an existing script by canonical source name and
its original native sprite instance. Re-entry invalidates that instance's prior
live task before starting the new procedure. Current attachment is tracked
separately, so a spawned script attached to another sprite keeps its own identity.
A missing procedure does not replace an active task. Normal entries keep their
persistent script-local dictionary.

External calls explicitly request a fresh instance and private locals. Spawn
already allocates a distinct native owner/handle, which supplies its independent
identity and persistent locals, including later named callbacks. Different
scripts on the same owner and the same script on different owners remain
independent. This maps the host's current script handles; it does not implement
all of FreeDink's script-loader and arbitrary callback semantics.

Cancellation is checked again after awaited results before writing locals or
globals. The old host await may return, but cannot overwrite replacement state
or execute the old tail. Text lifetime and input modality remain independent.

## Both causes and class coverage

What broke: DinkVM allocated a new live coroutine for every procedure entry on
an already-running instance. With freely walking stop-speech, repeated PUSH or
NPC events could have two live continuations and execute both old and new tails.
Why made: the cooperative-coroutine implementation treated an invocation as an
independent task without checking the source's single instruction cursor. The
old global speech modality prevented normal re-entry and hid this missing
instance contract from the event tests.

`tests/push_reentry_test.gd` holds real physical input for five seconds against
each of the four source PUSH scripts, plus the weak-rock stop-speech branch.
The rock's nonmoving approach avoids entering the cave; its successful moving
branch remains covered by `push_input_test.gd`. Each case records dispatches,
live-task counts and recent dialogue. A new speech line per repeated PUSH is
valid; overlapping continuations in one instance are not. The table's500ms wait
is compared with the latest entry, with one physics tick as timing resolution.

Injected procedures on the original mother NPC exercise repeated talk mid-stop-
speech, hit and touch through the actual event dispatcher. They require two
entries, preserved locals, one live task and exactly one completed tail. These
are labelled event probes, not real-input campaign or combat proof. Negative
controls retain different owners/scripts, external and spawned instances sharing
the NPC, failed procedure lookup, private external locals, spawned locals across
a named callback, and cancellation of an awaited expression before its write.
The fixture skips startup/progression and does not certify rendering.


## Screen construction is a new instance

A screen load is a constructor call, not an event on a previously loaded script.
FreeDink109.6 `game_engine.cpp:710–721` loads the screen script afresh before
locating main. `dinkc_bindings.cpp:1321–1326` attaches a force_vision caller to
pseudo-sprite1000 before rebuilding; `dinkc.cpp:872–892` preserves that owner.
The old caller can therefore execute its fade-up/unfreeze tail after the new
screen instance runs, even when both use the same source filename.

The first integrated suite exposed a missed constructor call: screen main still
used normal re-entry, so a force_vision reload cancelled the old aftermath tail.
The process cause was applying the source-name/owner identity heuristic to a
newly loaded instance. The prior event audit distinguished external/spawn but
stopped before screen construction; a reviewer also considered sprite0 re-entry
intended without reading this constructor path. That heuristic is appropriate
for event entry, not a substitute for classifying each script-load call.

Screen main now requests a fresh instance, and force_vision marks its caller's
source attachment before rebuilding. The original aftermath regression proves
the exact fade/vision/unfreeze/kill tail. A synthetic source-map constructor
fixture separately requires two constructors, one completed old tail, private
locals surviving the rebuild and the caller's1000 attachment. Existing repeated
event tests retain the single-cursor negative control. These fixtures do not
claim complete original callback/loader emulation.
