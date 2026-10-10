# RC4 continuous screen crossings — 2026-10-10

The first-person world places neighboring screens 600 × 400 source pixels apart.
The inherited overhead transition instead jumped to x32/608 or y10/390 after
checking only the departing screen. A legal departure could therefore land in a
tree, wall or tile mask and reject every subsequent movement direction.

FPS crossings now preserve world coordinates, query the incoming screen's
cached immediate startup state before entering, and divide player displacement
into steps no larger than one hardness pixel. Both axes normalize at corners;
horizontal row wrapping and nonexistent/indoor neighbors are rejected. Map
startup, music and script dispatch still pass through the existing transition.
Authored tile masks, entity hardboxes and building footprints are retained.

Native vision-0 editor-layer survey (startup scripts deliberately skipped):

| Behavior | Edge samples | Accepted crossings | Free 10px grid points | Zero-motion traps |
|---|---:|---:|---:|---:|
| Old FPS on compatible base | 221,656 | 207,448 | 1,281,755 | 1,586 |
| Continuous FPS, masks retained | 221,656 | 204,275 | 1,281,755 | 0 |

The adjacent JSON reports preserve every failing position and the final counts.
All 570 outdoor screens were sampled, at 5px spacing along four edges. Cardinal
and diagonal movement attempts use native axis ordering and normal/sprint step
sizes. A sample is a zero-motion trap only if every attempted direction fails;
an ordinary wall stopping one direction is not a trap. This survey does not
prove exhaustive reachability, a path to free space, or delayed script behavior.

Five integrated checks passed: the full sweep, four keyboard-driven seam vetoes
with reverse escape, four clear/blocked diagonal corner fixtures, the legacy
376→377 clearance-band escape, and actual duck-preview boundary crossing.
The original band regression remains explicit for saved/scripted x32 arrivals;
normal FPS entry now lands continuously at x21 in that fixture. Old FPS fails
the new sweep (1,586 traps) and all four seam keyboard vetoes.

Profiles were isolated and all Godot runs used Dummy audio. Before export replay
409→377 at x50 stopped trapped at (50,390), captured at
`tmp/rc4-evidence/collision-before/409-377.png`. Final export replay is pending.
Existing resource/RID shutdown warnings are not a lifecycle-cleanup claim.

Separate unresolved item-1 scope: source hardness without visible support.
The ranked 141-screen custom-mask overlays and four-state hidden-entity audit
live in `tmp/rc4-evidence/masks/` and `tmp/rc4-hidden-audit/`. Those masks must
retain their authored barriers while visible geometry is derived from their
actual tile/sprite provenance. The startup sandbox stops at blocking commands
and omits later dynamic blockers; collision prediction inherits that limit.
