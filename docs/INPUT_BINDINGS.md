# Runtime input bindings

`game.bindings` owns the registry and InputMap for that game instance. It is
initialized before world/UI setup. The settings dictionary returned by
`load_settings()` is also the game's settings dictionary: volume and binding
changes therefore save together without discarding each other.

Actions expose `id`, `name`, `contexts`, `defaults`, and `reserved` in
`bindings.actions`. Storage contexts are `2d`, `fps`, `menu`, and `global`.
Gameplay contexts are mutually exclusive; menu handlers run while gameplay
handlers are suspended. Global controls overlap all three. Fullscreen is
global; Escape is an immutable global fallback. F9 is reserved for local bug
reports. Escape may also be the ordinary Pause/Menu back binding, but another
action cannot take it, even with modifiers.

## API

```gdscript
var record = bindings.from_event(captured_input_event)
var result = bindings.add_binding("attack", record) # keeps mouse and pad slots
if not result.ok and result.error == "conflict":
    print(result.conflicts) # action ids, no mutation has occurred
    # To exchange a selected existing slot with the conflicting slot:
    result = bindings.replace_binding("attack", selected_index, record, "swap")

bindings.reset_action("attack")
bindings.reset_all()
print(bindings.label("attack"))
```

The UI-facing operations edit zero-based slots from `events(action, scope)`:

- `add_binding(action, record, policy="refuse", scope="")` appends without removing other devices. A conflicting add refuses even with swap, since it has no old slot to exchange.
- `replace_binding(action, index, record, policy="refuse", scope="")` edits one slot. Swap exchanges it with exactly one conflicting slot of one action in the same storage context, preserving all unrelated slots.
- `remove_binding(action, index, scope="")` removes only that slot. A stale/out-of-range index returns `invalid_index`.

`set_bindings(action, records, policy="refuse", scope="")` is an explicit whole-list
operation, including other devices. An empty list means unbound for optional
actions. The six essential menu actions (`ui_up/down/left/right/accept/cancel`)
must always retain at least one physical keyboard key and one pad button or
axis. An edit or swap that removes either family refuses transactionally with
`{ok:false, error:"menu_device_required", action:id, device:"keyboard"|"pad"}`.
The guard checks the other action in a swap too. Mouse or Escape recovery is
not a substitute for these routes. Focus traversal, paging, Home and End remain
optional. Scope
normally selects itself from the action and active game mode; explicit scope
allows editing the other game mode. `events()`/`defaults()` return copies.
`label()` selects the active device family and falls back to the other when
necessary; `short_label()` names its first binding. Labels are computed on
request, including keyboard layout lookup; labels are never binding identity.

Whole-list `set_bindings` swap exchanges complete lists with exactly one conflicting action in the same
storage context. Multiple conflicts, cross-context global conflicts, and
reserved actions are refused. A refused/invalid/write-failed operation changes
neither live bindings nor the file. A successful operation writes atomically,
installs the map and emits `changed`; existing hint surfaces refresh then.
Resetting one action can also conflict with another customization and accepts
the same refusal/swap policy. Resetting all always restores the registry.

Events are JSON-safe records: `{"type":"key","physical":75}`,
`{"type":"mouse","button":1}`, `{"type":"pad","button":0}`,
or `{"type":"axis","axis":0,"direction":-1}`. Keys optionally contain
boolean `shift`, `ctrl`, `alt`, and `meta` modifiers. Capture uses physical
keycode, clears redundant self-modifiers and does not store Unicode/text.
Gamepads match any device; axis direction is explicit. Analog stick look and
movement remain analog. Continuous mouse motion and native pointer clicking,
wheel scrolling, and text editing remain engine interactions.

## On disk

The existing `user://settings.json` gains one field:

```json
{"bindings_v1":{"version":1,"contexts":{"fps":{
  "attack":[{"type":"key","physical":75}]
}}}}
```

Other settings fields survive. No bindings field means original defaults;
loading it writes nothing. Unknown actions/contexts, unsupported versions,
malformed events, collisions and corrupt JSON produce warnings and defaults,
retaining unrelated valid action overrides. Invalid essential menu overrides
restore that action's defaults with a warning. Colliding overrides are considered
in registry order, independent of JSON order: the first survives and later
collisions fall back, removing only fallback slots that would reintroduce the
winning binding. Untouched defaults and essential menu device minimums remain
protected. Raw corrupt or unsupported-version files are left intact until an
explicit save; before replacement, their exact bytes are copied and verified
to `settings.json.bak`. Existing backups are preserved as `.bak.1`, `.bak.2`,
and so on. Backup failure refuses the write. Ordinary volume/settings saves
use `bindings.save_settings()` and receive the same protection. Only plain records are
parsed, never objects or resources from a save file.

Tests use isolated profiles, physical `Input.parse_input_event()` events and
separate process restarts. The table checks every non-reserved action in each
storage context; the gameplay dispatch fixture labels its skipped progression.
An input action table alone does not certify a rendered UI: the packed hint
fixture separately exercises Escape, pointer navigation, confirmation, choices
and the reset API. The reset button belongs to the subsequent UI unit.

Writes check the stream after flushing before replacing the previous file;
opening, short writes and renames can each return `write_failed`. The old
settings file remains available if a new binding cannot be saved.

Pause/back and map-toggle also remain active in menus (`menu_active` registry
metadata), so their bindings conflict with menu actions in either game mode.
The original Escape alias between Pause and Menu back is intentional. For
example, assigning menu confirmation to M is refused while M toggles the map;
assigning it to an ordinary gameplay attack key can be accepted.
