# North-south bridge ropes — 2026-10-08

Built on frozen rc1 `cc381df`, on the separate local row8 branch.
01 is an upper cap,03 a middle section and02 a lower cap. The rope spans are
bounded to independently measured wooden-plank rows, joined across screen
copies and the offset lower cap on701. Height36.5source pixels(0.913m) and
post cross-sections come from01. Terminal supports missing in the art are
explicit reconstructions from that post, not observed02 posts.02's remaining
tail stays grounded. Existing ray footprints and 2D movement data are retained.

[Final comparison sheet](final-before-after.jpg) contains original cameras on
416/448/480/512/544/701 and both axes/sides of448, short544 and offset701.
[Vision1](final-vision-1.jpg) and [vision2](final-vision-2.jpg) show533's separate
burned stubs and continuous run respectively. Full PNGs are in `final-frames`,
`final-vision-1` and `final-vision-2`. Direct editor-layer/vision camera setup
bypasses campaign progression; scripts and shadows are disabled.

The first material used complete source images on every rope face and sampled
timber/post pixels at seam/offset columns. The corrected side/bottom material
uses only neutral/olive03 rope core and adjacent dark outline: 3×57 atlas,
opaque source pixels, nearest valid-row repairs within the same donor column,
reflected shadow onto the unseen side, common source-world depth phase.
Actual materials, every mesh surface and UV phase are checked against original
pixels; no view-dependent shader swap is used.

**Visible limit for lead acceptance:** the original projected top/end textures
are deliberately retained. They still look striped and somewhat rigid up
close, especially `final-frames/after/448/axis-north.png`, `east-side.png`
and `final-frames/after/701/offset-701.png`. Astra passed the supported spans,
joins and side timber/opacity correction; that is not a full smooth-rope
material clearance. Changing those top colors is a separate canonical-view
tradeoff for the lead. The prior full-sprite frames/sheet remain as comparison
evidence in `frames` and `before-after.jpg`.

Original-camera material-change counts are recorded in
[material-canonical-delta.json](material-canonical-delta.json):54pixels on416,
37on448,124on701, zero on480/512/544; both533visions are byte-identical.
Coordinates/top UVs are unchanged; do not claim every full frame is identical.

**Checks:**14bridge tests passed, including deck bounds, all map/story-layer
builds, terminal supports, both sides of cross-screen/offset joins, preserved
central plank seams and actual donor material/phase. Selected new functional
checks fail on unchanged cc381df (3failed,10deselected). Removed-post and
moved-join corruptions of actual measured vertices fail the same validator.
The old whole-sprite side material fails the new two-surface/purity checks.

The real W key was held120physics frames starting(217,80)on448, heading north.
Before and after both end **(217,285)on416**. The initial map is scenario-loaded
without scripts; the normal crossing executes the next screen's path. Images
are `walk/before/walk.png` and `walk/after/walk.png`; exact stops are in
[walk.txt](walk.txt). This is one input-path check, not all-path certification.

**Static scope:** current NS placements are type1,brain0,script-empty,size100.
Layout/mesh caches use those source placements and vision layers; they do not
track arbitrary runtime movement/removal/editor-state mutation. No such
current-map failure was demonstrated. New dynamic bridge behavior must add
state-aware invalidation or deliberately extend this static contract.

Runs use nice10, Xvfb/software rendering, private XDG roots, Dummy audio and
bubblewrap input/audio/network isolation. Shader caches below local walk
profiles are deliberately excluded from the evidence commit. No GPU or push.
