# Speech and reading pace

Speech displays in a shared card. Dink can move and look around while characters
speak unless a script explicitly freezes him. Choices remain modal. Settings →
**Speech waits for me** is off by default. When enabled, a line whose script waits
(`say_stop`, `say_stop_npc`, or `say_stop_xy`) stays until any bound Talk input
dismisses it. Ambient `say` and
`say_xy` lines keep their natural lifetime and do not capture Talk.
The small dismiss hint follows the current Talk binding and input device. Movement
remains available. Explicit script removal or a script-specified lifetime still
controls its text sprite.

This host uses the following FreeDink 109.6 contracts. References are to `src/` in
[the source release](https://ftp.gnu.org/gnu/freedink/freedink-109.6.tar.gz).

| Command | Calling script | Player input | Source |
|---|---|---|---|
| `say` | Returns a text handle immediately | Does not freeze | `dinkc_bindings.cpp:748–764` |
| `say_stop` | Waits for its text | Does not freeze | `dinkc_bindings.cpp:766–788` |
| `say_stop_npc` | Waits for its text; returns immediately if that speaker already has text | Does not freeze | `dinkc_bindings.cpp:790–807` |
| `say_xy` | Returns a text handle immediately | Does not freeze | `dinkc_bindings.cpp:820–825` |
| `say_stop_xy` | Waits for its text | Does not freeze | `dinkc_bindings.cpp:809–818` |
| Choices | Waits for selection | Blocks movement | `dinkc.cpp:1635–1653`, `game_choice.cpp:38–54,166–177`, `brain_keyboard.cpp:219–220` |
| `freeze(1)` / `unfreeze(1)` | Returns immediately | Sets/clears explicit player freeze | `dinkc_bindings.cpp:542–559`, `brain_keyboard.cpp:222–240` |

The source text lifetime is `max(2700, expanded UTF8 byte count × 77)` milliseconds.
It includes colour codes before presentation strips them (`text.cpp:40–65`).
The creation deadline uses monotonic time, including slow rendering frames
(`game_engine.cpp:188–207`). Expiry resumes the waiting script (`update_frame.cpp:295–300`); other scripts
continue. Talk can hurry the most recent `say_stop`/`say_stop_xy` while Dink is
explicitly frozen (`brain_keyboard.cpp:222–240`). Unfrozen default speech does
not capture Talk. `sp_kill(id, 0)` keeps text alive, positive TTL is measured
from creation, and `sp_active(id, 0)` removes it (`dinkc_bindings.cpp:483–486`,
`live_sprite.cpp:88–98`). Each handle owns its lifetime independently.

Presentation adaptations: XY text uses the same accessible card rather than its
source screen coordinates. The card presents the newest live text; other owners
retain their lifetimes. Natural lifetime is at least P2's existing reading budget
at 170 words per minute with a 17 character per second ceiling, including text
that fits on one card. Overflow retains its reading scroll and can extend the visible
line so every line gets a readable turn. Explicit script deadlines override this
reading floor. This is a presentation extension, not a claim of exact source timing.
Natural reading time starts on reveal when speaker framing has to prepare a
hidden card; explicit script TTL remains measured from creation. Speaker framing is
limited to explicitly frozen dialogue so ambient speech cannot take the camera.
Choices use the separately remappable menu confirmation action.

Our pause, equipment and other modal menu pages preserve speech reading time,
including an explicit text deadline. This deliberately differs from FreeDink's
inventory: `update_frame.cpp:243–246` skips text expiry while inventory is open,
but its SDL clock keeps counting, so overdue text disappears on return. Script
choices retain their running speech clock (`update_frame.cpp:267–300`).

`wait_for_button` and `stop_wait_for_button` are currently unsupported. Neither
occurs in the bundled campaign AST. In FreeDink they suspend the caller and consume
direction/action edges, without setting a player freeze (`dinkc_bindings.cpp:639–651`,
`update_frame.cpp:171–203`).

The optional waiting mode follows [Game Accessibility Guidelines’ own-pace
recommendation](https://gameaccessibilityguidelines.com/allow-players-to-progress-through-text-prompts-at-their-own-pace/)
and [Xbox Accessibility Guideline 104](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/104).

Saving follows the source command: active speech, a choice, or an explicit freeze
does not refuse a save (`dinkc_bindings.cpp:1316–1319`, `savegame.cpp:348–490`).
Source saves do not include running script continuations or transient freeze and
control locks. Reload cancels pending scripts/text and clears `frozen`/`nocontrol`
so those unsaved continuations cannot leave the player stuck. The source
`SAVEBOT.c:18–48` machine path freezes Dink, offers choices, unfreezes and saves;
its actual script and menu input are covered alongside ambient-speech saves.
