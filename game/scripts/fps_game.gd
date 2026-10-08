# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Campaign-compatible first-person presentation.  Simulation, DinkC, audio and
# save format remain in game.gd; this class only translates controls/rendering.
extends "res://scripts/game.gd"

const SCALE: float = preload("res://scripts/fp_world.gd").SCALE # metres per source pixel
const EYE_HEIGHT := 1.65
const PROJECTILE := preload("res://scripts/fps_projectile.gd")

var fp_world
var fps_yaw := 0.0
var fps_pitch := -0.08
var fps_vertical_velocity := 0.0
var fps_jump_height := 0.0
var fps_fire_held := false
var fps_magic_held := false
var fps_recoil := 0.0
var fps_viewmodel: Node3D
var fps_viewmodel_key := ""
var fps_hand: Node3D
var fps_feed_use := 0.0
var fps_hit_timer := 0.0
# A dialogue camera may look from a nearby clear spot, but it never moves Dink.
# These are reset as soon as the individual line closes.
var fps_dialogue_camera_active := false
var fps_dialogue_camera_position := Vector3.ZERO
var fps_dialogue_restore_yaw := 0.0
var fps_dialogue_restore_pitch := 0.0
var fps_dialogue_subject := 0

func _ready() -> void:
	# The renderer must exist before base _ready reaches load_map(), whose virtual
	# visual hooks are dispatched to this subclass.
	var renderer_script := load("res://scripts/fp_world.gd")
	if renderer_script != null:
		fp_world = renderer_script.new()
		fp_world.setup(self)
	super._ready()
	_restore_fps_camera()
	var preview := true
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay" or arg == "--smoke-test" or arg.begins_with("--capture"): preview = false
	if preview and not playing and world.screens.has("439"):
		vm.globals["vision"] = 0
		entities[1]["x"] = 505.0
		entities[1]["y"] = 340.0
		load_map(439, false)
		fps_yaw = 0.55
		fps_pitch = -0.03
	_sync_fps_camera()

func _input_map() -> void:
	super._input_map()
	# Base binds Space to a melee action.  In first person Space is exclusively
	# jump; weapons are on the mouse/right trigger.
	for existing in InputMap.action_get_events("attack"):
		if existing is InputEventKey and existing.physical_keycode == KEY_SPACE:
			InputMap.action_erase_event("attack", existing)
	_fps_bind_key("sprint", KEY_SHIFT)
	_fps_bind_key("jump", KEY_SPACE)
	for pair in [["jump",JOY_BUTTON_RIGHT_STICK],["sprint",JOY_BUTTON_LEFT_STICK]]:
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = pair[1]
		InputMap.action_add_event(pair[0],button)
	# The right stick is reserved for camera look in first person.  Remove the
	# base game's camera toggle binding so a stick click cannot change the view.
	for existing in InputMap.action_get_events("camera"):
		if existing is InputEventJoypadButton and existing.button_index == JOY_BUTTON_RIGHT_STICK:
			InputMap.action_erase_event("camera", existing)
	for pair in [["look_left",JOY_AXIS_RIGHT_X,-1.0],["look_right",JOY_AXIS_RIGHT_X,1.0],["look_up",JOY_AXIS_RIGHT_Y,-1.0],["look_down",JOY_AXIS_RIGHT_Y,1.0]]:
		_fps_bind_joy(pair[0], pair[1], pair[2])
	_fps_bind_joy_button("weapon_previous", JOY_BUTTON_LEFT_SHOULDER)
	_fps_bind_joy_button("weapon_next", JOY_BUTTON_RIGHT_SHOULDER)
	_fps_bind_mouse("attack", MOUSE_BUTTON_LEFT)
	_fps_bind_mouse("magic", MOUSE_BUTTON_RIGHT)
	_fps_bind_joy("attack", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_fps_bind_joy("magic", JOY_AXIS_TRIGGER_LEFT, 1.0)

func _fps_bind_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _fps_bind_mouse(action: String, button: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _fps_bind_joy(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)

func _fps_bind_joy_button(action: String, button_index: int) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button_index
	InputMap.action_add_event(action, event)

func _new_game() -> void:
	_fps_restore_dialogue_camera()
	fps_yaw = 0.0
	fps_pitch = -0.08
	fps_jump_height = 0.0
	fps_vertical_velocity = 0.0
	await super._new_game()
	# The campaign still begins in the original interior and keeps its fists.  A
	# plain bow is an extra first-person starter tool; fireball remains quest loot.
	if not items.any(func(item: Dictionary): return str(item.get("script", "")).to_lower() == "item-b1"):
		items.append({"script":"item-b1", "name":"Bow", "seq":0, "frame":1})
		vm.globals["cur_weapon"] = items.size()
		ui.notify("A travel bow is ready. Left click or RT to fire.")
	_fps_face_mother()

func _fps_face_mother() -> void:
	if not entities.has(1): return
	var player_pos := _position2(1)
	var best := 999999.0
	var target := Vector2.ZERO
	for id in entities.keys():
		if int(id) == 1: continue
		var e: Dictionary = entities[id]
		var script := str(e.get("script", "")).to_lower()
		if script != "s1-h1-m": continue
		var offset := _position2(int(id)) - player_pos
		if offset.length_squared() < best:
			best = offset.length_squared()
			target = offset
	if best < 999999.0:
		fps_yaw = atan2(-target.x, -target.y)
	_sync_fps_camera()

func _build_ground(screen: Dictionary) -> void:
	if fp_world != null:
		fp_world.build_ground(screen)
	else:
		super._build_ground(screen)

func _create_visual(id: int) -> void:
	if fp_world != null:
		fp_world.create_visual(id)
	else:
		super._create_visual(id)

func _update_visual(id: int) -> void:
	if fp_world != null:
		fp_world.update_visual(id)
	else:
		super._update_visual(id)

func load_map(number: int, run_scripts: bool = true) -> void:
	_fps_restore_dialogue_camera()
	super.load_map(number, run_scripts)
	if last_music.is_empty(): _play_music("104")
	if fp_world != null and fp_world.has_method("refresh_neighbors"):
		fp_world.refresh_neighbors()
	_sync_fps_camera()

func _physics_process(delta: float) -> void:
	if not playing or changing:
		_fps_restore_dialogue_camera()
		_fps_update_mouse_mode()
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	warp_cooldown = maxf(0.0, warp_cooldown - delta)
	if not ui.modal and entities.has(1):
		_fps_move_player(delta)
		_update_ai(delta)
	for id in entities.keys():
		if entities.has(id): _animate(id, delta)
	_fps_update_jump(delta)
	_fps_update_controller_look(delta)
	_sync_fps_camera()
	if fp_world != null: fp_world.face_neighbours() # the neighbours' actors, for the camera as it is now
	_fps_update_viewmodel(delta)
	if ui.modal:
		fps_fire_held = fps_fire_held or Input.is_action_pressed("attack")
		fps_magic_held = fps_magic_held or Input.is_action_pressed("magic")
	_fps_update_mouse_mode()
	if not ui.modal and Input.is_action_pressed("attack") and not fps_fire_held:
		fps_fire_held = true
		_fps_attack()
	elif not Input.is_action_pressed("attack"):
		fps_fire_held = false
	if not ui.modal and Input.is_action_pressed("magic") and not fps_magic_held:
		fps_magic_held = true
		_fps_set_facing_from_camera()
		_cast()
	elif not Input.is_action_pressed("magic"):
		fps_magic_held = false
	hud_clock += delta
	if hud_clock > 0.15:
		hud_clock = 0.0
		var stats: Dictionary = vm.globals.duplicate()
		stats["location"] = _location()
		stats["weapon"] = _fps_weapon_name()
		_add_equipment_stats(stats)
		ui.show_hud(stats)

func _fps_move_player(delta: float) -> void:
	var player: Dictionary = entities[1]
	if player.get("frozen", false) or int(player.get("disabled", 0)) != 0 or int(player.get("nocontrol", 0)) != 0 or attack_cooldown >= 0.2:
		return
	var deadzone := _fps_controller_deadzone()
	var input := Input.get_vector("left", "right", "up", "down", deadzone)
	if input == Vector2.ZERO:
		if attack_cooldown <= 0.0: _set_animation(1, int(player.get("base_idle", 10)) + _cardinal(int(player.get("dir", 2))))
		_transitions()
		return
	var forward3 := Vector3(-camera.global_transform.basis.z.x, 0.0, -camera.global_transform.basis.z.z).normalized()
	var right3 := Vector3(camera.global_transform.basis.x.x, 0.0, camera.global_transform.basis.x.z).normalized()
	var source_direction := Vector2(forward3.x * -input.y + right3.x * input.x, forward3.z * -input.y + right3.z * input.x).normalized()
	player["dir"] = _direction(source_direction)
	var speed := 105.0 * maxf(0.5, float(player.get("speed", 3)) / 3.0)
	if Input.is_action_pressed("sprint"): speed *= 1.55
	_move_entity(1, source_direction * speed * input.length() * delta)
	_set_animation(1, int(player.get("base_walk", 70)) + int(player.dir))
	_transitions()

func _fps_update_jump(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and fps_jump_height <= 0.001 and not ui.modal:
		fps_vertical_velocity = 5.2
	fps_vertical_velocity -= 14.0 * delta
	fps_jump_height = maxf(0.0, fps_jump_height + fps_vertical_velocity * delta)
	if fps_jump_height <= 0.0: fps_vertical_velocity = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and playing and not ui.modal:
		var sensitivity := float(settings.get("mouse_sensitivity", 0.002))
		fps_yaw -= event.relative.x * sensitivity
		fps_pitch = clampf(fps_pitch - event.relative.y * sensitivity, -1.25, 1.25)
		_sync_fps_camera()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or (event.is_action_pressed("ui_cancel") and ui.modal):
		if ui.dialogue_mode: return
		if playing:
			if ui.modal: ui.request_back()
			else: ui.show_pause()
		elif ui.page != "title": ui.request_back()
		_fps_update_mouse_mode()
		get_viewport().set_input_as_handled()
		return
	if ui.modal or not playing: return
	if _fps_is_initial_action_press(event, "weapon_previous"):
		_fps_cycle_weapon(-1)
		get_viewport().set_input_as_handled()
		return
	if _fps_is_initial_action_press(event, "weapon_next"):
		_fps_cycle_weapon(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("talk"): _talk()
	if event.is_action_pressed("inventory"): ui.show_inventory(items, magic_items)
	if event.is_action_pressed("jump"): _fps_update_jump(0.0)
	if event is InputEventKey and event.pressed and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		_equip(int(event.physical_keycode - KEY_1), false)

func _fps_update_mouse_mode() -> void:
	var wanted := Input.MOUSE_MODE_CAPTURED if playing and not ui.modal else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted: Input.mouse_mode = wanted

func _sync_fps_camera() -> void:
	if not is_instance_valid(camera) or not entities.has(1): return
	var player: Dictionary = entities[1]
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = clampf(float(settings.get("fov", 80.0)), 60.0, 105.0)
	camera.near = 0.03
	camera.far = 180.0
	camera.position = fps_dialogue_camera_position if fps_dialogue_camera_active else Vector3((float(player.get("x", 320)) - 320.0) * SCALE, EYE_HEIGHT + fps_jump_height, (float(player.get("y", 200)) - 200.0) * SCALE)
	camera.rotation = Vector3(fps_pitch, fps_yaw, 0.0)

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings.master))))
	if is_instance_valid(music): music.volume_db = linear_to_db(maxf(0.0001, float(settings.music)))
	if is_instance_valid(ui) and is_instance_valid(ui.root): ui.set_text_scale(float(settings.text_scale))
	_sync_fps_camera()

func _fps_update_controller_look(delta: float) -> void:
	if ui.modal: return
	var aim := Input.get_vector("look_left", "look_right", "look_up", "look_down", _fps_controller_deadzone())
	if aim == Vector2.ZERO: return
	var sensitivity := clampf(float(settings.get("controller_sensitivity", 2.0)), 0.5, 4.0)
	var invert_y := -1.0 if bool(settings.get("controller_invert_y", false)) else 1.0
	fps_yaw -= aim.x * sensitivity * delta
	fps_pitch = clampf(fps_pitch - aim.y * sensitivity * invert_y * delta, -1.25, 1.25)

func _fps_controller_deadzone() -> float:
	return clampf(float(settings.get("controller_deadzone", 0.2)), 0.05, 0.4)

func _fps_is_initial_action_press(event: InputEvent, action: String) -> bool:
	if not event.is_action_pressed(action): return false
	return not (event is InputEventKey and event.echo)

func _fps_cycle_weapon(step: int) -> void:
	if items.is_empty(): return
	var current := int(vm.globals.get("cur_weapon", 1)) - 1
	var next := posmod(current + step, items.size())
	_equip(next, false)

func _fps_weapon_name() -> String:
	var index := int(vm.globals.get("cur_weapon", 1)) - 1
	return str(items[index].get("name", "Fists")) if index >= 0 and index < items.size() else "Fists"

func _fps_update_viewmodel(delta: float) -> void:
	var weapon := _fps_weapon_name().to_lower()
	var key := "feed" if weapon.contains("pig feed") else ("bow" if weapon.contains("bow") else ("sword" if weapon.contains("sword") else "fist"))
	if key != fps_viewmodel_key:
		fps_viewmodel_key = key
		if is_instance_valid(fps_viewmodel): fps_viewmodel.queue_free()
		fps_viewmodel = null
		if key == "feed":
			fps_viewmodel = _fps_make_feed_viewmodel()
		else:
			var scene: PackedScene = load("res://assets/models/%s.glb" % key)
			if scene != null:
				fps_viewmodel = scene.instantiate()
				fps_viewmodel.name = "FirstPersonWeapon"
				camera.add_child(fps_viewmodel)
	fps_recoil = maxf(0.0, fps_recoil - delta * 3.5)
	fps_feed_use = maxf(0.0, fps_feed_use - delta * 4.0)
	if fps_hand == null:
		fps_hand = load("res://assets/models/fist.glb").instantiate()
		camera.add_child(fps_hand)
		fps_hand.scale = Vector3.ONE*0.44
	if is_instance_valid(fps_hand):
		fps_hand.position = Vector3(0.59,-0.50,-0.86-fps_recoil*0.18) if key == "bow" else Vector3(0.4,-0.59,-0.78)
		if key == "feed": fps_hand.position = Vector3(0.53, -0.43, -0.94)
		fps_hand.visible = key != "fist" and not ui.modal
	if is_instance_valid(fps_viewmodel):
		fps_viewmodel.visible = not ui.modal
		fps_viewmodel.position = Vector3(0.40, -0.38 if key == "fist" else (-0.57 if key == "feed" else -0.64), -0.85 - fps_recoil * 0.18)
		fps_viewmodel.scale = Vector3.ONE * (0.6 if key == "bow" else (0.50 if key == "feed" else 0.42))
		fps_viewmodel.rotation_degrees = Vector3(-8.0 - fps_recoil * 18.0, -18.0, 0.0)
		if key == "feed":
			fps_viewmodel.position = Vector3(0.35, -0.30, -0.95)
			fps_viewmodel.scale = Vector3.ONE * 0.42
			fps_viewmodel.position.y -= fps_feed_use * 0.12
			fps_viewmodel.rotation_degrees.x += fps_feed_use * 18.0

func _fps_make_feed_viewmodel() -> Node3D:
	var root := Node3D.new()
	root.name = "FirstPersonPigFeed"
	camera.add_child(root)
	var sack := MeshInstance3D.new()
	var sack_mesh := CylinderMesh.new()
	sack_mesh.top_radius = 0.34
	sack_mesh.bottom_radius = 0.43
	sack_mesh.height = 0.72
	sack.mesh = sack_mesh
	sack.material_override = _fps_material(Color("b88d52"), 0.0)
	root.add_child(sack)
	var tie := MeshInstance3D.new()
	var tie_mesh := CylinderMesh.new()
	tie_mesh.top_radius = 0.16
	tie_mesh.bottom_radius = 0.18
	tie_mesh.height = 0.16
	tie.mesh = tie_mesh
	tie.position.y = 0.43
	tie.material_override = _fps_material(Color("6d4930"), 0.0)
	root.add_child(tie)
	var label := Label3D.new()
	label.text = "FEED"
	label.font_size = 32
	label.modulate = Color("3b271c")
	label.position = Vector3(0.0, 0.0, 0.44)
	label.pixel_size = 0.0025
	root.add_child(label)
	return root

func _fps_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness if roughness > 0.0 else 0.82
	return material

func _fps_line_clear(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	for step in range(1, int(distance / 5.0)):
		if _structure_blocked(from.lerp(to, float(step) * 5.0 / distance)): return false
	return true

func _fps_ray_reaches(id: int) -> bool:
	var visual: Node3D = visuals.get(id)
	if not is_instance_valid(visual): return false
	var height := float(visual.get_meta("height", 0.0))
	if height <= 0.0: return false
	var target := visual.global_position + Vector3.UP * minf(EYE_HEIGHT, height * 0.65)
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target, 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return false
	var collider: Object = hit.get("collider")
	return collider != null and int(collider.get_meta("entity_id", 0)) == id

func _fps_targetable(id: int, source_point: Vector2 = Vector2.INF, ray_height: float = -1.0) -> bool:
	if not entities.has(id): return false
	var target: Dictionary = entities[id]
	if int(target.get("active", 1)) == 0 or int(target.get("nohit", 0)) != 0 and str(target.get("script", "")).is_empty(): return false
	var visual: Node3D = visuals.get(id)
	var upper := float(visual.get_meta("height", 0.0)) if is_instance_valid(visual) else 0.0
	if upper <= 0.0 or (ray_height >= 0.0 and ray_height > upper): return false
	if source_point != Vector2.INF and not _fps_line_clear(source_point, _position2(id)): return false
	return true

func _fps_aim_target(max_distance: float, cone_dot: float = 0.93) -> int:
	if not entities.has(1): return 0
	var origin := _position2(1)
	var forward3 := -camera.global_transform.basis.z
	var forward := Vector2(forward3.x, forward3.z).normalized()
	var best := 0
	var best_distance := max_distance
	for id in entities.keys():
		if int(id) == 1 or not _fps_targetable(int(id), origin): continue
		var offset := _position2(int(id)) - origin
		var distance := offset.length()
		if distance > 0.1 and distance < best_distance and offset.normalized().dot(forward) >= cone_dot and _fps_ray_reaches(int(id)):
			best = int(id)
			best_distance = distance
	return best

func _talk() -> void:
	if not entities.has(1) or entities[1].get("frozen", false): return
	var candidate := 0
	var best := 90.0
	var origin := _position2(1)
	var forward3 := -camera.global_transform.basis.z
	var forward := Vector2(forward3.x, forward3.z).normalized()
	for id in entities.keys():
		if int(id) == 1 or not entities.has(id): continue
		var e: Dictionary = entities[id]
		if int(e.get("active", 1)) == 0 or int(e.get("type", 1)) != 1 or str(e.get("script", "")).is_empty(): continue
		if vm._procedure_code(str(e.script).to_lower(), "talk").is_empty(): continue
		var offset := _position2(int(id)) - origin
		if offset.length() < best and (offset.length() < 20.0 or offset.normalized().dot(forward) > 0.55) and _fps_line_clear(origin, _position2(int(id))) and _fps_ray_reaches(int(id)):
			candidate = int(id)
			best = offset.length()
	if candidate: _run_event(candidate, "talk")
	else: ui.notify("Move closer and face someone or something to talk.")

func _fps_attack() -> void:
	if attack_cooldown > 0.0 or not entities.has(1) or entities[1].get("frozen", false) or int(entities[1].get("nocontrol", 0)): return
	attack_cooldown = 0.45
	fps_recoil = 1.0
	var player: Dictionary = entities[1]
	_fps_set_facing_from_camera()
	_set_animation(1, int(player.get("base_attack", 100)) + _cardinal(int(player.get("dir", 2))))
	_play_sound(8)
	var equipped := int(vm.globals.get("cur_weapon", 1)) - 1
	var weapon := "item-fst"
	if equipped >= 0 and equipped < items.size():
		weapon = str(items[equipped].get("script", weapon)).to_lower()
		# Campaign bow scripts manufacture their own top-down missile.  First
		# person uses the same damage/event bridge below instead.
		if weapon not in ["item-b1","item-b2","item-b3"]:
			vm.run(weapon, "use", 1)
			if weapon == "item-pig": fps_feed_use = 1.0
	if weapon in ["item-b1", "item-b2", "item-b3"]:
		_fps_launch_projectile(false)
		return
	if weapon not in ["item-fst", "item-sw1", "item-sw2", "item-sw3"]: return
	var victim := _fps_aim_target(28.0 if weapon == "item-fst" else 43.0, 0.60)
	if victim != 0: _fps_projectile_hit(victim, 1, maxi(1, int(vm.globals.get("strength", 3))))

func _dialogue(text: String, speaker: int, context: Dictionary) -> void:
	var expected := generation
	while dialogue_busy and expected == generation:
		await get_tree().process_frame
	if expected != generation: return
	dialogue_busy = true
	var line := _interpolate(text, context)
	dialogue_log.append(line)
	if dialogue_log.size() > 100: dialogue_log.pop_front()
	if test_mode:
		await get_tree().process_frame
	else:
		var displayed_speaker := speaker
		if displayed_speaker == 0: displayed_speaker = int(context.get("sprite_id", 0))
		if displayed_speaker != 1 and entities.has(displayed_speaker): _fps_frame_speaker(displayed_speaker)
		elif displayed_speaker == 1: _fps_grief_dialogue_camera(context)
		ui.show_dialogue(line, _fps_speaker_name(displayed_speaker, context))
		# Hide a held model immediately, including the first rendered dialogue frame.
		_fps_update_viewmodel(0.0)
		await ui.dialogue_finished
		_fps_restore_dialogue_camera()
	dialogue_busy = false

func _fps_frame_speaker(speaker: int) -> void:
	if not entities.has(1) or not entities.has(speaker): return
	_fps_restore_dialogue_camera()
	if _fps_mother_dialogue_camera(speaker): return
	var offset := _position2(speaker) - _position2(1)
	if offset.length_squared() > 0.01:
		fps_yaw = atan2(-offset.x, -offset.y)
		var visual: Node3D = visuals.get(speaker)
		var head_height := float(visual.get_meta("height", 1.8)) * 0.85 if is_instance_valid(visual) else EYE_HEIGHT
		fps_pitch = clampf(atan2(head_height - EYE_HEIGHT - fps_jump_height, offset.length() * SCALE), -1.2, 1.2)
		_sync_fps_camera()

func _fps_mother_dialogue_camera(speaker: int) -> bool:
	# The first return-home conversation starts at the doorway while Mother is
	# behind furniture. Find a real, unobstructed view inside this one room.
	if bool(settings.get("reduced_motion", false)) or current_screen != 1 or str(entities[speaker].get("script", "")).to_lower() != "s1-h1-m" or int(vm.globals.get("story", 0)) != 2:
		return false
	var target_visual: Node3D = visuals.get(speaker)
	if not is_instance_valid(target_visual): return false
	# A ray to her collider can still leave Mother hidden behind the table or the
	# dialogue panel, so Story 2 always uses a tested in-room framing.
	var target := target_visual.global_position + Vector3.UP * minf(EYE_HEIGHT, float(target_visual.get_meta("height", 1.8)) * 0.65)
	# The room's north-west side has an open aisle. Test several positions rather
	# than relying on a particular imported wall size or Mother's movement tick.
	for source_offset in [Vector2(-64, 72), Vector2(-78, 20), Vector2(-40, 96), Vector2(-92, -28), Vector2(35, 90), Vector2(20, -70), Vector2(40, -60)]:
		var source2: Vector2 = _position2(speaker) + source_offset
		var source := Vector3((source2.x - 320.0) * SCALE, EYE_HEIGHT, (source2.y - 200.0) * SCALE)
		if not _fps_camera_point_clear(source): continue
		var query := PhysicsRayQueryParameters3D.create(source, target, 3)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): continue
		var collider: Object = hit.get("collider")
		if collider == null or int(collider.get_meta("entity_id", 0)) != speaker: continue
		fps_dialogue_restore_yaw = fps_yaw
		fps_dialogue_restore_pitch = fps_pitch
		fps_dialogue_camera_position = source
		fps_dialogue_camera_active = true
		var offset := target - source
		fps_yaw = atan2(-offset.x, -offset.z)
		fps_pitch = clampf(atan2(offset.y, Vector2(offset.x, offset.z).length()), -1.2, 1.2)
		_sync_fps_camera()
		return true
	return false

func _fps_grief_dialogue_camera(context: Dictionary) -> bool:
	# S1-H1-S keeps Dink frozen in the original room while he grieves. The
	# doorway view points into a wall, so hold a clear in-room view on the actual
	# fireplace/flame model without changing Dink's source coordinates.
	if bool(settings.get("reduced_motion", false)) or current_screen != 1:
		return false
	if str(context.get("script", "")).to_lower() != "s1-h1-s" or int(vm.globals.get("story", 0)) != 3:
		return false
	if fps_dialogue_camera_active: return true
	var player := _position2(1)
	# Prefer viewpoints behind Dink that include the hearth, then test alternate
	# room positions against the real 3D collision scene. A fireplace has a
	# collision body; source flame sprites intentionally do not, so their clear
	# ray correctly ends with no collision.
	var source2_candidates: Array[Vector2] = [player + Vector2(-72, -28), player + Vector2(72, -28), player + Vector2(-64, 36), player + Vector2(64, 36), player + Vector2(0, -72)]
	var subjects: Array[int] = []
	# The indoor hearth is the most meaningful subject. Only fall back to source
	# fire sprites when that original fixture has no fireplace.
	for key in ["fireplace", "flame"]:
		for id in visuals:
			var visual: Node3D = visuals[id]
			if is_instance_valid(visual) and str(visual.get_meta("model_key", "")) == key:
				subjects.append(int(id))
	for subject in subjects:
		var subject_visual: Node3D = visuals.get(subject)
		var model_key := str(subject_visual.get_meta("model_key", ""))
		var subject_height := float(subject_visual.get_meta("height", 1.8))
		var target := subject_visual.global_position + Vector3.UP * minf(1.35, maxf(0.55, subject_height * 0.55))
		var subject2 := _position2(subject)
		var candidates := source2_candidates.duplicate()
		candidates.append_array([subject2 + Vector2(-50, 42), subject2 + Vector2(50, 42), subject2 + Vector2(-50, -42), subject2 + Vector2(50, -42)])
		for source2 in candidates:
			var source := Vector3((source2.x - 320.0) * SCALE, EYE_HEIGHT, (source2.y - 200.0) * SCALE)
			if not _fps_camera_point_clear(source): continue
			var query := PhysicsRayQueryParameters3D.create(source, target, 3)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			var reaches_subject := hit.is_empty() if model_key == "flame" else false
			if model_key == "fireplace" and not hit.is_empty():
				var collider: Object = hit.get("collider")
				reaches_subject = collider != null and int(collider.get_meta("entity_id", 0)) == subject
			if not reaches_subject: continue
			fps_dialogue_restore_yaw = fps_yaw
			fps_dialogue_restore_pitch = fps_pitch
			fps_dialogue_camera_position = source
			fps_dialogue_subject = subject
			fps_dialogue_camera_active = true
			var offset := target - source
			fps_yaw = atan2(-offset.x, -offset.z)
			fps_pitch = clampf(atan2(offset.y, Vector2(offset.x, offset.z).length()), -1.2, 1.2)
			_sync_fps_camera()
			return true
	return false

func _fps_camera_point_clear(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = 3
	return get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()

func _fps_restore_dialogue_camera() -> void:
	if not fps_dialogue_camera_active: return
	fps_dialogue_camera_active = false
	fps_dialogue_subject = 0
	fps_yaw = fps_dialogue_restore_yaw
	fps_pitch = fps_dialogue_restore_pitch
	_sync_fps_camera()

func _fps_speaker_name(speaker: int, context: Dictionary = {}) -> String:
	if speaker == 1: return "Dink"
	var script := str(entities.get(speaker, {}).get("script", "")).to_lower()
	var source_script := str(context.get("script", "")).to_lower()
	if source_script == "s1-ltr": return "Aunt Maria's letter"
	if source_script == "s1-gg": return "Renton"
	if source_script == "s1-h1-o":
		# S1-H1-O creates these four anonymous sprites in source order: old lady,
		# girl, Silver knight, and girl2. Only the first and third have source
		# identities; the two girls remain the truthful generic neighbor label.
		# pseq can advance while an actor animates, so use its source walk base
		# when the currently displayed sequence no longer identifies the sprite.
		var pseq := int(entities.get(speaker, {}).get("pseq", 0))
		var base_walk := int(entities.get(speaker, {}).get("base_walk", 0))
		if pseq == 231 or base_walk == 230: return "Ethel"
		if pseq == 411 or base_walk == 410: return "Guard"
		if pseq in [221, 257] or base_walk in [220, 250]: return "Neighbor"
	return {"s1-bul": "Milder", "s1-gg": "Renton", "s1-h1-m": "Mother", "s1-h2-o": "Ethel",
		"s1-oldd": "Quackers", "s1-h2-dk": "Quackers"}.get(script, "Conversation")

func _attack() -> void:
	_fps_attack()

func _cast() -> void:
	if not entities.has(1) or entities[1].get("frozen",false): return
	if magic_items.is_empty():
		ui.notify("No magic equipped yet. Seek a teacher on your travels.")
		return
	var index := int(vm.globals.get("cur_magic", 0)) - 1
	if index < 0 or index >= magic_items.size():
		ui.notify("Choose a spell from Equipment first.")
		return
	var cost := maxi(0, int(vm.globals.get("magic_cost", 0)))
	if cost <= 0 or int(vm.globals.get("magic_level", 0)) < cost:
		ui.notify("Your magic is still recharging.")
		return
	var spell := str(magic_items[index].get("script", "")).to_lower()
	if spell == "item-fb":
		# The original script creates an eight-direction overhead missile.  Its
		# first-person equivalent consumes the same gauge and reaches the same
		# campaign hit/die callbacks through _fps_projectile_hit().
		vm.globals["magic_level"] = 0
		_fps_set_facing_from_camera()
		_fps_launch_projectile(true)
		return
	super._cast()

func _fps_launch_projectile(is_spell: bool) -> void:
	var projectile := PROJECTILE.new()
	add_child(projectile)
	var forward := -camera.global_transform.basis.z
	projectile.configure(self, 1, camera.global_position + forward * 0.35, forward, maxi(1, int(vm.globals.get("strength", 3))), is_spell)

func _fps_set_facing_from_camera() -> void:
	if not entities.has(1): return
	var forward := -camera.global_transform.basis.z
	entities[1]["dir"] = _direction(Vector2(forward.x, forward.z))

func _fps_projectile_hit(id: int, source: int, amount: int) -> void:
	if not _fps_targetable(id): return
	var target: Dictionary = entities[id]
	vm.globals["enemy_sprite"] = source
	vm.globals["missle_source"] = source
	vm.globals["missile_target"] = id
	target["last_hit"] = source
	if int(target.get("base_attack", -1)) != -1 or int(target.get("touch_damage", 0)) > 0: target["target"] = source
	_run_event(id, "hit")
	if int(target.get("nohit", 0)) == 0:
		_damage(id, amount)
		fps_hit_timer = 0.15

func _save_game(path: String = "user://adventure.json") -> bool:
	var saved := super._save_game(path)
	if saved:
		var data := _read_json(path)
		data["fps_camera"] = {"yaw": fps_yaw, "pitch": fps_pitch}
		return _write_json(path, data)
	return saved

func _load_game(path: String = "user://adventure.json") -> bool:
	var loaded := super._load_game(path)
	if loaded:
		_restore_fps_camera(path)
		_sync_fps_camera()
	return loaded

func _restore_fps_camera(path: String = "user://adventure.json") -> void:
	var saved: Dictionary = _read_json(path).get("fps_camera", {})
	fps_yaw = float(saved.get("yaw", fps_yaw))
	fps_pitch = clampf(float(saved.get("pitch", fps_pitch)), -1.25, 1.25)

func _smoke_test() -> void:
	await get_tree().process_frame
	var failures: Array = []
	if world.screens.size() < 600: failures.append("World import incomplete")
	if sequences.size() < 400: failures.append("Animation import incomplete")
	await _new_game()
	await get_tree().create_timer(2.0).timeout
	if not visuals.has(1) or not is_instance_valid(visuals[1]): failures.append("Player model")
	if not _save_game("user://smoke-save.json"): failures.append("Save")
	if not _load_game("user://smoke-save.json"): failures.append("Load")
	DirAccess.remove_absolute("user://smoke-save.json")
	if failures.is_empty(): print("SMOKE PASS: FPS world, player model, save/load")
	else:
		for failure in failures: push_error("SMOKE FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _input(event: InputEvent) -> void:
	super._input(event)
	if not is_instance_valid(ui): return
	# Remember presses before the GUI consumes a menu button and closes it.
	if ui.modal or not playing:
		if event.is_action_pressed("attack"): fps_fire_held = true
		if event.is_action_pressed("magic"): fps_magic_held = true
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F11:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _location() -> String:
	var places := {1:"Dink's home",2:"Ethel's home",407:"Stonebrook • Pig farm",
		408:"Stonebrook • Village gate",409:"Stonebrook • Ethel's cottage",
		439:"Stonebrook • Dink's cottage",440:"Stonebrook • The village",
		441:"Stonebrook • East village",438:"Stonebrook • Western woods"}
	return places.get(current_screen,"The kingdom • Area %d" % current_screen)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if vm: vm.cancel_all()
	if fp_world:
		fp_world.terrain_cache.clear()
		fp_world.models.clear()
		fp_world.materials.clear()
		fp_world.host = null
		fp_world = null
