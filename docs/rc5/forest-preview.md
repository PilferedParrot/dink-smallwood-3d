# Disabled forest picture fixture, screens 144 and 375

This is a local prototype for Chris's picture decision. No production game
caller enables it. `rc5_forest_preview.gd::build` defaults to disabled and rejects
every center except 144 and 375. Only the external preview harness opts in.
It adds whole original seq32/frame1 firs through `SourceFir.at_foot`, including
that constructor's shadow twin, with collision false. Source entities, tile
hardness, completed-fir collision and interaction methods are unchanged.

The relaxed root rule accepts any raw source-hard pixel in a four-connected
component touching forest tile art. The fitter reuses RC4's contour extraction
and checks its exact full-pixel SHA and count. A deterministic greedy cover
adds roots to cover the stricter 43px root-disc proxy, subject to a minimum
spacing from the source's own crowns; it also measures 47px. Tree08's measured
apexes `(1,12)`, `(39.5,0)`, `(123,0)`, `(201,12)` yield a 40.326790102858425px
minimum nearest-neighbor spacing. RC4's four hand-identified atlas foreground
tips have a nearest distance 87.14355971613737px; even allowing 4px uncertainty
per axis, their 75.82985121715261px lower bound cannot change the winner.
Every new root must be at least the tree08 spacing from existing/completed
roots and earlier additions. Existing authored roots are unchanged. Residuals
are reported for the chosen greedy stand, without claiming a global optimum.
These are two-dimensional source-foot proxies,
not proofs of eye-level occlusion, card placement or reconstructed volume.
Existing generic tree01 cards have a metadata hotspot distinct from the
measured art foot. The reported before counts retain that source-foot
instrument; they do not imply a newly measured native placement.

Variant A retains the original forest-tile ground. Variant B uses RC4's
`replacement_ground` unchanged, porting its exact owned forest-pixel runs and
source grass-donor provenance into this fixture's JSON. It changes the ground
texture only, with the same new firs and no source sprite suppression. Neither
variant constructs a curtain or shell. B's floor is an inferred picture from
source grass donors; the original forest atlas does not show its hidden floor.

Prior art reused: the project-native RC4 contour and forest-pixel ownership
compiler; RC5 whole-fir/shadow constructor; current static reach masks; packed
`fps_capture.gd` camera harness; and the native collision sweep's escape rule.
A fresh open-web check of [PyDink](https://github.com/wijnen/pydink) confirms
existing tile/sprite/hardness editing machinery. The open arXiv search found
single-image and multiple-image forest reconstruction work, but this fixture
does not reconstruct unknown botanical depth or introduce a new reconstruction
method. No new assets, models or research PDFs were downloaded.

Both causes of the earlier boundary failure: a density-based layout left
uncovered hard edges; we misapplied area density to a boundary task. The next
exact fit exposed grass-hard extensions outside the permitted forest-art
roots; we had treated two disagreeing source inputs as though they necessarily
coincided. This prototype changes the root admissibility rule explicitly and
tests every retained contour pixel. That addresses the measured class rather
than tuning the two reported gaps; visual judgment remains separate.

## Reproduction

Run only after the lead's CPU courtesy hold ends, with load1 at most 24. The
wrapper sets Dummy audio, disposable XDG directories, nice 10, single-threaded
BLAS and software rendering with at most six llvmpipe threads. It launches one
Godot at a time and never uses the player's profile or display.

```sh
# Use an existing environment containing numpy, scipy and pillow.
export FOREST_PYTHON=/path/to/existing/environment/bin/python
bash tools/rc5_forest_preview.sh fit
bash tools/rc5_forest_preview.sh parse
bash tools/rc5_forest_preview.sh export
bash tools/rc5_forest_preview.sh gates
bash tools/rc5_forest_preview.sh capture
bash tools/rc5_forest_preview.sh sheet
```

The fitter reads retained native inventories in `tmp/rc5-fir-eye/` and
`tmp/fir-collision/` (the final all-frame completed inventory), whose producer commands are documented in
`dispatch-and-fir-eye-reproduction.md`. Eye poses reuse
`tmp/rc5-d2-expanded/reach-masks.npz`. New outputs stay in
`tmp/rc5-forest-preview/`; the export stays in `tmp/rc5-forest-package/`.
The lead permitted three retained exports for this unit, preserving both
earlier packages. No package is installed or published.

The packed baseline column loads `tmp/rc5-package-2/`; A and B load the new
package with explicit flags. All captures use vision0 editor layers with
startup scripts disabled and simulation frozen. They skip campaign progression.
Neighbor prediction uses seed 20261011 in every column.
Each screen has four qualified eye poses and one orthographic source-camera
view. Camera selection requires current static reachability, no static
hardness and clearance beyond every recorded scaled 47px fir disc plus 20px;
the packed native gate separately checks actual hardness at each eye.

`gates.json` records full 240,000-cell native collision comparisons per screen
and variant, physics-body counts, a 10px interior/1px boundary escape survey,
eight talk/melee headings per walkable grid cell, and W/A/S/D events through
the real input mapping with a deterministic movement tick. These screens have
no authored scripted interaction targets; empty talk dispatch is expected.
The exact ordered melee target stream is hashed and compared, including
unscripted targets if the engine exposes any. This does not certify campaign, saved/dynamic script state or all-cell
interaction availability. Native logic checks do not certify rendering.

The artifact ledger enumerates frames and poses without verdicts. Findings
and verification results belong in the separate builder report, which a blind
reviewer reads only after recording independent findings.
