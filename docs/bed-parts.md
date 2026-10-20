# Source-derived bed parts

The source is `game/assets/graphics/inside/details/inacc-03.png` (121 × 93).
`game/data/bed_measurements.json` records pixel landmarks on its post caps,
post feet, bedding boundary and the visible rail. These are measurements of the
source art, not measurements of a first-person screenshot. The hidden rear
post's foot is inferred using the median of the three visible post heights.
The measured cap-to-foot spans are 31, 32 and 29 source pixels. The bedding's
reference height is the existing silhouette-derived 31 pixels; a sample down
its long edge gives the cloth/rail join and rail thickness. Adjacent source
rows share a physical boundary, so there is no air gap between rail and quilt.

`tools/bed_parts.py` emits `game/data/bed_parts.json` and two derived textures.
A bed consists of bedding, a rail frame and four post prisms, with closed
undersides. It keeps the source projection `(X, Z - Y)` and the sprite hotspot.
The source's 70% instance uses the same assembly scaled uniformly, including
its ray body and height metadata. Source movement hardness is unchanged.
The bedding remains a planar approximation: pillow relief and individual cloth
folds are not reconstructed by this change.

Authored wood and bedding samples are preserved byte for byte. Where a part's
projection has no authored samples of that part, P4a's native authored-square
continuation supplies pixels from that part's own domain. Every donor index is
recorded. Missing bedding takes quilt donors; pillows remain authored features
and are not repeated into missing quilt. Missing wood takes wood, including
unseen post faces. These regions and the reverse sides are inferred material.
They are not a recovery of unseen original artwork. Native repetition can show
joins or repeated grain; the local gate does not certify those appearances.

Opposite bed faces translate to their authored counterparts. A point reflection
through the centre reverses both axes: it puts the source head's pillow pattern
at the foot on the opposite long side. Translation preserves position along
the long axis. The shared prism helper's existing behavior remains the default
for its other callers; the bed explicitly selects preservation of its ends.

The technical causes were an undivided prism receiving several physical parts'
art and a reverse-face mapping that exchanged the bed's ends. The process
causes were accepting the silhouette's box fit as the object's internal form,
then generalizing point symmetry to directional furniture. Previous tests
checked size and solidity without checking part ownership or end alignment.

The census covers all 16 bed sprites on 14 screens, including the 70% bed on
screen 66. The same interior prism helper also emits the already separate
legs of `table-09`, `table-01` and `table-07`. The adjacent prop-box constructor
is separate code: its source family has 18 chest frames and eight crate/stack
frames. Their geometry is not changed by the bed option. Wood/bedding masks
cannot certify a chest lid or the arrangement of stacked crates; those need
their own component references and rendered inspection.

Regenerate with Python providing NumPy, Pillow and SciPy:

```sh
python tools/bed_parts.py --audit tmp/bed-parts-audit.json
```

G1 first rejects all five actual baseline faces using local 3×3 windows that
mix separately measured wood and bedding domains. Authored wood grain and a
multi-colour bedding patch stay green; the unrepaired composite stays red.
Native constructor tests then check all 36 emitted part faces, their actual
imported texture bytes against donor provenance, and all 16 instances' scaled
height/ray geometry. A separate control fails on the legacy head/foot
reflection and passes the bed mapping. These checks measure the named material
and mapping mechanisms, not general fidelity of arbitrary composite props.

G2's fourteen committed source-camera masks are generated before examining any
after-render. They contain the baseline mesh bounds and the measured candidate
envelope, projected at each source hotspot and size, plus conservative raster
and Lanczos3 kernel support. They include the old 70% stand-in's bounds.
Frozen editor-layer fixtures skip scripts and campaign progression and disable
shadows in both pictures. Zero changes are permitted outside these masks; an
unrelated pixel mutation must fail each same mask. This is a controlled source
projection regression, not a certificate of shadow appearance or campaign play.
