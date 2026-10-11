# RC5 static hardness census — 2026-10-11

570 outdoor screens; 603 authored vision-layer fixtures.
17 stone-wall screens: [244, 385, 386, 387, 388, 417, 420, 449, 450, 451, 452, 536, 625, 680, 681, 712, 713]. Snake-only screen 238 makes 18 sprite-wall screens.
Vision0 effective-hard pixel attribution: {'nothing': 1559742, 'built_solid': 2014580, 'billboard_object': 3081512, 'sprite_wall': 196871, 'tile_forest': 407990, 'water_cliff_edge': 1126050, 'sprite_decoration': 18927}.
712: 19389 wall-projected hard pixels; no fitted wall volume.
375: 5457 forest-associated hard pixels;
707 unresolved hard pixels in 42 components.

The JSON preserves every effective hard pixel as classification runs, every removed/added
source cell, every original hardbox owner, wall candidates and every unresolved component.
All counts are pixel counts before movement-dependent clearance escape. Categories describe
source/renderer attribution, **not certified eye-level visibility or exclusive ground ownership**.
Wall projections and forest-connected masks lack standing volume on this base. Billboard
hardboxes have their own category. Ambiguity is counted separately; categories partition each
fixture rather than adding overlaps twice. Natural terrain attribution excludes grass from
inspected rock/cliff/snow/water atlas families, with the rule preserved in the compiler.

Unresolved source breakdown: {'tile_hardness': 1408634, 'ground_picture_hardbox': 79368, 'invisible_sprite_hardbox': 71740}.
Native collision probes: 112761; mismatch fixtures: 0.
Inert house control 439: {'nothing': 0, 'built_solid': 64608, 'billboard_object': 0, 'sprite_wall': 0, 'tile_forest': 0, 'water_cliff_edge': 0, 'sprite_decoration': 0}.
Top unresolved components (screen, area, bbox): [(145, 47090, [20, 0, 620, 400]), (208, 18750, [245, 0, 620, 400]), (680, 18628, [105, 150, 620, 400]), (370, 17175, [20, 150, 470, 400]), (681, 14122, [20, 150, 449, 400]), (208, 13750, [370, 0, 620, 325]), (712, 13735, [70, 0, 320, 325]), (336, 12550, [245, 250, 620, 400]), (367, 12513, [395, 75, 620, 400]), (600, 12500, [370, 0, 420, 400])].

Static graph from outdoor home439 (323,390), including vision0 warp edges: 530
screens, 100397252 plain-free pixels;145 walking connected:
False, static-warp connected:
True. Reachable boundary categories:
{'nothing': 246852, 'built_solid': 58637, 'billboard_object': 127352, 'sprite_wall': 8818, 'tile_forest': 47528, 'water_cliff_edge': 377931, 'sprite_decoration': 664}.
Top unresolved reachable boundaries: [(145, 774, [20, 0, 620, 175]), (208, 774, [245, 0, 620, 400]), (145, 724, [20, 275, 620, 400]), (208, 574, [370, 0, 620, 325]), (145, 550, [45, 24, 595, 25]), (188, 482, [414, 0, 620, 37]), (176, 400, [245, 0, 246, 400]), (176, 400, [269, 0, 270, 400]), (176, 400, [370, 0, 371, 400]), (176, 400, [394, 0, 395, 400])].
Startup scripts, story state and fractional arrivals are excluded; this does not establish
campaign reachability or certify every reachable boundary's visibility.

Known-case validation: 712 wall pixels >0, 375 forest pixels >0 and unresolved components >0;
17/18 distinction asserted. No gameplay masks or rendered objects changed. Existing helpers:
collision_map.tile_mask/rect_mask/poly_mask; rc4_fir_stand_fit.source_canvas/forest_hardness;
native fp_world dispatch and per-part seam rules. Prior art: PyDink's tile/sprite/hardness
editing model (https://github.com/wijnen/pydink); no external depth/ownership implementation
found for Dink's source art. Footprints now use native integer-pixel point queries.
Visual ownership review remains necessary before item2's collision migration.
