# Render determinism, 2026-10-12

## Mechanism and controls

The RC5 screen-496 fixture was quiet in 20 launches each at llvmpipe thread
settings 1, 4 and unset: all 1,500 images matched. That alone did not explain
CI's retired screen-251 fixture. An isolated cc381df snapshot reproduced its
cross-process noise in 3/20 single-thread and 5/20 four-thread launches. Nine
views changed one or two pixels, with a maximum channel change of 74. The
reported `(18, 17)` surviving/outer-view tuple occurred in this reproduction.
Changed-launch counts compare each matrix with its first-launch reference.

Changed pixels in the 960 x 540 historical frames, coordinates from the top
left. The region column is an inclusive bounding box over the changed pixels;
the last column is the largest observed RGB channel difference, on 0..255.

| View | Changed pixels | Region (x0, y0, x1, y1) | Max channel change |
| --- | --- | --- | --- |
| ring-251-230-225 | 1 | 225, 244, 225, 244 | 45 |
| ring-251-230-135 | 1 | 587, 192, 587, 192 | 57 |
| ring-251-130-045 | 1 | 653, 233, 653, 233 | 55 |
| sheet-251-1 | 1 | 609, 214, 609, 214 | 36 |
| ring-251-130-270 | 1 | 630, 219, 630, 219 | 26 |
| band-251-207 | 1..2 | 217, 332, 413, 397 | 48 |
| cabin-251-3 | 1 | 597, 237, 597, 237 | 74 |
| ring-251-230-180 | 1 | 436, 369, 436, 369 | 22 |
| cabin-251-0 | 1 | 315, 299, 315, 299 | 7 |

Eight instrumented processes supplied 800 exact repeated frames. Their binary
camera transforms, scene order, mesh arrays and runtime texture contents agreed.
The cabin's three material slot indices changed relative order, predicting the
pixel state. Three forced forward and three forced reverse launches were exact
within each order; each order reproduced one of the original pictures. After
the source fix, 20 launches each at threads 1 and 4 produced 1,000 exact images
on the historical fixture.
Pinning one thread did not fix the historical noise. Freezing gameplay earlier
also failed: 13/20 launches differed from that experiment's first reference.

Godot's implementation confirms the ordering mechanism:
[rasterizer sort keys](https://github.com/godotengine/godot/blob/4.6.1-stable/drivers/gles3/rasterizer_scene_gles3.h),
[material local indices and priority](https://github.com/godotengine/godot/blob/4.6.1-stable/drivers/gles3/rasterizer_scene_gles3.cpp).
The documented [3D material priority](https://docs.godotengine.org/en/4.6/classes/class_material.html#class-material-property-render-priority)
also preserves the separation between opaque and transparent passes.

## Geometry and material cost

The native catalog contains all 33 fitted base models: ten houses/church/cabin,
ten castle definitions, six huts and seven kits, initially 20,120 triangles.
Independent coplanar triangle intersection checks distinguish positive area from
shared edges. Cabin has no duplicated positive-area face and one cross-material
shared ridge. Exact dormer copies accounted for all positive-area overlaps
between different material surfaces: kit251 five dormers describe two distinct
solids, kit537 six describe four, kit570 two describe one. Same-mesh internal
block faces are a separate, deterministic category. Removing the six copies
leaves 20,066 triangles and no positive-area overlap between different material
surfaces in the same 33-model catalog.

All 570 outdoor scene builds were censused. The largest cached fitted model has
six emitted surfaces: priorities 0..5 within the supported 0..127 range. The
constructor rejects counts outside that range at runtime. Call-site inspection
found no fitted-material priority setter; the separate Sprite3D actor ordering
in game.gd remains its own policy. Ordered copies own their priority, keep
alpha-scissor settings and sharing, and prune dead transient source owners.

Four headings through freshly loaded scenes, llvmpipe with four threads:

| Scene | Why selected | Active explicit materials, before/after | Active + cached explicit materials, before/after | Draw calls, before = after |
| --- | --- | --- | --- | --- |
| 10 | Highest loaded drawable count: 914 | 8 / 8 | 18 / 30 | 852, 826, 607, 878 |
| 15 | Highest tagged house/castle mesh count: 45 | 63 / 63 | 67 / 80 | 762, 350, 120, 452 |

Counts include explicit scene materials and fitted-builder cache materials;
implicit Sprite3D materials and other engine caches are outside that counter.
The scene-selection tag counts house/castle meshes; the six-surface capacity
check covers cached houses, castles, huts and kits.
No frame-time or player-experience improvement is claimed from unchanged draw
calls. The cached copies add 12/13 material resources in these launches.

## Verification status

The exact/stability class is the fitted-surface regression, sideflip rendered
gate, tree draw-order rendered gate and neighbour-picture stability gate. Each
gets ten independent runs at one thread and ten at four threads. The tolerant
class is cards, castle, huts, bridges, bridge rails and fences; three runs at
thread settings 1, 4 and 1 record each printed metric's spread and threshold
margin. Seams, landmarks, interiors, posters and bake inspect geometry or source
texture data rather than a rendered framebuffer. Capture-only presentation
tests prove capture and game assertions without comparing golden pixels. These
checks remain in the full suite.

The final exact/stability audit passed all 20 runs: 80 test executions and 180
native launches, 90 each at one and four threads. No flaky gate appeared.
All 18 tolerant native runs and their existing Python assertions passed. Every
one of 184 matching printed numeric metrics had zero spread across the three
runs, at the logged precision. Selected closest margins:

| Family / measurement | Observed | Required | Spare margin |
| --- | --- | --- | --- |
| Cards: east tree width | 235 px | at least 0.8 x 235 = 188 px | 47 px |
| Castle: smallest wrong-control XOR gap | 0.0278 | greater than 0.0200 | 0.0078 |
| Huts: largest fitted XOR | 0.0763 | below 0.0900 | 0.0137 |
| Bridges: central water fraction | 0.0004 | below 0.0800 | 0.0796 |
| Bridge rails: smallest axis silhouette | 216 px | at least 100 px | 116 px |
| Fences: axis silhouette | 5,893 px | greater than 1,000 px | 4,893 px |

The castle control gap is the narrowest checked fractional margin. Its zero
measured spread supports this driver; remeasure that margin on other Mesa
versions. The castle's fitted-XOR margin is 0.0320 and colour margin is 6.522;
the hut controls retain additional XOR gaps of 0.0223, 0.0853 and 0.2173 beyond
the required 0.02. Tree shadows cover 10,187 pixels against the 3,000 minimum.

The host's full suite passed 200 tests in 1,823.55 seconds, with no skips, using
Python 3.14.7, pytest 9.1.1, NumPy 2.5.3 and Pillow 12.3.0.

The isolated Ubuntu 24.04 workflow passed: import succeeded, pytest reported
193 passed / 7 skipped in 1,808.00 seconds, and the 45-second-bounded smoke
reported `SMOKE PASS: FPS world, player model, save/load` and exited zero.
It uses its own Python 3.12.3 environment, the workflow's pip/install/import/test
and smoke commands, and the official Godot 4.6.1 archive verified against its
published SHA-256. It shares the host kernel/CPU and limits Docker to eight CPUs;
Ubuntu's Python patch version substitutes for actions/setup-python's selected
3.12 patch. It exports the working source without host Git metadata or tmp
artifacts and uses Mesa 25.2.8 / LLVM 20.1.2, the same driver as the host.
Its resolved packages are pytest 9.1.1, NumPy 2.5.4 and Pillow 12.3.0.

| Check | Passed | Skipped |
| --- | --- | --- |
| Full host suite | 200 | 0 |
| Full fresh Ubuntu workflow | 193 | 7 |
| Ubuntu ffmpeg supplement | 1 | 0 |

Five skips require installed FreeDink reference data: mother layout, opening
scripts, sequence metadata, home warp and sound manifest in test_assets.py.
The workflow has no FreeDink-data installation step. One skip requires ffmpeg;
apt ffmpeg 6.1.1-3ubuntu5 was added to the container and the audio rebuild check
passed separately. The workflow itself does not install ffmpeg, so its coverage
depends on runner tool availability. The seventh reads
ignored `tmp/rc5-pocket-audit/ray-census*.json`; a fresh checkout and the workflow
do not provide that artifact. These six unavailable evidence checks are distinct
from missing native executables: Godot/xvfb are required, and the executable
render and live hit-target checks ran.

The stored ray-census check now has the registered `local_evidence(reason)`
marker and an explicit missing-local-artifact reason. The project-tmp input
search found no other such tests; the legacy baseline is in the same check.
This final metadata-only follow-up was verified separately: one host pass,
one expected fresh-Ubuntu skip, and exactly one of 200 tests selected by the
marker, with no warnings. No census generation was added to CI.

The smoke emits shutdown RID/ObjectDB/resource warnings after its pass. An
unchanged f005b52 snapshot also passes/exits zero with the same warning
categories: 24 material RIDs, 34 mesh RIDs and 25 resources still in use. Its
texture count is 90 versus the container's 95. This unit does not certify clean
shutdown resource disposal.

Native render checks do not claim cross-driver golden images, arbitrary saved
story states or exhaustive player experience.
