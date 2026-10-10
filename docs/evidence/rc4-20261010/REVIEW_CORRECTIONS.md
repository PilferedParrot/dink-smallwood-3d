# Blind-review corrections — 2026-10-10

GPT-6.1 Sol high integrated the lead's six selected findings from the independent
Claude review. The original findings remain unchanged in the review worktree.

| Finding | What broke | Why we made it / correction |
| --- | --- | --- |
| F1 speaker behind card | Rotation targeted an approximate actor head without measuring the opaque card or complete rendered art. | We treated facing the camera as sufficient visibility and stopped the visual check too early. Measure the final card and decorations before revealing them; project cleaned source art or mesh bounds into the remaining viewport; validate room rays and visible effect alpha. Restore player rotation after the line. Mother at both viewport sizes and text scales, Guard and Neighbor have class checks; an independent floor/top projection check fails the old pack. |
| F2 repeated equipment | Toast, text tags and original HUD icons repeated the same state. | We added feedback without identifying its existing owner. Keep original HUD icon slots, remove equip toast and text tags, retain actual arm/disarm scripts. The old packed feedback-ownership test fails. |
| F5 grief view | Self-speech retained a player view dominated by fire; an experimental camera did not pass its actual rendered gate. Prone editor death art had incorrectly used an upright card, putting much of its texture below the floor. | Initial reasoning confused inactive Mother with absence of her separate vision-1 death picture, then confused that card with an imported model. Inspect all seven one-frame static People/death editor assets and source hotspots; reuse original ground painting, preserving exactly one owner and original coordinates. A bounding-box effect test also rejected transparent fire pixels; replace it with exact cleaned alpha intersections for enabled NPC framing. The bounded grief search remains disabled and its negative evidence is preserved. The player view remains unchanged; original script freezes/movement remain. This is an accepted fallback, not a demonstrated fully visible death scene. |
| F12 split speech styles | Nonblocking say used the feedback banner while say_stop used the named card. | We equated nonblocking execution with a different visual channel. Share the named card while preserving immediate return, timeout, input and focus semantics. Generation/request ownership prevents old timers or pending ambient lines from closing blocking speech. The old pack fails the semantics test. |
| F13 stale version | Source and local reports still said 0.3.0. | We omitted release metadata during integration. Merge main, set candidate 0.3.2 and assert the actual F9 report version. |
| F14 cursor/equipment ambiguity | Cursor description looked like the equipped item's heading. | We did not distinguish selection from persistent state. Header uses current weapon/spell, separate Selected label describes cursor; a deliberately mismatched selection/equipment fixture checks both before and after real equip. |

Tests cannot certify every scene or accessibility configuration. Reduced motion
keeps the original eye, so an obstructed full-body fit can remain impossible.
Mesh visibility uses bounds and physics rays rather than per-triangle texture
opacity. Source-art effect tests use cleaned alpha and the active Sprite3D region,
flips, transform and near-plane distance. No scene-specific camera offsets were
introduced.

The first packed correction gate exposed two integration mistakes. Hiding the
panel for layout made the initial deferred Continue focus miss its visibility
condition; our logic tests emitted completion directly and missed the input
failure. Reveal now restores focus, and all ordinary speaker fixtures continue
through actual Enter events. Timed speech kept the gameplay hint at the same
screen height as its name: we had tested timing ownership without checking both
layers together. Timed speech now suppresses that hint and its backing. The
rejected packed frames/hash remain under
`tmp/rc4-evidence/post-review-failed-ui-ownership`; they are not final selections.

`tools/rc4_grief_alpha_probe.gd` preserves the negative diagnostic. Its final
all-effect/union extension is unexecuted; do not report it as a successful check.
Earlier evidence remains in `tmp/grief-ray-diagnosis.log`,
`tmp/grief-alpha-diagnosis.log`, and the failed rendered frame under
`tmp/grief-review-source`. Normal gameplay never enables the grief experiment.
