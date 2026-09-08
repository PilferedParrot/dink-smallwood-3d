# DinkC story support

`tools/compile_story.py` turns the installed Dink story sources into a JSON program.
It only reads the data package; it does not copy or link the FreeDink engine. The
Godot VM executes that program and delegates every game command to the scene host.

Regenerate the bundled program with:

```sh
python3 tools/compile_story.py /usr/share/games/dink/dink/Story \
  --overrides tools/dialogue_overrides.json -o game/data/story.json
```

## Runtime contract

Create `DinkVM.new(self)`, call `load_story()`, and use
`await vm.run(script_name, procedure_name, sprite_id)`. Call
`vm.cancel_screen_tasks()` before a map transition and `vm.cancel_all()` for a full
reset or title transition. The VM keeps `vm.globals` and each script's per-sprite local
variables across event runs.
Use `snapshot_state()` and `restore_state(data)` for those values when saving. Sprite
identifiers should remain unique across screens; if an id must be reused, call
`clear_sprite_locals(sprite_id)` before assigning its script.

The host method is:

```gdscript
func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
    # apply the command and return its DinkC result; await when the command blocks
    pass
```

`context` includes `script`, `procedure`, `sprite_id`, `task_id`, `globals`, and
`locals`. The compiler preserves calls by name, so the bridge receives original Dink
commands such as `sp_x`, `create_sprite`, `say_stop`, `move_stop`, `load_screen`, and
`external`. `wait`, `say_stop`, `move_stop`, and the batched `choice` command may be
asynchronous. For `choice`, args are `[title, options]`, where each option has `text`
and `value`; return the selected value (DinkC assigns it to `&result`).

`script_attach(sprite)` is interpreter state as well as a bridge call. It changes the
task's `context.sprite_id` for later instructions; attachment `1000` is the DinkC
pseudo-sprite that survives a screen transition. Call `cancel_screen_tasks()` when a
screen changes to retain those tasks, or `cancel_all()` for a title/reset transition.
When the host starts an `external` script, it should pass the received
`context.sprite_id` so the child task inherits that attachment.

The JSON report contains `unsupported`, `recoveries`, `excluded`, and `dialogue_overrides`.
`unsupported` preserves source that cannot be executed; `recoveries` records a small
set of unambiguous typographical repairs in the released data; and
`excluded` identifies non-executable source data that is intentionally not emitted;
and `dialogue_overrides` counts replacements by source script. Treat a nonempty
`unsupported` report as an implementation checklist for the host/compiler; unsupported
source is never dropped.

## Instruction format

The output uses `scripts[script].procedures[procedure].code`. Expressions are literal,
reference, unary, binary, or host-call nodes. Instructions include assignment, calls,
labels/goto, conditionals, returns, and choice blocks. Variable references retain the
leading `&`, including names with hyphens, so global state is unambiguous. Choice option
`result` values are their original source positions, including positions hidden by
conditions. The VM flattens conditional blocks per task before execution, so labels and
gotos inside those blocks retain their DinkC behavior without changing story data.

Delegate tasks to the local qwen or other openai agents for parsimony in accordance with what each model can reliably handle. Astra directs, supervises, and inspects. update linux and windows versions on github.  if the end result is not a finished game, leave a prompt for the next session.
