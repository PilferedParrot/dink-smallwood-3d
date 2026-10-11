extends SceneTree
# Headless source-prism and real FPS talk/ray class gate. load_map(n,false)
# skips campaign progression while constructing the production visual/input path.

const GAME := preload("res://scripts/fps_game.gd")
const MOUNTED := preload("res://scripts/mounted_posters.gd")
var failures: Array[String] = []
var game

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func near(a: float, b: float, label: String, tolerance := 0.0001) -> void:
	check(absf(a-b) <= tolerance, "%s: %.6f vs %.6f" % [label,a,b])

func _model_box(model: Node3D) -> AABB:
	var first := true
	var bounds := AABB()
	for child in model.get_children():
		if not child is MeshInstance3D: continue
		var mesh: MeshInstance3D = child
		var box: AABB = mesh.get_aabb()
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					var p: Vector3 = mesh.transform * Vector3(x,y,z)
					if first:
						bounds = AABB(p,Vector3.ZERO)
						first = false
					else: bounds = bounds.expand(p)
	return bounds

func _wall_class() -> void:
	var rooms := 0
	var walls := 0
	var clamped := 0
	for key in game.world.screens:
		var n := int(key)
		if not bool(game.world.screens[key].get("indoor",false)): continue
		if not game.fp_world.solids.walls_fitted(n): continue
		var found := false
		for e in game.world.screens[key].get("sprites",[]):
			var path: String = game.fp_world.frame_path(e)
			var fit: Dictionary = game.fp_world.solids.fit_of(path)
			if str(fit.get("kind","")) != "wall": continue
			found = true
			var prism: Dictionary = game.fp_world.solids.wall_prism(e,fit,n)
			var rect: Rect2 = prism["rect"]
			var original: Rect2 = game.fp_world.hard_rect(e)
			if rect.end.y < original.end.y - 0.001: clamped += 1
			check(rect.position == original.position and rect.end.y <= original.end.y + 0.0001,
				"%d wall %d source hardness untouched, ray prism clipped" % [n,int(e.get("index",0))])
			var node := Node3D.new()
			game.fp_world.solids.add_entity(node,e,999,true,n)
			var model := node.get_node_or_null("Model") as Node3D
			var body := node.get_node_or_null("HitBody") as StaticBody3D
			check(model != null and body != null,"%d wall %d built model and body" % [n,int(e.get("index",0))])
			if model == null or body == null: continue
			var shape := body.get_child(0) as CollisionShape3D
			var box := shape.shape as BoxShape3D
			var visual := _model_box(model)
			var collision := AABB(shape.position-box.size*0.5,box.size)
			for axis in 3:
				near(float(visual.position[axis]),float(collision.position[axis]),
					"%d wall %d axis%d min" % [n,int(e.get("index",0)),axis])
				near(float(visual.end[axis]),float(collision.end[axis]),
					"%d wall %d axis%d max" % [n,int(e.get("index",0)),axis])
			walls += 1
			node.free()
		if found: rooms += 1
	check(rooms > 0 and walls > 0 and clamped > 0,"all fitted rooms inspected, at least one source-front clamp")
	print("POSTER WALL PRISMS rooms=",rooms," walls=",walls," clipped=",clamped)

func _find_poster() -> int:
	for id in game.entities:
		if int(id) == 1: continue
		var e: Dictionary = game.entities[id]
		if game.fp_world.frame_path(e).begins_with("assets/graphics/inner/poster"):
			return int(id)
	return 0

func _poster_projection(sp: Sprite3D, e: Dictionary, n: int) -> void:
	var frame: Dictionary = game._frame(int(e.get("pseq",0)),int(e.get("pframe",1)))
	var source_x := float(e.get("x",0))-float(frame.get("dx",0))
	var source_y := float(e.get("y",0))-float(frame.get("dy",0))
	var quad: AABB = sp.get_aabb()
	var upper_left: Vector3 = sp.global_transform * Vector3(quad.position.x,quad.end.y,quad.position.z)
	var lower_right: Vector3 = sp.global_transform * Vector3(quad.end.x,quad.position.y,quad.position.z)
	near(320.0+upper_left.x/0.025,source_x,"%d mounted poster left projection" % n,0.8)
	near(320.0+lower_right.x/0.025,source_x+float(frame.get("width",sp.texture.get_width())),
		"%d mounted poster right projection" % n,0.8)
	near(200.0+(upper_left.z-upper_left.y)/0.025,source_y,
		"%d mounted poster top projection" % n,0.8)
	near(200.0+(lower_right.z-lower_right.y)/0.025,source_y+float(sp.texture.get_height()),
		"%d mounted poster bottom projection" % n,0.8)

func _direct_mount_class() -> void:
	game.load_map(33,false)
	await process_frame
	var id := _find_poster()
	check(id != 0,"direct constructor has live raw poster")
	if id == 0: return
	var e: Dictionary = game.entities[id]
	var path: String = game.fp_world.frame_path(e)
	var texture: Texture2D = game.fp_world.clean_texture(path)
	var d: Dictionary = game._frame(int(e.get("pseq",0)),int(e.get("pframe",1)))
	var node := Node3D.new()
	node.position = game.fp_world.point(float(e.get("x",0)),float(e.get("y",0)))
	game.scene_root.add_child(node)
	var sp := Sprite3D.new()
	sp.pixel_size = 0.025
	game.fp_world.set_sprite_texture(sp,path,texture,d)
	var mounted = MOUNTED.new(game.fp_world)
	check(mounted.add(node,sp,e,id,33,true),"direct shared poster constructor")
	var support: Dictionary = node.get_meta("mounted_poster",{})
	check(not support.is_empty(),"direct constructor reports source wall support")
	if not support.is_empty():
		var body := node.get_node_or_null("HitBody") as StaticBody3D
		check(body != null,"direct constructor supplies own ray body")
		_poster_projection(sp,e,33)
		var old: Node3D = game.visuals[id]
		var old_body := old.get_node_or_null("HitBody") as StaticBody3D
		if old_body != null: old_body.collision_layer = 0
		old.visible = false
		game.visuals[id] = node
		await physics_frame
		var witnessed := false
		for distance in [25.0,35.0,45.0,55.0,65.0]:
			var p := Vector2(float(e.get("x",0)),float(support["front_source_y"])+distance)
			if game._blocked(p,1): continue
			game.entities[1]["x"] = p.x
			game.entities[1]["y"] = p.y
			game.fps_yaw = 0.0
			game.fps_pitch = 0.0
			game._sync_fps_camera()
			if game._fps_ray_reaches(id):
				witnessed = true
				break
		check(witnessed,"direct mounted card wins own native ray before fitted wall")
		game.visuals[id] = old
	node.queue_free()

func _poster_class() -> void:
	for n in [33,35,195,225,226]:
		game.vm.cancel_all()
		game.load_map(n,false)
		await process_frame
		await physics_frame
		var id := _find_poster()
		check(id != 0,"%d source poster loaded" % n)
		if id == 0: continue
		var e: Dictionary = game.entities[id]
		var direct = MOUNTED.new(game.fp_world)
		var derived: Dictionary = direct.mount(e,n)
		check(not derived.is_empty(),"%d original source rectangle fits one wall front" % n)
		var node: Node3D = game.visuals.get(id)
		var support: Dictionary = node.get_meta("mounted_poster",{})
		check(not support.is_empty(),"%d production poster mount" % n)
		if support.is_empty(): continue
		var front := float(support.get("front_source_y",-1))
		near(front,100.0,"%d fitted wall front" % n)
		var sp := node.get_node_or_null("Model") as Sprite3D
		var body := node.get_node_or_null("HitBody") as StaticBody3D
		check(sp != null and body != null,"%d own mounted card and ray body" % n)
		if sp == null or body == null: continue
		check(sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED,"%d fixed +Z poster plane" % n)
		var shape := body.get_child(0) as CollisionShape3D
		var box := shape.shape as BoxShape3D
		near(box.size.z,sp.pixel_size,"%d source-pixel ray thickness" % n)
		_poster_projection(sp,e,n)
		var source_y := INF
		for raw in game.world.screens[str(n)]["sprites"]:
			if int(raw.get("index",0)) == int(e.get("editor_num",0)):
				source_y = float(raw.get("y",0))
				break
		near(float(e.get("y",0)),source_y,"%d source hotspot unchanged" % n)
		if n == 33:
			check(game._blocked(Vector2(340,104),1),
				"source wall movement hardness remains through original 107px hardbox")
		var winner := Vector2.INF
		var target := Vector2(float(e.get("x",0)),front)
		for distance in [25.0,35.0,45.0,55.0,65.0,75.0]:
			if winner != Vector2.INF: break
			for offset in [0.0,-10.0,10.0,-20.0,20.0]:
				var p := Vector2(target.x+offset,target.y+distance)
				if game._blocked(p,1) or not game._fps_line_clear(p,target): continue
				game.entities[1]["x"] = p.x
				game.entities[1]["y"] = p.y
				game.fps_yaw = atan2(-(target.x-p.x),-(target.y-p.y))
				game.fps_pitch = 0.0
				game._sync_fps_camera()
				if game._fps_ray_reaches(id):
					winner = p
					break
		check(winner != Vector2.INF,"%d source-clear south-side own-body ray witness" % n)
		if winner == Vector2.INF: continue
		var before: int = game.dialogue_log.size()
		game.entities[1]["frozen"] = false
		game._talk()
		for _i in 8: await process_frame
		check(game.dialogue_log.size() > before,"%d real talk event reaches poster script" % n)
	print("POSTER CLASS 5 native ray and talk witnesses")

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(0.2).timeout
	game.vm.cancel_all()
	_wall_class()
	await _direct_mount_class()
	await _poster_class()
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("FPS MOUNTED POSTERS PASS")
	quit(0 if failures.is_empty() else 1)
