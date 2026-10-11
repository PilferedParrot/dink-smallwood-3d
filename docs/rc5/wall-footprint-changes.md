# RC5 wall footprint changes — 2026-10-11

92,246 originally reachable free pixels become solid: the art-derived occupied floor plus its standard 4px clearance band. These are additions to authored source hardness, not pixels removed from another owner. The footprint comes from selected original stone alpha at ground AND ground-minus-74px, composed across screen seams. Height and contours are shared source rules.

|Screen|New occupied floor|New clearance band|Total|Source-space bbox (x0,y0,x1,y1)|Frames|
|---|---:|---:|---:|---|---|
|385|14454|5229|19683|[170, 95, 620, 400]|[1, 2, 5, 8]|
|386|15471|5367|20838|[20, 95, 620, 130]|[1, 2]|
|387|15472|5366|20838|[20, 95, 620, 130]|[1, 2, 3]|
|388|9167|4439|13606|[20, 95, 425, 400]|[1, 2, 3, 5, 6, 7]|
|417|5607|2138|7745|[170, 0, 345, 400]|[5, 7, 10]|
|420|0|1976|1976|[420, 0, 425, 400]|[5]|
|449|6212|38|6250|[320, 0, 345, 250]|[1, 2, 5, 10]|
|452|0|1310|1310|[420, 0, 425, 269]|[1, 4, 5, 9]|

The old source masks allowed entry into these drawn wall footprints (and the four-pixel approach band was absent there). Keeping the source masks alone would retain visible-wall walk-throughs. Replacing the walls with solids makes those parts of the picture obstruct traversal. The exact per-screen component runs and masks are in the topology/compiled fit artifacts. No piers, arch, ivy, cage or foreign sprite hardness was replaced. New neighboring composition/protection increases additions from 90,134 to 92,246 (2,112px); it also covers the formerly detached 550px screen449 pocket inside the source column. Source-free pixels that remain outside the wall are preserved, and unrelated source-hard pixels are retained even when still unexplained.

Whole-world checks: 599,070 actual FPS collision probes agree with the independent mask; only two fir pockets on768 remain cut off. Story/start/warp and interaction gates are recorded separately. The fit cannot claim the entire D1 residue: current census still has 243,472 potentially reachable unowned hard-boundary pixels.
