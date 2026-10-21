# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Static vision-0 editor state. Startup scripts/progression deliberately skipped.
# Reads ACTUAL MultiMesh transforms; the Python oracle independently reads
# raw source masks and atlas PNGs. Movement is queried through production _blocked.
const HOST = preload("res://../tests/collision_survey_host.gd")
var report_path := ""
var presentation_path := "res://scripts/fp_world.gd"
var selected_screens := []
var failures: Array = []
var control := true # --control=0: run an older presentation whose fixed geometry differs (the G1 red run)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--presentation="): presentation_path = arg.trim_prefix("--presentation=")
		if arg == "--control=0": control = false
		if arg.begins_with("--screens="):
			for n in arg.trim_prefix("--screens=").split(","): selected_screens.append(int(n))
	_run.call_deferred()

func rects(game, name := "SolidTerrain") -> Array:
	var result := []
	var node: MultiMeshInstance3D = game.scene_root.get_node_or_null(name)
	if node == null: return result
	var multi := node.multimesh
	var box := multi.mesh.get_aabb()
	for i in multi.instance_count:
		var t := multi.get_instance_transform(i)
		var a := t*box.position
		var b := t*(box.position+box.size)
		var x := roundi(a.x/0.025+320.0)
		var y := roundi(a.z/0.025+200.0)
		result.append([x,y,roundi((b.x-a.x)/0.025),roundi((b.z-a.z)/0.025)])
	return result

func clear_scene(game) -> void:
	for node in game.scene_root.get_children():
		game.scene_root.remove_child(node)
		node.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain census requires a real software GL renderer; Dummy loses MultiMesh transforms")
		quit(2)
		return
	var game = HOST.new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	game.scene_root = Node3D.new()
	root.add_child(game.scene_root)
	var presentation = load(presentation_path).new()
	presentation.setup(game)
	var rows := []
	# A current-screen floor build must not accidentally read stale neighbour
	# predictions from the real FPS startup history; this static census has none.
	var screens: Array = game.world.screens.keys()
	screens.sort_custom(func(a,b): return int(a)<int(b))
	for key in screens:
		var n := int(key)
		if not selected_screens.is_empty() and n not in selected_screens: continue
		game.load_map(n,false)
		presentation.interior = bool(game.world.screens[key].indoor)
		clear_scene(game)
		presentation.add_terrain_walls(game.world.screens[key])
		var actual := rects(game)
		# Fixed control: 99's rock-band rim is the 3px hard line at rows 132-134 (a centre sample never sees it).
		if control and n == 99 and ([20,132,10,3] not in actual or [610,132,10,3] not in actual):
			push_error("Terrain census instrument failed fixed screen99 geometry control")
			quit(2)
			return
		var covered := {}
		var cells := {}
		var violations := []
		for r in actual:
			cells[Vector2i((int(r[0])-20)/10,int(r[1])/10)] = true
			for y in range(int(r[1]),int(r[1]+r[3])):
				for x in range(int(r[0]),int(r[0]+r[2])):
					covered[Vector2i(x,y)] = true
					if not game._blocked(Vector2(x+0.5,y+0.5),1): violations.append([x,y])
		var physics_covered := {}
		var body: StaticBody3D = game.scene_root.get_node_or_null("TerrainCollision")
		if body != null:
			for shape in body.get_children():
				var low: Vector3 = shape.position-shape.shape.size*0.5
				var high: Vector3 = shape.position+shape.shape.size*0.5
				for y in range(roundi(low.z/0.025+200),roundi(high.z/0.025+200)):
					for x in range(roundi(low.x/0.025+320),roundi(high.x/0.025+320)):
						physics_covered[Vector2i(x,y)] = true
		if physics_covered != covered: failures.append("Visible/physics terrain coverage differs on screen%d" % n)
		var selected := []
		for c in cells: selected.append([25+c.x*10,5+c.y*10])
		selected.sort_custom(func(a,b): return a[1]<b[1] or (a[1]==b[1] and a[0]<b[0]))
		# Adversarial composited-ground image: changing presentation RGB cannot
		# change terrain. Seed all cache entries the old code could read.
		var texture: Texture2D = presentation.ground_texture(n) if presentation.interior else null
		var saved_cache: Dictionary = presentation.terrain_cache.duplicate()
		var perturb_equal := true
		if texture != null:
			var poison := Image.create(600,400,false,Image.FORMAT_RGB8)
			poison.fill(Color(0,1,0))
			for cache_key in presentation.terrain_cache: presentation.terrain_cache[cache_key] = ImageTexture.create_from_image(poison)
			clear_scene(game)
			presentation.add_terrain_walls(game.world.screens[key])
			perturb_equal = JSON.stringify(rects(game)) == JSON.stringify(actual)
			presentation.terrain_cache = saved_cache
		var without := []
		for y in range(5,400,10):
			for x in range(25,620,10):
				var p := Vector2(x,y)
				if covered.has(Vector2i(x,y)) or not game._blocked(p,1): continue
				var owners := []
				var hard: int = game._tile_hardness(p)
				if hard != 0:
					var tile: Dictionary = game.world.screens[key].tiles[int(y/50)*12+int((x-20)/50)]
					owners.append({"kind":"tile","hardness":hard,"tile_id":int(tile.tile),"custom_mask":int(tile.hard)})
				var id: int = game._blocking_sprite(p,1)
				if id != 0:
					var e: Dictionary = game.entities[id]
					owners.append({"kind":"sprite_or_clearance","editor":int(e.get("editor_num",0)),"path":presentation.frame_path(e),"model_key":presentation.model_key(e),"source_type":int(e.get("type",1)),"nodraw":int(e.get("nodraw",0)),"disabled":int(e.get("disabled",0)),"inside_hardbox":game._hard_rect(e).has_point(p)})
				if game._footprint_blocked(p): owners.append({"kind":"fitted_footprint_or_clearance"})
				if game._additional_structure_blocked(p,Vector2.INF): owners.append({"kind":"additional_fitted_structure"})
				without.append({"cell":[x,y],"owners":owners})
		rows.append({"screen":n,"indoor":presentation.interior,"rects":actual,"fill_rects":rects(game,"SolidTerrainFill"),"cells":selected,"sprite_perturbation_equal":perturb_equal,"native_coverage_violations":violations,"blocked_cells_without_terrain":without})
		print("TERRAIN SCREEN ",n," rects=",actual.size()," native_free_pixels=",violations.size())
	var output := {"schema":"terrain-columns-1","presentation":presentation_path,"setup":"Static editor vision0; scripts/progression skipped. Full emitted pixel footprints queried natively; uncovered movement samples at 10px centres are conservatively listed, not certified invisible.","screens":rows,"failures":failures}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	game.scene_root.free()
	# Survey host never enters the tree, so invoke its normal cycle cleanup.
	# Also release the renderer helpers that retain their renderer owner.
	presentation.rails.world = null
	presentation.rails.ns_rails.rails = null
	presentation.castle_doors.fw = null
	presentation.solids.world = null
	presentation.ceilings.world = null
	presentation.fences.world = null
	game.fp_world = presentation
	game._exit_tree()
	game.free()
	print("TERRAIN CENSUS DONE ",rows.size())
	quit()
