extends SceneTree

const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	var world = game.fp_world
	var player: Dictionary = game.entities[1]
	var visual: Node3D = game.visuals[1]
	var shadow := visual.get_node_or_null("Model") as Sprite3D
	check(shadow != null,"Dink has a source-sprite shadow card")
	if shadow == null:
		quit(1)
		return
	check(shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"Dink's card draws only in the shadow pass")
	check(shadow.billboard == BaseMaterial3D.BILLBOARD_DISABLED,"Dink's shadow card has a physical fixed plane")
	check(not shadow.no_depth_test and visual.get_meta("billboard",false),"Dink's card follows the allowed scene sprite path")
	await game._new_game()
	game.vm.cancel_all(); game.ui.close_menu()
	player = game.entities[1]; visual = game.visuals[1]; shadow = visual.get_node("Model")
	# All actual starter held meshes, plus the source-authored feed item, must
	# remain color-pass tools without casting the disembodied weapon shadow.
	game.items.append({"script":"item-pig","name":"Pig Feed","seq":437,"frame":1})
	for i in game.items.size():
		game.vm.globals["cur_weapon"] = i+1
		game._fps_update_viewmodel(0.0)
		check(_no_shadows(game.fps_viewmodel),"Held %s casts no shadow" % game.items[i].name)
		check(_no_shadows(game.fps_hand),"Held support hand casts no shadow")

	player["seq"] = 12 # Original south idle; with the sun due south, its south frame faces the light.
	player["frame"] = 1
	player["dir"] = 2
	player["x"] = 410.0
	player["y"] = 260.0
	player["size"] = 125
	world.light.rotation_degrees = Vector3(-48,0,0)
	game._update_visual(1)
	check(visual.position.is_equal_approx(world.point(410.0,260.0)),"Shadow follows Dink's source position")
	check(is_equal_approx(shadow.pixel_size,world.SCALE*1.25),"Shadow follows Dink's source size")
	check(str(shadow.get_meta("path","")) == str(game._frame(12,1).get("path","")),"Sun south sees Dink's south idle frame")
	check(shadow.texture == world.clean_texture(str(game._frame(12,1).get("path",""))),"Shadow uses Dink's cleaned original art")
	_check_sun(shadow,world.light,"south")

	# Rotate the sun, leaving Dink, his animation and the camera unchanged. Its view must now see his north side.
	world.light.rotation_degrees = Vector3(-48,180,0)
	game._update_visual(1)
	check(str(shadow.get_meta("path","")) == str(game._frame(18,1).get("path","")),"Sun north selects Dink's north idle frame, independent of the eye camera")
	_check_sun(shadow,world.light,"north")
	game.camera.global_position += Vector3(4,0,5)
	game._update_visual(1)
	check(str(shadow.get_meta("path","")) == str(game._frame(18,1).get("path","")),"Moving the eye camera does not change Dink's shadow frame")

	player["seq"] = 72 # Source walking animation, same source-facing direction.
	player["frame"] = 2
	player["x"] = 380.0
	player["y"] = 245.0
	player["size"] = 80
	world.light.rotation_degrees = Vector3(-48,0,0)
	game._update_visual(1)
	check(str(shadow.get_meta("path","")) == str(game._frame(72,2).get("path","")),"Shadow advances to Dink's current walking animation frame")
	check(visual.position.is_equal_approx(world.point(380.0,245.0)),"Shadow follows Dink after movement")
	check(is_equal_approx(shadow.pixel_size,world.SCALE*0.8),"Shadow updates after Dink changes size")
	player["nodraw"] = 1
	game._update_visual(1)
	check(not shadow.visible,"Hidden Dink casts no shadow")

	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS PLAYER SHADOW PASS")
	else: print("FPS PLAYER SHADOW FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)

func _no_shadows(node: Node) -> bool:
	if node == null: return false
	if node is GeometryInstance3D and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
	for child in node.get_children():
		if not _no_shadows(child): return false
	return true

func _check_sun(shadow: Sprite3D, light: DirectionalLight3D, label: String) -> void:
	var toward: Vector3 = light.global_transform.basis.z
	var face: Vector3 = shadow.global_transform.basis.z
	var angle := Vector2(toward.x,toward.z).normalized().angle_to(Vector2(face.x,face.z).normalized())
	check(absf(angle) < 0.001,"Dink's fixed shadow card faces the %s sun" % label)
