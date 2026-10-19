# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Static unlocked vision-0 census, NOT earned progression or arbitrary DinkC states.
# Original: FreeDink109.6 freedink.cpp:132-242; live_screen.cpp:132-169,216-239;
# game_engine.cpp:477-503,570-577. Indoor never participates in eligibility.
const HOST = preload("res://../tests/collision_survey_host.gd")
var game
var failures: Array = []
var report_path := ""
var original_masks := {}
var presentation
var wall_cache := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

# Deliberately independent of _tile_hardness and all fitted replacement hooks.
func original_hard(n: int, p: Vector2) -> bool:
	if p.x < 20 or p.x >= 620 or p.y < 0 or p.y >= 400: return false
	var screen: Dictionary = game.world.screens[str(n)]
	var tile: Dictionary = screen.tiles[int(p.y)/50*12+int(p.x-20)/50]
	var hard: Dictionary = game.world.hardness
	var mask := int(tile.hard)
	if mask == 0: mask = int(hard.tile_defaults[int(tile.tile)])
	if mask > 0:
		if not original_masks.has(mask):
			var pixels := PackedByteArray()
			for run in hard.masks_rle[mask]:
				for _i in int(run[1]): pixels.append(int(run[0]))
			original_masks[mask] = pixels
		if int(original_masks[mask][(int(p.x-20)%50)*51+int(p.y)%50]) != 0: return true
	for e in screen.sprites:
		if int(e.get("vision",0)) != 0 or int(e.get("hard",1)) != 0: continue
		var frame: Dictionary = game._frame(int(e.seq),int(e.frame))
		var box: Array = frame.get("hardbox",[0,0,0,0])
		if p.x >= float(e.x)+float(box[0]) and p.x < float(e.x)+float(box[2]) \
				and p.y >= float(e.y)+float(box[1]) and p.y < float(e.y)+float(box[3]): return true
	return false

# Exact fitted wall prisms, plus the fallback plaster wall's main box at
# player height (fp_world.gd make_entity/instance_model), plus native10px
# terrain boundary cells. No rendering claim about doors, other objects,
# arbitrary DinkC states or selected vision layers.
func walls(n: int) -> Array:
	if wall_cache.has(n): return wall_cache[n]
	var previous: int = game.current_screen
	var was_interior: bool = presentation.interior
	game.current_screen = n
	presentation.interior = bool(game.world.screens[str(n)].indoor)
	var out: Array = []
	for source in game.world.screens[str(n)].sprites:
		var e: Dictionary = game.editor_entity(n,source)
		if e.is_empty() or presentation.model_key(e) != "wall": continue
		var rect: Rect2 = presentation.hard_rect(e)
		var kind := "fallback plaster box"
		if bool(game.world.screens[str(n)].indoor) and presentation.solids.handles(e):
			var fit: Dictionary = presentation.solids.fit_of(presentation.frame_path(e))
			if str(fit.get("kind","")) == "wall":
				rect = presentation.solids.wall_prism(e,fit,n).rect
				kind = "fitted wall prism"
		else:
			# update_visual hides type2 unless fitted add_entity marks hard_wall.
			if int(e.get("type",1)) == 2: continue
			var extent := Vector2(maxf(12.0,rect.size.x),maxf(12.0,rect.size.y))/1.02
			rect = Rect2(rect.get_center()-extent/2.0,extent)
		out.append({"rect":rect,"editor_index":int(source.index),"kind":kind})
	if bool(game.world.screens[str(n)].indoor):
		# Production add_terrain_walls draws these cells from the native tile
		# collision and composited ground colors. Only boundary cells can
		# overlap a screen-edge source point or the original arrival point.
		var saved_sprites: Dictionary = game.footprint_sprites
		var saved_polys: Array = game.screen_footprints
		var saved_tiles: Dictionary = game.footprint_tiles
		game.footprint_sprites = {}; game.screen_footprints = []; game.footprint_tiles = {}
		game._load_footprints(n)
		var terrain: Image = presentation.ground_texture(n).get_image()
		for row in 40:
			for col in 60:
				if row not in [0,39] and col not in [0,59]: continue
				var x := 25+col*10
				var y := 5+row*10
				if not game._tile_blocked(Vector2(x,y)): continue
				var color := terrain.get_pixel(x-20,y)
				if color.b > color.r*1.1 and color.b > color.g*0.85: continue
				if color.g > color.r*1.12: continue
				out.append({"rect":Rect2(x-5,y-5,10,10),"editor_index":-1-row*60-col,"kind":"terrain boundary cell"})
		game.footprint_sprites = saved_sprites; game.screen_footprints = saved_polys; game.footprint_tiles = saved_tiles
	game.current_screen = previous
	presentation.interior = was_interior
	wall_cache[n] = out
	return out

func wall_owners(n: int, p: Vector2) -> Array:
	var out: Array = []
	for wall in walls(n):
		var rect: Rect2 = wall.rect
		if rect.has_point(p): out.append(wall.editor_index)
	return out

func points(direction: String, along: int) -> Array:
	match direction:
		"west": return [Vector2(20,along),Vector2(19,along)]
		"east": return [Vector2(619,along),Vector2(620,along)]
		"north": return [Vector2(along,0),Vector2(along,-1)]
		_: return [Vector2(along,399),Vector2(along,400)]

func collision_owners(n: int, p: Vector2, from: Vector2 = Vector2.INF) -> Array:
	game.load_map(n,false)
	var out: Array = []
	var sprite: int = game._blocking_sprite(p,1,from)
	if sprite != 0:
		var e: Dictionary = game.entities[sprite]
		out.append({"kind":"sprite_hardbox_and_clearance","editor_index":int(e.get("editor_num",0)),"path":presentation.frame_path(e)})
	if game._footprint_blocked(p,from): out.append({"kind":"fitted_footprint_and_clearance"})
	var hardness: int = game._tile_hardness(p)
	if hardness != 0: out.append({"kind":"tile_hardness","value":hardness})
	if game.stone_walls.blocked(p,from,n): out.append({"kind":"fitted_stone_wall"})
	if game.fir_collision.blocked(p,from,n): out.append({"kind":"complete_fir_hardbox"})
	return out

func edge(source: int, target: int, direction: String, kind: String) -> Dictionary:
	game.load_map(source,false)
	var record := {"source":source,"target":target,"direction":direction,"kind":kind,
		"samples":0,"original_open":0,"fps_open":0,"both_open":0,
		"original_open_fps_refused":0,"fps_open_original_hard":0,
		"fps_source_veto":0,"fps_incoming_veto":0,
		"presentation_source_wall_cells":0,"presentation_arrival_wall_cells":0,
		"presentation_wall_examples":[],"veto_examples":[],"first_original_open":[],"first_fps_open":[]}
	var horizontal := direction in ["west","east"]
	for along in range(0 if horizontal else 20,400 if horizontal else 620):
		var pp := points(direction,along)
		var p: Vector2 = pp[0]
		var q: Vector2 = pp[1]
		var original := not original_hard(source,p)
		var source_veto: bool = game._blocked(p,1)
		var incoming_veto: bool = game._blocked(q,1,p)
		var fps := not source_veto and not incoming_veto
		record.samples += 1
		if original:
			var source_owners := wall_owners(source,p)
			var landing := p
			match direction:
				"west": landing.x = 619
				"east": landing.x = 20
				"north": landing.y = 399
				"south": landing.y = 0
			var target_owners := wall_owners(target,landing)
			if not source_owners.is_empty(): record.presentation_source_wall_cells += 1
			if not target_owners.is_empty(): record.presentation_arrival_wall_cells += 1
			if (not source_owners.is_empty() or not target_owners.is_empty()) and record.presentation_wall_examples.size() < 3:
				record.presentation_wall_examples.append({"source_point":[p.x,p.y],"original_arrival":[landing.x,landing.y],"source_wall_owners":source_owners,"target_wall_owners":target_owners,"fps_allows":fps})
			record.original_open += 1
			if record.first_original_open.is_empty(): record.first_original_open = [p.x,p.y]
		if fps:
			record.fps_open += 1
			if record.first_fps_open.is_empty(): record.first_fps_open = [p.x,p.y]
		if original and fps: record.both_open += 1
		if original and not fps:
			var veto_kind := "source" if source_veto else "incoming"
			if not record.veto_examples.any(func(item): return item.kind == veto_kind):
				record.veto_examples.append({"kind":veto_kind,"source_point":[p.x,p.y],"next_point":[q.x,q.y]})
			record.original_open_fps_refused += 1
			if source_veto: record.fps_source_veto += 1
			else: record.fps_incoming_veto += 1
		if fps and not original: record.fps_open_original_hard += 1
	# A separate all-free fixture isolates edge eligibility from physical data.
	# This catches the blanket flag guard even for naturally closed room walls.
	var saved: Dictionary = game.world.screens[str(target)]
	var clear := saved.duplicate(true)
	clear.sprites = []; clear.tiles = []
	for _i in 96: clear.tiles.append({"tile":0,"hard":0})
	game.world.screens[str(target)] = clear
	var fp = game.footprints.get(str(target),null)
	var walls: Dictionary = game.stone_walls.data.get("screens",{})
	var wall_fit = walls.get(str(target),null)
	walls.erase(str(target))
	game.stone_walls._floor.erase(target); game.stone_walls._clear.erase(target)
	var firs = game.fir_collision._rects.get(target,null)
	game.fir_collision._rects.erase(target)
	game.footprints.erase(str(target))
	game.survey_states.erase(target)
	var middle := points(direction,200 if horizontal else 320)
	# Tile0 may have default hardness: override mask defaults only inside fixture.
	var defaults: Array = game.world.hardness.tile_defaults.duplicate()
	game.world.hardness.tile_defaults[0] = 0
	record.metadata_original_allowed = true
	record.metadata_fps_allowed = not game._blocked(middle[1],1,middle[0])
	check(record.metadata_fps_allowed,"metadata eligibility %d->%d %s" % [source,target,kind])
	game.world.hardness.tile_defaults = defaults
	game.world.screens[str(target)] = saved
	if fp != null: game.footprints[str(target)] = fp
	if wall_fit != null: walls[str(target)] = wall_fit
	game.stone_walls._floor.erase(target); game.stone_walls._clear.erase(target)
	if firs != null: game.fir_collision._rects[target] = firs
	game.survey_states.erase(target)
	for example in record.veto_examples:
		var p := Vector2(float(example.source_point[0]),float(example.source_point[1]))
		var q := Vector2(float(example.next_point[0]),float(example.next_point[1]))
		if str(example.kind) == "source": example.owners = collision_owners(source,p)
		elif not record.metadata_fps_allowed: example.owners = [{"kind":"indoor_metadata_gate_on_base"}]
		else:
			game.current_screen = source
			var destination: Dictionary = game._edge_destination(q)
			var at: Vector2 = destination.position
			example.owners = collision_owners(target,at,p+(at-q))
		check(not example.owners.is_empty(),"every sampled veto has a native collision owner %d->%d" % [source,target])
	game.load_map(source,false)
	return record

func _run() -> void:
	game = HOST.new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	presentation = preload("res://scripts/fp_world.gd").new()
	presentation.setup(game)
	var edges: Array = []
	var counts := {"indoor_indoor":0,"mixed":0}
	for key in game.world.screens:
		var source := int(key)
		var column := (source-1)%32
		for d in [[-1,"west"],[1,"east"],[-32,"north"],[32,"south"]]:
			var target: int = source+int(d[0])
			if not game.world.screens.has(str(target)): continue
			if (int(d[0]) == -1 and column == 0) or (int(d[0]) == 1 and column == 31): continue
			var a := bool(game.world.screens[key].indoor)
			var b := bool(game.world.screens[str(target)].indoor)
			if not a and not b: continue
			var kind := "indoor_indoor" if a and b else "mixed"
			counts[kind] += 1
			edges.append(edge(source,target,str(d[1]),kind))
	check(counts.indoor_indoor == 230,"230 directed indoor pairs enumerated")
	# Isolated negative controls use the same native boundary path.
	game.load_map(131,false)
	game.locked = true
	var locked: bool = game._blocked(Vector2(290,-1),1,Vector2(290,0))
	check(locked,"locked screen rejects otherwise open cave edge")
	game.locked = false
	var saved99 = game.world.screens["99"]
	game.world.screens.erase("99")
	var missing: bool = game._blocked(Vector2(290,-1),1,Vector2(290,0))
	check(missing,"missing link rejects cave edge")
	game.world.screens["99"] = saved99
	game.load_map(33,false)
	var row_wrap: bool = game._blocked(Vector2(19,200),1,Vector2(20,200))
	check(row_wrap,"intentional horizontal row-wrap protection remains")
	# Record raw-hard boundaries; redirect semantics have a separate input test.
	var hard_cases := 0
	for e in edges:
		if int(e.original_open) == 0:
			hard_cases += 1
			# A raw hard warp is a redirect, not an ordinary solid. Its real
			# input path is tested separately (34's door must warp to498).
	check(hard_cases > 0,"raw-hard boundaries are represented in census")
	game.load_map(34,false)
	var hard_source := Vector2(50,399)
	var original_wall := original_hard(34,hard_source)
	var fps_wall: bool = game._blocked(hard_source,1)
	check(original_wall and fps_wall,"plain34 south wall stays hard in both engines")
	var result := {"setup":"Static unlocked vision0 editor layer, scripts/persistence skipped. Metadata eligibility checked independently with labelled empty target fixtures. Physical original rules use raw source hardness; FPS uses retained fitted-source and incoming-solid protection. No claim about arbitrary script states.",
		"presentation_owner_key":"positive: editor wall index; negative: terrain cell -(1+row*60+column); static geometry overlap, not rendered certification",
		"counts":counts,"edges":edges,"negative_controls":{"locked":locked,"missing_link":missing,"row_wrap":row_wrap,"hard_source_point":original_wall and fps_wall,"original_fully_hard_edges":hard_cases},"failures":failures}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"  "))
	print("INDOOR EDGES %s failures=%d" % [str(counts),failures.size()])
	game.vm.cancel_all()
	# setup() helpers retain their world; break those fixture-only cycles.
	game.stone_walls.fp_world = null
	for member in ["buildings","rails","castle_doors","solids","fences","props","source_firs","source_interaction_body","mounted_posters","stone_walls"]:
		presentation.set(member,null)
	presentation = null
	game.free()
	quit(0 if failures.is_empty() else 1)
