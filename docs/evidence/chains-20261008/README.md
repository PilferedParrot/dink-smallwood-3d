# cdoor-06 drawbridge chains, 2026-10-08

The final `after/` frames use the `cc381df` game with only `castle_doors.gd` and its fitted
`cdoor_chain_profile.json` changed. `baseline/` is unchanged `cc381df`. `rejected-draft/`
preserves the prior 4.4 × 3.0 × 0.56 px link attempt that Astra found to have oversized
holes. Each directory has the original camera, two oblique views, and a closeup of each of the
four arch/leaf joins. Every visible frame has a matching `*_hidden.png` with both chains
hidden. Baseline and final hidden frames are pixel-identical in all seven views, as are all
fourteen final isolated and integrated frames.

These are Godot 4.6.1 Compatibility renders on Mesa llvmpipe under private Xvfb/XDG and
Dummy audio, with shadows disabled. The capture loads screen 80, vision 0, without map
scripts: **scenario setup that bypasses normal campaign progression**. Astra/lead visual
judgment is required; the masks below measure source-camera geometry and tone only.

The source is `game/assets/graphics/struct/Castle/cdoor-06.png`. The broad chain-only palette
mask (`source-chain-mask.png`) is 633 opaque pixels at `x >= 65` above `_leaf_top(x)-3`:
median RGB `(49,49,57)`, p25 `(33,33,33)`, p75 `(70,74,90)`, p90 `(74,95,106)`.
In the narrower suspended right-chain fitting strip (rows 55–108, x 65–124, within 6 px of
the trace), source occupancy is 376/403 = 93.3%; seven enclosed apertures have areas
`[8,4,4,3,3,3,2]` px. This is why fitting the one-pixel bright stroke as the whole wire
failed. The rejected draft had 67.0% rendered occupancy and 15–19 px main apertures.

`tools/fit_chain_geometry.py` fits the projected 16 × 8 tube mesh to source opacity, balancing
iron and opening pixels and measuring row centering and occupancy. It fits major/minor/wire
radii, alternating plane tilt, centerline offset, longitudinal phase, and counts 18–21.
Rows 91–102 were held out; count 19 had the lowest training loss and also the lowest held-out
loss. The selected profile (`game/prototype/cdoor_chain_profile.json`) uses radii
4.9545 × 2.3505 px, wire radius 0.9803 px, tilt ±34.52°, interior normal offset −1.947 px,
and phase −0.574 px. Both endpoint centers remain at the original source-traced anchors.
`fit-report.json` records every count and the held-out results.
The fit uses the isolated right chain; the left chain shares the fitted link dimensions and
keeps its original anchors. Its overlap with arch and leaf art prevents the same clean mask.

The regression probe exports the **actual loaded Godot triangle vertices**. Its independent
4× raster has 365/398 = 91.7% occupancy, seven apertures `[6,6,6,5,4,3,3]` px, and
source binary IoU 0.8855. It differs from the fitter's modeled projection at only two native
pixels in the measured strip. At 8×, occupancy is 90.1%, with seven apertures and IoU 0.8656;
the held-out rows have IoU 0.8966 at 4×. The final visible-minus-hidden render at threshold
10 has 357/393 = 90.8% occupancy and 4–7 px main apertures. The original-camera changed
pixels have median RGB `(49,49,58)`, against source `(49,49,57)` and baseline
`(82,95,110)`. `metrics.json`, `geometry.json`, `actual-triangle-projection.png`, and
`fitted-projection.png` hold the measurements and masks.

The integrated `test_fps_doors.py` passes. It retains the original 2 px attachment/line
checks and the other door assertions, then checks source-derived palette, alternating link
planes, actual-triangle occupancy/aperture/alignment, 4×/8× convergence, and the held-out
region. It rejects the old thin-wire mesh, plain thickening, a filled strip, and a displaced
mesh. The test fails against `cc381df`'s old uniform chain. No commit or push was made for
this chain unit.
