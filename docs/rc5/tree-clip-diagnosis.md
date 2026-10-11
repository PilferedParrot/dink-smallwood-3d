# RC5 review finding: additional partial-tree family (2026-10-11)

The blind review found the common flat crown bottoms in the packed screen768 save frames. This diagnosis concerns the frozen RC5 commit8b70efa/export `d1bc5c42c2828b110b2fab757995ce7fec394838b23646024efd56c97b0496cc`, before the expanded correction. The forest preview was immediately held.

## Exact provenance and before comparison

Source screen768 editor2 is entity31, `Entity_31_dead_tree/Model`, seq32/frame8 at(353,174). Despite the legacy `dead_tree` key, its source is the green forest-edge collage `assets/graphics/lands/Trees/tree-08.png`,200×95px. The generic fixed-Y Sprite3D uses hotspot(133,69), offset(-33,21.5),0.025m/px, with quad vertical bounds[-0.65,1.725]m. It has no region crop, no depth shader in this scene, no surface lift, and no whole-fir constructor. It is not a tile-forest mesh or the disabled RC4/RC5 forest stand.

The source image itself shows four fir crowns whose trunks/bases are missing, with substantial left/right/bottom crop contacts. Anchoring the69px hotspot to physical ground additionally hides rows69–94. With pixel centers, worldY=(69-row-0.5)×0.025, so the hotspot row69 is already below ground. There are9348 nonblack opaque source pixels,3535 below ground (2099 green-dominant), including127 in row69. An early diagnostic mask excluded that row and reported3408; the corrected class formula is applied to all13 frames and cross-checks the frozen package.

Packed captures at exactly the same north(322,78.625,yawπ,pitch-.45) and south(322,240,yaw0,pitch-.45) poses use the actual0ac3ea1 archive and frozen8b70efa package, with startup scripts skipped and HUD/held tools hidden. In both versions, hiding **only editor2's Model** removes all three visible north cut crowns and the shared foreground cut line in the south view. These eight frames were inspected. The defect predates RC5. The surrounding09/10 parts differ between versions, and their whole-fir trunks become visible when the foreground strip is hidden.

Evidence: `tmp/rc5-crown-diagnosis/crowns-before-after.jpg`, full-size PNGs/JSON in `before/` and `after/`, pose JSON `views.json`, and `baseline-pack.sha256`. `tools/rc5_crown_provenance.gd` derives node/texture geometry and performs visibility isolation in the packed game. Hiding is diagnostic scenario setup, not a gameplay fix.

## Class census

The retained [native inventory](tree-clip-native-8b70efa.json.gz) and [source/native summary](tree-clip-census-8b70efa.json.gz) contain869 outdoor source tree placements across all seq32 frames1–13. Native seam eligibility finds793 standing vision0 placements and one in its own alternate authored vision. Every one has a representative native geometry sample. The collector computes570 actual5×5 scene blocks and seam flags; it does not assemble/render570 complete gameplay scenes or execute startup scripts.

Frame8 has40 authored placements:38 standing and2 ground-painted. All38 standing owners remain generic billboards. They belong to24 source screens and are potentially eligible in199 scene centers,786 owner appearances. A cheap original-source audit finds no neighbour fingerprint duplicates involving frame8. Dynamic startup remains unverified. One frame8 owner has a depth-shift shader; its ground occlusion effect is not established by this headless inventory.

Affected source screens:186,208,209,238,239,251,273,279,280,281,282,283,288,303,333,334,335,560,568,735,736,766,767,768. Every source screen and scene-center row is preserved, including245 source screens without trees and22 scene centers without standing tree candidates. Generic visible region crops:0. Native09/10 inventory still cross-checks165 shown whole-fir parts from123 source placements/246 parts.

Border contact is screening evidence, not a trim definition. The complete frame1 template itself has six nonblack top-border pixels and one right-border pixel. Frames2–7 also have natural apex/frond contacts; frames11–13 are stumps. Their contacts cannot justify turning them into firs. Tree01/02 have72/9 green-dominant pixels below their generic hotspot; this is a color proxy and an inconclusive visible-crown result, not a half-crown certification. All source/frame contact counts and per-owner classifications are in the JSON.

## Both causes and revised gate

What broke: a multi-crown forest-edge trim was treated as one complete standing object; a two-dimensional source hotspot became the physical ground anchor and clipped additional foliage. Why we made it: the importer generalized the per-picture billboard rule without checking whether that picture contained complete objects. RC5 then scoped the class instrument and constructor to vertically stacked09/10 art. The123/246 count was correct for that narrow mechanism, but did not establish that every standing tree picture was whole. That was reasoning stopped short at known asset IDs; the broad whole-object principle remains right, the asset-ID shortcut was wrong.

The reviewer prompted a new all-frame instrument. Its pixel-center off-by-one came from treating an integer row boundary as a pixel center, a diagnostic oversight; the corrected formula tests the entire source-frame family.

The lead's initial literal border-touch criterion was challenged because it also classifies the complete template and natural contacts as trims. The corrected authorized criterion is confirmed missing structure: a cut crown, missing trunk/base, or correspondence to a whole-tree crop. Confirmed fir trims8/9/10 use the same whole original fir/shadow constructor; natural-contact controls stay unchanged; partial art of other species is reported rather than converted to fir. The expanded implementation and collision/topology/interaction gates are a later unit. This diagnosis changes no runtime, source art or collision. The forest preview remains held.

## Reproduction

Run the native collector with Godot4.6.1 headless/Dummy, nice10 and single-thread math settings, passing `--out=<absolute JSON>`. Use a named systemd user service with runtime identity variables and an absolute log for a long collection. Then run `/usr/bin/python3 tools/rc5_tree_clip_summary.py --native <JSON> --out <summary JSON> --summary <text>`. The historical data is tied to8b70efa; subsequent constructor changes must not be described as this frozen run. For visible provenance, run `tools/rc5_crown_provenance.gd` through the frozen package with screen768/scripts0 and the saved pose batch.
