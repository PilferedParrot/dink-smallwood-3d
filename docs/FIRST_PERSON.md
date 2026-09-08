# First-person Godot adaptation

The main scene uses `fps_game.gd`. It extends the existing campaign host to reuse
DinkC scripts, state, inventory, enemy brains, saves, music, and effects. Rendering
is replaced by `fp_world.gd`; the default game has no Sprite3D scenery or actors.

## World

Original source coordinates map uniformly to metres at 0.06 metres per pixel.
Each original 600 by 400 area occupies 36 by 24 metres. Neighboring outdoor areas
are rendered at their map-grid offsets. Their scripts become active on entering
that map, preserving the original campaign's ordering and persistence rules.
Interiors remain separate spaces reached through the original warp triggers.

The renderer maps original asset families to the 38 Blender models and procedural
wall, door, furnishing, and pickup geometry. Original ground sheets form the
terrain material. Original collision masks constrain movement; modeled solid
bodies provide projectile occlusion. This is a reinterpretation of the original
pre-rendered art, not a recovery of its original 3D source models. Related source
characters and props currently share models. Walking uses procedural movement
of model parts; full skeletal animation is not implemented.

## Controls and combat

Mouse and right stick control an eye-level perspective camera. Walking follows
camera direction, with strafing, sprinting, and jumping. A new adventure includes
a basic bow as a first-person adaptation; the original quest progression still
unlocks magic. Projectiles sweep 3D physics rays, hit modeled bodies at the aimed
height, stop on scenery, and invoke campaign hit/death callbacks. Menus release
the mouse and suspend projectile motion. Map changes discard old projectiles.
Camera orientation is stored with each adventure save.

Controller movement and aiming use device-independent input actions, so they
also work when the gamepad is assigned a nonzero device index. Both sticks use
a configurable radial dead zone; walking preserves stick magnitude and aiming
is scaled by elapsed time. Settings also offer look sensitivity and vertical
inversion. LB/RB cycle equipment, Back/Select opens equipment, Start pauses,
and A/B confirm or leave menus. D-pad and left stick navigate menus and adjust
settings, with scrolling following the focused control. Gameplay hints follow
the most recently used input type.

## Verification and limits

`tests/fps_test.gd` covers the real FPS host, opening story, house exit, neighbor
rendering, perspective camera, UI capture, save/load, and controlled projectile
hits, height misses, wall occlusion, pause, and map changes. Existing campaign and
VM tests remain available. `tests/fps_capture.gd` captures actual rendered views.
`tests/fps_controller_test.gd` exercises simulated controller gameplay input;
`tests/ui_controller_test.gd` covers controller navigation and menu controls.

All imported areas use the 3D renderer. A complete campaign playthrough has not
been certified. The original screen-based script activation is retained, and
scenery mapping is by asset family; some set pieces and characters share forms.
New assets are generated locally in Blender with their source and generator
included. Existing third-party artwork and audio keep their original licenses.
