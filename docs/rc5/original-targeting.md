# Original sprite targeting — primary source, 2026-10-11

GNU FreeDink109.6 engine source, distributed by Debian109.6-8:
https://sources.debian.org/src/freedink/109.6-8/src/freedink.cpp/
https://sources.debian.org/src/freedink/109.6-8/src/gfx_sprites.cpp/

Downloaded source bytes from the matching Debian `data/main/f/freedink/109.6-8/src/` HTTPS URLs. These are first-party engine code, not forum descriptions.

`freedink.cpp:240` (`run_through_tag_list_talk`) starts with the target's current image hardbox, offsets by the live sprite position, inflates10px, and extends in the player's facing direction (50px horizontal or35px vertical). It tests the player's point inside that rectangle, then invokes TALK if the target script defines it.

`freedink.cpp:571` (`run_through_tag_list`) likewise uses the target's current image hardbox, offset by the live sprite origin. It adds the documented melee margins and directional range (default28horizontal/36vertical), tests the player's point, and invokes HIT where present. A zero-hitpoint object can remain targetable; that does not imply it can take damage or is a quest objective.

The `gfx_sprites.cpp:309` loader uses supplied hardbox dimensions where present, otherwise derives defaults from image dimensions. Targeting uses that resolved hardbox, not an independently inferred picture box. The port already preserves the frame hardbox in sequences.json and applies explicit live/editor override through game._hard_rect. FPS `_fps_melee_hit_rect` is based on that same source rectangle.

For a ray-only body on a nonstanding scripted hazard, using this exact horizontal source rectangle is faithful to the original targeting domain. A measured source-picture vertical thickness is a 3D presentation inference, not recovered source height; it must not add movement collision. Primary targeting does not require thorn HIT/TALK handlers to exist. The thorn script defines only startup touch damage, so its actual campaign role is hazard/contact, not search or key collection.
