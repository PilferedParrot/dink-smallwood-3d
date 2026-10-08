extends SceneTree
# The house interior stands solid (docs/DIRECTION.md, "The interior stands solid"). Headless: loads Dink's house (screen 1) as the
# game does, arriving from the outdoors, and prints one "INT key value..." line per fact tests/test_fps_interior.py checks:
#   sky       the environment keeps no sky inside (the outdoor sky was drawn past the corridor's end with a flat background set)
#   wall      each wall node: built from its sprite (interior_solid), its height in metres
#   door      the exit door's width, its height, its place
#   table     the round table's footprint radius and its top's height; its legs
#   bed       each bed's width and height
#   hearth    the hearth's height and whether a recess and a stack stand in it
#   fire      the fire's plane depth (m) and whether it is a fixed card; hearthz the hearth's hotspot depth (m)
#   pie       the pie's height above the floor, and the table top's
# Verdict: written 2026-10-07 (Sonnet 5.5 subagent).
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025

func _initialize() -> void:
	_run.call_deferred()

func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: meshes.append(node)
	for m in meshes:
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(1, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	var fw = game.fp_world
	var env: Environment = fw.environment
	print("INT sky ", env.sky == null, " ", env.background_mode)
	for id in game.entities.keys():
		if id == 1: continue
		var e: Dictionary = game.entities[id]
		var node: Node3D = game.visuals.get(id)
		if node == null: continue
		var key := str(node.get_meta("model_key", ""))
		var solid := bool(node.get_meta("interior_solid", false))
		var box := _aabb(node)
		if key == "wall":
			print("INT wall ", id, " ", solid, " ", snappedf(box.size.y, 0.001), " ", node.visible)
		elif key == "table" and int(e.get("pseq", 0)) == 87:
			print("INT table ", solid, " ", snappedf(box.size.x, 0.001), " ", snappedf(box.size.y, 0.001), " ", snappedf(box.size.z, 0.001))
		elif key == "bed":
			print("INT bed ", solid, " ", snappedf(box.size.x, 0.001), " ", snappedf(box.size.y, 0.001), " ", snappedf(box.size.z, 0.001))
		elif key == "fireplace":
			var surfaces := 0
			for m in node.find_children("*", "MeshInstance3D", true, false): surfaces += (m as MeshInstance3D).mesh.get_surface_count()
			print("INT hearthz ", snappedf(node.global_position.z, 0.001))
			print("INT hearth ", solid, " ", snappedf(box.size.y, 0.001), " ", snappedf(box.size.x, 0.001), " ", snappedf(box.size.z, 0.001))
		elif int(e.get("pseq", e.get("seq", 0))) == 86:
			# the fire (fire-01, drawn over the hearth's firebox): where its plane stands, and whether it still turns to the camera
			var model := node.get_node_or_null("Model")
			var fixed: bool = model is Sprite3D and (model as Sprite3D).billboard == BaseMaterial3D.BILLBOARD_DISABLED
			print("INT fire ", snappedf(node.global_position.z, 0.001), " ", fixed)
		elif int(e.get("pseq", 0)) == 421 and int(e.get("pframe", 0)) == 11:
			print("INT pie ", snappedf(node.position.y, 0.001))
	var top := 0.0
	var has_solids: bool = "solids" in fw # the 0.3.0 code has none: every fact below reads as it was
	for e in fw.drawn_sprites(1, 0):
		if has_solids and int(e.get("pseq", e.get("seq", 0))) == 87 and int(e.get("pframe", e.get("frame", 0))) == 9:
			var fit: Dictionary = fw.solids.fit_of(fw.frame_path(e))
			top = float(fit.top.height) * SCALE
	print("INT tabletop ", snappedf(top, 0.001))
	var door: Node3D = game.scene_root.get_node_or_null("ExitDoor")
	if door != null:
		var b: AABB = _aabb(door)
		print("INT door ", snappedf(b.size.x, 0.001), " ", snappedf(b.size.y, 0.001), " ", snappedf(b.position.z, 0.001))
	else:
		print("INT door none")
	print("INT room ", snappedf(fw.solids.room_height(1) * SCALE, 0.001) if has_solids else 0.0)
	game.queue_free()
	await process_frame
	print("FPS INTERIOR DONE")
	quit(0)
