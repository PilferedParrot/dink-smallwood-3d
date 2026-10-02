# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Translates campaign coordinates into a solid, first-person world. No Sprite3D.
extends RefCounted
# Metres per source pixel, for the ground, the buildings and every position: the player's eye
# (EYE_HEIGHT, 1.65 m) stands where Dink's eyes are in his sprite, 66 px above his feet
# (docs/DIRECTION.md, eighth pass). The game logic stays in source pixels.
const SCALE := 0.025
const WIDTH := 600.0*SCALE # one screen
const DEPTH := 400.0*SCALE
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")
# Models that stand in for a sprite, sized to it; the rest keep their own sizes (or their hardbox).
# Not "crate": it stands in for anything scripted or unknown (tools leaning on walls, sacks), and a
# cube as tall as a leaning rake is a wall.
const SPRITE_SIZED := ["man","woman","wizard","knight","pig","duck","pillbug","bonca","slime","dragon",
	"oak_tree","pine_tree","dead_tree","barrel","chest","well","sign","gravestone","fountain"]
var host
var models: Dictionary = {}
var materials: Dictionary = {}
var terrain_cache: Dictionary = {}
var interior_cache: Dictionary = {}
var bounds_cache: Dictionary = {}
var interior := false
var light: DirectionalLight3D
var environment: Environment
var scene_generation := -1
# Fingerprint to the currently live structural node. A node reference lets
# save/load rebuild after the previous visual has been queued for deletion.
var structural_seen: Dictionary = {}
# Buildings fitted from their sprites (tools/facade_fit.py), built by scripts/sprite_buildings.gd,
# the prototype's own build; see add_fitted_building.
var facades: Dictionary = {}
var buildings # sprite_buildings.gd
var fitted_built: Dictionary = {} # world position key -> the node holding it (null: reserved), this scene
var plan_key := "" # scene, screen and story layer the plan below was gathered for
var plan_claimed: Dictionary = {} # "screen:index" -> true: sprites a fitted house draws (itself, its parts)
var plan_parts: Dictionary = {} # fitted_key -> the parts it draws (sprite_buildings.gd gather)
var plan_hulls: Array = [] # [wall footprint (world px), the house's hotspot (world px), its que, its screen, its bounding box(, a kit's upright sprites)]: see depth_rule
var sprite_heights: Dictionary = {} # sprite path -> drawn height above its hotspot, px
# Everything that is not a building is the original sprite itself, drawn as the prototype draws it
# (prototype/sprite_world_proto.gd _add_sprite; docs/DIRECTION.md, ninth pass): upright sprites
# stand at their hotspots as Y-axis billboards, directional actors pick their frame from the camera
# angle, structures (fences, walls, signs, huts: is_structure) keep the orientation they were drawn
# in, and background (type 0) sprites are painted into the ground. Castle and stone walls ("tower")
# are fixed cards of their sprites, as the prototype draws them, except the castle's fitted walls and
# towers (key "castle", built in 3D: add_castle_piece). Bridges are two kinds of art, not a model: the
# decks (bridge_part) lie on the water and are painted into the ground whatever their type, the railings
# stand as fixed cards. These keys keep their 3D build: fitted and unfitted houses, the castle's fitted
# pieces, doors, stairs, interior furniture and interior walls, and the arrow.
const BUILT := ["cottage","inn","door","stairs","shelf","table","chair","bed",
	"fireplace","cave_entrance","ruin","arrow","castle",""]
const ACTORS := ["man","woman","wizard","knight","pig","duck","pillbug","bonca","slime","dragon"]
# What the original draws without a shadow casts none here (shadow_twin). The art says which: a drawn shadow is a
# checkerboard of isolated black pixels (the dither clean_texture removes), and over every frame the map places
# upright, the fire (fire1), sparks, coins, grass tufts and the seeds have 0-8 such pixels, the holes and burns of
# the damage art 0-31 scattered specks, where a duck has 40-70, a tool 17-79, a barrel 133, a pig 123-277 and a
# tree up to 4,150. Light and things lying on the ground cast no shadow.
const SHADOWLESS := ["flame","effect","feed_grains","burn_scar","hole","coin","grass"]
# Dink directions (numpad) -> facing in source space (x right, y toward the original viewer).
const DIRS := {1: Vector2(-1,1), 2: Vector2(0,1), 3: Vector2(1,1), 4: Vector2(-1,0),
	6: Vector2(1,0), 7: Vector2(-1,-1), 8: Vector2(0,-1), 9: Vector2(1,-1)}
var clean_cache: Dictionary = {} # sprite path -> its texture without the shadow dither
var kit_members: Dictionary = {} # "screen:index" -> true: map sprites a kit building draws
var neighbour_actors: Array = [] # [Sprite3D, entity dict] of the actors the neighbour screens draw, this scene
var neighbour_states: Dictionary = {} # screen -> sandboxed startup state for this 5x5 block

func setup(game) -> void:
	host = game
	var path := "res://prototype/facades.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	facades = parsed if parsed is Dictionary else {}
	buildings = BUILDINGS.new(host.sequences,host.world,facades,SCALE)

func point(x: float, y: float) -> Vector3:
	return Vector3((x-320.0)*SCALE,0,(y-200.0)*SCALE)

# An interior is what the original's own map says it is: the per-screen indoor flag of dink.dat
# (world.json "indoor"; the engine keeps the last outdoor screen for the map by it). Every screen
# with interior wall sprites (innwalls) carries it. Counting wall sprites (3 or more innwalls or
# stnwalls) also took 18 outdoor screens for rooms: kit-417's courtyard (385-388, 417, 420) and the
# walled streets south of it (449-452), 238, 244, 536, 625, 680-681 and 712-713. All are flagged
# outdoor, every neighbour they have is an outdoor screen, and their "walls" are the stonw and snak
# stone-wall pieces of the stnwalls folder. They were drawn as rooms, with ceilings and no sky, and
# their neighbours showed wilderness in their place.
func is_inside(number: int) -> bool:
	if interior_cache.has(number): return interior_cache[number]
	var result := bool(host.world.screens.get(str(number),{}).get("indoor",false))
	interior_cache[number] = result
	return result

func source_path(e: Dictionary) -> String:
	var seq := int(e.get("pseq",e.get("seq",0)))
	var frame := int(e.get("pframe",e.get("frame",1)))
	return str(host._frame(seq,frame).get("path","")).to_lower()

# What a sprite is drawn as. It depends only on its picture (sequence and frame) and whether it has a script, so
# it is cached by those: the scene build asks it of every sprite of the 5x5 block several times a load.
var key_cache: Dictionary = {} # seq * 100000 + frame * 2 + scripted -> model key
func model_key(e: Dictionary) -> String:
	if e.has("fps_model"): return str(e.fps_model)
	var ck := int(e.get("pseq",e.get("seq",0)))*100000+int(e.get("pframe",e.get("frame",1)))*2+(0 if str(e.get("script","")).is_empty() else 1)
	if key_cache.has(ck): return key_cache[ck]
	var key := _model_key(e)
	key_cache[ck] = key
	return key

func _model_key(e: Dictionary) -> String:
	var p := source_path(e)
	var frame := int(e.get("pframe",e.get("frame",1)))
	if p.is_empty(): return ""
	if "innwalls" in p or "stnwalls" in p: return "wall"
	if "trees" in p:
		if frame in [8,9,10,11,12,13]: return "dead_tree"
		return "pine_tree" if frame == 2 else "oak_tree"
	if "shrubs" in p: return "bush"
	if "rocks" in p: return "rock"
	if "/grass/" in p: return "grass"
	if "/fence/" in p: return "fence"
	if "/garden/" in p:
		if frame >= 23: return "fountain"
		return "flowers" if frame >= 13 else "mushroom"
	if "/landmark/" in p:
		if frame <= 3: return "well"
		return "bridge_deck" if frame <= 6 else "sign" # landm-04..06 the stone bridge: its deck, parapets and arches
	if "/home/" in p:
		if frame in [11,12,13]: return "ruin"
		return "cottage" if frame in [1,4,5,6,7,8,9,10] else ""
	if "/outinn/" in p: return "" # Assembled as buildings, not one house per wall fragment.
	if "/cabin/" in p: return "cottage" if frame == 1 else ""
	if "/church/" in p: return "cottage" if frame == 1 else ""
	if "/building/" in p: return "cottage"
	# A castle piece fitted from its sprite (tools/facade_fit.py castle_fit) stands in 3D; the rest of struct/Castle
	# and the monuments of struct/Stone are cards ("tower").
	if "/castle/" in p and not buildings.castle_fit(frame_path(e)).is_empty() and absf(float(e.get("size",100)) - 100.0) < 0.5: return "castle"
	if "/castle/" in p or "/stone/" in p: return "tower"
	if "/bridge/" in p: return "bridge_" + bridge_part(p)
	if "/island/" in p:
		# By the art's own file: isle-01..06 are round huts, isle-07..12 rail fences, isle-13..18 spears.
		# (The torches of the same folder, seq 425, have frames 1-6 too, so the frame cannot say.)
		# isle-08 is the exception: it is a rail drawn along the depth axis (30 x 192 px: a lattice
		# post as tall as its length), which as a card in the +z plane is a 4.8 m pole that vanishes
		# edge-on from the side. It keeps its billboard until it is rebuilt from the side-view rail
		# turned 90 degrees, as the fence post column is (add_billboard).
		var file := p.get_file()
		var number := int(file.trim_prefix("isle-")) if file.begins_with("isle-") else 0
		if number >= 1 and number <= 6: return "hut"
		return "fence" if number in [7,9,10,11,12] else "rock"
	if "/door/" in p: return "door"
	if "/details/inacc" in p:
		return {1:"shelf",2:"table",3:"bed",4:"shelf",5:"fireplace",6:"cave_entrance"}.get(frame,"table")
	if "/details/table" in p: return "chair" if frame in [4,6,8,10] else "table"
	if "/details/fire" in p: return "torch"
	if "/stairs/" in p: return "stairs"
	if "/pig/" in p: return "pig"
	if "/duck/" in p: return "duck"
	if "/fish/" in p: return "duck"
	if "/pill/" in p: return "pillbug"
	if "/bonca/" in p: return "bonca"
	if "/puddle/" in p: return "slime"
	if "/dragon/" in p: return "dragon"
	if "/stonegnt/" in p: return "bonca"
	if "/slayers/" in p: return "knight"
	if "/goblin/" in p: return "knight"
	if "/people/" in p:
		if "knight" in p or "soldier" in p: return "knight"
		# S1-H1-O's Silver knight uses the imported Peasant2 sequence
		# (c11w1), whose source art is armored despite its folder name.
		if "peasant2" in p: return "knight"
		if "mom" in p or "maiden" in p or "girl" in p: return "woman"
		if "oldman" in p or "gnome" in p: return "wizard"
		return "man"
	if "/dink/" in p: return "man"
	if "/barrels/" in p: return "barrel"
	if "/chest/" in p: return "chest"
	if "/boxes/" in p or "/grain/" in p: return "crate"
	if "/tomb/" in p: return "gravestone"
	if "/save/" in p: return "save"
	if "/bottles/" in p: return "potion"
	if "/coins/" in p: return "coin"
	if "/heart/" in p or "/health/" in p: return "heart"
	if "/food/" in p: return "food"
	if "/paper/" in p or "/inner/" in p: return "sign"
	if "/cup/" in p: return "potion"
	if "/tools/" in p: return "crate"
	if "/effects/fire/" in p or "/damage/fire" in p: return "flame"
	if "/damage/damag" in p: return "burn_scar"
	if "/damage/hole" in p: return "hole"
	if "/effects/arrow/" in p: return "arrow"
	if "/effects/seed/" in p: return "feed_grains"
	if "/effects/" in p: return "effect"
	if "/lands/details/" in p: return "rock" if frame < 7 else "grass"
	if "/teleport/" in p: return "save"
	if "/damage/" in p: return ""
	return "crate" if not str(e.get("script","")).is_empty() else "rock"

# The two kinds of bridge art (struct/Bridge), by the art's own file: brdge-04, 07, 09 and 11 are rope railings
# drawn standing (the near railing of an east-west bridge is a sprite of its own, drawn after the deck, in front
# of it); the rest are decks: 01-03 the north-south plank bridge (start, middle, end, with its side rails), 05 the
# diagonal rope bridge, 06, 08 and 10 the east-west deck with its far railing. A deck lies on the water: in the
# original's projection (screen = X, Z - Y) a deck at water level is drawn at its own place on the ground, as a
# background sprite is. The rails of a deck's own sprite, and the far railing drawn inside 06, 08 and 10, lie
# flat on it.
func bridge_part(path: String) -> String:
	var file := path.get_file()
	var number := int(file.trim_prefix("brdge-")) if file.begins_with("brdge-") else 0
	return "rail" if number in [4,7,9,11] else "deck"

# The original draws each screen alone, clipped to its 600 x 400 playfield, so the map stitches an object across a
# seam by placing a copy of it in each screen (437 of the 4,199 outdoor placements have their hotspot outside their own
# screen; 311 seam pairs stand at the same world point, the rest offset across the seam by up to 200 px); and two
# trees' arts, tree-09/10, draw two half-trees one above the other, the upper one a tree standing about 190 px further
# north in the original's projection (screen = X, Z - Y). The 5x5 block draws every screen's sprites whole, so a seam
# tree stood twice, and a stacked strip stood as one card with its far tree floating in the air (docs/DIRECTION.md, M3).
# Each part of an art (stack_rows: parts split by a fully transparent band of > 3 rows, each >= 30 rows tall) stands at
# its own foot, its lowest drawn row; and a part of static scenery (type 1, no script, no brain, size 100) is not built
# when no drawn pixel of it lies in its own screen (the original never drew it), or when its foot lies outside its own
# screen and the screen holding the foot (across one seam, or diagonally across two) places the same art (same vision)
# crossing those seams at the same coordinates along them, with a part whose foot lies in that screen: that copy is the object. An object whose copies both stand outside (a crossing
# pair) keeps both. tools/seam_objects.py is the independent reading tests/test_fps_seams.py compares with.
var stack_cache: Dictionary = {}
# The screens the scene being built holds (the 5x5 block; seam_partner): a copy whose partner screen is not built stays,
# so an object at the block's edge stands where it will stand when the next screen loads. Empty: every screen (the
# classification test).
var scene_block: Dictionary = {}
var art_cache: Dictionary = {}
func art_image(path: String) -> Image:
	if not art_cache.has(path): art_cache[path] = sprite_image(path)
	return art_cache[path]

func stack_rows(path: String) -> Array:
	if stack_cache.has(path): return stack_cache[path]
	var out: Array = []
	var img := art_image(path)
	if img != null:
		var drawn: Array[int] = []
		for y in img.get_height():
			if not img.get_region(Rect2i(0,y,img.get_width(),1)).is_invisible(): drawn.append(y)
		if not drawn.is_empty():
			var cuts: Array[int] = [0]
			for j in range(1,drawn.size()):
				if drawn[j]-drawn[j-1] > 3 and drawn[j-1]+1-drawn[cuts[-1]] >= 30 and drawn[-1]+1-drawn[j] >= 30: cuts.append(j)
			for k in cuts.size():
				var last: int = (cuts[k+1] if k+1 < cuts.size() else drawn.size())-1
				out.append([drawn[cuts[k]],drawn[last]+1,drawn[last]])
	stack_cache[path] = out
	return out

func static_scenery(e: Dictionary) -> bool:
	return int(e.get("type",1)) == 1 and str(e.get("script","")).is_empty() and int(e.get("brain",0)) == 0 and absf(float(e.get("size",100))-100.0) < 0.5

# [[row0 or -1 if the art is one part, row1, foot row, shown], ...] for e on screen n (seam_parts' comment above).
func seam_parts(e: Dictionary, n: int) -> Array:
	var path := frame_path(e)
	var rows := stack_rows(path)
	if rows.size() <= 1: rows = [[-1,0,0]]
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var x := float(e.get("x",0))
	var y := float(e.get("y",0))
	var out: Array = []
	var still := static_scenery(e) and not interior
	for r in rows:
		var shown := true
		if still:
			var foot := y if int(r[0]) < 0 else y-float(d.get("dy",0))+float(r[2])
			if not drawn_inside(path,d,x,y,int(r[0]),int(r[1])): shown = false
			else:
				var sx := -1 if x < 20.0 else (1 if x >= 620.0 else 0)
				var sy := -1 if foot < 0.0 else (1 if foot >= 400.0 else 0)
				if (sx != 0 or sy != 0) and seam_partner(n,path,d,x,y,sx,sy,int(e.get("vision",0))): shown = false
		out.append([int(r[0]),int(r[1]),int(r[2]),shown])
	return out

# Whether a drawn pixel of the art's rows [r0, r1) (all rows if r0 < 0) placed at (x, y) lies in the playfield.
func drawn_inside(path: String, d: Dictionary, x: float, y: float, r0: int, r1: int) -> bool:
	var img := art_image(path)
	if img == null: return false
	var left := int(x-float(d.get("dx",0)))
	var top := int(y-float(d.get("dy",0)))
	if r0 < 0:
		r0 = 0
		r1 = img.get_height()
	var rows := Vector2i(maxi(r0,-top),mini(r1,400-top))
	var cols := Vector2i(maxi(0,20-left),mini(img.get_width(),620-left))
	if rows.y <= rows.x or cols.y <= cols.x: return false
	return not img.get_region(Rect2i(cols.x,rows.x,cols.y-cols.x,rows.y-rows.x)).is_invisible()

func crosses(path: String, d: Dictionary, x: float, y: float, side: String) -> bool:
	var img := art_image(path)
	if img == null: return false
	var top := y-float(d.get("dy",0))
	var left := x-float(d.get("dx",0))
	match side:
		"top": return top < 0.0 and 0.0 < top+img.get_height()
		"bottom": return top < 400.0 and 400.0 < top+img.get_height()
		"left": return left < 20.0 and 20.0 < left+img.get_width()
		_: return left < 620.0 and 620.0 < left+img.get_width()

# Whether the screen holding the foot (sx, sy: -1, 0, 1 screens across) places the same static art, of the same vision,
# lined up with this copy exactly along every seam both cross (x along a top or bottom seam, y along a side seam: a pair
# 2 px apart, 409's fence and 408's, kept apart, since one copy for both would kink the fence where it joins its own screen's),
# with a part whose foot lies in that screen.
func seam_partner(n: int, path: String, d: Dictionary, x: float, y: float, sx: int, sy: int, vision: int) -> bool:
	var m: int = n+sx+32*sy
	if sx != 0 and int((n+sx-1)/32) != int((n-1)/32): return false
	if not host.world.screens.has(str(m)) or is_inside(m): return false
	if not scene_block.is_empty() and not scene_block.has(m): return false
	if sx != 0 and not crosses(path,d,x,y,"left" if sx < 0 else "right"): return false
	if sy != 0 and not crosses(path,d,x,y,"top" if sy < 0 else "bottom"): return false
	for r in host.world.screens[str(m)].get("sprites",[]):
		if not static_scenery(r) or int(r.get("vision",0)) != vision: continue
		var rd: Dictionary = host._frame(int(r.get("seq",0)),int(r.get("frame",1)))
		if str(rd.get("path","")) != path: continue
		var rx := float(r.x)
		var ry := float(r.y)
		if sy != 0 and absf(rx+600.0*sx-x) > 0.5: continue
		if sx != 0 and absf(ry+400.0*sy-y) > 0.5: continue
		if sx != 0 and not crosses(path,rd,rx,ry,"right" if sx < 0 else "left"): continue
		if sy != 0 and not crosses(path,rd,rx,ry,"bottom" if sy < 0 else "top"): continue
		var parts := stack_rows(path)
		if parts.size() <= 1: parts = [[-1,0,int(rd.get("dy",0))]]
		for p in parts:
			var foot := ry-float(rd.get("dy",0))+float(p[2])
			if foot >= 0.0 and foot < 400.0 and rx >= 20.0 and rx < 620.0: return true
	return false

# The placement of part k of a stacked art: the same sprite, its frame the part's rows, standing at the part's foot.
func stack_part(e: Dictionary, k: int, r: Array) -> Dictionary:
	if int(r[0]) < 0: return e
	var seq := int(e.get("pseq",e.get("seq",0)))
	var frame := int(e.get("pframe",e.get("frame",1)))
	var d: Dictionary = host._frame(seq,frame)
	var vseq := 1000000+seq*10+k
	var key := str(vseq)
	if not host.sequences.has(key): host.sequences[key] = {"frames":(host.sequences.get(str(seq),{}).get("frames",[]) as Array).duplicate(true),"delay":100}
	var frames: Array = host.sequences[key].frames
	var part_path := "%s#%d-%d" % [str(d.get("path","")),int(r[0]),int(r[1])]
	if frame >= 1 and frame <= frames.size() and str(frames[frame-1].get("path","")) != part_path:
		frames[frame-1] = {"path":part_path,"dx":d.get("dx",0),"dy":int(r[2])-int(r[0]),"hardbox":[0,0,0,0],"delay":d.get("delay",100),"special":0}
	var out := e.duplicate()
	out.seq = 0
	out.frame = frame
	out.pseq = vseq
	out.pframe = frame
	out.y = float(e.get("y",0))-float(d.get("dy",0))+float(r[2])
	return out

func build_ground(screen: Dictionary) -> void:
	scene_generation = host.generation
	# The campaign data is read after setup(); the builder keeps its caches across scenes.
	buildings.world = host.world
	buildings.sequences = host.sequences
	structural_seen.clear()
	fitted_built.clear()
	neighbour_actors.clear()
	neighbour_states.clear()
	# The current screen's own buildings carry its story state; a neighbour showing the
	# same building (one placed on both screens) leaves it to them.
	for source in screen.get("sprites",[]):
		if int(source.get("vision",0)) != 0 and int(source.vision) != int(host.vm.globals.get("vision",0)): continue
		var key := fitted_key(source,host.current_screen)
		if not key.is_empty(): fitted_built[key] = null
		key = castle_key(source,host.current_screen)
		if not key.is_empty(): fitted_built[key] = null
	interior = is_inside(host.current_screen)
	scene_block.clear()
	scene_block[host.current_screen] = true
	if not interior:
		# Ground painting and house_plan also read neighbouring sprites. Compute
		# each arrival once before any of those readers build the scene.
		var column: int = (host.current_screen-1)%32
		for dz in range(-2,3):
			for dx in range(-2,3):
				if dx == 0 and dz == 0: continue
				if column+dx < 0 or column+dx >= 32: continue
				var n: int = host.current_screen+dx+dz*32
				if host.world.screens.has(str(n)) and not is_inside(n):
					scene_block[n] = true
					neighbour_states[n] = host.neighbour_arrival_state(n, host._incoming_arrival_basis)
	configure_environment()
	add_ground(host.current_screen,host.scene_root,Vector3.ZERO)
	add_terrain_walls(screen)
	if interior:
		add_ceiling(screen)
	else:
		# Only outdoor neighbors are connected. Interior maps live in their own spaces. The block is
		# 5x5 screens, as the prototype builds it and as house_plan gathers: at 0.025 m/px a 3x3
		# block ended the world 15 m from the player and left buildings two screens away undrawn.
		var column: int = (host.current_screen-1)%32
		for dz in range(-2,3):
			for dx in range(-2,3):
				if dx == 0 and dz == 0: continue
				if column+dx < 0 or column+dx >= 32: continue
				var n: int = host.current_screen+dx+dz*32
				var offset := Vector3(dx*WIDTH,0,dz*DEPTH)
				if host.world.screens.has(str(n)) and not is_inside(n):
					add_ground(n,host.scene_root,offset)
					var backdrop := Node3D.new()
					backdrop.name = "Neighbor_%d" % n
					backdrop.position = offset
					host.scene_root.add_child(backdrop)
					var dedup: Dictionary = {}
					for e in neighbour_states[n].get("sprites", []):
						if int(e.get("type",1)) == 2 or int(e.get("active",1)) == 0 or int(e.get("nodraw",0)) != 0 or int(e.get("disabled",0)) != 0: continue
						var key := model_key(e)
						if key in ["flame","effect","arrow",""]: continue
						var fingerprint := "%s:%d:%d" % [key,int(e.x),int(e.y)]
						if key == "castle": fingerprint += ":" + frame_path(e)
						# A copy painted into the ground stands nothing: it must not take the fingerprint of a standing
						# twin at the same place (the map places 9 trees twice, type 0 and type 1: from the next screen
						# they never stood; M3, U7).
						if paints_ground(e,n): fingerprint += ":ground"
						if dedup.has(fingerprint): continue
						dedup[fingerprint] = true
						var node := make_entity(e,0,backdrop,false,n)
						var model: Node = node.get_node_or_null("Model")
						if model is Sprite3D: update_billboard(model as Sprite3D,e)
						# Their brains run only on their own screen (as in the original): they stand in the frame the
						# screen loads them with, turned toward the camera each frame (face_neighbours).
						if node.get_meta("actor",false) and model is Sprite3D: neighbour_actors.append([model,e])
				else:
					add_wilderness(host.scene_root,offset,n)
		add_horizon()

# The neighbours' actors show the frame drawn for their facing as seen from the camera, as the current
# screen's actors do (update_visual -> update_billboard); the game calls this each frame after the camera is synced.
func face_neighbours() -> void:
	for pair in neighbour_actors:
		if is_instance_valid(pair[0]): update_billboard(pair[0] as Sprite3D,pair[1])

func configure_environment() -> void:
	for child in host.get_children():
		if child is WorldEnvironment: environment = child.environment
		if child is DirectionalLight3D: light = child
	if environment:
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color("548399")
		sky_mat.sky_horizon_color = Color("d4d6af")
		sky_mat.ground_bottom_color = Color("687449")
		sky_mat.ground_horizon_color = Color("b8bea0")
		sky_mat.sun_angle_max = 2.5
		sky.sky_material = sky_mat
		environment.sky = sky
		environment.background_mode = Environment.BG_COLOR if interior else Environment.BG_SKY
		environment.background_color = Color("181916")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("ffe3af") if interior else Color("c6dfef")
		environment.ambient_light_energy = 0.30 if interior else 0.32
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.fog_enabled = not interior
		environment.fog_light_color = Color("b0baa1")
		environment.fog_density = 0.0025
		environment.fog_sky_affect = 0.12
	if light:
		light.rotation_degrees = Vector3(-48,-32,0)
		light.light_color = Color("fff0d9")
		light.light_energy = 0.25 if interior else 0.65
		light.shadow_enabled = true
		light.directional_shadow_max_distance = 65
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

func ground_texture(number: int) -> Texture2D:
	# Keyed by the background sprites painted in, so a story change to them (a kill left as
	# background, a removed sprite) recomposes the ground on the next load.
	var background := background_sprites(number,int(host.vm.globals.get("vision",0)))
	var signature := []
	for e in background: signature.append(background_key(e))
	var cache_key := "%d:%s" % [number,",".join(signature).md5_text()]
	if terrain_cache.has(cache_key): return terrain_cache[cache_key]
	var screen: Dictionary = host.world.screens[str(number)]
	var img := Image.create(600,400,false,Image.FORMAT_RGBA8)
	img.fill(Color("677744"))
	var sheets: Dictionary = {}
	var kit_tiles: Dictionary = {}
	for i in host.footprints.get(str(number),{}).get("clear",[]): kit_tiles[int(i)] = true
	for i in range(mini(96,screen.tiles.size())):
		var index := ground_tile(screen.tiles,i,kit_tiles)
		var sheet := int(index/128)+1
		var cell := index%128
		if not sheets.has(sheet):
			var texture: Texture2D = host._texture("res://assets/tiles/ts%02d.png" % sheet)
			if texture == null: texture = host._texture("res://assets/tiles/ts%d.png" % sheet)
			var image: Image = texture.get_image() if texture else null
			if image and image.is_compressed(): image.decompress()
			if image: image.convert(Image.FORMAT_RGBA8)
			sheets[sheet] = image
		var source: Image = sheets[sheet]
		if source: img.blit_rect(source,Rect2i((cell%12)*50,int(cell/12)*50,50,50),Vector2i((i%12)*50,int(i/12)*50))
	paint_background(background,img)
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	var result := ImageTexture.create_from_image(img)
	terrain_cache[cache_key] = result
	return result

# The background (type 0) sprites of screen n as drawn now, in the map's order. One with an upright
# twin at the same spot is left to the twin.
func background_sprites(number: int, vision: int) -> Array:
	var sprites := drawn_sprites(number,vision)
	var upright := {}
	var out: Array = []
	var decks: Array = []
	for e in sprites:
		if effective_type(e) == 1 and model_key(e) != "bridge_deck": upright[background_key(e)] = true
	for e in sprites:
		if not paints_ground(e,number): continue
		if upright.has(background_key(e)): continue
		if model_key(e) == "bridge_deck": decks.append(e)
		else: out.append(e)
	# The map draws a deck among the upright sprites, in their order (its que, else its y), over the background;
	# ties keep the map's order (the sort is not stable).
	var ranked: Array = []
	for i in decks.size(): ranked.append([deck_order(decks[i]),i])
	ranked.sort()
	for r in ranked: out.append(decks[int(r[1])])
	return out

func deck_order(e: Dictionary) -> float:
	return float(e.get("que",0)) if int(e.get("que",0)) != 0 else float(e.get("y",0))

# A sprite's type as load_map gives it: a story persistence (editor_type 2-5) makes it background
# (3, 5: a kill left lying) or upright.
func effective_type(e: Dictionary) -> int:
	var persistence := int(e.get("editor_type",0))
	if persistence in [3,5]: return 0
	if persistence in [2,4]: return 1
	return int(e.get("type",1))

# Background sprites painted into the ground, exactly where and as the original draws them (the
# prototype's _build_screen), shadow dither included: on the ground it is a shadow.
func display_frame(e: Dictionary) -> Vector2i:
	var seq := int(e.get("seq",0))
	var frame := int(e.get("frame",1))
	if seq == 0:
		seq = int(e.get("pseq",0))
		frame = int(e.get("pframe",1))
	return Vector2i(seq,frame)

func background_key(e: Dictionary) -> String:
	var display: Vector2i = display_frame(e)
	return "%d:%d:%d:%d" % [display.x,display.y,int(e.get("x",0)),int(e.get("y",0))]

func paint_background(sprites: Array, img: Image) -> void:
	for e in sprites:
		var display: Vector2i = display_frame(e)
		var d: Dictionary = host._frame(display.x,display.y)
		var sprite := sprite_image(str(d.get("path","")))
		if sprite == null: continue
		img.blend_rect(sprite,Rect2i(Vector2i.ZERO,sprite.get_size()),Vector2i(int(float(e.get("x",0))-20.0-float(d.get("dx",0))),int(float(e.get("y",0))-float(d.get("dy",0)))))

# Whether a sprite is a background sprite painted into its screen's ground (paint_background).
func paints_ground(e: Dictionary, screen: int) -> bool:
	if model_key(e) == "bridge_deck": return true # whatever its type: the map draws a deck as an upright sprite
	if effective_type(e) != 0 or source_path(e).contains("/struct/"): return false
	if kit_member(e,screen): return false
	var key := model_key(e)
	return key != "wall" and sprite_drawn(key)

# Keys drawn as their sprite (see BUILT). Outdoor walls are the stone-wall sprites; a room's
# walls stay boxes.
func sprite_drawn(key: String) -> bool:
	if key == "wall": return not interior
	return key not in BUILT

func kit_member(e: Dictionary, screen: int) -> bool:
	if kit_members.is_empty():
		kit_members["-"] = true
		for b in facades.get("_kit_buildings",[]):
			for m in b.members:
				if str(m[1]) != "s": continue
				var sprites: Array = host.world.screens.get(str(int(m[0])),{}).get("sprites",[])
				if int(m[2]) < sprites.size(): kit_members["%d:%d" % [int(m[0]),int(sprites[int(m[2])].get("index",-1))]] = true
	return kit_members.has("%d:%d" % [screen,int(e.get("editor_num",e.get("index",-1)))])

# A kit building's own tiles are pictures of its upper storey, which now stands in 3D: the
# ground continues the row they interrupt (ground tiles alternate in pairs, so keep the column
# parity), else the column. As the prototype does (sprite_world_proto.gd _ground_tile).
func ground_tile(tiles: Array, i: int, kit_tiles: Dictionary) -> int:
	if not kit_tiles.has(i): return int(tiles[i].get("tile",0))
	var row := int(i/12)
	var col := i%12
	for dist in range(2,12,2):
		for c in [col-dist,col+dist]:
			var j: int = row*12+c
			if c >= 0 and c < 12 and j < tiles.size() and not kit_tiles.has(j): return int(tiles[j].get("tile",0))
	for dist in range(1,8):
		for rr in [row-dist,row+dist]:
			var j: int = rr*12+col
			if rr >= 0 and rr < 8 and j < tiles.size() and not kit_tiles.has(j): return int(tiles[j].get("tile",0))
	return int(tiles[i].get("tile",0))

func add_ground(number: int, parent: Node3D, offset: Vector3) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Terrain_%d" % number
	var plane := PlaneMesh.new()
	plane.size = Vector2(WIDTH,DEPTH)
	ground.mesh = plane
	ground.position = offset
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ground_texture(number)
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = mat
	parent.add_child(ground)
	add_kit_buildings(number,parent,offset)
	if offset == Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH,0.2,DEPTH)
		shape.shape = box
		body.position.y = -0.1
		body.add_child(shape)
		parent.add_child(body)

func mat(name: String, color: Color) -> StandardMaterial3D:
	if materials.has(name): return materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	materials[name] = m
	return m

func box_mesh(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func add_ceiling(screen: Dictionary) -> void:
	var limits := Rect2(20,0,600,400)
	var found := false
	for e in screen.get("sprites",[]):
		if model_key(e) == "wall":
			var r: Rect2 = hard_rect(e)
			limits = limits.merge(r) if found else r
			found = true
	var center := point(limits.get_center().x,limits.get_center().y)
	box_mesh(host.scene_root,Vector3(limits.size.x*SCALE,0.18,limits.size.y*SCALE),center+Vector3(0,3.65,0),mat("ceiling",Color("665036")))
	var beam_mat := mat("beam",Color("37291c"))
	for x in range(int(limits.position.x),int(limits.end.x)+1,75):
		box_mesh(host.scene_root,Vector3(0.18,0.26,limits.size.y*SCALE),point(x,limits.get_center().y)+Vector3(0,3.45,0),beam_mat)
	var glow := OmniLight3D.new()
	glow.position = center+Vector3(0,2.8,0)
	glow.light_color = Color("ffd395")
	glow.light_energy = 1.8
	glow.omni_range = 22
	host.scene_root.add_child(glow)

func add_wilderness(parent: Node3D, offset: Vector3, seed_number: int) -> void:
	box_mesh(parent,Vector3(WIDTH,0.3,DEPTH),offset-Vector3(0,0.2,0),mat("wilderness",Color("647548")))
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(seed_number)*335
	var tree_m := sprite_height({"pseq":32,"pframe":1})*SCALE # tree-01
	for i in 12:
		var node := instance_model("oak_tree")
		node.position = offset+Vector3(rng.randf_range(-0.47,0.47)*WIDTH,0,rng.randf_range(-0.46,0.46)*DEPTH)
		# As tall as the map's own trees (sized by their sprites, make_entity): tree-01, the most placed.
		node.scale *= rng.randf_range(0.8,1.4)*tree_m/maxf(0.1,model_bounds("oak_tree",node).size.y)
		node.rotation.y = rng.randf()*TAU
		parent.add_child(node)

func add_horizon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987
	for i in 24:
		var hill := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radial_segments = 16
		mesh.rings = 8
		hill.mesh = mesh
		var angle := i*TAU/24
		hill.position = Vector3(cos(angle)*130,-9,sin(angle)*130)
		hill.scale = Vector3(rng.randf_range(35,65),rng.randf_range(20,45),rng.randf_range(35,60))
		hill.material_override = mat("hill%d" % (i%3),Color("637655").lightened((i%3)*0.035))
		host.scene_root.add_child(hill)

func instance_model(key: String) -> Node3D:
	if key == "inn" and not ResourceLoader.exists("res://assets/models/inn.glb"): key = "cottage"
	if not models.has(key):
		var path := "res://assets/models/%s.glb" % key
		models[key] = load(path) if ResourceLoader.exists(path) else null
	if models[key] is PackedScene: return models[key].instantiate()
	return primitive_model(key)

func primitive_model(key: String) -> Node3D:
	var node := Node3D.new()
	var wood := mat("wood",Color("6e4828"))
	var stone := mat("stone",Color("857e6e"))
	match key:
		"feed_grains":
			# Original ITEM-PIG creates these short-lived seed sprites. Keep their
			# script lifetime and position, with grain instead of a glowing orb.
			for i in 18:
				var angle := float(i) * 2.39996
				var radius := 0.15 + float(i % 6) * 0.11
				box_mesh(node, Vector3(0.085, 0.045, 0.13),
					Vector3(cos(angle) * radius, 0.06 + float(i % 3) * 0.055, sin(angle) * radius),
					mat("feed_grain", Color("e4c478")))
		"fence_open":
			# The source hard=1 fence frames are visible gate approaches. Leave a
			# central opening and show short rails/posts at either side.
			box_mesh(node,Vector3(0.12,1.05,1.0),Vector3(-0.48,0.525,0),wood)
			box_mesh(node,Vector3(0.12,1.05,1.0),Vector3(0.48,0.525,0),wood)
			for side in [-1.0,1.0]:
				box_mesh(node,Vector3(0.38,0.10,0.10),Vector3(side*0.72,0.38,0),wood)
				box_mesh(node,Vector3(0.38,0.10,0.10),Vector3(side*0.72,0.72,0),wood)
		"wall":
			box_mesh(node,Vector3(1,3.6,1),Vector3(0,1.8,0),mat("plaster",Color("b1a07b")))
			box_mesh(node,Vector3(1.02,0.15,1.02),Vector3(0,0.25,0),wood)
			box_mesh(node,Vector3(1.02,0.2,1.02),Vector3(0,3.35,0),wood)
		"door":
			box_mesh(node,Vector3(1.8,2.7,0.16),Vector3(0,1.35,0),wood)
			for x in [-1.0,1.0]: box_mesh(node,Vector3(0.2,3.0,0.3),Vector3(x,1.5,0),stone)
			box_mesh(node,Vector3(2.2,0.22,0.3),Vector3(0,2.9,0),stone)
			box_mesh(node,Vector3(0.1,0.16,0.12),Vector3(0.55,1.25,0.12),mat("brass",Color("d9a74a")))
		"shelf":
			box_mesh(node,Vector3(2.8,2.3,0.3),Vector3(0,1.15,0.2),wood)
			for y in [0.3,1.0,1.7,2.3]:
				box_mesh(node,Vector3(2.9,0.1,0.7),Vector3(0,y,0),wood)
				for i in 9: box_mesh(node,Vector3(0.17,0.42,0.3),Vector3(-1.1+i*0.26,y+0.26,0),mat("book%d"% (i%3),[Color("624333"),Color("395650"),Color("9b843e")][i%3]))
		"fireplace":
			box_mesh(node,Vector3(2.8,0.2,1.2),Vector3(0,0.1,0),stone)
			for x in [-1.1,1.1]: box_mesh(node,Vector3(0.5,1.5,1.0),Vector3(x,0.8,0),stone)
			box_mesh(node,Vector3(2.8,1.5,0.9),Vector3(0,2.1,0),stone)
			var fire := primitive_model("flame")
			fire.position = Vector3(0,0.2,0.25)
			node.add_child(fire)
		"ruin":
			# home-11..13 are the source's charred cottage debris pieces. Keep
			# them low and broad so they read as rubble instead of a second house.
			var ash := mat("charred_wood",Color("29251f"))
			var soot := mat("soot_stone",Color("4a4439"))
			box_mesh(node,Vector3(1.55,0.22,0.42),Vector3(0,0.12,0),ash).rotation.y = -0.18
			box_mesh(node,Vector3(1.18,0.18,0.34),Vector3(-0.2,0.34,0.1),ash).rotation.z = 0.38
			box_mesh(node,Vector3(0.48,0.42,0.42),Vector3(0.48,0.3,-0.08),soot).rotation.z = -0.22
			box_mesh(node,Vector3(0.34,0.3,0.3),Vector3(-0.62,0.25,0.02),soot).rotation.z = 0.2
		"burn_scar":
			var ember := mat("burn_scar",Color("321f18"))
			box_mesh(node,Vector3(0.9,0.10,0.24),Vector3(0,0.06,0),ember).rotation.z = -0.2
			box_mesh(node,Vector3(0.48,0.08,0.22),Vector3(0.16,0.14,0.02),mat("burn_edge",Color("6e321d"))).rotation.z = 0.3
		"hole":
			# Vision 2 hole sprites are flat dark openings on the surviving walls.
			var opening := mat("ruin_hole",Color("171817"))
			box_mesh(node,Vector3(0.42,0.08,0.28),Vector3(0,0.24,0),opening)
			box_mesh(node,Vector3(0.24,0.06,0.18),Vector3(0.08,0.34,0.03),mat("hole_edge",Color("65513a"))).rotation.z = -0.35
		"flame":
			# Fire remains a still, readable source-state marker under reduced motion.
			var fire_orange := mat("fire_orange",Color("e85a20"))
			fire_orange.emission_enabled = true
			fire_orange.emission = Color("ff4e1b")
			fire_orange.emission_energy_multiplier = 1.4
			var fire_yellow := mat("fire_yellow",Color("ffc34a"))
			fire_yellow.emission_enabled = true
			fire_yellow.emission = Color("ff9c2e")
			fire_yellow.emission_energy_multiplier = 1.2
			var outer := CylinderMesh.new()
			outer.top_radius = 0.02
			outer.bottom_radius = 0.18
			outer.height = 0.72
			outer.radial_segments = 6
			var outer_mesh := MeshInstance3D.new()
			outer_mesh.mesh = outer
			outer_mesh.material_override = fire_orange
			outer_mesh.position.y = 0.36
			node.add_child(outer_mesh)
			var inner := CylinderMesh.new()
			inner.top_radius = 0.01
			inner.bottom_radius = 0.09
			inner.height = 0.42
			inner.radial_segments = 6
			var inner_mesh := MeshInstance3D.new()
			inner_mesh.mesh = inner
			inner_mesh.material_override = fire_yellow
			inner_mesh.position = Vector3(0,0.27,0.03)
			node.add_child(inner_mesh)
			var lamp := OmniLight3D.new()
			lamp.position.y = 0.42
			lamp.light_color = Color("ff6427")
			lamp.light_energy = 0.75
			lamp.omni_range = 3.5
			node.add_child(lamp)
		"stairs":
			for i in 6: box_mesh(node,Vector3(2.0,0.2*(i+1),0.4),Vector3(0,0.1*(i+1),-i*0.4),stone)
		_:
			var visual := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.22
			mesh.height = 0.44
			mesh.radial_segments = 12
			mesh.rings = 6
			visual.mesh = mesh
			visual.position.y = 0.3
			var color := Color("cb9a48")
			if key in ["flame","effect"]: color = Color("ff7c23")
			if key == "heart": color = Color("cf2d36")
			if key == "potion": color = Color("58a5d1")
			if key == "save": color = Color("68d5dd")
			var material := mat(key,color)
			if key in ["flame","effect","save"]:
				material.emission_enabled = true
				material.emission = color
				material.emission_energy_multiplier = 1.6
			visual.material_override = material
			if key == "coin": visual.scale = Vector3(1,1,0.22)
			if key == "flame": visual.scale = Vector3(0.8,2.2,0.8)
			node.add_child(visual)
			if key in ["flame","save"]:
				var lamp := OmniLight3D.new()
				lamp.position.y = 0.8
				lamp.light_color = color
				lamp.light_energy = 1.2
				lamp.omni_range = 5.0
				node.add_child(lamp)
	return node

func model_bounds(key: String, node: Node3D) -> AABB:
	if bounds_cache.has(key): return bounds_cache[key]
	var box := AABB()
	var nodes: Array = [node]
	while not nodes.is_empty():
		var n: Node = nodes.pop_back()
		if n is MeshInstance3D:
			var transform := Transform3D.IDENTITY
			var current: Node3D = n
			while current != node:
				transform = current.transform*transform
				current = current.get_parent()
			var b: AABB = transform*n.get_aabb()
			box = box.merge(b)
		nodes.append_array(n.get_children())
	bounds_cache[key] = box
	return box

func make_entity(e: Dictionary, id: int, parent: Node3D, collision: bool = true, screen: int = -1) -> Node3D:
	var node := Node3D.new()
	var key := model_key(e)
	node.name = "Entity_%d_%s" % [id,key]
	node.set_meta("model_key",key)
	node.set_meta("entity_id",id)
	parent.add_child(node)
	node.position = point(float(e.get("x",320)),float(e.get("y",200)))
	if key.is_empty(): return node
	if screen < 0: screen = host.current_screen
	if key == "cottage" and not fitted_key(e,screen).is_empty():
		add_fitted_building(node,e,id,screen,collision)
		return node
	if house_part(e,screen) or (not interior and kit_member(e,screen)):
		# Drawn onto its fitted house (a door, a window, damage, a chimney) or into its kit building
		# (kit_member, as the prototype leaves its pieces to the kit): no model of its own.
		# A scripted part without a warp (a door to talk to or hit) keeps an unseen body where
		# it is drawn, turned into the wall.
		node.set_meta("house_part",true)
		node.set_meta("height",sprite_height(e)*SCALE)
		if collision and e.get("warp") == null and not str(e.get("script","")).is_empty():
			var texture: Texture2D = host._texture("res://"+frame_path(e))
			var h := maxf(0.2,sprite_height(e)*SCALE)
			var body := StaticBody3D.new()
			body.name = "HitBody"
			body.set_meta("entity_id",id)
			body.collision_layer = 2
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(0.3,(texture.get_width() if texture else 20)*SCALE),h,0.3)
			shape.shape = box
			shape.position.y = h*0.5
			body.add_child(shape)
			node.add_child(body)
			set_in_wall(node,body,e,screen)
		return node
	if paints_ground(e,screen):
		node.set_meta("ground_painted",true) # painted into the ground (paint_background)
		return node
	if key == "castle":
		add_castle_piece(node,e,id,screen,collision)
		return node
	if key == "hut" and hut_fitted(e):
		add_hut(node,e,id,collision)
		return node
	if sprite_drawn(key):
		# Seam copies and stacked art (seam_parts): one billboard per object part the original shows standing here.
		var parts := seam_parts(e,screen)
		if parts.size() == 1 and bool(parts[0][3]) and int(parts[0][0]) < 0:
			add_billboard(node,e,id,key,collision,screen)
			return node
		for k in parts.size():
			if not bool(parts[k][3]):
				node.set_meta("seam_hidden",true)
				continue
			var part: Dictionary = stack_part(e,k,parts[k])
			var holder := Node3D.new()
			holder.name = "Part_%d" % k
			holder.set_meta("model_key",key)
			holder.position = point(float(part.x),float(part.y))-node.position
			node.add_child(holder)
			add_billboard(holder,part,id,key,collision,screen)
		return node
	var passable_fence := key == "fence" and int(e.get("hard",0)) != 0
	# Hard=1 fence artwork marks an opening. Keep a readable gate shape while
	# leaving the center visually open for the source walk corridor.
	var model := instance_model("fence_open" if passable_fence else key)
	model.name = "Model"
	node.add_child(model)
	var bounds := model_bounds("fence_open" if passable_fence else key,model)
	var rect: Rect2 = hard_rect(e)
	var factor := maxf(0.05,float(e.get("size",100))/100.0)
	var structural := key in ["wall","cottage","inn","tower","fence"]
	if structural:
		var size := rect.size*SCALE
		var desired := Vector3(maxf(0.3,size.x),3.6,maxf(0.3,size.y))
		if key in ["cottage","inn"]: desired.y = 5.8 if key == "cottage" else 7.0
		if key == "tower": desired.y = 8.5
		if key == "fence": desired.y = 1.05
		model.scale = desired/Vector3(maxf(0.1,bounds.size.x),maxf(0.1,bounds.size.y),maxf(0.1,bounds.size.z))
		node.position = point(rect.get_center().x,rect.get_center().y)
		if key in ["cottage","inn"]: model.rotation.y = PI
		if key == "cottage" and is_story_house(e,screen):
			if screen_vision(screen) == 1:
				add_story_fire(node,size.x)
			elif screen_vision(screen) == 2:
				add_ruin_skin(node,model)
	else:
		# Stand-in models of sprites are as tall as their sprites stand (see sprite_height).
		if key in SPRITE_SIZED:
			var drawn := sprite_height(e)
			if drawn > 0.0 and bounds.size.y > 0.05: model.scale *= drawn*SCALE/bounds.size.y
		model.scale *= factor
		# Damage sprites are decorative map state. Keep their primitive
		# equivalents on the ground instead of creating raised floating debris.
		if key == "flame":
			model.scale *= 1.55
			model.position.y = 1.55
		if key == "burn_scar":
			model.scale *= 1.35
		if key == "hole":
			model.scale *= 1.25
		if key == "ruin":
			model.scale *= 1.18
		if key in ["rock","bush"]:
			var target := clampf(rect.size.x*SCALE,0.3,4.0)
			model.scale *= target/maxf(bounds.size.x,0.1)
		if key in ["oak_tree","pine_tree","dead_tree","bush","rock"]:
			model.rotation.y = fmod(float(e.get("x",0))*1.74+float(e.get("y",0)),TAU)
		if key in ["bed","table","shelf","fireplace"]:
			# Furniture remains human-sized; campaign hardness defines its footprint.
			var size := rect.size*SCALE
			model.scale.x *= clampf(size.x/maxf(bounds.size.x,0.1),0.8,2.8)
			model.scale.z *= clampf(size.y/maxf(bounds.size.z,0.1),0.8,2.8)
			model.rotation.y = PI
		if key == "door" and not interior:
			model.rotation.y = PI
			set_in_wall(node,model,e,screen)
	var height := maxf(0.2,bounds.size.y*model.scale.y)
	node.set_meta("height",height)
	node.set_meta("base_model_position",model.position)
	var actor := key in ["man","woman","wizard","knight","pig","duck","pillbug","bonca","slime","dragon"]
	node.set_meta("actor",actor)
	# Dink uses hard=1 for fence artwork that is a visible opening/decoration.
	# Keep a visible gate mesh but do not turn that source non-solid stretch into
	# an invisible first-person rail. Hard-zero fences
	# retain their structural body for walking and projectile occlusion.
	# Damage/fire sprites are visual state markers in the original map.  They
	# must not add collision on top of the unchanged cottage footprint.
	if collision and not passable_fence and key not in ["grass","flowers","mushroom","effect","feed_grains","flame","burn_scar","hole","ruin","arrow"] and e.get("warp") == null:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id",id)
		body.collision_layer = 2 if actor or not str(e.get("script","")).is_empty() else 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if structural:
			box.size = Vector3(maxf(0.2,rect.size.x*SCALE),height,maxf(0.2,rect.size.y*SCALE))
		else:
			box.size = Vector3(maxf(0.3,bounds.size.x*model.scale.x),height,maxf(0.3,bounds.size.z*model.scale.z))
			if key in ["oak_tree","pine_tree","dead_tree"]: box.size = Vector3(0.8,height,0.8)
		shape.shape = box
		shape.position.y = height*0.5
		body.add_child(shape)
		node.add_child(body)
	return node

func create_visual(id: int) -> void:
	if not host.entities.has(id): return
	if id == 1:
		var player := Node3D.new()
		host.scene_root.add_child(player)
		host.visuals[id] = player
		return
	var e: Dictionary = host.entities[id]
	var key := model_key(e)
	var fingerprint := "%s:%s:%s" % [key,e.get("x",0),e.get("y",0)]
	if key == "castle": fingerprint += ":" + frame_path(e) # two different pieces may share a hotspot
	if key in ["cottage","tower","wall","castle"] and structural_seen.has(fingerprint):
		var existing: Node = structural_seen[fingerprint]
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			var duplicate := Node3D.new()
			host.scene_root.add_child(duplicate)
			host.visuals[id] = duplicate
			return
	var node := make_entity(e,id,host.scene_root)
	if key in ["cottage","tower","wall","castle"]: structural_seen[fingerprint] = node
	host.visuals[id] = node
	update_visual(id)

func update_visual(id: int) -> void:
	if not host.entities.has(id) or not host.visuals.has(id): return
	var e: Dictionary = host.entities[id]
	var node: Node3D = host.visuals[id]
	if not is_instance_valid(node): return
	if id == 1:
		node.position = point(float(e.x),float(e.y))
		return
	var visible := int(e.get("active",1)) != 0 and int(e.get("nodraw",0)) == 0 and int(e.get("disabled",0)) == 0 and int(e.get("type",1)) != 2
	node.visible = visible
	var body: StaticBody3D = node.get_node_or_null("HitBody")
	if body: body.collision_layer = (2 if node.get_meta("actor",false) or not str(e.get("script","")).is_empty() else 1) if visible and not e.get("dead",false) else 0
	if not visible: return
	var key: String = node.get_meta("model_key","")
	if node.has_meta("surface_position"):
		node.position = node.get_meta("surface_position")
	elif key not in ["wall","cottage","inn","tower","fence"]:
		node.position = point(float(e.get("x",320)),float(e.get("y",200)))
	var model: Node3D = node.get_node_or_null("Model")
	if model == null: return
	if model is Sprite3D:
		update_billboard(model as Sprite3D,e)
		return
	if node.get_meta("actor",false):
		var direction: Vector2 = host._dir_vector(int(e.get("dir",2)))
		if not direction.is_zero_approx(): model.rotation.y = atan2(-direction.x,-direction.y)
		var clock := Time.get_ticks_msec()/1000.0
		if e.get("dead",false):
			model.rotation.z = PI*0.5
			model.position.y = 0.25
		else:
			var moving: bool = int(e.get("seq",0)) != 0 and not e.get("frozen",false) and not host.ui.modal
			model.position.y = absf(sin(clock*7.0+id))*0.045 if moving else 0.0
			model.rotation.z = sin(clock*7.0+id)*0.025 if moving else 0.0
			animate_limbs(model,clock,id,moving)
	elif key in ["save","heart","coin","potion"]:
		model.rotation.y = Time.get_ticks_msec()*0.0007
		model.position.y = 0.15+sin(Time.get_ticks_msec()*0.002+id)*0.08

func animate_limbs(model: Node3D, time: float, id: int, moving: bool) -> void:
	# Blender parts retain descriptive names; rotation gives a simple gait in 3D.
	for child in model.get_children():
		if not child is Node3D: continue
		var n := str(child.name).to_lower()
		if "leg" in n or "arm" in n:
			if not child.has_meta("rest_rotation"): child.set_meta("rest_rotation",child.rotation)
			var rest: Vector3 = child.get_meta("rest_rotation")
			child.rotation.x = rest.x + (sin(time*7+id+(PI if "right" in n or "_r" in n or "-1" in n else 0.0))*0.2 if moving else 0.0)

# Solid dungeon/cliff silhouettes follow the imported collision mask. Water
# retains its original surface; it is not mistaken for stone walls.
func add_terrain_walls(_screen: Dictionary) -> void:
	if not interior: return # Outdoor masks also stamp grass, shores and invisible campaign gates.
	var terrain: Image = ground_texture(host.current_screen).get_image()
	var mesh := BoxMesh.new()
	var cell := 10.0*SCALE # one 10 px cell of the mask
	mesh.size = Vector3(cell,3.7 if interior else 2.8,cell)
	var material := mat("dungeon_rock" if interior else "cliff_rock",Color("5c5a4d") if interior else Color("82775c"))
	mesh.material = material
	var transforms: Array[Transform3D] = []
	for y in range(5,400,10):
		for x in range(25,620,10):
			if not host._tile_blocked(Vector2(x,y)): continue
			var tile_index := int(_screen.tiles[int(y/50)*12+int((x-20)/50)].get("tile",0))
			if not interior and tile_index < 128: continue # Stamped grass hardness belongs to modeled scenery.
			var color := terrain.get_pixel(x-20,y)
			if color.b > color.r*1.1 and color.b > color.g*0.85: continue
			# Wood flooring and grass are not walls, even on scripted barriers.
			if color.g > color.r*1.12: continue
			if not interior and color.r > color.g*1.4: continue
			var trans := Transform3D.IDENTITY
			trans.origin = point(x,y)+Vector3(0,mesh.size.y*0.5-0.05,0)
			transforms.append(trans)
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "SolidTerrain"
	instance.multimesh = multi
	host.scene_root.add_child(instance)
	var cells: Dictionary = {} # (x - 25, y - 5) / 10 of each blocked 10 px cell
	for trans in transforms:
		cells[Vector2i(roundi(trans.origin.x/SCALE+320.0-25.0)/10,roundi(trans.origin.z/SCALE+200.0-5.0)/10)] = true
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	for row in 40:
		var column := 0
		while column < 60:
			if not cells.has(Vector2i(column,row)):
				column += 1
				continue
			var start := column
			while column < 60 and cells.has(Vector2i(column,row)): column += 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3((column-start)*cell,mesh.size.y,cell)
			shape.shape = box
			shape.position = point(20.0+(start+column)*5.0,5.0+row*10.0)+Vector3(0,mesh.size.y*0.5-0.05,0)
			body.add_child(shape)
	host.scene_root.add_child(body)


func hard_rect(e: Dictionary) -> Rect2:
	var normalized := e.duplicate()
	if not normalized.has("pseq"): normalized["pseq"] = e.get("seq",0)
	if not normalized.has("pframe"): normalized["pframe"] = e.get("frame",1)
	return host._hard_rect(normalized)

# --- Fitted buildings --------------------------------------------------------------------
# A building sprite is a picture of a 3D building from the original raised camera;
# tools/facade_fit.py recovers the building from its pixels, and scripts/sprite_buildings.gd
# builds it textured by projecting the sprite back through that camera, as the prototype does:
# doors, windows and damage drawn over it composited onto its walls, chimneys standing on its
# roof, dormers, mirrored backs. Its footprint is also what the player collides with (game.gd,
# data/footprints.json), so what stands here is exactly what blocks.

func frame_path(e: Dictionary) -> String:
	var seq := int(e.get("pseq",e.get("seq",0)))
	var frame := int(e.get("pframe",e.get("frame",1)))
	return str(host._frame(seq,frame).get("path",""))

# "path:x:y" of the sprite's top-left in world pixels, or "" when it has no fitted building.
func fitted_key(e: Dictionary, screen: int) -> String:
	if int(e.get("type",1)) == 2: return ""
	var path := frame_path(e)
	if not facades.has(path) or not (facades[path] is Dictionary) or not facades[path].has("faces"): return ""
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var o := screen_origin(screen)
	return "%s:%d:%d" % [path,int(o.x+float(e.get("x",0))-float(d.get("dx",0))),int(o.y+float(e.get("y",0))-float(d.get("dy",0)))]

func screen_origin(n: int) -> Vector2:
	return Vector2(((n-1)%32)*600-20,int((n-1)/32)*400)

# The map's sprites of screen n as drawn now: the story layer, removed sprites, type 2 left out.
func drawn_sprites(n: int, vision: int) -> Array:
	if n != host.current_screen and neighbour_states.has(n):
		var predicted: Array = []
		for e in neighbour_states[n].get("sprites", []):
			if int(e.get("type",1)) != 2 and int(e.get("active",1)) != 0 and int(e.get("nodraw",0)) == 0 and int(e.get("disabled",0)) == 0:
				predicted.append(e)
		return predicted
	var out: Array = []
	for source in host.world.screens.get(str(n),{}).get("sprites",[]):
		if int(source.get("vision",0)) != 0 and int(source.vision) != vision: continue
		var e: Dictionary = source
		var state: Dictionary = host.editor_state.get("%d:%d" % [n,int(source.get("index",0))],{})
		if not state.is_empty():
			e = source.duplicate()
			e.merge(state,true)
		if e.get("removed",false) or int(e.get("type",1)) == 2: continue
		out.append(e)
	return out

# Which sprites each fitted house draws, gathered as the prototype gathers them (in the order of a
# 5x5 block of screens round the current one, a part going to the first house that claims it), for
# the current scene and story layer.
func house_plan() -> void:
	var vision := int(host.vm.globals.get("vision",0))
	var key := "%d:%d:%d" % [host.generation,host.current_screen,vision]
	if key == plan_key: return
	plan_key = key
	plan_claimed = {}
	plan_parts = {}
	plan_hulls = []
	if is_inside(host.current_screen): return
	var candidates: Array = []
	var block: Dictionary = {} # the screens of the block
	var column: int = (host.current_screen-1)%32
	for dz in range(-2,3):
		for dx in range(-2,3):
			if column+dx < 0 or column+dx >= 32: continue
			var n: int = host.current_screen+dx+dz*32
			if not host.world.screens.has(str(n)) or is_inside(n): continue
			block[n] = true
			for e in drawn_sprites(n,vision): candidates.append([e,n,"%d:%d" % [n,int(e.get("index",0))]])
	for c in candidates:
		if not buildings.is_fitted(c[0]): continue
		plan_claimed[c[2]] = true
		var hk := fitted_key(c[0],int(c[1]))
		if plan_parts.has(hk): continue
		var rect: Rect2 = buildings.world_rect(c[0],int(c[1]))
		plan_parts[hk] = buildings.gather(facades[frame_path(c[0])],rect,candidates,plan_claimed)
		var hull: PackedVector2Array = buildings.hull_of(facades[frame_path(c[0])],rect)
		if hull.size() >= 3:
			var d: Dictionary = buildings.sprite_frame(c[0])
			var box := Rect2(hull[0],Vector2.ZERO)
			for q in hull: box = box.expand(q)
			plan_hulls.append([hull,rect.position+Vector2(float(d.get("dx",0)),float(d.get("dy",0))),int(c[0].get("que",0)),int(c[1]),box])
	# The kit buildings (the inn and its kin), after the houses: one footprint per block of wall faces (one hull round
	# all of kit-417 would take in its courtyard). A kit is many sprites over its tiles and has no one hotspot to order
	# by; its sixth field holds its upright sprites, [drawn world rect, world y], for depth_rule.
	for b in facades.get("_kit_buildings",[]):
		if not (b.screens as Array).any(func(m): return block.has(int(m))): continue
		var members: Array = []
		for m in b.members:
			if str(m[1]) != "s": continue
			var sprites: Array = host.world.screens.get(str(int(m[0])),{}).get("sprites",[])
			if int(m[2]) >= sprites.size(): continue
			var s: Dictionary = sprites[int(m[2])]
			if int(s.get("type",1)) != 1: continue # background sprites are drawn under every upright one
			var d: Dictionary = host._frame(int(s.get("seq",0)),int(s.get("frame",1)))
			var tex: Texture2D = host._texture("res://"+str(d.get("path","")))
			if tex == null: continue
			var f := maxf(0.01,float(s.get("size",100))/100.0)
			var at := screen_origin(int(m[0]))+Vector2(float(s.get("x",0)),float(s.get("y",0)))
			members.append([Rect2(at-Vector2(float(d.get("dx",0)),float(d.get("dy",0)))*f,Vector2(tex.get_width(),tex.get_height())*f),at.y])
		var top_left := Vector2(float(b.rect[0]),float(b.rect[1]))
		var feet: Dictionary = {}
		for f in b.faces:
			if int(f.label) != 1: continue
			for q in f.pts:
				if absf(float(q[1])) < 1e-3:
					if not feet.has(int(f.block)): feet[int(f.block)] = []
					feet[int(f.block)].append(top_left+Vector2(float(q[0]),float(q[2])))
		for k in feet:
			var hull := Geometry2D.convex_hull(PackedVector2Array(feet[k]))
			if hull.size() < 3: continue
			var box := Rect2(hull[0],Vector2.ZERO)
			for q in hull: box = box.expand(q)
			plan_hulls.append([hull,Vector2.ZERO,0,-1,box,members])
	# The castle's walls and towers: the same rule (a door in a castle wall is drawn over it).
	for piece in castle_pieces():
		var fit: Dictionary = buildings.castle_fit(str(piece[1]))
		var at: Vector2 = piece[2]
		for q in fit.parts:
			var hull := PackedVector2Array()
			if str(q.type) == "wall":
				var s := float(q.s)
				var c := float(q.c)
				var tv := float(q.get("depth",q.tv))
				var x0 := float(q.x0)
				var x1 := float(q.x1)
				for p in [Vector2(x0,s*x0+c),Vector2(x1,s*x1+c),Vector2(x1,s*x1+c-tv),Vector2(x0,s*x0+c-tv)]: hull.append(at+p)
			elif str(q.type) == "block":
				# The gatehouse and the corner: the plan polygon's hull (the cornice's overhang included).
				var flat := PackedVector2Array()
				for p in (q.poly_ov if q.get("poly_ov") != null else q.poly): flat.append(at+Vector2(float(p[0]),float(p[1])))
				hull = Geometry2D.convex_hull(flat)
				if hull.size() > 1 and hull[0] == hull[hull.size()-1]: hull.remove_at(hull.size()-1)
			else:
				for i in 24:
					var t := TAU*float(i)/24.0
					hull.append(at+Vector2(float(q.cx)+float(q.ar)*cos(t),float(q.cz)+float(q.k)*float(q.ar)*sin(t)))
			var box := Rect2(hull[0],Vector2.ZERO)
			for p in hull: box = box.expand(p)
			# The order the original draws it in: the hotspot's y, a background (type 0) piece before everything else.
			var order: Vector2 = piece[3]
			plan_hulls.append([hull,Vector2(at.x,order.y if order.x > 0.0 else order.y-100000.0),0,int(piece[4]),box])

# Whether a fitted house draws this sprite of `screen` onto itself (a door, a window, damage, a
# chimney): then it has no model of its own.
func house_part(e: Dictionary, screen: int) -> bool:
	if interior or not source_path(e).contains("/struct/"): return false
	house_plan()
	return plan_claimed.has("%d:%d" % [screen,int(e.get("editor_num",e.get("index",-1)))])

func add_fitted_building(node: Node3D, e: Dictionary, id: int, screen: int, collision: bool) -> void:
	var key := fitted_key(e,screen)
	var own: bool = screen == host.current_screen and id != 0
	if fitted_built.has(key):
		var holder: Variant = fitted_built[key]
		if holder == null and not own: return # the current screen builds its own
		# Built once: a house drawn twice (its foot and its top), or on two screens. A save
		# being loaded frees the old visuals, so a stale holder is rebuilt.
		if holder != null and is_instance_valid(holder) and not holder.is_queued_for_deletion(): return
	fitted_built[key] = node
	house_plan()
	var path := frame_path(e)
	var fit: Dictionary = facades[path]
	var rect: Rect2 = buildings.world_rect(e,screen)
	var parts: Dictionary = plan_parts.get(key,{"details":[],"roof":[],"ground":[]})
	# The node stands at the centre of the footprint, so story treatments sit on the house.
	var foot := PackedVector2Array()
	for f in fit.faces:
		for q in f.pts:
			if absf(float(q[1])) < 0.5: foot.append(Vector2(float(q[0]),float(q[2])))
	var box := Rect2(foot[0],Vector2.ZERO)
	for q in foot: box = box.expand(q)
	var top_left := rect.position-screen_origin(screen)
	var centre := top_left+box.get_center()
	node.position = point(centre.x,centre.y)
	var sig := parts_signature(parts)
	var vision := screen_vision(screen)
	var built: Dictionary = buildings.house(path,rect,parts,"%s|%s|%d" % [key,sig,vision],bake_key(key,sig),false)
	var model: Node3D = built.node
	model.name = "Model"
	model.position = Vector3(-box.get_center().x*SCALE,0,-box.get_center().y*SCALE)
	node.add_child(model)
	if collision: node.add_child(ray_body(model,id))
	node.set_meta("height",model_height(model))
	node.set_meta("fitted",true)
	if is_story_house(e,screen):
		if vision == 1: add_story_fire(node,box.size.x*SCALE,roof_spots(fit,box.get_center()))
		elif vision == 2: add_ruin_skin(node,model)

# The castle pieces of the 5x5 block as drawn now: [key, path, sprite top-left (world px), draw order], once per
# scene, screen and story layer.
var castle_plan_key := ""
var castle_list: Array = []
func castle_pieces() -> Array:
	var vision := int(host.vm.globals.get("vision",0))
	var key := "%d:%d:%d" % [host.generation,host.current_screen,vision]
	if key == castle_plan_key: return castle_list
	castle_plan_key = key
	castle_list = []
	if is_inside(host.current_screen): return castle_list
	var seen := {}
	var column: int = (host.current_screen-1)%32
	for dz in range(-2,3):
		for dx in range(-2,3):
			if column+dx < 0 or column+dx >= 32: continue
			var n: int = host.current_screen+dx+dz*32
			if not host.world.screens.has(str(n)) or is_inside(n): continue
			for e in drawn_sprites(n,vision):
				var ck := castle_key(e,n)
				if ck.is_empty() or seen.has(ck): continue
				seen[ck] = true
				castle_list.append([ck,frame_path(e),castle_origin(e,n),castle_order(e,n),n])
	return castle_list

func castle_origin(e: Dictionary, screen: int) -> Vector2:
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	return screen_origin(screen)+Vector2(float(e.get("x",0))-float(d.get("dx",0)),float(e.get("y",0))-float(d.get("dy",0)))

# The original's draw order: background (type 0) sprites first, then by que, else y (world px, the hotspot's).
func castle_order(e: Dictionary, screen: int) -> Vector2:
	var que := float(e.get("que",0))
	return Vector2(0.0 if effective_type(e) == 0 else 1.0,que if que != 0.0 else screen_origin(screen).y+float(e.get("y",0)))

# Where a later-drawn piece lies along the same wall (same slope, same base line, to a pixel) covers this piece,
# the original draws it over: this piece's wall parts are clipped to the span left of it, part index -> [x0, x1]
# in the sprite's own pixels. A piece wholly inside another one is left whole.
func castle_clips(e: Dictionary, screen: int) -> Dictionary:
	var key := castle_key(e,screen)
	var path := frame_path(e)
	var fit: Dictionary = buildings.castle_fit(path)
	var here := castle_origin(e,screen)
	var order := castle_order(e,screen)
	var clips := {}
	for i in fit.parts.size():
		var q: Dictionary = fit.parts[i]
		if str(q.type) != "wall": continue
		var lo := float(q.x0)
		var hi := float(q.x1)
		var line := float(q.c)+here.y-float(q.s)*here.x # the base line's intercept in world px
		for other in castle_pieces():
			if other[0] == key: continue
			var o_order: Vector2 = other[3]
			if not (o_order.x > order.x or (o_order.x == order.x and o_order.y > order.y)): continue
			var o_fit: Dictionary = buildings.castle_fit(str(other[1]))
			for oq in o_fit.parts:
				if str(oq.type) != "wall" or absf(float(oq.s)-float(q.s)) > 0.002: continue
				var o_at: Vector2 = other[2]
				if absf(float(oq.c)+o_at.y-float(oq.s)*o_at.x-line) > 2.0: continue
				var o_lo := o_at.x+float(oq.x0)-here.x
				var o_hi := o_at.x+float(oq.x1)-here.x
				if o_lo <= lo+1.0 and o_hi > lo: lo = minf(o_hi,hi)
				elif o_hi >= hi-1.0 and o_lo < hi: hi = maxf(o_lo,lo)
		if lo != float(q.x0) or hi != float(q.x1): clips[i] = [lo,hi]
	return clips

# "castle|path|x|y" of a fitted castle piece's sprite top-left in world pixels, or "" if it is not one.
func castle_key(e: Dictionary, screen: int) -> String:
	if int(e.get("type",1)) == 2 or model_key(e) != "castle": return ""
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var o := screen_origin(screen)
	return "castle|%s|%d|%d" % [frame_path(e),int(o.x+float(e.get("x",0))-float(d.get("dx",0))),int(o.y+float(e.get("y",0))-float(d.get("dy",0)))]

# A castle piece fitted from its sprite (scripts/sprite_buildings.gd castle: a prism of wall or a round tower)
# stands in 3D where the fixed card stood: its model has its sprite's top-left for origin, its ray body is its
# faces' (as a house's); movement still reads the source hardbox (game.gd). One placed twice at a spot, or on two
# screens, is built once (the current screen's own placement wins, as for houses).
func add_castle_piece(node: Node3D, e: Dictionary, id: int, screen: int, collision: bool) -> void:
	var key := castle_key(e,screen)
	var own: bool = screen == host.current_screen and id != 0
	if fitted_built.has(key):
		var holder: Variant = fitted_built[key]
		if holder == null and not own: return
		if holder != null and is_instance_valid(holder) and not holder.is_queued_for_deletion(): return
	fitted_built[key] = node
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var model: Node3D = buildings.castle(frame_path(e),castle_clips(e,screen))
	model.name = "Model"
	model.position = Vector3(-float(d.get("dx",0))*SCALE,0,-float(d.get("dy",0))*SCALE)
	node.add_child(model)
	if collision and e.get("warp") == null: node.add_child(ray_body(model,id))
	node.set_meta("height",model_height(model))
	node.set_meta("castle",true)

# A hut of struct/Island (isle-01..06) fitted from its sprite (tools/hut_fit.py) stands in 3D where the fixed card
# stood (docs/DIRECTION.md, M3): a solid of revolution about its axis, textured by the original camera's projection
# (scripts/sprite_buildings.gd hut). Drawn at its own size only; its ray body is its faces' (as a castle piece's), and
# movement still reads the source hardbox (game.gd).
func hut_fitted(e: Dictionary) -> bool:
	return absf(float(e.get("size",100)) - 100.0) < 0.5 and not buildings.hut_fit(frame_path(e)).is_empty()

func add_hut(node: Node3D, e: Dictionary, id: int, collision: bool) -> void:
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var model: Node3D = buildings.hut(frame_path(e))
	model.name = "Model"
	model.position = Vector3(-float(d.get("dx",0))*SCALE,0,-float(d.get("dy",0))*SCALE)
	node.add_child(model)
	if collision and e.get("warp") == null: node.add_child(ray_body(model,id))
	node.set_meta("height",model_height(model))
	node.set_meta("hut",true)

# What a house draws, for its cache key: the same parts give the same textures.
func parts_signature(parts: Dictionary) -> String:
	var keys: Array = []
	for group in ["details","roof","ground"]:
		for p in parts.get(group,[]): keys.append("%s:%s:%s" % [group,frame_path(p[0]),str(p[1] if p[1] is Rect2 else p[2])])
	return ",".join(keys).sha1_text()

# The house's key in the bake (tools/bake_houses.gd): the house and the parts it draws.
func bake_key(key: String, signature: String) -> String:
	return "%s|%s" % [key,signature]

func model_height(model: Node3D) -> float:
	var top := 0.0
	for child in model.get_children():
		if child is MeshInstance3D: top = maxf(top,(child as MeshInstance3D).get_aabb().end.y)
	return top

func sprite_image(path: String) -> Image:
	var rows := ""
	if "#" in path: # a stacked part's rows (stack_part): "art.png#r0-r1"
		rows = path.get_slice("#",1)
		path = path.get_slice("#",0)
	var texture: Texture2D = host._texture("res://"+path)
	if texture == null: return null
	var image := texture.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if not rows.is_empty():
		var r0 := int(rows.get_slice("-",0))
		image = image.get_region(Rect2i(0,r0,image.get_width(),int(rows.get_slice("-",1))-r0))
	return image

# The height of a sprite's drawn pixels above its hotspot, in source pixels (0 if it has none):
# how tall the thing it draws stands, as the prototype's billboards stand it. The black shadow
# dither is left out.
func sprite_height(e: Dictionary) -> float:
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var path := str(d.get("path",""))
	if path.is_empty(): return 0.0
	if sprite_heights.has(path): return sprite_heights[path]
	var image := sprite_image(path)
	var result := 0.0
	if image != null:
		for y in image.get_height():
			var found := false
			for x in image.get_width():
				var c := image.get_pixel(x,y)
				if c.a > 0.5 and c.r+c.g+c.b >= 0.04:
					found = true
					break
			if found:
				result = maxf(0.0,float(d.get("dy",image.get_height()))-y)
				break
	sprite_heights[path] = result
	return result

# The building's faces as a body for rays only (aim, projectiles, dialogue cameras); movement
# reads the footprint (game.gd).
func ray_body(model: Node3D, id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 1
	body.collision_mask = 0
	var faces := PackedVector3Array()
	for child in model.get_children():
		if not child is MeshInstance3D: continue
		var t: Transform3D = model.transform*(child as MeshInstance3D).transform
		for v in (child as MeshInstance3D).mesh.get_faces(): faces.append(t*v)
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	return body

# Where a roof slope faces +X (the discovery camera's side, add_story_fire): the middle of each
# such roof face, relative to the footprint's centre `origin` (sprite pixels).
func roof_spots(fit: Dictionary, origin: Vector2) -> Array:
	var spots: Array = []
	for f in fit.faces:
		if int(f.label) != 2: continue
		var pts: Array[Vector3] = buildings.pts_of(f)
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for q in pts: mid += q/pts.size()
		var c: Array = fit.centers[int(f.block)]
		if normal.dot(mid-Vector3(float(c[0]),float(c[1]),float(c[2]))) < 0: normal = -normal
		if normal.x > 0.3 and spots.size() < 4:
			spots.append(Vector3((mid.x-origin.x)*SCALE,mid.y*SCALE,(mid.z-origin.y)*SCALE))
	return spots

# Kit buildings (the inn and its kin: seq 33 pieces and building tiles, found over the whole
# map by tools/facade_fit.py) with a piece on screen `number`, built once per scene.
func add_kit_buildings(number: int, parent: Node3D, offset: Vector3) -> void:
	for b in facades.get("_kit_buildings",[]):
		if not (b.screens as Array).any(func(m): return int(m) == number): continue
		var key := "kit:%s" % str(b.name)
		if fitted_built.has(key): continue
		var o := screen_origin(number)
		var rect: Array = b.rect
		var top_left := Vector2(float(rect[0]),float(rect[1]))-o
		var node := Node3D.new()
		node.name = "Kit_%s" % str(b.name)
		node.set_meta("model_key","inn")
		parent.add_child(node)
		fitted_built[key] = node
		node.position = point(top_left.x,top_left.y)+offset
		var model: Node3D = buildings.kit(b)
		model.name = "Model"
		node.add_child(model)
		if offset == Vector3.ZERO: node.add_child(ray_body(model,0))

# A door drawn on a building stands in its wall: on the nearest footprint edge, turned to it.
func set_in_wall(node: Node3D, model: Node3D, e: Dictionary, screen: int) -> void:
	var at := Vector2(float(e.get("x",0)),float(e.get("y",0)))
	var best := 30.0
	var hit := Vector2.INF
	var along := Vector2.RIGHT
	var outward := Vector2.DOWN
	for p in host.footprints.get(str(screen),{}).get("polys",[]):
		var poly := PackedVector2Array()
		for q in p.pts: poly.append(Vector2(float(q[0]),float(q[1])))
		var mid := Vector2.ZERO
		for q in poly: mid += q/poly.size()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i+1)%poly.size()]
			var c := Geometry2D.get_closest_point_to_segment(at,a,b)
			if c.distance_to(at) < best:
				best = c.distance_to(at)
				hit = c
				along = (b-a).normalized()
				outward = Vector2(-along.y,along.x)
				if outward.dot(c-mid) < 0: outward = -outward
	if hit == Vector2.INF: return
	node.position = point(hit.x,hit.y)
	# The door model faces its local +Z (the knob side); turn that outward.
	model.rotation.y = atan2(outward.x,outward.y)

func screen_vision(screen: int) -> int:
	if screen != host.current_screen and neighbour_states.has(screen):
		return int(neighbour_states[screen].get("vision",0))
	return int(host.vm.globals.get("vision",0))

func is_story_house(e: Dictionary, screen: int) -> bool:
	# Map 439's home-01 at this anchor is Dink's house.  The other Home and
	# fire sprites on the map are scenery, and must not inherit its story state.
	return screen == 439 and int(e.get("x",-1)) == 275 and int(e.get("y",-1)) == 234 and source_path(e).ends_with("/home/home-01.png")

func add_story_fire(node: Node3D, house_width: float, roof_spots: Array = []) -> void:
	# The discovery camera approaches from the house's +X side.  Keep flames
	# just beyond that roof plane so they read as attached roof fire rather than
	# being hidden inside the imported cottage mesh.
	node.set_meta("story_house_state","burning")
	var treatment := Node3D.new()
	treatment.name = "StoryHouseFire"
	treatment.set_meta("story_house_treatment",true)
	node.add_child(treatment)
	if not roof_spots.is_empty():
		# A fitted house burns with the map's own fire: its fire1-0x sprites, standing on the roof
		# where they are drawn (place_on_surface). No second set of flames is added.
		return
	var face_x := house_width*0.5+0.28
	for spec in [[4.00,-1.70,0.95],[4.72,-0.60,1.25],[4.46,0.72,1.08],[3.92,1.72,0.88]]:
		var fire := story_flame(int(spec[0]*10))
		fire.position = Vector3(face_x,float(spec[0]),float(spec[1]))
		fire.scale = Vector3.ONE*float(spec[2])
		treatment.add_child(fire)

# A flame of the original fire (seq 427, fire1, the burning house's own sprites), playing its
# frames at the sequence's delay from frame `phase`: a billboard standing on its roof spot.
var fire_frames: SpriteFrames
func story_flame(phase: int) -> Node3D:
	var node := Node3D.new()
	if fire_frames == null:
		fire_frames = SpriteFrames.new()
		var frames: Array = host.sequences.get("427",{}).get("frames",[])
		var delay := float(frames[0].get("delay",100)) if not frames.is_empty() else 100.0
		fire_frames.set_animation_speed("default",1000.0/maxf(delay,15.0))
		for f in frames:
			var t := clean_texture(str(f.get("path","")))
			if t != null: fire_frames.add_frame("default",t)
	if fire_frames.get_frame_count("default") == 0: return primitive_model("flame")
	var t0: Texture2D = fire_frames.get_frame_texture("default",0)
	var sp := AnimatedSprite3D.new()
	sp.sprite_frames = fire_frames
	sp.pixel_size = SCALE
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.centered = true
	# The fire's hotspot lies 21 px below and right of its drawn flames (the original's raised view
	# puts it on the ground under the roof). On a roof spot the flames stand on the thatch: the
	# frame's bottom centre, a few pixels sunk in, is the anchor.
	sp.offset = Vector2(0,t0.get_height()/2.0-4.0)
	sp.frame = phase%fire_frames.get_frame_count("default")
	sp.autoplay = "default"
	node.add_child(sp)
	sp.play("default")
	return node

func add_ruin_skin(node: Node3D, model: Node3D) -> void:
	# Vision 2 keeps the original cottage mesh and collision body.  Each mesh
	# surface gets a private charcoal material, preserving its roof/wall geometry
	# across viewpoints instead of placing an opaque facade in front of it.
	node.set_meta("story_house_state","charred")
	var treatment := Node3D.new()
	treatment.name = "StoryHouseRuin"
	treatment.set_meta("story_house_treatment",true)
	node.add_child(treatment)
	var nodes: Array[Node] = [model]
	while not nodes.is_empty():
		var current: Node = nodes.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current
			var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
			for surface in surface_count:
				var original := mesh_instance.get_active_material(surface)
				if original is BaseMaterial3D:
					var charred: BaseMaterial3D = original.duplicate()
					# This multiplies the existing wood/stone textures: visibly ash-dark
					# while retaining the original roof seams and wall detail.
					charred.albedo_color = Color("7f6d55")
					charred.emission_enabled = false
					mesh_instance.set_surface_override_material(surface,charred)
		nodes.append_array(current.get_children())

# --- Sprites -----------------------------------------------------------------------------
# Whether a card keeps the orientation it was drawn in. Only a structure does: a fence (and the island's
# rail fences), a wall (stone and castle walls: "tower", but not the monuments of struct/Stone/mdink, the
# statues, which stand upright), a sign (a signboard is a flat board: edge-on from the side is right), a
# bridge's rope railing (bridge_part; a bridge's deck is painted into the ground) and the island's round
# huts. Everything else is a Y-axis billboard whatever its width: the width of an art includes its shadow
# dither, so it says nothing of what stands in it (every tree is over 100 px).
func is_structure(key: String, path: String) -> bool:
	if key in ["fence","wall","hut","sign","bridge_rail"]: return true
	return key == "tower" and not "/stone/" in path.to_lower()

# The original sprite of a thing that is not a building, drawn as the prototype draws it
# (sprite_world_proto.gd _add_sprite): at its hotspot, 0.025 m per pixel times its size, unshaded
# with the light the art was drawn with, its shadow dither removed. Props, trees and actors are
# Y-axis billboards, whatever their width; structures (is_structure: fences, walls, castle walls, signs,
# huts) keep the orientation they were drawn in (facing the original viewer, +Z), and a fence post
# column drawn along the depth axis is rebuilt from the side-view rail (seq 93 frame 1) turned 90
# degrees. A tree is round: seen from the side it must stand whole, not as the edge of a card. Collision
# stays in source pixels (game.gd); the body here is for rays (aim, projectiles, dialogue cameras).
# A fixed card casts its own shadow; a billboard casts its silhouette from a twin turned to the sun
# (shadow_twin).
func add_billboard(node: Node3D, e: Dictionary, id: int, key: String, collision: bool, screen: int) -> void:
	var path := frame_path(e)
	var texture := clean_texture(path)
	if texture == null: return
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var factor := maxf(0.01,float(e.get("size",100))/100.0)
	var sp := Sprite3D.new()
	sp.name = "Model"
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sp.pixel_size = SCALE*factor
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lower := path.to_lower()
	var fence := "/fence/" in lower
	var fixed := fence or is_structure(key,lower)
	if fence and texture.get_height() > 2*texture.get_width():
		# The drawn post column spans the segment's depth; cover it with a side-view rail.
		var rail := str(host._frame(93,1).get("path",""))
		var rt := clean_texture(rail)
		if rt != null:
			var length := float(texture.get_height())*0.8
			sp.texture = rt
			sp.region_enabled = true
			sp.region_rect = Rect2(0,0,minf(length,rt.get_width()),rt.get_height())
			sp.centered = true
			sp.offset = Vector2(0,rt.get_height()/2.0-8.0)
			sp.rotation_degrees.y = 90
			sp.position.z = -(float(d.get("dy",texture.get_height()))-texture.get_height()/2.0)*SCALE*factor
			sp.set_meta("static",true)
	if not sp.has_meta("static"):
		place_on_surface(node,sp,e,d,screen)
		set_sprite_texture(sp,path,texture,d)
	if fixed:
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(sp)
	if not fixed: shadow_twin(sp,false)
	var height := maxf(0.2,sprite_height(e)*SCALE*factor)
	node.set_meta("height",height)
	node.set_meta("base_model_position",sp.position)
	var actor := key in ACTORS
	node.set_meta("actor",actor)
	node.set_meta("billboard",true)
	sp.set_meta("screen",screen)
	# A door or gate drawn in a castle wall is drawn over it (the wall's hull is in plan_hulls: castle_pieces).
	if not (fence or ("/struct/" in lower and not ("/cdoor" in lower or "/cgate" in lower))): settle_depth(sp,e)
	if actor: update_billboard(sp,e)
	var passable_fence := key == "fence" and int(e.get("hard",0)) != 0
	if not collision or passable_fence or e.get("warp") != null: return
	if key in ["grass","flowers","mushroom","effect","feed_grains","flame","burn_scar","hole","arrow"]: return
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 2 if actor or not str(e.get("script","")).is_empty() else 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if key in ["fence","wall","tower","bridge_rail"]:
		# On the source hardbox, as the stand-ins' bodies were.
		var rect: Rect2 = hard_rect(e)
		box.size = Vector3(maxf(0.2,rect.size.x*SCALE),height,maxf(0.2,rect.size.y*SCALE))
		shape.position = point(rect.get_center().x,rect.get_center().y)-node.position
	else:
		var width := maxf(0.3,float(texture.get_width())*SCALE*factor)
		box.size = Vector3(width,height,minf(width,0.6))
		if key in ["oak_tree","pine_tree","dead_tree"]: box.size = Vector3(0.8,height,0.8)
	shape.position.y = height*0.5
	shape.shape = box
	body.add_child(shape)
	node.add_child(body)

# The frame the original shows now (its animation, else its still frame); a directional actor's
# frame is the one drawn for its facing as seen from the camera, as Doom does (the prototype's
# _face_actors).
func update_billboard(sp: Sprite3D, e: Dictionary) -> void:
	if sp.has_meta("static"): return
	var seq := int(e.get("seq",0))
	var frame := int(e.get("frame",1))
	if seq == 0:
		seq = int(e.get("pseq",0))
		frame = int(e.get("pframe",1))
	var camera: Camera3D = host.camera if "camera" in host else null
	if camera != null and is_instance_valid(camera) and str(sp.get_parent().get_meta("model_key","")) in ACTORS:
		for base_key in ["base_walk","base_idle","base_attack"]:
			var base := int(e.get(base_key,-1))
			if base <= 0 or seq <= base or seq > base+9 or not DIRS.has(seq-base): continue
			var at := sp.get_parent() as Node3D
			var to_actor := Vector2(at.global_position.x-camera.global_position.x,at.global_position.z-camera.global_position.z)
			if to_actor.length() < 0.001: break
			var rel: Vector2 = (DIRS[seq-base] as Vector2).normalized().rotated(-Vector2(0,-1).angle_to(to_actor.normalized()))
			var best := seq-base
			var best_dot := -2.0
			for k in DIRS:
				var dd: float = (DIRS[k] as Vector2).normalized().dot(rel)
				if dd > best_dot and host.sequences.has(str(base+k)):
					best_dot = dd
					best = k
			seq = base+best
			break
	var d: Dictionary = host._frame(seq,frame)
	var path := str(d.get("path",""))
	sp.pixel_size = SCALE*maxf(0.01,float(e.get("size",100))/100.0)
	sync_twin(sp)
	if not path.is_empty() and path != str(sp.get_meta("path","")):
		var texture := clean_texture(path)
		if texture != null: set_sprite_texture(sp,path,texture,d)
	# Settled for the frame it shows now: its half-width is the sprite's reach, and an actor's frame (and its
	# width) changes with where it stands and where the camera looks. The texture, the depth shader's and the
	# shadow twin's, is the new frame's by now (set_sprite_texture).
	if sp.has_meta("depth_sig"): settle_depth(sp,e)

# The texture of frame `d`, anchored at its hotspot (the prototype's _set_anchor).
func set_sprite_texture(sp: Sprite3D, path: String, texture: Texture2D, d: Dictionary) -> void:
	sp.texture = texture
	sp.set_meta("path",path)
	if sp.material_override is ShaderMaterial: (sp.material_override as ShaderMaterial).set_shader_parameter("tex",texture)
	var dx := float(d.get("dx",texture.get_width()/2.0))
	var dy := float(d.get("dy",texture.get_height()-10.0))
	if sp.has_meta("on_surface"):
		var foot := sprite_foot(path)
		dx = foot.x
		dy = foot.y
	sp.centered = true
	sp.offset = Vector2(texture.get_width()/2.0-dx,dy-texture.get_height()/2.0)
	sync_twin(sp)

# The prototype's clean(): the original draws shadows as a 50% black checkerboard on the ground;
# standing upright, that dither floats in the air, so isolated pure-black pixels are removed.
func clean_texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if clean_cache.has(path): return clean_cache[path]
	var img := sprite_image(path)
	if img == null:
		clean_cache[path] = null
		return null
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var out := src.duplicate()
	var dark := PackedByteArray()
	dark.resize(w*h)
	for i in w*h:
		var o := i*4
		dark[i] = 1 if src[o+3] > 127 and int(src[o])+int(src[o+1])+int(src[o+2]) < 11 else 0
	for y in h:
		for x in w:
			var i := y*w+x
			if dark[i] == 0: continue
			if (x > 0 and dark[i-1] == 1) or (x < w-1 and dark[i+1] == 1) or (y > 0 and dark[i-w] == 1) or (y < h-1 and dark[i+w] == 1): continue
			out[i*4+3] = 0
	var cleaned := Image.create_from_data(w,h,false,Image.FORMAT_RGBA8,out)
	cleaned.generate_mipmaps()
	clean_cache[path] = ImageTexture.create_from_image(cleaned)
	return clean_cache[path]

# A sprite drawn over a fitted house stands on the surface it is drawn on, found as the chimneys'
# feet are (sprite_buildings.gd claim, ray_hit): the original camera's view ray through the
# sprite's foot (its lowest drawn pixels) meets the house where the sprite stands. "Drawn over"
# is the original's draw order: its que, else its y, after the house's. The story fire's flames
# (fire1-0x, que 1000) were drawn on the cottage's roof with their hotspots 21 px below them, on the
# ground; they now stand on the roof. A sprite whose foot misses every house, or lies in front of
# its walls, keeps its hotspot.
func place_on_surface(node: Node3D, sp: Sprite3D, e: Dictionary, d: Dictionary, screen: int) -> void:
	if interior or node.get_meta("model_key","") in ACTORS: return
	var foot := sprite_foot(frame_path(e))
	if foot.y <= 0.0: return
	var o := screen_origin(screen)
	var factor := maxf(0.01,float(e.get("size",100))/100.0)
	var world_foot := o+Vector2(float(e.get("x",0)),float(e.get("y",0)))+(foot-Vector2(float(d.get("dx",0)),float(d.get("dy",0))))*factor
	var order := float(e.get("que",0)) if int(e.get("que",0)) != 0 else float(e.get("y",0))
	var best := []
	for h in drawn_sprites(screen,int(host.vm.globals.get("vision",0))):
		if not buildings.is_fitted(h): continue
		var h_order := float(h.get("que",0)) if int(h.get("que",0)) != 0 else float(h.get("y",0))
		if order <= h_order: continue
		var rect: Rect2 = buildings.world_rect(h,screen)
		var hit: Array = buildings.ray_hit(facades[frame_path(h)],world_foot.x-rect.position.x,world_foot.y-rect.position.y)
		if hit.is_empty() or float(hit[0]) <= 0.5: continue
		if best.is_empty() or float(hit[0]) > float(best[0]): best = [float(hit[0])]
	if best.is_empty():
		# A door or gate drawn in a castle wall stands on the wall's base, anchored by its foot: the art's hotspot lies
		# above the foot (cdoor-01: 40 px), and a card standing at the hotspot sinks its lower rows under the ground. The
		# picture from the original camera is the same; settle_depth then draws it over the wall.
		var lower := frame_path(e).to_lower()
		if "/cdoor" in lower or "/cgate" in lower:
			node.position = point(world_foot.x-o.x,world_foot.y-o.y)
			node.set_meta("surface_position",node.position)
			sp.set_meta("on_surface",true)
			sp.set_meta("castle_door",true)
		return
	var height: float = best[0]
	# The hit point (x, Y, y + Y): its ground point lies Y deeper than the foot's screen y.
	var at := world_foot+Vector2(0,height)-o
	node.position = point(at.x,at.y)+Vector3(0,height*SCALE,0)
	node.set_meta("surface_position",node.position)
	sp.set_meta("on_surface",true)

# --- Sprites against buildings (docs/DIRECTION.md, "Trees against buildings in the game") ---------
# A sprite stands at its hotspot as a flat card, so a canopy wider than the distance from its trunk
# to a house is cut by the house's walls wherever the card's plane passes inside them. The original
# draws it whole, on the side of the house its draw order says: after the house (its que, else its y,
# above the house's) it is over the house, before it, under. A card whose hotspot lies within its
# half-width of a house's wall footprint therefore takes a depth shift of that half-width in its own
# shader (the prototype's _flag_nudge and _push_back; sprite_world_proto.gd): drawn over, it is pulled
# toward the camera, so the walls cannot cut it; drawn under, it is pushed away, so the house hides
# its canopy. Only the depth moves: the sprite keeps its place and its size, and its trunk and its body
# stay where the source puts them.
# The original's draw order is fixed to one camera, which looks north: the y of the hotspots. The game's
# camera looks every way. Seen from the original's side of the wall nearest the sprite (the side of that
# wall's plane the original camera is on) the order is the original's, so from the original camera the
# picture is the prototype's; seen from the other side of that wall the house stands between the camera
# and the sprite, and the order is reversed: a tree that stands south of a house is under it from the
# north (pulled toward that camera it stood on the house's back wall). A sprite inside the footprint, or
# one a que orders (an explicit draw order, comparable on one screen), keeps the original's order from
# every side.
# The side turns when the camera crosses the wall's plane. A turn in one step pops: a patch of canopy appears over the
# wall in one frame when the two overlap on the screen (3,872 px at 251's cabin). So within `blend` (SIDE_BLEND reaches) of
# the plane either side, each fragment takes the one side or the other by a fixed screen-space threshold against the
# camera's place in the band (a screen-door cross-fade, as a LOD fade does): every fragment turns once, and the patch is
# revealed in step with the camera. Beyond the band, and through the original camera, the picture is the old one.
# Each fragment's push is capped at 0.9 of its clearance above the ground along the view ray, so a
# trunk's foot is never pushed under the ground (which moving the sprite did), and a pull at 0.9 of
# its distance from the camera. A fragment below the ground (the rows an art draws under its hotspot)
# is not shifted at all: the ground hides it as before, and the shift moves only what the buildings do.
# A moving sprite is settled again when it moves or when its frame changes its width (depth_sig holds its
# hotspot and its half-width): an actor standing against a wall is not cut by it either, from the side it
# stands on.
# Compatibility renderer: window depth = NDC z * 0.5 + 0.5. With the reach at 0 the sprite equals the
# plain one's pixels (tests/fps_trees_test.gd checks it).
const DEPTH_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_nearest_mipmap;
uniform float reach = 0.0; // metres: the sprite's half-width; 0 shifts nothing
uniform float side0 = 1.0; // +1 over the house, -1 under it, as the original camera sees it
uniform vec2 wall = vec2(0.0); // the nearest point of the house's walls, x z in metres
uniform vec2 normal = vec2(0.0); // from there to the sprite's trunk, unit; 0: the same side from every camera
uniform float blend = 0.0; // metres: the camera turns the side over this distance either side of the plane; 0 turns it at the plane
uniform float flip = 1.0; // the tests' wrong-rule control: -1 swaps the sides
uniform bool bill = true;
void vertex() {
	if (bill) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb;
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	// Which side of the wall's plane the camera is on, against the original camera's (it looks from +z).
	vec2 toward = ortho ? INV_VIEW_MATRIX[2].xz : INV_VIEW_MATRIX[3].xz - wall;
	float side = side0;
	if (dot(normal, normal) > 0.5) {
		float e = dot(toward, normal) * sign(normal.y); // the camera's distance from the plane, + on the original camera's side
		float turn = e < 0.0 ? -1.0 : 1.0;
		if (blend > 0.0 && !ortho) {
			// Within `blend` of the plane each pixel takes the one side or the other by a fixed screen-space threshold
			// (interleaved gradient noise) against the camera's place in the band, as a LOD cross-fade does: every pixel turns
			// once, so the picture changes in step with the camera instead of in one step. (Shifting the whole sprite by a
			// fraction of the reach does not: a card and a wall are planes, and the pixels it wins reveal in a few big steps.)
			float p = 0.5 + 0.5 * clamp(e / blend, -1.0, 1.0);
			float h = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
			turn = h < p ? 1.0 : -1.0;
		}
		side = side0 * turn;
	}
	float off = -side * flip * reach; // > 0 pushes away from the camera, < 0 pulls toward it
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dw = ortho ? -INV_VIEW_MATRIX[2].xyz : normalize(wp - INV_VIEW_MATRIX[3].xyz);
	vec3 dv = ortho ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);
	float shift = off;
	if (off > 0.0) {
		float room = -dw.y > 1e-4 ? 0.9 * max(wp.y, 0.0) / -dw.y : off;
		shift = min(off, room);
	} else if (!ortho) {
		shift = max(off, -0.9 * length(VERTEX));
	}
	if (wp.y <= 0.0) { shift = 0.0; } // what the ground hides stays hidden: only the buildings' order moves
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + dv * shift, 1.0);
	DEPTH = clip.z / clip.w * 0.5 + 0.5;
}
"""
var depth_shader: Shader
# How wide the side's turn is, in the sprite's reach. The side a sprite is drawn on turns when the camera crosses the wall's
# plane (the original draws it one way only); turned in one step while the canopy overlaps the house, a patch of canopy
# appears over the wall in one frame (docs/DIRECTION.md, "The side flip, walked"). Within SIDE_BLEND reaches of the plane
# either side the shader turns it pixel by pixel instead (a screen-door cross-fade, as a LOD fade does), so the patch is
# revealed in step with the camera. Beyond the band every camera gets the old picture bit for bit: the narrow band keeps the
# cut the trees pass removed away (its first sheet camera stands 0.43 reach from the plane, in the old picture).
const SIDE_BLEND := 0.1

# The depth rule's reading of a sprite of entity `e` on `screen` whose half-width is `half` px: {} if no
# house's wall footprint lies within `half` of its hotspot, else {"side": +1 over the house, -1 under it,
# as the original draws it; "wall": the nearest point of the footprint, world px; "normal": the unit vector
# from there to the sprite, or (0, 0) if the same side holds from every camera (a que orders it, or it
# stands inside the footprint)}. The first house within reach decides, as in the prototype; kit blocks come after the
# houses.
func depth_rule(e: Dictionary, screen: int, half: float) -> Dictionary:
	if interior or half <= 0.0: return {}
	house_plan()
	var at := screen_origin(screen)+Vector2(float(e.get("x",0)),float(e.get("y",0)))
	for h in plan_hulls:
		if not (h[4] as Rect2).grow(half).has_point(at): continue
		var hull: PackedVector2Array = h[0]
		var dist := 0.0
		var wall := at
		if not Geometry2D.is_point_in_polygon(at,hull):
			dist = INF
			for i in hull.size():
				var q := Geometry2D.get_closest_point_to_segment(at,hull[i],hull[(i+1) % hull.size()])
				if at.distance_to(q) < dist:
					dist = at.distance_to(q)
					wall = q
		if dist >= half: continue
		if h.size() > 5:
			# A kit block: the original draws the sprite over the kit unless one of the kit's upright sprites that its
			# picture overlaps is drawn after it (its y at or below the sprite's); the kit's tiles are under every sprite.
			var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
			var tex := clean_texture(str(d.get("path","")))
			var f := maxf(0.01,float(e.get("size",100))/100.0)
			var drawn := Rect2(at-Vector2(float(d.get("dx",0)),float(d.get("dy",0)))*f,Vector2(tex.get_width(),tex.get_height())*f) if tex != null else Rect2(at,Vector2.ONE)
			var side := 1.0
			for m in h[5]:
				if (m[0] as Rect2).intersects(drawn) and float(m[1]) >= at.y: side = -1.0
			return {"side": side,"wall": wall,"normal": Vector2.ZERO if dist < 0.01 else (at-wall)/dist}
		# The original's draw order: que, else y. A que is only comparable on its own screen.
		var home: Vector2 = h[1]
		var order := at.y
		var house_order := home.y
		var fixed := dist < 0.01
		if int(h[3]) == screen and (int(e.get("que",0)) != 0 or int(h[2]) != 0):
			order = float(e.get("que",0)) if int(e.get("que",0)) != 0 else float(e.get("y",0))
			house_order = float(h[2]) if int(h[2]) != 0 else home.y-screen_origin(screen).y
			fixed = true
		return {"side": 1.0 if order > house_order else -1.0,"wall": wall,"normal": Vector2.ZERO if fixed else (at-wall)/dist}
	return {}

# A point in world px as the scene places it: metres from the centre of the current screen.
func world_to_scene(world_px: Vector2) -> Vector2:
	var local := world_px-screen_origin(host.current_screen)
	return Vector2((local.x-320.0)*SCALE,(local.y-200.0)*SCALE)

# Settle sp's depth rule for where its entity stands now (a sprite that moves is settled again).
func settle_depth(sp: Sprite3D, e: Dictionary) -> void:
	if interior or sp.texture == null or (sp.has_meta("on_surface") and not sp.has_meta("castle_door")) or not is_instance_valid(sp.get_parent()): return
	var factor := maxf(0.01,float(e.get("size",100))/100.0)
	var half := float(sp.texture.get_width())/2.0*factor
	var sig := Vector3(float(e.get("x",0)),float(e.get("y",0)),half)
	if sp.get_meta("depth_sig",Vector3.INF) == sig: return
	sp.set_meta("depth_sig",sig)
	var screen := int(sp.get_meta("screen",host.current_screen))
	var rule := depth_rule(e,screen,half)
	if rule.is_empty():
		sp.material_override = null
		if sp.has_meta("depth_px"): sp.remove_meta("depth_px")
		shadow_twin(sp,false)
		return
	# What the original camera shows, in px: < 0 pulled toward the camera (over), > 0 pushed away (under).
	sp.set_meta("depth_px",-float(rule.side)*half)
	if not (sp.material_override is ShaderMaterial):
		if depth_shader == null:
			depth_shader = Shader.new()
			depth_shader.code = DEPTH_SHADER
		var material := ShaderMaterial.new()
		material.shader = depth_shader
		material.set_shader_parameter("tex",sp.texture)
		material.set_shader_parameter("bill",sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
		sp.material_override = material
		shadow_twin(sp,true)
	var m := sp.material_override as ShaderMaterial
	m.set_shader_parameter("reach",half*SCALE)
	m.set_shader_parameter("blend",SIDE_BLEND*half*SCALE)
	m.set_shader_parameter("side0",float(rule.side))
	m.set_shader_parameter("wall",world_to_scene(rule.wall))
	m.set_shader_parameter("normal",rule.normal)

# Every card casts a shadow. A fixed card casts its own, but the shadow pass runs the same shader, and a
# shifted depth would move the shadow on the ground, so a fixed card the depth rule shifts casts none and a
# twin of it, drawn plain and in the shadow pass only, casts its own. A Y-axis billboard has no plane of its
# own to cast with (it turns to whatever looks at it, and the sun is not the player's camera), so it casts
# from a twin, a plain card turned to face the sun: its silhouette as the sun sees it, the same for every
# camera, shifted or not. (Before the twin only the fixed cards cast a shadow, and every tree was one: a
# tree that stands up must not lose its shadow for it.) `shifted`: the depth rule has put sp's own shader on.
# Except what the original draws without a shadow (SHADOWLESS): it casts none.
func shadow_twin(sp: Sprite3D, shifted: bool) -> void:
	var upright := sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y
	var twin := sp.get_node_or_null("ShadowTwin") as Sprite3D
	if is_instance_valid(sp.get_parent()) and str(sp.get_parent().get_meta("model_key","")) in SHADOWLESS:
		if twin != null:
			sp.remove_child(twin)
			twin.queue_free()
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	if not upright and not shifted:
		if twin != null:
			sp.remove_child(twin)
			twin.queue_free()
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return
	if twin == null:
		twin = Sprite3D.new()
		twin.name = "ShadowTwin"
		twin.shaded = false
		twin.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		twin.texture_filter = sp.texture_filter
		twin.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sp.add_child(twin)
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	twin.rotation.y = sun_yaw(sp) if upright else 0.0
	sync_twin(sp)

# The yaw, in sp's own frame, that turns a card's face (+z) to the sun: the horizontal direction toward the
# scene's light (a directional light shines along its -z, so +z points at it).
func sun_yaw(sp: Sprite3D) -> float:
	var toward := Vector3.BACK
	if light != null and is_instance_valid(light) and light.is_inside_tree(): toward = light.global_transform.basis.z
	var yaw := atan2(toward.x,toward.z) if Vector2(toward.x,toward.z).length() > 0.001 else 0.0
	return yaw-(sp.global_rotation.y if sp.is_inside_tree() else 0.0)

func sync_twin(sp: Sprite3D) -> void:
	var twin := sp.get_node_or_null("ShadowTwin") as Sprite3D
	if twin == null: return
	twin.texture = sp.texture
	twin.pixel_size = sp.pixel_size
	twin.centered = sp.centered
	twin.offset = sp.offset
	twin.region_enabled = sp.region_enabled
	twin.region_rect = sp.region_rect

var feet: Dictionary = {} # sprite path -> its foot: the centre of its lowest drawn row, bottom edge (px)
func sprite_foot(path: String) -> Vector2:
	if feet.has(path): return feet[path]
	var result := Vector2(0,-1)
	var img := sprite_image(path)
	if img != null:
		for y in range(img.get_height()-1,-1,-1):
			var xs := 0.0
			var count := 0
			for x in img.get_width():
				var c := img.get_pixel(x,y)
				if c.a > 0.5 and c.r+c.g+c.b >= 0.04:
					xs += x+0.5
					count += 1
			if count > 0:
				result = Vector2(xs/count,y+1.0)
				break
	feet[path] = result
	return result
