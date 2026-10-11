extends SceneTree
# Native static tree ownership for real 5x5 outdoor scenes; no render/scripts.
const GAME = preload("res://scripts/fps_game.gd")
const VM = preload("res://scripts/dink_vm.gd")
const FP = preload("res://scripts/fp_world.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
	if out_path.is_empty():
		push_error("Pass --out=<json path>")
		quit(2)
		return
	var game = GAME.new()
	game.test_mode = true
	game.world = game._read_json("res://data/world.json")
	var doc: Dictionary = game._read_json("res://data/sequences.json")
	game.sequences = doc.get("sequences",doc)
	game.original_sequences = game.sequences.duplicate(true)
	game.footprints = game._read_json("res://data/footprints.json").get("screens",{})
	game.vm = VM.new(game)
	game.vm.globals["vision"] = 0
	game.fp_world = FP.new()
	game.fp_world.setup(game)
	var fw = game.fp_world
	fw.interior = false
	var placements: Array = []
	for sn in game.world.screens:
		var screen := int(sn)
		if bool(game.world.screens[sn].get("indoor",false)): continue
		var sprites: Array = game.world.screens[sn].get("sprites",[])
		for list_index in sprites.size():
			var src: Dictionary = sprites[list_index]
			if int(src.get("seq",0)) != 32 or int(src.get("frame",0)) not in [1,2,3,4,5,6,7]: continue
			if int(src.get("type",1)) != 1 or int(src.get("vision",0)) != 0: continue
			var e: Dictionary = game.editor_entity(screen,src,true,0)
			if e.is_empty() or not fw.static_scenery(e): continue
			var frame := int(e.get("pframe",1))
			var path: String = fw.frame_path(e)
			var d: Dictionary = game._frame(32,frame)
			var foot: Vector2 = fw.sprite_foot(path)
			if foot.y < 0.0: continue
			var root: Vector2 = fw.screen_origin(screen) + Vector2(float(e.x),float(e.y)) \
				+ (foot-Vector2(float(d.get("dx",0)),float(d.get("dy",0))))
			var parts: Array = fw.seam_parts(e,screen)
			if parts.size() != 1 or int(parts[0][0]) >= 0:
				push_error("Expected one whole tree art part: %d:%d" % [screen,int(src.get("index",-1))])
				quit(2)
				return
			var hb: Rect2 = game._hard_rect(e)
			placements.append({"screen":screen,"list_index":list_index,
				"editor_index":int(src.get("index",-1)),"source_xy":[float(e.x),float(e.y)],
				"frame":frame,"path":path,"model_key":fw.model_key(e),
				"foot_art_px":[foot.x,foot.y],"global_foot_xy":[root.x,root.y],
				"source_hard":int(e.get("hard",1)),"source_hardbox_xyxy":
				[hb.position.x,hb.position.y,hb.end.x,hb.end.y],
				"fullworld_shown":bool(parts[0][3]),"scene5x5_shown_centers":[]})
	var centers := 0
	for center_text in game.world.screens:
		var center := int(center_text)
		if bool(game.world.screens[center_text].get("indoor",false)): continue
		centers += 1
		var col := (center-1)%32
		var block: Dictionary = {center:true}
		for dz in range(-2,3):
			for dx in range(-2,3):
				if dx == 0 and dz == 0: continue
				if col+dx < 0 or col+dx >= 32: continue
				var neighbor := center+dx+32*dz
				if game.world.screens.has(str(neighbor)) and not fw.is_inside(neighbor): block[neighbor] = true
		fw.scene_block = block
		for item in placements:
			if not block.has(int(item.screen)): continue
			var raw: Dictionary = game.world.screens[str(item.screen)].sprites[int(item.list_index)]
			var e: Dictionary = game.editor_entity(int(item.screen),raw,true,0)
			var flags: Array = fw.seam_parts(e,int(item.screen))
			if flags.size() == 1 and bool(flags[0][3]):
				item.scene5x5_shown_centers.append(center)
	fw.scene_block.clear()
	var counts: Dictionary = {}
	for item in placements:
		var key := "%s:%d" % [item.model_key,int(item.frame)]
		if not counts.has(key): counts[key] = {"source_placements":0,"shown_union":0,"fullworld_shown":0}
		counts[key].source_placements += 1
		if bool(item.fullworld_shown): counts[key].fullworld_shown += 1
		if not item.scene5x5_shown_centers.is_empty(): counts[key].shown_union += 1
	var out := {"schema":"rc5-native-existing-standing-tree-inventory-1",
		"scope":"outdoor static type1 vision0 seq32 frames1-7, native editor_entity/model_key/seam_parts",
		"outdoor_scene_centers":centers,"placements":placements,"counts":counts}
	var file := FileAccess.open(out_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(out,"\t"))
	print("EXISTING TREE INVENTORY outdoor=",centers," source=",placements.size()," counts=",counts)
	fw.art_cache.clear()
	fw.stack_cache.clear()
	fw.clean_cache.clear()
	fw.host = null
	game.textures.clear()
	game.fp_world = null
	await process_frame
	quit(0)
