# Fitted-building material continuation

`game/scripts/building_continuation.gd` consumes the donor map in
`game/data/building_continuations.json`. Its facade hash must match
`game/prototype/facades.json`; an incompatible map is ignored with a warning.
Regenerate after changing source art or material composition as well as facade fits;
the runtime facade-hash check does not authenticate every source image.
The original geometry and source projection remain the authority. Continuation
changes only missing material where a fitted face samples outside authored
alpha support, excluding isolated black shadow dither.

A whole connected unsupported region takes a rigid integer translation into
supported pixels of the same material domain. Search prefers the face's physical
horizontal tangent projected onto the source lattice, then immutable-boundary
RGB error and displacement. Source doors and signs are protected at runtime;
base material supplies donors so they cannot be copied into a missing wall.
If the whole region cannot fit, the fallback repeats a fully authored square
from that domain at native spacing. Its phase minimizes the same boundary error.
A recursive split into unrelated translations was rejected because joins could
collapse the local provenance Jacobian. Periodic tiles retain distinct adjacent
source samples, including at wraps; their repetition can still show visually.
Singleton components retain the previous padding rather than introducing a new
inference where the local gate has no two-dimensional evidence.
Copying between source planes also carries their projection shear: native pixel
spacing alone does not preserve physical course direction. On the cabin's gable,
the long-wall donor's projected log courses slope−0.48 where the gable chart
needs+0.48, producing diagonal courses. The local provenance gate does not
certify material orientation across planes.

This is constrained patch reuse. [Efros and Freeman's *Image Quilting for Texture
Synthesis and Transfer* (2001)](https://www2.eecs.berkeley.edu/Research/Projects/CS/vision/papers/efros-siggraph01.pdf)
shows why native patches preserve texture relationships and mismatched patch
boundaries can reveal seams (Figures 2–4). This implementation neither synthesizes
new colours nor implements their general quilting algorithm.

Compatible per-face maps share atlases; ten conflicting domains remain private.
The 93 atlas groups include hut bands merged into deterministic material roles,
keeping the existing 128-role limit. Most groups crop to used UV bounds with an
8px gutter aligned to 8px. Thirty-three retain native dimensions because the
original camera's UV derivatives select mip levels. Gutters wrap the original
filled RGB, preserving its prior sampling behavior. Sharing asserts identical
donor assignments; it does not resolve conflicts by overwriting one face's map.

Regenerate using Python with NumPy, Pillow and SciPy, and Godot 4.6.1. `godot`
below denotes an isolated, Dummy-audio, software-rendered xvfb launch under the
studio's shared Godot lock. Use a bounded scratch directory; the image manifest
contains local scratch paths and is not an asset to commit.

```sh
mkdir -p tmp/building-source
godot --headless --path game --script "$PWD/tools/export_building_continuations.gd" -- \
  --source-out="$PWD/tmp/building-source" \
  --building-continuation-audit="$PWD/tmp/building-polygons.json"
python tools/building_continuations.py tmp/building-polygons.json \
  --images tmp/building-source/images.json --out tmp/building-continuations.json
python tools/pack_building_atlases.py tmp/building-continuations.json \
  --polygons tmp/building-polygons.json --images tmp/building-source/images.json
python tools/audit_building_continuations.py tmp/building-continuations.json \
  --images tmp/building-source/images.json --out tmp/building-audit.json
```

Inspect the audit and rendered comparisons before replacing the committed map.
The audit tests local distinct donor support, Jacobian singular values and
repeated-source runs against fully authored 3×3 controls. It records retained
singleton padding and excluded rank-deficient UVs separately. Re-run the native
building, door, collision and interior tests after integrating a map.

`tests/building_capture.gd` supplies deterministic scenario pictures, not campaign
progression. It freezes entities as well as simulation: merely stopping physics
does not freeze wall-clock animation. Original-camera fixtures retain the same
player position, neighbour seed and source scene on both builds. The three
committed masks are generated from unsupported source samples, not observed
before/after differences. Geometry overrides preserve depth and alpha while
painting only the permitted material samples white.

The original-camera crop is resized with Lanczos3. A filtered white image is
not a conservative mask: signed lobes can cancel to black while a changed RGB
sample still affects the output. `tools/building_render_gate.py` takes the Boolean
union of native mask samples in every actual kernel window, following
[Godot 4.6.1's image resampler](https://github.com/godotengine/godot/blob/4.6.1-stable/core/io/image.cpp#L1099).
The integration test requires zero changes outside that support and proves the
same mask rejects an unrelated pixel mutation. The mask does not certify visual
quality inside the inferred strips; inspect packed eye-level views as well.
