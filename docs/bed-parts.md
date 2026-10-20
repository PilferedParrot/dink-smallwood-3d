# Source-derived bed parts

The source is `game/assets/graphics/inside/details/inacc-03.png` (121 × 93).
`game/data/bed_measurements.json` records pixel landmarks on post caps, feet,
quilt edges and rails. A bed contains six closed convex prisms: bedding, frame
and four posts. Each physical part has separate material surfaces. All 16 source
beds use the assembly, including the 70% instance; source size scales geometry,
height metadata, ray triangles and placement-height queries together. Source
movement hardness is unchanged.

## Parts meet in physical space

The three visible post heights are 31, 32 and 29 source pixels. The hidden rear
foot uses their median 31, an explicitly inferred dimension. Each post's ground
footprint is its measured cap plus its height in sourceZ. The source bedding
corners must fall within the corresponding post footprints. Intersecting those
four vertical scanline constraints gives bedding height 25.5..27.7142857 pixels;
its midpoint 26.6071429 gives clearance inside all four posts. The top's source
projection remains `(X,Z-Y)`: changing height also changes physicalZ by the same
amount. Cloth/rail heights use the same ground reference and measured edge
rows, so bedding meets frame, and both overlap each post. The rail's 3 pixel
thickness is measured from the source; it is not enlarged for a target view.

The previous 31 pixel bedding height was inherited from the outer silhouette,
without checking contact against the individually measured posts. That left
real gaps. The technical cause was inconsistent physical footprints; the
process cause was conflating post height with bedding height and stopping the
geometry check at size and solidity. The contact gate consumes actual emitted
indexed vertices, derives each convex XZ footprint and Y interval, and requires
positive overlap for all nine bedding/frame/post contacts. A four-source-pixel
outward post displacement stays red with correct materials; a uniformly scaled
and translated complete bed stays green. Its convex-envelope method applies to
these closed prism parts, not to arbitrary concave furniture.

## Every face uses its own source region

The measured visible source domains are:

| Surface | Source region |
|---|---|
| Bedding top | `(44,9),(112,44),(77,62),(9,27)` |
| Long hanging cloth | `(9,27),(77,62),(70,74),(12,44)` |
| End hanging cloth | `(77,62),(112,44),(108,56),(85,68)` |
| Long rail | `(12,44),(70,74),(70,78),(12,48)` |
| End rail | `(85,68),(108,56),(108,61),(85,73)` |
| Posts | Four measured post polygons |

Post pixels own occluded corners; rails own cloth/rail joins; hanging cloth owns
its shared edge with the top. Authored pixels inside each assigned domain remain
byte-exact. Unknown samples use P4a's native authored-square continuation, with
every donor recorded. Long cloth uses only long-cloth donors; end cloth uses
only end-cloth donors. Top continuation uses quilt donors, excluding pillows.
The thin diagonal long rail has no 3×3 authored square alone, so unseen rail
samples use the union of the two rail regions. No rail borrows cloth or posts.
Opposite faces translate to their visible counterparts, preserving head/foot
position; the shared prism helper's default behavior for other callers remains.

A single pooled cloth atlas previously allowed a vertical face to borrow top
quilt/pillow content. Wood-versus-cloth purity could not detect that. This was
a gate-design error: the first mechanism found was treated as a sufficient
account of the visible defect. The new gate classifies actual emitted planes
from geometry, checks actual imported RGBA hashes, then checks every sampled
donor against that face's independently measured source region. The reviewed
`18897e8` meshes/donors are committed as a red calibration artifact. Top borrowing
and long/end-swapped all-cloth controls stay red; original side samples and the
correct emitted faces stay green. The earlier local role gate still rejects
all five original unsplit faces while retaining authored grain and multicolour
bedding controls.

Reverse faces, missing samples, the frame's hidden top and the inferred rear
post sides are identified in the four-view diagnostic tint sheets. Cyan marks
a directly sampled authored pixel on a measured visible surface; magenta marks
continuation, a reverse/underside face or an inferred rear-post side. These are
rendered from the same geometry and donor maps as the normal pictures.

Pillows and cloth folds still have planar geometry. A uniform cloth prism also
has a longer end hanging area than the source's end strip; extra end pixels
are inferred from end cloth. The gate certifies contact and face provenance,
not grain repetition, join appearance, drape geometry or shadow fidelity.

## Class and camera regression

The census covers 16 beds on 14screens. The shared interior prism helper also
emits already separate legs of table-09/table-01/table-07. The adjacent separate
box constructor has 18 chest frames and 8 crate/stack frames. Their four-side
inspection records unresolved open-lid flattening and broken composite stacks;
the bed gates do not certify those props.

G2 compares 14 room cutaways and 16 isolated bed pictures from the original camera.
Only inferred ceilings/beams are hidden in room views. Rooms 6/36 hide their
beds behind source walls: a white-with-original-alpha mutation has zero visible
pixels and the first centre ray hits a wall. Their whole frames remain compared;
the isolated fixtures visibly expose all 16 actual beds. An intact-ceiling
control stays red for visibility. Every material mutation uses a fresh map.

Masks were independently projected before after-renders: actual baseline mesh
bounds plus source envelope X0..121, Y0..32, Z31..93 at each hotspot/size, with
raster quantization and Boolean Lanczos3 support. They include the old70%
stand-in. The contact/face-content fix retains those same masks byte-for-byte.
An unrelated outside pixel mutation must fail. The fixtures skip scripts and
campaign progression and disable shadows; a ceiling-obscured false zero-change
pass was inspected and rejected before registration.

Pre-existing wall overlaps have depth ties. On the unchanged base, perturbing
only wall resource slots flips every wall strip previously reported outside
the bed masks. Geometry arrays/textures remain unchanged. Unique fixture-only
wall priorities make opposite allocations identical on both affected screens.
G2 applies the same deterministic entity-id/child/surface order to both packs.
This holds a nuisance variable fixed; it does not fix or certify production
wall ordering. The original-camera claim is explicitly this controlled fixture.

Regenerate with Python providing NumPy, Pillow and SciPy:

```sh
python tools/bed_parts.py --audit tmp/bed-parts-audit.json
```

Post occlusion refinement: the source silhouette of a post also encloses cloth in front of its shaft. Two measured cloth polygons are subtracted before wood classification. Unknown post faces repeat an 8×8 authored wood square at (76,80); all 1,401 unoccluded source wood texels remain exact. The actual first-fix post donor map is retained as a negative control. Technical root cause: cloth occlusion was labeled as wood and repeated on reverse faces. Process root cause: we assumed the post outline was a material mask, then trusted that same coarse label in the gate. The calibrated gate now rejects that real atlas; this remains a measured source classification, with the ambiguous lower-right boundary retained conservatively.
