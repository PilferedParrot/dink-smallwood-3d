# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends Node3D
const VM = preload("res://scripts/dink_vm.gd")
const UI = preload("res://scripts/game_ui.gd")
const UNIT := 0.025
const DEPTH := 0.035
var vm
var ui
var world: Dictionary = {}
var sequences: Dictionary = {}
var sounds: Dictionary = {}
var entities: Dictionary = {}
var visuals: Dictionary = {}
var textures: Dictionary = {}
var editor_state: Dictionary = {}
var items: Array = []
var magic_items: Array = []
var sound_slots: Dictionary = {}
var settings := {"master":0.8,"music":0.55,"sfx":0.8,"text_scale":1.0,"camera_angle":50.0,"reduced_motion":false}
var scene_root: Node3D
var camera: Camera3D
var music: AudioStreamPlayer
var current_screen := 1
var next_entity := 2
var playing := false
var locked := false
var walk_off_screen := false
var changing := false
var attack_cooldown := 0.0
var hurt_cooldown := 0.0
var warp_cooldown := 0.0
var hud_clock := 0.0
var dialogue_busy := false
var unknown: Dictionary = {}
var last_music := ""
var generation := 0
var visited: Array = []
var dialogue_log: Array = []
var test_mode := false
var hardness_cache: Dictionary = {}
var asset_frames: Array = []
var original_sequences: Dictionary = {}

func _ready() -> void:
	_input_map()
	world = _read_json("res://data/world.json")
	var seq := _read_json("res://data/sequences.json")
	sequences = seq.get("sequences", seq)
	original_sequences = sequences.duplicate(true)
	asset_frames = seq.get("asset_frames",[])
	sounds = _read_json("res://data/sounds.json")
	vm = VM.new(self)
	vm.load_story()
	ui = UI.new()
	add_child(ui)
	ui.action_requested.connect(_ui_action)
	music = AudioStreamPlayer.new()
	add_child(music)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.near = 0.05
	camera.far = 150.0
	add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("11241d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.9
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60,-20,0)
	light.light_energy = 0.6
	add_child(light)
	var saved_settings := _read_json("user://settings.json")
	settings.merge(saved_settings, true)
	_apply_settings()
	_load_sound_slots()
	_make_player()
	load_map(400 if world.get("screens",{}).has("400") else 1, false)
	ui.show_title(FileAccess.file_exists("user://adventure.json"))
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke-test":
			test_mode = true
			_smoke_test.call_deferred()
		if arg.begins_with("--capture-title="):
			_capture_title.call_deferred(arg.trim_prefix("--capture-title="))
		if arg.begins_with("--capture="):
			test_mode = true
			_capture.call_deferred(arg.trim_prefix("--capture="))
		if arg == "--autoplay":
			_new_game.call_deferred()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _input_map() -> void:
	var keys := {"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"up":[KEY_W,KEY_UP],"down":[KEY_S,KEY_DOWN],"talk":[KEY_E,KEY_ENTER],"attack":[KEY_SPACE],"magic":[KEY_Q],"pause":[KEY_ESCAPE],"inventory":[KEY_I],"camera":[KEY_R],"map":[KEY_M]}
	var buttons := {"talk":JOY_BUTTON_A,"attack":JOY_BUTTON_X,"magic":JOY_BUTTON_Y,"pause":JOY_BUTTON_START,"inventory":JOY_BUTTON_BACK,"camera":JOY_BUTTON_RIGHT_STICK}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)
		if buttons.has(action):
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = buttons[action]
			InputMap.action_add_event(action,event)
	for pair in [["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0],["up",JOY_AXIS_LEFT_Y,-1.0],["down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = pair[1]
		event.axis_value = pair[2]
		InputMap.action_add_event(pair[0],event)

func _make_player() -> void:
	entities[1] = {"x":334.0,"y":161.0,"pseq":14,"pframe":1,"seq":0,"frame":1,"brain":1,"dir":4,"base_walk":70,"base_idle":10,"base_attack":100,"speed":3,"size":100,"active":1,"hard":1,"frozen":false,"anim_time":0.0,"script":"","editor_num":0}

func _new_game() -> void:
	vm.cancel_all()
	vm = VM.new(self)
	vm.load_story()
	sequences = original_sequences.duplicate(true)
	dialogue_busy = false
	walk_off_screen = false
	entities.clear()
	editor_state.clear()
	items.clear()
	magic_items.clear()
	visited.clear()
	dialogue_log.clear()
	next_entity = 2
	_make_player()
	await vm.run("main", "main", 1)
	items.append({"script":"item-fst","name":"Fists","seq":438,"frame":1})
	vm.globals["cur_weapon"] = 1
	playing = true
	ui.close_menu()
	load_map(1)
	vm.run("item-fst", "arm", 1)

func load_map(number: int, run_scripts: bool = true) -> void:
	if not world.get("screens",{}).has(str(number)):
		ui.notify("The path ends here.")
		return
	generation += 1
	changing = true
	locked = false
	current_screen = number
	vm.globals["player_map"] = number
	if not visited.has(number): visited.append(number)
	if is_instance_valid(scene_root):
		remove_child(scene_root)
		scene_root.queue_free()
	scene_root = Node3D.new()
	add_child(scene_root)
	visuals.clear()
	var player: Dictionary = entities.get(1, {})
	entities.clear()
	entities[1] = player
	player["frozen"] = false
	var screen: Dictionary = world.screens[str(number)]
	_build_ground(screen)
	# Screen startup can select a vision (for example FINDDUCK). Run its
	# immediate instructions before filtering editor sprites by that vision.
	# Sprite main procedures still start after all entities have been created.
	if run_scripts:
		var expected := generation
		# Vision belongs to the incoming screen. Loading a save with scripts
		# disabled retains its saved vision instead of rerolling quest state.
		vm.globals["vision"] = 0
		var script := str(screen.get("script", ""))
		if not script.is_empty() and not vm._procedure_code(script.to_lower(), "main").is_empty():
			vm.run(script, "main", 0)
		if generation != expected: return
	var editor_entities: Array[int] = []
	for source in screen.get("sprites",[]):
		var e: Dictionary = source.duplicate(true)
		var idx := int(e.get("index",0))
		var key := "%d:%d" % [number,idx]
		if editor_state.has(key):
			e.merge(editor_state[key],true)
		if e.get("removed",false): continue
		var state: Dictionary = editor_state.get(key,{})
		var persistence := int(state.get("editor_type",0))
		if persistence in [6,7,8] and float(state.get("return_at",0)) > Time.get_unix_time_from_system(): continue
		if persistence in [2,3,4,5]:
			e["hard"] = 0 if persistence in [4,5] else 1
			e["type"] = 0 if persistence in [3,5] else 1
			e["brain"] = 0
			e["script"] = ""
		if int(e.get("vision",0)) != 0 and int(e.get("vision",0)) != int(vm.globals.get("vision",0)): continue
		e["editor_num"] = idx
		e["pseq"] = e.get("seq",0)
		e["pframe"] = maxi(1,int(e.get("frame",1)))
		e["seq"] = 0
		e["frame"] = 1
		e["active"] = 1
		e["anim_time"] = 0.0
		e["frozen"] = false
		e["dir"] = 2
		if int(e.get("size",100)) == 0: e["size"] = 100
		entities[next_entity] = e
		editor_entities.append(next_entity)
		next_entity += 1
	for id in entities:
		# A screen main may already have created a sprite and its visual.
		if not visuals.has(id): _create_visual(id)
	_play_music(str(screen.get("music",0)), true)
	warp_cooldown = 0.65
	changing = false
	if run_scripts:
		_run_screen_scripts.call_deferred(generation, editor_entities)

func _run_screen_scripts(expected: int, editor_entities: Array[int]) -> void:
	if generation != expected: return
	# Runtime sprites start main when sp_script attaches it; only editor
	# sprites need startup here, or screen-created actors would run twice.
	for id in editor_entities:
		if generation != expected: return
		if id == 1 or not entities.has(id): continue
		var e: Dictionary = entities[id]
		if int(e.get("type",1)) == 1 and not str(e.get("script","")).is_empty() and not vm._procedure_code(str(e.script).to_lower(),"main").is_empty(): vm.run(e.script,"main",id)

func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not path.begins_with("res://"): path = "res://" + path
	if textures.has(path): return textures[path]
	if ResourceLoader.exists(path):
		var texture = load(path)
		textures[path] = texture
		return texture
	return null

func _frame(seq: int, frame: int) -> Dictionary:
	var data: Dictionary = sequences.get(str(seq),{})
	var frames: Array = data.get("frames",[])
	if frames.is_empty(): return {}
	return frames[clampi(frame-1,0,frames.size()-1)]

func _build_ground(screen: Dictionary) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(15.0,14.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("5f7040")
	var image := Image.create(600,400,false,Image.FORMAT_RGBA8)
	image.fill(Color("5f7040"))
	var tile_images: Dictionary = {}
	for i in range(mini(96,screen.get("tiles",[]).size())):
		var tile: Variant = screen.tiles[i]
		var index := int(tile.get("tile",0)) if tile is Dictionary else int(tile)
		var sheet := index / 128 + 1
		var cell := index % 128
		var path := "res://assets/tiles/ts%02d.png" % sheet
		if not tile_images.has(sheet):
			var tex := _texture(path)
			if tex == null: tex = _texture("res://assets/tiles/ts%d.png" % sheet)
			if tex == null: tex = _texture("res://assets/tiles/ts%02d.png" % sheet)
			tile_images[sheet] = tex.get_image() if tex != null else null
		var source: Image = tile_images[sheet]
		if source != null:
			if source.is_compressed(): source.decompress()
			image.blit_rect(source,Rect2i((cell%12)*50,(cell/12)*50,50,50),Vector2i((i%12)*50,(i/12)*50))
	mat.albedo_texture = ImageTexture.create_from_image(image)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	ground.material_override = mat
	scene_root.add_child(ground)
	# A deep rim makes each original screen a tangible miniature landscape.
	var rim := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(15.15,0.6,14.15)
	rim.mesh = box
	rim.position.y = -0.33
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("322d20")
	rim.material_override = rim_mat
	scene_root.add_child(rim)

func _create_visual(id: int) -> void:
	var sprite := Sprite3D.new()
	sprite.pixel_size = UNIT
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	scene_root.add_child(sprite)
	visuals[id] = sprite
	_update_visual(id)

func _update_visual(id: int) -> void:
	if not entities.has(id) or not visuals.has(id): return
	var e: Dictionary = entities[id]
	var sprite: Sprite3D = visuals[id]
	var seq := int(e.get("seq",0))
	var frame := int(e.get("frame",1))
	if seq == 0:
		seq = int(e.get("pseq",0))
		frame = int(e.get("pframe",1))
	var data := _frame(seq,frame)
	var texture := _texture(str(data.get("path","")))
	sprite.visible = texture != null and int(e.get("active",1)) != 0 and int(e.get("nodraw",0)) == 0 and int(e.get("disabled",0)) == 0 and (id == 1 or int(e.get("type",1)) != 2)
	if texture == null: return
	sprite.texture = texture
	# Dink frames already contain isometric depth and shadows. Sort cutouts by
	# their source depth dot instead of letting the 3D floor clip their lower half.
	var depth_order := float(e.get("que",0))
	if depth_order == 0: depth_order = float(e.get("y",200))
	sprite.render_priority = clampi(int(depth_order/4)-50,-128,127)
	var scale_factor := maxf(0.01,float(e.get("size",100))/100.0)
	sprite.scale = Vector3.ONE * scale_factor
	var dx := float(data.get("dx",texture.get_width()/2.0))
	var dy := float(data.get("dy",texture.get_height()-10.0))
	# The original game clips every frame at its 600 x 400 playfield.
	# Keep off-screen editor decorations out of the surrounding menus and HUD.
	var left := float(e.get("x",320))-dx*scale_factor
	var top := float(e.get("y",200))-dy*scale_factor
	var clip_left := clampf((20.0-left)/scale_factor,0,texture.get_width())
	var clip_top := clampf(-top/scale_factor,0,texture.get_height())
	var clip_right := clampf((620.0-left)/scale_factor,0,texture.get_width())
	var clip_bottom := clampf((400.0-top)/scale_factor,0,texture.get_height())
	if clip_right <= clip_left or clip_bottom <= clip_top:
		sprite.visible = false
		return
	sprite.region_enabled = true
	sprite.region_rect = Rect2(clip_left,clip_top,clip_right-clip_left,clip_bottom-clip_top)
	sprite.offset = Vector2((clip_right-clip_left)/2.0+clip_left-dx,dy-clip_top-(clip_bottom-clip_top)/2.0)
	sprite.position = Vector3((float(e.get("x",320))-320)*UNIT,0.015,(float(e.get("y",200))-200)*DEPTH)
	if int(e.get("type",1)) == 0 and id != 1:
		# Flatten ground decorations; upright scene objects retain their original art.
		if int(e.get("que",0)) < -1000:
			sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			sprite.rotation_degrees.x = -90
			sprite.position.y = 0.02

func _physics_process(delta: float) -> void:
	if not playing or changing: return
	attack_cooldown = maxf(0,attack_cooldown-delta)
	hurt_cooldown = maxf(0,hurt_cooldown-delta)
	warp_cooldown = maxf(0,warp_cooldown-delta)
	if not ui.modal and entities.has(1):
		var player: Dictionary = entities[1]
		if not player.get("frozen",false) and not int(player.get("disabled",0)) and not int(player.get("nocontrol",0)) and attack_cooldown < 0.2:
			var input := Input.get_vector("left","right","up","down")
			if input.length() > 0.15:
				player["dir"] = _direction(input)
				var speed := 105.0 * maxf(0.5,float(player.get("speed",3))/3.0)
				_move_entity(1,input*speed*delta)
				_set_animation(1,int(player.get("base_walk",70))+int(player.dir))
			else:
				if attack_cooldown <= 0:
					_set_animation(1,int(player.get("base_idle",10))+_cardinal(int(player.dir)))
			_transitions()
		_update_ai(delta)
	for id in entities.keys():
		if entities.has(id): _animate(id,delta)
	hud_clock += delta
	if hud_clock > 0.15:
		hud_clock = 0
		var stats: Dictionary = vm.globals.duplicate()
		stats["location"] = _location()
		ui.show_hud(stats)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(ui) or not event.is_action_pressed("map") or event.is_echo(): return
	if not playing: return
	if ui.page == "map":
		ui.close_menu()
	elif not ui.modal:
		_open_world_map()
	else:
		return
	get_viewport().set_input_as_handled()

func _open_world_map() -> void:
	if not playing or not entities.has(1) or dialogue_busy: return
	var player: Dictionary = entities[1]
	if player.get("frozen", false) or player.get("disabled", false) or int(player.get("nocontrol", 0)): return
	if ui.modal and ui.page != "pause": return
	ui.close_menu()
	# Keep the original ownership check and map artwork in the campaign script.
	vm.run("button6", "main", 1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if ui.dialogue_mode: return
		if playing:
			if ui.modal: ui.close_menu()
			else: ui.show_pause()
		elif ui.page != "title": ui.show_title(FileAccess.file_exists("user://adventure.json"))
		get_viewport().set_input_as_handled()
		return
	if ui.modal or not playing: return
	if event.is_action_pressed("talk"): _talk()
	if event.is_action_pressed("attack"): _attack()
	if event.is_action_pressed("magic"): _cast()
	if event.is_action_pressed("inventory"): ui.show_inventory(items,magic_items)
	if event.is_action_pressed("camera"):
		settings.camera_angle = 65.0 if float(settings.camera_angle) < 60 else 45.0
		_apply_settings()

func _direction(v: Vector2) -> int:
	var x := 0 if absf(v.x)<0.3 else (1 if v.x>0 else -1)
	var y := 0 if absf(v.y)<0.3 else (1 if v.y>0 else -1)
	return int({Vector2i(-1,1):1,Vector2i(0,1):2,Vector2i(1,1):3,Vector2i(-1,0):4,Vector2i(1,0):6,Vector2i(-1,-1):7,Vector2i(0,-1):8,Vector2i(1,-1):9}.get(Vector2i(x,y),2))

func _cardinal(dir: int) -> int:
	return {1:2,3:2,7:8,9:8}.get(dir,dir)

func _dir_vector(dir: int) -> Vector2:
	return {1:Vector2(-1,1),2:Vector2(0,1),3:Vector2(1,1),4:Vector2(-1,0),6:Vector2(1,0),7:Vector2(-1,-1),8:Vector2(0,-1),9:Vector2(1,-1)}.get(dir,Vector2.ZERO).normalized()

func _position2(id: int) -> Vector2:
	var e: Dictionary = entities.get(id,{})
	return Vector2(float(e.get("x",0)),float(e.get("y",0)))

func _set_animation(id: int, seq: int) -> void:
	if not entities.has(id) or not sequences.has(str(seq)): return
	var e: Dictionary = entities[id]
	if int(e.get("seq",0)) != seq:
		e["seq"] = seq
		e["frame"] = 1
		e["anim_time"] = 0.0

func _animate(id: int, delta: float) -> void:
	var e: Dictionary = entities[id]
	# Dink's magic gauge advances by the magic stat once per engine tick.  Keep the
	# fractional part on the player so this remains stable at any Godot frame rate.
	if id == 1 and not ui.modal:
		var magic_cost := maxi(0,int(vm.globals.get("magic_cost",0)))
		var magic_level := maxi(0,int(vm.globals.get("magic_level",0)))
		if magic_cost > 0 and magic_level < magic_cost:
			e["magic_recharge"] = float(e.get("magic_recharge",0.0))+maxi(0,int(vm.globals.get("magic",0)))*50.0*delta
			var gained := int(floor(float(e.magic_recharge)))
			if gained > 0:
				e["magic_recharge"] = float(e.magic_recharge)-gained
				vm.globals["magic_level"] = mini(magic_cost,magic_level+gained)
	if int(e.get("brain",0)) == 12 and int(e.get("active",1)) != 0:
		var target_size := int(e.get("brain_parm",0))
		var old_size := float(e.get("size",100))
		var new_size := move_toward(old_size,float(target_size),250.0*delta)
		e["size"] = new_size
		if is_equal_approx(new_size,float(target_size)):
			e["active"] = 0
	var seq := int(e.get("seq",0))
	if seq > 0 and not (ui.modal and not ui.dialogue_mode):
		var frame := int(e.get("frame",1))
		var data := _frame(seq,frame)
		var delay := float(e.get("frame_delay",0))
		if delay <= 0: delay = float(data.get("delay",100))
		e["anim_time"] = float(e.get("anim_time",0))+delta
		if float(e.anim_time) >= maxf(0.015,delay/1000.0):
			e["anim_time"] = 0.0
			var count: int = sequences.get(str(seq),{}).get("frames",[]).size()
			frame += -1 if int(e.get("reverse",0)) else 1
			if count > 0 and (frame > count or frame < 1):
				if id == 1 and int(e.get("nocontrol",0)):
					e["nocontrol"] = 0
					e["seq"] = 0
				var brain := int(e.get("brain",0))
				if brain == 5:
					# Brain 5 bakes its final frame into the old 2D background.  Retain
					# that frame as a static sprite in the diorama instead.
					e["pseq"] = seq
					e["pframe"] = 1 if int(e.get("reverse",0)) else count
					e["seq"] = 0
					e["brain"] = 0
				if brain == 7 or brain == 17:
					e["active"] = 0
				# Brain 6 and ordinary walking sequences repeat. Reverse sequences
				# restart at their last frame.
				frame = count if int(e.get("reverse",0)) else 1
			e["frame"] = frame
	_update_visual(id)

func _hard_rect(e: Dictionary) -> Rect2:
	var hb: Array = e.get("hardbox",[])
	if hb.size() != 4 or (float(hb[0]) == 0 and float(hb[1]) == 0 and float(hb[2]) == 0 and float(hb[3]) == 0):
		hb = _frame(int(e.get("pseq",0)),int(e.get("pframe",1))).get("hardbox",[-10,-6,10,6])
	if hb.size() != 4: hb = [-10,-6,10,6]
	var factor := float(e.get("size",100))/100.0
	return Rect2(Vector2(float(e.get("x",0)),float(e.get("y",0)))+Vector2(hb[0],hb[1])*factor,Vector2(hb[2]-hb[0],hb[3]-hb[1])*factor)

func _blocked(pos: Vector2, mover: int) -> bool:
	for id in entities:
		if id == mover or id == 1: continue
		var e: Dictionary = entities[id]
		if int(e.get("active",1)) == 0 or int(e.get("hard",1)) != 0 or e.get("warp") != null: continue
		if _hard_rect(e).grow(4).has_point(pos): return true
	return _tile_blocked(pos)

func _tile_blocked(pos: Vector2) -> bool:
	if pos.x < 20 or pos.x >= 620 or pos.y < 0 or pos.y >= 400: return false
	var tx := int((pos.x-20)/50)
	var ty := int(pos.y/50)
	var tile: Dictionary = world.screens[str(current_screen)].tiles[ty*12+tx]
	var mask := int(tile.get("hard",0))
	var hardness: Dictionary = world.get("hardness",{})
	if mask == 0:
		var defaults: Array = hardness.get("tile_defaults",[])
		var tile_id := int(tile.get("tile",0))
		if tile_id >= 0 and tile_id < defaults.size(): mask = int(defaults[tile_id])
	if mask <= 0: return false
	if not hardness_cache.has(mask):
		var masks: Array = hardness.get("masks_rle",[])
		if mask >= masks.size(): return false
		var decoded := PackedByteArray()
		for run in masks[mask]:
			for i in int(run[1]): decoded.append(int(run[0]))
		hardness_cache[mask] = decoded
	# Hard.dat is a 51 x 51, x-major mask; the final row/column are padding.
	var x := int(pos.x-20)%50
	var y := int(pos.y)%50
	var pixels: PackedByteArray = hardness_cache[mask]
	return x*51+y < pixels.size() and pixels[x*51+y] != 0

func _move_entity(id: int, displacement: Vector2, ignore_hardness: bool = false) -> void:
	if not entities.has(id): return
	var pos := _position2(id)
	var e: Dictionary = entities[id]
	var noclip := ignore_hardness or int(e.get("noclip",0)) != 0
	if noclip or not _blocked(pos+Vector2(displacement.x,0),id): pos.x += displacement.x
	if noclip or not _blocked(pos+Vector2(0,displacement.y),id): pos.y += displacement.y
	e["x"] = pos.x
	e["y"] = pos.y

func _transitions(scripted_move: bool = false, from_position: Vector2 = Vector2.INF) -> void:
	# Freeze blocks player input, but an original move_stop can still walk Dink
	# through a doorway (the burning-home evacuation never calls unfreeze).
	if walk_off_screen or warp_cooldown > 0 or (entities[1].get("frozen",false) and not scripted_move) or int(entities[1].get("disabled",0)): return
	var pos := _position2(1)
	for id in entities.keys():
		if id == 1 or not entities.has(id): continue
		var e: Dictionary = entities[id]
		if int(e.get("active",1)) == 0: continue
		if e.get("warp") != null and _hard_rect(e).grow(7).has_point(pos):
			# A delayed entrance cutscene can begin inside this doorway's trigger
			# after its cooldown expires. Let its move_stop walk into the room;
			# only motion approaching the door should activate a scripted exit.
			var center := _hard_rect(e).get_center()
			if scripted_move and from_position != Vector2.INF and pos.distance_squared_to(center) >= from_position.distance_squared_to(center):
				continue
			var warp: Dictionary = e.warp
			if world.screens.has(str(int(warp.get("map",0)))):
				vm.cancel_screen_tasks()
				entities[1].x = warp.x
				entities[1].y = warp.y
				load_map(int(warp.map))
				return
		if int(e.get("touch_damage",0)) == -1 and _hard_rect(e).grow(8).has_point(pos):
			if float(e.get("touch_cooldown",0)) <= 0:
				e["touch_cooldown"] = 1.0
				var before := generation
				_run_event(id,"touch")
				if generation != before: return
	var target := current_screen
	if pos.x < 20: target -= 1; pos.x = 608
	elif pos.x > 620: target += 1; pos.x = 32
	elif pos.y < 0: target -= 32; pos.y = 390
	elif pos.y > 400: target += 32; pos.y = 10
	if target != current_screen:
		if not locked and world.screens.has(str(target)):
			vm.cancel_screen_tasks()
			entities[1].x = pos.x
			entities[1].y = pos.y
			load_map(target)
		else:
			entities[1].x = clampf(float(entities[1].x),21,619)
			entities[1].y = clampf(float(entities[1].y),1,399)

func _run_event(id: int, event: String) -> void:
	if not entities.has(id): return
	var script := str(entities[id].get("script",""))
	if not script.is_empty() and not vm._procedure_code(script.to_lower(),event).is_empty():
		vm.run(script,event,id)

func _talk() -> void:
	if entities[1].get("frozen",false): return
	var nearest := 0
	var distance := 90.0
	var forward := _dir_vector(int(entities[1].get("dir",2)))
	for id in entities:
		if id == 1: continue
		var e: Dictionary = entities[id]
		if int(e.get("active",1)) == 0 or int(e.get("type",1)) != 1 or str(e.get("script","")).is_empty(): continue
		var offset := _position2(id)-_position2(1)
		if offset.length() < distance and (offset.normalized().dot(forward)>-0.2 or offset.length()<28):
			if vm._procedure_code(str(e.script).to_lower(),"talk").is_empty(): continue
			distance = offset.length()
			nearest = id
	if nearest:
		_run_event(nearest,"talk")
	else: ui.notify("Move closer and face someone or something to talk.")

func _attack() -> void:
	if attack_cooldown > 0 or entities[1].get("frozen",false) or int(entities[1].get("nocontrol",0)): return
	attack_cooldown = 0.45
	_set_animation(1,int(entities[1].get("base_attack",100))+_cardinal(int(entities[1].get("dir",2))))
	_play_sound(8)
	var equipped := int(vm.globals.get("cur_weapon",1))-1
	if equipped >= 0 and equipped < items.size():
		vm.run(items[equipped].script,"use",1)
		if str(items[equipped].script) not in ["item-fst","item-sw1","item-sw2","item-sw3"]: return
	var player: Dictionary = entities[1]
	var forward := _dir_vector(int(player.get("dir",2)))
	var reach := 48.0 if int(player.get("range",0)) <= 0 else float(player.get("range",40))+25.0
	for id in entities.keys():
		if id == 1 or not entities.has(id): continue
		var e: Dictionary = entities[id]
		if int(e.get("active",1)) == 0: continue
		if int(e.get("nohit",0)) != 0 and str(e.get("script","")).is_empty(): continue
		var offset := _position2(id)-_position2(1)
		if offset.length()<reach and (offset.length()<1 or offset.normalized().dot(forward)>-0.15):
			var can_damage: bool = int(e.get("nohit",0)) == 0
			vm.globals["enemy_sprite"] = 1
			vm.globals["missle_source"] = 1
			e["last_hit"] = 1
			if int(e.get("base_attack",-1)) != -1 or int(e.get("touch_damage",0)) > 0: e["target"] = 1
			_run_event(id,"hit")
			if can_damage:
				var strength := maxi(1,int(vm.globals.get("strength",3)))
				var blow := strength if strength == 1 else strength/2+randi_range(1,(strength+1)/2)
				_damage(id,blow)

func _damage(id: int, amount: int) -> void:
	if not entities.has(id): return
	var e: Dictionary = entities[id]
	var defense := int(vm.globals.get("defense",0)) if id == 1 else int(e.get("defense",0))
	var dealt := maxi(0,amount-defense)
	if amount > 0 and dealt == 0 and randi_range(0,1) == 1: dealt = 1
	if dealt <= 0: return
	_play_sound(9)
	if id == 1:
		if hurt_cooldown > 0: return
		hurt_cooldown = 0.65
		vm.globals.life = maxi(0,int(vm.globals.get("life",10))-dealt)
		if int(vm.globals.life) <= 0:
			ui._clear("The road is not over", "defeat")
			ui._label("Dink has fallen. Load your saved adventure or begin again.")
			ui._button("Load saved adventure","load")
			ui._button("Begin again","new_game")
			ui._focus()
		return
	var hp := int(e.get("hitpoints",0))
	if hp > 0 and not e.get("dead",false):
		e["hitpoints"] = hp-dealt
		if int(e.hitpoints) <= 0:
			e["dead"] = true
			vm.globals["exp"] = int(vm.globals.get("exp",0))+int(e.get("exp",0))
			var old_brain := int(e.get("brain",0))
			_run_event(id,"die")
			# A die procedure may deliberately take ownership of the body (the
			# final boss changes to brain 0/12). Otherwise play its death art.
			if entities.has(id) and int(e.get("brain",0)) == old_brain:
				var death_base := int(e.get("base_death",e.get("base_die",-1)))
				var death_dir := int(e.get("dir",2))
				if death_base < 0 and sequences.has(str(int(e.get("base_walk",0))+5)):
					death_base = int(e.get("base_walk",0))
					death_dir = 5
				var death_seq := death_base+death_dir
				if death_base >= 0 and not sequences.has(str(death_seq)):
					death_dir = int({1:9,3:7,7:3,9:1,4:6,6:4,8:2,2:8}.get(death_dir,death_dir))
					death_seq = death_base+death_dir
				if death_base >= 0 and sequences.has(str(death_seq)):
					e["nohit"] = 1
					e["touch_damage"] = 0
					e["brain"] = 5
					e["seq"] = death_seq
					e["frame"] = 1
					e["anim_time"] = 0.0
				else:
					e["active"] = 0
			_check_level()

func _check_level() -> void:
	if not entities.has(1) or entities[1].get("leveling",false): return
	var level := int(vm.globals.get("level",1))
	var required := mini(99999,100*level*level)
	if int(vm.globals.get("exp",0)) >= required:
		vm.globals["exp"] = int(vm.globals.exp)-required
		entities[1]["leveling"] = true
		await vm.run("lraise","raise",1)
		if entities.has(1): entities[1].erase("leveling")
		_check_level()

func _cast() -> void:
	if magic_items.is_empty():
		ui.notify("No magic equipped yet. Seek a teacher on your travels.")
		return
	var idx := int(vm.globals.get("cur_magic",0))-1
	if idx < 0 or idx >= magic_items.size():
		ui.notify("Choose a spell from Equipment first.")
		return
	var cost := maxi(0,int(vm.globals.get("magic_cost",0)))
	if cost <= 0 or int(vm.globals.get("magic_level",0)) < cost:
		ui.notify("Your magic is still recharging.")
		return
	vm.run(magic_items[idx].script,"use",1)

func _update_ai(delta: float) -> void:
	for id in entities.keys():
		if not entities.has(id) or id == 1: continue
		var e: Dictionary = entities[id]
		e["touch_cooldown"] = maxf(0,float(e.get("touch_cooldown",0))-delta)
		if int(e.get("active",1)) == 0 or int(e.get("disabled",0)) or e.get("frozen",false) or e.has("moving"): continue
		var brain := int(e.get("brain",0))
		var follow_id := int(e.get("follow",0))
		if follow_id > 0 and entities.has(follow_id) and int(entities[follow_id].get("active",1)) != 0:
			var follow_offset := _position2(follow_id)-_position2(id)
			if follow_offset.length() >= 40.0:
				e["dir"] = _direction(follow_offset)
				_move_entity(id,follow_offset.normalized()*float(e.get("speed",1))*25.0*delta)
				_set_animation(id,int(e.get("base_walk",0))+int(e.get("dir",2)))
			continue
		if brain in [9,10,16,3,4]:
			var target_id := int(e.get("target",0))
			if target_id != 0 and (not entities.has(target_id) or int(entities[target_id].get("active",1)) == 0):
				target_id = 0
				e["target"] = 0
			var target := _position2(target_id)-_position2(id) if target_id != 0 else Vector2.ZERO
			var enemy := brain in [9,10]
			e["ai_time"] = float(e.get("ai_time",0))-delta
			if float(e.ai_time) <= 0:
				e["ai_time"] = randf_range(1.0,3.0)
				e["dir"] = [1,2,3,4,6,7,8,9].pick_random()
			var vec := target.normalized() if enemy and target_id != 0 else _dir_vector(int(e.get("dir",2)))
			if enemy and target_id != 0 and vec != Vector2.ZERO: e["dir"] = _direction(vec)
			_move_entity(id,vec*float(e.get("speed",1))*25.0*delta)
			entities[id].x = clampf(float(entities[id].x),30,610)
			entities[id].y = clampf(float(entities[id].y),10,390)
			_set_animation(id,int(e.get("base_walk",0))+int(e.get("dir",2)))
			# Brain 9 attacks at close range; brain 10 attack procedures are
			# ranged (dragons and the final boss). DinkC stores the next delay in
			# sp_attack_wait, in milliseconds.
			e["ai_attack_time"] = maxf(0.0,float(e.get("ai_attack_time",0.0))-delta)
			var should_attack := target_id != 0 and ((brain == 10) or (brain == 9 and target.length()<maxf(25.0,float(e.get("distance",5)))))
			if should_attack and float(e.ai_attack_time) <= 0 and not vm._procedure_code(str(e.get("script","")).to_lower(),"attack").is_empty():
				_run_event(id,"attack")
				e["ai_attack_time"] = maxf(0.15,float(e.get("attack_wait",1000))/1000.0)
			if int(e.get("touch_damage",0)) > 0 and _hard_rect(e).grow(4).has_point(_position2(1)) and float(e.get("touch_cooldown",0)) <= 0:
				e["touch_cooldown"] = 0.4
				vm.globals["enemy_sprite"] = id
				entities[1]["last_hit"] = id
				_run_event(id,"touch")
				_damage(1,int(e.get("touch_damage",0)))
		if brain in [11,17]:
			var velocity := Vector2(float(e.get("mx",0)),float(e.get("my",0)))
			if velocity == Vector2.ZERO: velocity = _dir_vector(int(e.get("dir",2)))*float(e.get("speed",6))
			var next_pos := _position2(id)+velocity*delta*30.0
			# Dynamic hard sprites are resolved below so their HIT procedure receives
			# the correct missile_target. Only the tile map is an anonymous impact.
			if brain == 11 and _tile_blocked(next_pos):
				vm.globals["missile_target"] = 0
				vm.globals["missle_source"] = id
				if vm._procedure_code(str(e.get("script","")).to_lower(),"damage").is_empty(): e["active"] = 0
				else: _run_event(id,"damage")
				continue
			_move_entity(id,velocity*delta*30,true)
			e["age"] = float(e.get("age",0))+delta
			if float(e.age)>5: e["active"] = 0
			if brain == 17 and e.get("exploded",false): continue
			if brain == 17: e["exploded"] = true
			for target in entities.keys():
				if target == id or not entities.has(target): continue
				var victim: Dictionary = entities[target]
				if int(victim.get("active",1)) == 0 or target == int(e.get("brain_parm",0)) or target == int(e.get("brain_parm2",0)): continue
				if int(victim.get("nohit",0)) != 0 and str(victim.get("script","")).is_empty(): continue
				var blast_range := float(e.get("range",0))+12.0 if brain == 17 else 12.0
				if _hard_rect(victim).grow(blast_range).has_point(_position2(id)):
					var can_damage: bool = int(victim.get("nohit",0)) == 0 and (int(target) == 1 or int(victim.get("hitpoints",0)) > 0)
					vm.globals["missile_target"] = target
					vm.globals["missle_source"] = id
					vm.globals["enemy_sprite"] = int(e.get("brain_parm",1))
					victim["last_hit"] = int(e.get("brain_parm",1))
					if int(victim.get("base_attack",-1)) != -1 or int(victim.get("touch_damage",0)) > 0: victim["target"] = int(e.get("brain_parm",1))
					if not vm._procedure_code(str(e.get("script","")).to_lower(),"damage").is_empty(): _run_event(id,"damage")
					elif brain == 11: e["active"] = 0
					_run_event(target,"hit")
					if can_damage:
						var strength := maxi(1,int(e.get("strength",1)))
						var shot := strength if strength == 1 else strength/2+randi_range(1,maxi(1,strength/2))
						_damage(target,shot)
					if brain == 11: break

func _interpolate(value: Variant, context: Dictionary) -> String:
	var result := str(value)
	var regex := RegEx.new()
	regex.compile("&[A-Za-z_][A-Za-z0-9_-]*")
	var matches := regex.search_all(result)
	for i in range(matches.size()-1,-1,-1):
		var found: RegExMatch = matches[i]
		var name := found.get_string().substr(1)
		var val: Variant = context.get("locals",{}).get(name,vm.globals.get(name,0))
		if name == "current_sprite": val = context.get("sprite_id",0)
		result = result.substr(0,found.get_start())+str(val)+result.substr(found.get_end())
	regex.compile("`.")
	return regex.sub(result,"",true)

func _dialogue(text: String, speaker: int, context: Dictionary) -> void:
	var expected := generation
	while dialogue_busy and expected == generation:
		await get_tree().process_frame
	if expected != generation: return
	dialogue_busy = true
	var line := _interpolate(text,context)
	dialogue_log.append(line)
	if dialogue_log.size()>100: dialogue_log.pop_front()
	if test_mode:
		await get_tree().process_frame
	else:
		ui.show_dialogue(line,"Dink" if speaker == 1 else "Conversation")
		await ui.dialogue_finished
	dialogue_busy = false

func _script_move(id: int, dir: int, destination: float, speed: float) -> void:
	if not entities.has(id): return
	var expected := generation
	var e: Dictionary = entities[id]
	var token := int(e.get("move_token",0))+1
	e["move_token"] = token
	e["moving"] = true
	e["dir"] = dir
	var axis := "y" if dir in [2,8] else "x"
	var elapsed := 0.0
	while entities.has(id) and generation == expected and int(e.move_token) == token:
		var gap := destination-float(e.get(axis,0))
		if absf(gap)<1: break
		await get_tree().physics_frame
		if ui.modal and not ui.dialogue_mode: continue
		var delta := get_physics_process_delta_time()
		elapsed += delta
		if elapsed>60: break
		var old_value := float(e.get(axis,0))
		var from_position := _position2(id)
		e[axis] = move_toward(old_value,destination,maxf(1,speed)*25*delta)
		if dir in [1,3,7,9]:
			e["y"] = float(e.get("y",0))+absf(float(e[axis])-old_value)*(1 if dir in [1,3] else -1)
		_set_animation(id,int(e.get("base_walk",0))+dir)
		if id == 1:
			_transitions(true, from_position)
	if generation == expected and entities.has(id) and int(e.move_token) == token:
		e.erase("moving")
		e["seq"] = 0

func dink_call(command: String, args: Array, context: Dictionary) -> Variant:
	var cmd := command.to_lower()
	var a: Variant = args[0] if args.size()>0 else 0
	var b: Variant = args[1] if args.size()>1 else 0
	var c: Variant = args[2] if args.size()>2 else 0
	var d: Variant = args[3] if args.size()>3 else 0
	var sid := int(context.get("sprite_id",0))
	if cmd.begins_with("sp_") and cmd not in ["sp_kill","sp_kill_wait","sp_script","sp_prop"]:
		var id := int(a)
		if not entities.has(id): return 0
		var key := cmd.substr(3)
		if key == "editor_num": return int(entities[id].get("editor_num",0))
		# Unlike ordinary sprite-property queries, touch damage -1 enables the
		# script's touch procedure. Runtime pickups such as S1-NUT require it.
		if args.size()>1 and (int(b) != -1 or cmd == "sp_touch_damage"):
			entities[id][key] = b
			if key == "seq":
				entities[id]["frame"] = 1
				entities[id]["anim_time"] = 0.0
		return entities[id].get(key,0)
	match cmd:
		"make_global_int":
			var name := str(a).trim_prefix("&")
			vm.globals[name] = b
			return vm.globals[name]
		"random": return randi_range(0,maxi(0,int(a)-1))+int(b)
		"wait":
			await get_tree().create_timer(maxf(0.001,float(a)/1000.0)).timeout
		"freeze", "freeeze", "unfreeze", "unfreeeze":
			if entities.has(int(a)): entities[int(a)]["frozen"] = cmd in ["freeze","freeeze"]
		"say_stop", "say_stop_npc", "say_stop_xy":
			await _dialogue(str(a),int(b) if cmd != "say_stop_xy" else 0,context)
		"say", "say_xy":
			var line := _interpolate(a,context)
			ui.notify(line)
			dialogue_log.append(line)
			return 0
		"choice":
			var options: Array = b if b is Array else []
			if options.is_empty(): return 0
			if test_mode: return options[0].get("value",1)
			var labels: Array = []
			for option in options: labels.append(_interpolate(option.text,context))
			ui.show_choices(_interpolate(a,context),labels)
			var choice: int = await ui.dialogue_finished
			return options[clampi(choice-1,0,options.size()-1)].get("value",choice)
		"create_sprite":
			var id := next_entity
			next_entity += 1
			entities[id] = {"x":float(a),"y":float(b),"brain":int(c),"pseq":int(d),"pframe":int(args[4]) if args.size()>4 else 1,"seq":0,"frame":1,"active":1,"hard":1,"size":100,"speed":1,"dir":2,"anim_time":0.0,"script":"","editor_num":0}
			if int(c) in [5,6,7]: entities[id]["seq"] = int(d)
			_create_visual(id)
			return id
		"sp_script":
			if args.size()<2 or str(b) == "-1": return str(entities.get(int(a),{}).get("script",""))
			if entities.has(int(a)):
				entities[int(a)]["script"] = str(b).to_lower()
				if not vm._procedure_code(str(b).to_lower(),"main").is_empty(): vm.run(str(b),"main",int(a))
		"sp":
			for id in entities:
				if int(entities[id].get("editor_num",0)) == int(a): return id
			return 0
		"move", "move_stop":
			if cmd == "move_stop": await _script_move(int(a),int(b),float(c),float(d))
			else: _script_move(int(a),int(b),float(c),float(d))
		"external": return await vm.run(str(a),str(b),sid)
		"spawn", "load":
			var id := next_entity
			next_entity += 1
			entities[id] = {"x":0,"y":0,"active":0,"script":str(a),"editor_num":0}
			vm.run(str(a),"main",id)
			return id
		"run_script_by_number":
			if entities.has(int(a)): return await vm.run(str(entities[int(a)].get("script","")),str(b),int(a))
		"script_attach": pass # Cooperative tasks already retain their context across awaits.
		"screenlock": locked = bool(a)
		"load_screen":
			vm.cancel_screen_tasks(int(context.get("task_id",0)))
			load_map(int(vm.globals.get("player_map",current_screen)))
		"force_vision":
			vm.globals["vision"] = int(a)
			load_map(current_screen)
		"editor_type", "editor_seq", "editor_frame":
			var key := "%d:%d" % [current_screen,int(a)]
			var property: String = {"editor_type":"editor_type","editor_seq":"seq","editor_frame":"frame"}[cmd]
			if not editor_state.has(key): editor_state[key] = {}
			if args.size()>1 and int(b) != -1:
				editor_state[key][property] = b
				if cmd == "editor_type":
					editor_state[key]["removed"] = int(b) == 1
					if int(b) in [6,7,8]: editor_state[key]["return_at"] = Time.get_unix_time_from_system()+{6:300,7:180,8:60}[int(b)]
			return editor_state[key].get(property,0)
		"get_sprite_with_this_brain", "get_rand_sprite_with_this_brain":
			var found: Array = []
			for id in entities:
				if id != int(b) and int(entities[id].get("brain",0)) == int(a) and int(entities[id].get("active",1)) != 0: found.append(id)
			return 0 if found.is_empty() else (found.pick_random() if cmd.begins_with("get_rand") else found[0])
		"compare_sprite_script": return int(entities.has(int(a)) and str(entities[int(a)].get("script","")).to_lower() == str(b).to_lower())
		"is_script_attached":
			if a is int or a is float:
				return int(a) if entities.has(int(a)) and not str(entities[int(a)].get("script","")).is_empty() else 0
			for id in entities:
				if str(entities[id].get("script","")).to_lower() == str(a).to_lower(): return id
			return 0
		"inside_box": return int(Rect2(float(c),float(d),float(args[4])-float(c),float(args[5])-float(d)).has_point(Vector2(float(a),float(b)))) if args.size()>=6 else 0
		"add_item", "add_magic":
			var list: Array = items if cmd == "add_item" else magic_items
			if list.size()>=16: return 0
			list.append({"script":str(a).to_lower(),"name":_item_name(str(a)),"seq":int(b),"frame":int(c)})
			return 1
		"count_item", "count_magic":
			var count := 0
			for item in (items if cmd == "count_item" else magic_items):
				if str(item.script).to_lower() == str(a).to_lower(): count += 1
			return count
		"free_items": return 16-items.size()
		"free_magic": return 16-magic_items.size()
		"compare_weapon":
			var idx := int(vm.globals.get("cur_weapon",0))-1
			return int(idx>=0 and idx<items.size() and str(items[idx].script).to_lower() == str(a).to_lower())
		"kill_this_item", "kill_cur_item":
			var script := str(a) if cmd == "kill_this_item" else str(context.get("script",""))
			for i in range(items.size()-1,-1,-1):
				if str(items[i].script).to_lower() == script.to_lower():
					items.remove_at(i)
					break
			vm.globals["cur_weapon"] = mini(int(vm.globals.get("cur_weapon",1)),items.size())
		"arm_weapon": await _equip(int(vm.globals.get("cur_weapon",1))-1,false)
		"set_dink_speed":
			if entities.has(1): entities[1]["speed"] = int(a)
		"hurt":
			_damage(int(a),int(b))
			return b
		"add_exp":
			vm.globals["exp"] = int(vm.globals.get("exp",0))+int(a)
			_check_level()
		"attack": _attack()
		"load_sound":
			sound_slots[str(int(b))] = "res://assets/sound/"+str(a).get_file().to_lower()
		"playsound": return _play_sound(int(a),float(b)/22050.0 if float(b)>0 else 1.0)
		"playmidi": _play_music(str(a))
		"stopmidi", "stopcd": music.stop()
		"save_game": return int(_save_game())
		"load_game": return int(_load_game())
		"game_exist": return int(FileAccess.file_exists("user://adventure.json"))
		"restart_game": _new_game.call_deferred()
		"kill_game": get_tree().quit()
		"set_mode": playing = int(a) == 2
		"show_bmp":
			var filename := str(a).get_file().get_basename().to_lower()
			var texture := _texture("res://assets/tiles/"+filename+".png")
			if texture != null and not test_mode:
				ui._clear("World map","map")
				var picture := TextureRect.new()
				picture.texture = texture
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				picture.custom_minimum_size = Vector2(580,400)
				ui.column.add_child(picture)
				ui._button("Return to adventure","resume")
				ui._focus()
		"stop_entire_game": pass # Modal level-up dialogue already suspends player input/AI.
		"get_version": return 108
		"activate_bow":
			await get_tree().create_timer(0.3).timeout
		"get_last_bow_power": return 100
		"get_burn": return int(vm.globals.get("burn",0))
		"scripts_used": return vm._live_tasks.size()
		"set_callback_random": _callback(str(a),int(b),int(c),context.duplicate())
		"sp_kill": _kill_after(int(a),float(b))
		"sp_prop":
			# Legacy campaign door toggle; modern sprite state uses active.
			if entities.has(int(a)): entities[int(a)]["active"] = int(b)
		"sp_kill_wait":
			if entities.has(int(a)): entities[int(a)]["anim_time"] = 0.0
		"dink_can_walk_off_screen": walk_off_screen = bool(a)
		"fade_down", "fade_up":
			if not test_mode and not settings.reduced_motion: await get_tree().create_timer(0.15).timeout
		"init": _init_sequence(str(a))
		"fill_screen", "preload_seq", "draw_screen", "draw_status", "draw_hard_sprite", "draw_hard_map", "kill_shadow", "set_y", "set_title_color", "reset_timer", "set_button", "debug", "kill_this_task": pass
		_:
			if not unknown.has(cmd):
				unknown[cmd] = context.get("script","")
				push_warning("Unimplemented Dink command: %s (%s)" % [cmd,context.get("script","")])
	return 0

func _callback(procedure: String, minimum: int, maximum: int, context: Dictionary) -> void:
	var expected := generation
	await get_tree().create_timer(maxf(0.01,float(randi_range(minimum,maxi(minimum,maximum)))/1000)).timeout
	if expected == generation:
		vm.run(str(context.script),procedure,int(context.sprite_id))

func _kill_after(id: int, milliseconds: float) -> void:
	var expected := generation
	await get_tree().create_timer(maxf(0.001,milliseconds/1000.0)).timeout
	if generation == expected and entities.has(id): entities[id]["active"] = 0

func _init_sequence(line: String) -> void:
	# Animation remaps supplied by weapon scripts use already imported frame paths.
	var tokens := line.replace("\\","/").split(" ",false)
	if tokens.size()<3 or not tokens[0].to_lower().begins_with("load_sequence"): return
	var prefix := tokens[1].to_lower()
	var frames: Array = []
	var available: Array = asset_frames
	if available.is_empty():
		for sequence in original_sequences.values(): available.append_array(sequence.get("frames",[]))
	for frame in available:
		var record: Dictionary = frame if frame is Dictionary else {"path":str(frame)}
		var path := str(record.get("path","")).to_lower()
		if path.contains(prefix) and not frames.any(func(f): return f.path == record.path): frames.append(record.duplicate(true))
	frames.sort_custom(func(a,b): return str(a.path).naturalnocasecmp_to(str(b.path))<0)
	if frames.is_empty(): return
	for frame in frames:
		if tokens.size()>3: frame["delay"] = int(tokens[3])
		if tokens.size()>5:
			frame["dx"] = int(tokens[4]); frame["dy"] = int(tokens[5])
		if tokens.size()>9: frame["hardbox"] = [int(tokens[6]),int(tokens[7]),int(tokens[8]),int(tokens[9])]
	sequences[str(int(tokens[2]))] = {"frames":frames,"delay":int(tokens[3]) if tokens.size()>3 else 100}

func _item_name(script: String) -> String:
	return {"item-fst":"Fists","item-sw1":"Sword","item-sw2":"Clawsword","item-sw3":"Light sword","item-b1":"Bow","item-b2":"Longbow","item-b3":"Massive bow","item-axe":"Throwing axe","item-pig":"Pig feed","item-nut":"Nut","item-bom":"Bomb","item-fb":"Fireball","item-acd":"Acid rain","item-ice":"Ice ball","item-hel":"Healing"}.get(script.to_lower(),script.trim_prefix("item-").capitalize())

func _equip(index: int, magic: bool) -> void:
	var list: Array = magic_items if magic else items
	if index<0 or index>=list.size(): return
	var variable := "cur_magic" if magic else "cur_weapon"
	var previous := int(vm.globals.get(variable,0))-1
	if previous>=0 and previous<list.size():
		var old := str(list[previous].script)
		if not vm._procedure_code(old,"disarm").is_empty(): await vm.run(old,"disarm",1)
	vm.globals[variable] = index+1
	var script := str(list[index].script)
	if not vm._procedure_code(script,"arm").is_empty(): await vm.run(script,"arm",1)
	ui.close_menu()
	ui.notify("Equipped "+_item_name(script))

func _load_sound_slots() -> void:
	# Start.c establishes the original numbered sound registry.
	if not vm._procedure_code("start","main").is_empty():
		var code: Array = vm._procedure_code("start","main")
		for op in code:
			if op.get("op","") == "call" and str(op.get("name","")).to_lower() == "load_sound":
				var args: Array = op.get("args",[])
				if args.size()>=2: sound_slots[str(int(args[1].get("value",0)))] = "res://assets/sound/"+str(args[0].get("value","")).to_lower()

func _play_sound(slot: int, pitch: float = 1.0) -> int:
	var path := str(sound_slots.get(str(slot),""))
	if path.is_empty() or not ResourceLoader.exists(path): return 0
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = linear_to_db(maxf(0.0001,float(settings.sfx)))
	player.pitch_scale = clampf(pitch,0.2,4)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player.get_instance_id()

# Music ids above 1000 are CD-track cues, and the original engine has no CD: it
# plays "<id-1000>.mid" instead (GNU FreeDink 109.6, game_engine.cpp:334-339 for a
# screen's music; dinkc_bindings.cpp:1264-1278 for playmidi, which plays the
# mapped track and then the name as written, so the name as written wins when
# that file exists, as START.c's playmidi("1003.mid") relies on). A cue with no
# file is left silent and the current track keeps playing (bgm.cpp:137-142).
static func music_candidates(track: String, screen := false) -> Array[String]:
	var stem := track.get_file().get_basename().to_lower()
	var out: Array[String] = []
	if stem == "0" or stem.is_empty(): return out
	if stem.is_valid_int() and int(stem) > 1000:
		var cd_track := str(int(stem)-1000)
		if screen: out.append(cd_track)
		else: out.append_array([stem, cd_track])
	else:
		out.append(stem)
	return out

func _play_music(track: String, screen := false) -> void:
	for stem in music_candidates(track, screen):
		for ext in ["ogg","wav"]:
			var path: String = "res://assets/sound/"+stem+"."+ext
			if not ResourceLoader.exists(path): continue
			if stem == last_music and music.playing: return
			music.stream = load(path)
			if music.stream is AudioStreamOggVorbis: music.stream.loop = true
			music.play()
			last_music = stem
			return

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,float(settings.master))))
	if is_instance_valid(music): music.volume_db = linear_to_db(maxf(0.0001,float(settings.music)))
	if is_instance_valid(camera):
		var angle := deg_to_rad(float(settings.camera_angle))
		camera.position = Vector3(0,sin(angle)*25,cos(angle)*25)
		camera.look_at(Vector3.ZERO)
	if is_instance_valid(ui) and is_instance_valid(ui.root): ui.set_text_scale(float(settings.text_scale))

func _location() -> String:
	return "Screen %d • %d places explored" % [current_screen,visited.size()]

func _ui_action(action: String, payload: Variant) -> void:
	match action:
		"new_game": _new_game()
		"continue", "load": _load_game()
		"resume":
			if playing: ui.close_menu()
			else: ui.show_title(FileAccess.file_exists("user://adventure.json"))
		"save":
			if _save_game(): ui.notify("Adventure saved.")
			else: ui.notify("Could not save the adventure.")
		"pause": ui.show_pause()
		"inventory": ui.show_inventory(items,magic_items)
		"map": _open_world_map()
		"settings": ui.show_settings(settings)
		"credits": ui.show_credits()
		"back":
			if playing: ui.show_pause()
			else: ui.show_title(FileAccess.file_exists("user://adventure.json"))
		"journal": ui.show_journal("%s\n\nRecent conversations\n\n%s" % [_location(),"\n\n".join(dialogue_log.slice(maxi(0,dialogue_log.size()-20)))])
		"equip": _equip(int(payload),false)
		"equip_magic": _equip(int(payload),true)
		"setting":
			settings[payload.key] = payload.value
			_apply_settings()
			_write_json("user://settings.json",settings)
		"title":
			vm.cancel_all()
			playing = false
			ui.show_title(FileAccess.file_exists("user://adventure.json"))
		"patreon": OS.shell_open("https://www.patreon.com/PilferedParrot")
		"source": OS.shell_open("https://github.com/PilferedParrot/dink-smallwood-3d")
		"quit": get_tree().quit()

func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path+".tmp",path) == OK

func _save_game(path: String = "user://adventure.json") -> bool:
	if not playing or dialogue_busy or entities[1].get("frozen",false): return false
	return _write_json(path,{"version":1,"vm":vm.snapshot_state(),"screen":current_screen,"entities":entities,"editor_state":editor_state,"items":items,"magic_items":magic_items,"visited":visited,"dialogue_log":dialogue_log,"next_entity":next_entity,"locked":locked})

func _load_game(path: String = "user://adventure.json") -> bool:
	var data := _read_json(path)
	if int(data.get("version",0)) != 1 or not world.screens.has(str(int(data.get("screen",0)))) or not data.get("entities",{}).has("1"):
		ui.notify("No compatible saved adventure found.")
		return false
	vm.cancel_all()
	vm.restore_state(data.get("vm",{}))
	editor_state = data.get("editor_state",{})
	items = data.get("items",[])
	magic_items = data.get("magic_items",[])
	visited = data.get("visited",[])
	dialogue_log = data.get("dialogue_log",[])
	entities[1] = data.entities["1"]
	load_map(int(data.screen),false)
	for visual in visuals.values(): visual.queue_free()
	visuals.clear()
	entities.clear()
	for key in data.entities:
		entities[int(key)] = data.entities[key]
		entities[int(key)].erase("moving")
		_create_visual(int(key))
	next_entity = int(data.get("next_entity",next_entity))
	locked = bool(data.get("locked",false))
	walk_off_screen = false
	playing = true
	dialogue_busy = false
	ui.close_menu()
	var idx := int(vm.globals.get("cur_weapon",0))-1
	if idx>=0 and idx<items.size():
		# Arm remaps animation and adds equipment stats. Restore saved stats after
		# remapping so loading cannot repeatedly grant the sword's strength bonus.
		var saved_globals: Dictionary = vm.globals.duplicate(true)
		if not vm._procedure_code(str(items[idx].script),"arm").is_empty(): vm.run(str(items[idx].script),"arm",1)
		vm.globals = saved_globals
	return true

func _smoke_test() -> void:
	await get_tree().process_frame
	var failures: Array = []
	if world.screens.size()<600: failures.append("World import incomplete")
	if sequences.size()<400: failures.append("Animation import incomplete")
	await _new_game()
	await get_tree().create_timer(2.0).timeout
	if int(vm.globals.get("life",0)) != 10: failures.append("New game globals")
	if not visuals.has(1) or visuals[1].texture == null: failures.append("Player animation")
	if not _save_game("user://smoke-save.json"): failures.append("Save")
	vm.globals.gold = 999
	if not _load_game("user://smoke-save.json"): failures.append("Load")
	if int(vm.globals.gold) != 0: failures.append("Restored stats")
	if not entities.has(1): failures.append("Restored player")
	DirAccess.remove_absolute("user://smoke-save.json")
	if failures.is_empty():
		print("SMOKE PASS: imported world, player, globals, save/load")
	else:
		for failure in failures: push_error("SMOKE FAIL: "+str(failure))
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(path: String) -> void:
	await _new_game()
	await get_tree().create_timer(2.0).timeout
	vm.cancel_all()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			load_map(int(arg.trim_prefix("--screen=")),false)
			entities[1].x = 365.0
			entities[1].y = 307.0
			_update_visual(1)
	ui.show_hud(vm.globals.merged({"location":_location()}))
	playing = false
	ui.close_menu()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _capture_title(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
