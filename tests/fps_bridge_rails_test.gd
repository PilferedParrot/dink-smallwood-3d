extends SceneTree
# Bridge railings stand and decks take rays (docs/DIRECTION.md, Dink M3 unit U1). Parts, run by
# tests/test_fps_bridge_rails.py (all through fp_world.gd and scripts/bridge_rails.gd as the game builds a scene):
#
#   --sweep    (headless) every bridge sprite of the map built as a scene builds it, collision on: what each holds.
#              "RAIL screen index vision file kind meshes=N posts=P min=x,y,z max=x,y,z body=layer/mask/shapes"
#              (kind: deck or rail by the art's file; min/max the extent of its Rail / Posts meshes in the node's own
#              metres; body: the HitBody's layer, mask and shape count, or none); "CARD ..." the foot line of a standing
#              card; "PLATE ... x a to b z c to d top t" the extent of a deck's ray plate (node metres).
#   --ground   (headless) the planks painted into each screen's ground, with --mask=<bridges.json> (the same count runs on
#              any checkout, since it reads only the ground texture): "GROUND screen decks=D rail_pixels_in_ground=N
#              planks=P planks_kept=K whole=W whole_kept=WK": for the split decks (east-west: those with an entry in the
#              json), N counts the ground pixels inside the sprites that still equal the art's rail pixels (the json's
#              "card" runs), so a build without the split reads its whole rail; K of P counts the art's plank pixels (an
#              independent rule from the json's foot line only, never from the "card" runs: 2 px under the line) that are
#              still in the ground, so a split that eats the planks' dark seams loses them. For the decks painted whole (no
#              entry: the north-south decks, whose side ropes stay in the ground as at 46b68a0), WK of W
#              counts their opaque art pixels that are in the ground as the art has them. --shift=dx,dy moves the mask off the
#              sprites: the chance rate.
#   --render   (rendered, under xvfb, Dummy audio) rays and pictures: a downward ray onto each deck of 404 and 448
#              hits it, one beside it does not; from a camera exactly on 404's near railing's axis the railing's own
#              pixels (the picture with it hidden against the picture with it shown) are counted.
# Verdict: written 2026-10-02 (Sonnet 5.5, unit U1 of Dink M3).
const GAME = preload("res://scripts/fps_game.gd")

var game
var failures: Array[String] = []
var mask_path := ""
var shift := Vector2i.ZERO # --shift=dx,dy: the chance rate: the mask moved off the sprites

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var sweep := false
	var ground := false
	var render := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--sweep": sweep = true
		if arg == "--ground": ground = true
		if arg == "--render": render = true
		if arg.begins_with("--mask="): mask_path = arg.trim_prefix("--mask=")
		if arg.begins_with("--shift="): shift = Vector2i(int(arg.trim_prefix("--shift=").split(",")[0]), int(arg.trim_prefix("--shift=").split(",")[1]))
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	if sweep: _sweep()
	if ground: await _ground()
	if render: await _render()
	if failures.is_empty():
		print("FPS BRIDGE RAILS PASS")
		quit(0)
	else:
		print("FPS BRIDGE RAILS FAIL ", failures.size())
		quit(1)

func _is_bridge_art(path: String) -> bool:
	var p := path.to_lower()
	if "/struct/bridge/" in p: return true
	if "/struct/landmark/" in p:
		var file := p.get_file()
		return file.begins_with("landm-") and int(file.trim_prefix("landm-")) in [4, 5, 6]
	return false

func _extent(node: Node) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var meshes := 0
	var queue: Array = [node]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		for c in n.get_children(): queue.append(c)
		if n is MeshInstance3D and n.get_parent() != null and n.get_parent().name == "Rail":
			var box: AABB = (n as MeshInstance3D).mesh.get_aabb()
			var t: Transform3D = (n as MeshInstance3D).transform
			var parent := n.get_parent()
			while parent != null and parent != node:
				if parent is Node3D: t = (parent as Node3D).transform * t
				parent = parent.get_parent()
			for i in 8:
				var corner: Vector3 = t * box.get_endpoint(i)
				lo = lo.min(corner)
				hi = hi.max(corner)
			meshes += 1
	return [meshes, lo, hi]

func _sweep() -> void:
	var fw = game.fp_world
	var scratch := Node3D.new()
	root.add_child(scratch)
	var lines := 0
	for number in game.world.screens:
		var n := int(number)
		game.current_screen = n
		game.generation += 1
		fw.interior = fw.is_inside(n)
		for vision in [0, 1, 2]:
			game.vm.globals["vision"] = vision # actual story context for modular joins
			for source in fw.drawn_sprites(n, vision):
				var e: Dictionary = source.duplicate()
				if not _is_bridge_art(fw.frame_path(e)): continue
				var node: Node3D = fw.make_entity(e, int(e.get("index", 1)), scratch, true, n)
				var info := _extent(node)
				var body := node.get_node_or_null("HitBody")
				var body_text := "none"
				if body is StaticBody3D:
					body_text = "%d/%d/%d" % [(body as StaticBody3D).collision_layer, (body as StaticBody3D).collision_mask, body.get_child_count()]
				# The deck's plate: the extent of its hull in the node's own metres (x, z; y is the plate's 5 cm).
				if body is StaticBody3D:
					for c in body.get_children():
						if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
							var points: PackedVector3Array = ((c as CollisionShape3D).shape as ConvexPolygonShape3D).points
							var plo := Vector3(INF, INF, INF)
							var phi := Vector3(-INF, -INF, -INF)
							for pt in points:
								plo = plo.min(pt)
								phi = phi.max(pt)
							print("PLATE %d %d %d %s x %.4f to %.4f z %.4f to %.4f top %.3f" % [n, int(e.get("index", -1)), vision, fw.frame_path(e), plo.x, phi.x, plo.z, phi.z, phi.y])
				var lo: Vector3 = info[1]
				var hi: Vector3 = info[2]
				var posts := 0
				for c in node.find_children("*", "MeshInstance3D", true, false):
					if c.name == "Posts": posts += 1
				print("RAIL %d %d %d %s %s meshes=%d posts=%d min=%.3f,%.3f,%.3f max=%.3f,%.3f,%.3f body=%s" % [n, int(e.get("index", -1)), vision,
					fw.frame_path(e), "deck" if node.has_meta("ground_painted") else "rail", info[0], posts, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, body_text])
				lines += 1
				# The first rope child's bottom edge (its first two vertices: bottom-left, bottom-right) in the node's metres:
				# for an east-west deck or a near railing that is the card's foot line.
				var rail := node.get_node_or_null("Rail")
				if rail != null:
					for c in rail.get_children():
						if c is MeshInstance3D and c.name == "Rope":
							var v: PackedVector3Array = ((c as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
							print("CARD %d %d %d %s foot x %.4f z %.4f to x %.4f z %.4f top %.4f" % [n, int(e.get("index", -1)), vision, fw.frame_path(e), v[0].x, v[0].z, v[1].x, v[1].z, (c as MeshInstance3D).mesh.get_aabb().end.y])
							break
				if fw.frame_path(e).get_file() in ["brdge-01.png","brdge-02.png","brdge-03.png"]:
					var row := {"screen":n,"index":int(e.get("index",-1)),"vision":vision,"path":fw.frame_path(e),"meshes":{},"materials":{}}
					if rail != null:
						for part in rail.get_children():
							if not part is MeshInstance3D: continue
							var points: Array = []
							var materials: Array = []
							for surface in part.mesh.get_surface_count():
								var arrays: Array = part.mesh.surface_get_arrays(surface)
								var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
								var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
								for vertex in vertices:
									var actual: Vector3 = rail.transform*part.transform*vertex
									points.append([actual.x,actual.y,actual.z])
								if str(part.name) in ["RopeLeft","RopeRight"]:
									var mat: StandardMaterial3D = part.material_override if part.material_override != null else part.get_surface_override_material(surface)
									var image: Image = mat.albedo_texture.get_image()
									if image.is_compressed(): image.decompress()
									var samples: Array = []
									var coords: Array = []
									for uv in uvs: coords.append([uv.x,uv.y])
									if image.get_width() == 3:
										for yy in image.get_height():
											for xx in image.get_width():
												var c := image.get_pixel(xx,yy)
												samples.append([roundi(c.r*255),roundi(c.g*255),roundi(c.b*255),roundi(c.a*255)])
									materials.append({"size":[image.get_width(),image.get_height()],"pixels":samples,"uvs":coords,"vertices":[]})
									for vertex in vertices: materials[-1].vertices.append([vertex.x,vertex.y,vertex.z])
							row.meshes[str(part.name)] = points
							if not materials.is_empty(): row.materials[str(part.name)] = materials
					print("NSJSON ",JSON.stringify(row))
				scratch.remove_child(node)
				node.free()
	scratch.free()
	print("RAILS ", lines)

# The ground pixels of each deck sprite that still equal the art's rail pixels, read from a bridges.json (--mask).
func _ground() -> void:
	var fw = game.fp_world
	var mask: Dictionary = {}
	if mask_path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(mask_path))
		if parsed is Dictionary: mask = parsed
	var total := 0
	var planks_total := 0
	var kept_total := 0
	var whole_total := 0
	var whole_kept_total := 0
	# 533's bridge is only in the story layers 1 and 2 (pieces 1 and 25 in 1, 2 and 3 in 2).
	for pair in [[404, 0], [416, 0], [448, 0], [480, 0], [512, 0], [533, 1], [533, 2], [544, 0], [693, 0], [701, 0]]:
		var n: int = pair[0]
		var vision: int = pair[1]
		game.vm.cancel_all()
		game.vm.globals["vision"] = vision
		game.load_map(n, false)
		await create_timer(0.3).timeout
		var image: Image = fw.ground_texture(n).get_image()
		var count := 0
		var split_decks := 0
		var planks := 0
		var kept := 0
		var card_total := 0
		var whole_decks := 0
		var whole := 0
		var whole_kept := 0
		var ns_planks := 0
		var ns_planks_kept := 0
		var ns_edges := 0
		var ns_edges_kept := 0
		for e in fw.background_sprites(n, vision):
			var path: String = fw.frame_path(e)
			if str(path).find("/struct/Bridge/brdge-") < 0: continue
			if mask.has(path) and str(mask[path].kind) == "near": continue
			var d: Dictionary = game._frame(int(fw.display_frame(e).x), int(fw.display_frame(e).y))
			var art: Image = fw.sprite_image(path)
			var left := int(float(e.get("x", 0)) - 20.0 - float(d.get("dx", 0)))
			var top := int(float(e.get("y", 0)) - float(d.get("dy", 0)))
			if path.get_file() in ["brdge-01.png","brdge-02.png","brdge-03.png"]:
				# Independently read central plank rows and cold edge strokes from
				# original pixels, without the split mask or generated mesh metadata.
				for y in art.get_height():
					var warm_count := 0
					for x in art.get_width():
						var c := art.get_pixel(x,y)
						if c.a >= 0.5 and (c.r-c.g)*255.0 >= 24.0 and (c.g-c.b)*255.0 >= 10.0: warm_count += 1
					for x in art.get_width():
						var a := art.get_pixel(x,y)
						if a.a < 0.99: continue
						var gx := left+x
						var gy := top+y
						if gx < 0 or gy < 0 or gx >= image.get_width() or gy >= image.get_height(): continue
						var g := image.get_pixel(gx,gy)
						var same := absf(a.r-g.r) < 0.002 and absf(a.g-g.g) < 0.002 and absf(a.b-g.b) < 0.002
						var central := x >= art.get_width()/4 and x < art.get_width()*3/4
						if central and float(warm_count) >= 0.4*art.get_width():
							ns_planks += 1
							if same: ns_planks_kept += 1
						elif not central and a.r-a.g < 12.0/255.0:
							ns_edges += 1
							if same: ns_edges_kept += 1
			if not (mask.has(path) and str(mask[path].kind) == "ew"): # an "ns" entry (the first version of this unit) is not a split the build may make
				# A deck that is painted whole (the north-south decks): every opaque pixel of its art that
				# nothing later paints over is in the ground as the art has it, its side ropes included, as at 46b68a0.
				whole_decks += 1
				for y in art.get_height():
					for x in art.get_width():
						var a := art.get_pixel(x, y)
						if a.a < 0.99: continue
						var gx := left + x
						var gy := top + y
						if gx < 0 or gy < 0 or gx >= image.get_width() or gy >= image.get_height(): continue
						whole += 1
						var g := image.get_pixel(gx, gy)
						if absf(a.r - g.r) < 0.002 and absf(a.g - g.g) < 0.002 and absf(a.b - g.b) < 0.002: whole_kept += 1
				continue
			split_decks += 1
			var info: Dictionary = mask[path]
			for y in art.get_height():
				for x in art.get_width():
					var a := art.get_pixel(x, y)
					if a.a < 0.5: continue
					# The planks by an independent rule from the json's foot line only, never from its "card" runs: 2 px under it.
					if float(y) < ceilf(float(info.line[0]) + float(info.line[1]) * (float(x) + 0.5)) + 2.0: continue
					var gx := left + x
					var gy := top + y
					if gx < 0 or gy < 0 or gx >= image.get_width() or gy >= image.get_height(): continue
					planks += 1
					var g := image.get_pixel(gx, gy)
					if absf(a.r - g.r) < 0.002 and absf(a.g - g.g) < 0.002 and absf(a.b - g.b) < 0.002: kept += 1
			for r in mask[path].card:
				var y := int(r[0])
				for x in range(int(r[1]), int(r[2]) + 1):
					var gx := left + x + shift.x
					var gy := top + y + shift.y
					if gx < 0 or gy < 0 or gx >= image.get_width() or gy >= image.get_height(): continue
					var a := art.get_pixel(x, y)
					var g := image.get_pixel(gx, gy)
					card_total += 1
					if absf(a.r - g.r) < 0.002 and absf(a.g - g.g) < 0.002 and absf(a.b - g.b) < 0.002:
						count += 1
		print("GROUND %d v%d split=%d rail_pixels_in_ground=%d rail_total=%d planks=%d planks_kept=%d whole_decks=%d whole=%d whole_kept=%d" % [n, vision, split_decks, count, card_total, planks, kept, whole_decks, whole, whole_kept])
		if ns_planks > 0: print("NSGROUND %d v%d planks=%d kept=%d cold_edges=%d edge_kept=%d" % [n,vision,ns_planks,ns_planks_kept,ns_edges,ns_edges_kept])
		total += count
		planks_total += planks
		kept_total += kept
		whole_total += whole
		whole_kept_total += whole_kept
	print("GROUND TOTAL %d planks=%d planks_kept=%d whole=%d whole_kept=%d" % [total, planks_total, kept_total, whole_total, whole_kept_total])

# --- rays and pictures ------------------------------------------------------------------------------------------
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_root().get_world_3d().direct_space_state.intersect_ray(query)

func _settle(number: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(number, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""
	game.ui.visible = false
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	# The light's shadows off: a railing's own pixels, not its shadow on the water (a card seen edge-on still casts one).
	if game.fp_world != null and game.fp_world.light != null: game.fp_world.light.shadow_enabled = false
	await physics_frame
	await physics_frame

func _shoot(x: float, y: float, yaw: float, pitch: float) -> Image:
	game.entities[1].x = x
	game.entities[1].y = y
	game.fps_yaw = yaw
	game.fps_pitch = pitch
	game._sync_fps_camera()
	for id in game.entities.keys(): game._update_visual(id)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func _render() -> void:
	var fw = game.fp_world
	# 1. rays: a downward ray onto each deck of 404 and 448 hits it (the deck's own entity); one 4 m to the side does not.
	for number in [404, 448, 512, 693]:
		await _settle(number)
		var decks := 0
		var hit := 0
		var missed := 0
		for id in game.entities.keys():
			if int(id) == 1: continue
			var e: Dictionary = game.entities[id]
			if fw.model_key(e) != "bridge_deck": continue
			var node: Node3D = game.visuals.get(id)
			if node == null: continue
			decks += 1
			# A point on the planks, from the art alone (the centroid of its warm-brown pixels), whatever body the build has.
			var art: Image = fw.sprite_image(fw.frame_path(e))
			var d: Dictionary = game._frame(int(fw.display_frame(e).x), int(fw.display_frame(e).y))
			var sx := 0.0
			var sy := 0.0
			var count := 0
			for yy in art.get_height():
				for xx in art.get_width():
					var c := art.get_pixel(xx, yy)
					if c.a >= 0.5 and (c.r - c.g) * 255.0 >= 24.0 and (c.g - c.b) * 255.0 >= 10.0:
						sx += xx
						sy += yy
						count += 1
			if count == 0: continue
			var centre: Vector3 = node.global_position + Vector3((sx / count - float(d.dx)) * 0.025, 0, (sy / count - float(d.dy)) * 0.025)
			# From 0.3 m over the planks, not from the sky: a railing's own box (its hardbox, as before) stands over part of
			# a deck and is what an arrow from above would meet first.
			var down := _ray(centre + Vector3(0, 0.3, 0), centre + Vector3(0, -1, 0))
			if not down.is_empty() and int((down.collider as Object).get_meta("entity_id", 0)) == int(id): hit += 1
			else: print("RAYMISS %d %s index %d at %.3f,%.3f: %s" % [number, fw.frame_path(e).get_file(), int(e.get("index", -1)), centre.x, centre.z, "nothing" if down.is_empty() else "entity %d %s" % [int((down.collider as Object).get_meta("entity_id", 0)), str((down.collider as Node).get_parent().name)]])
			var far := float(art.get_width()) * 0.0125 + 4.0
			var aside := _ray(centre + Vector3(far, 0.3, 0), centre + Vector3(far, -1, 0))
			if aside.is_empty() or int((aside.collider as Object).get_meta("entity_id", 0)) != int(id): missed += 1
		print("RAY %d decks=%d hit=%d aside_missed=%d" % [number, decks, hit, missed])
	# 2. from a camera exactly on each railing's axis (the vertical plane its card stands in, read from the build's own
	# geometry: the baseline's card at its hotspot, the new one on its posts' foot line), 3 m before its left end, looking
	# along it: the railing's own pixels (the picture with the entity hidden against the picture with it shown). A card
	# is a sliver from its own axis; posts that are prisms are not. The same railing seen from 1.5 m to the side is the
	# positive control: the counter does count a railing that is there.
	for number in [404, 512]:
		await _settle(number)
		var ids: Array = []
		for id in game.entities.keys():
			if int(id) == 1: continue
			var key: String = fw.model_key(game.entities[id])
			if key == "bridge_rail": ids.append(id)
			# A north-south deck's rails run along its depth, not on a foot line (its first rope mesh is a ribbon).
			elif key == "bridge_deck" and "rails" in fw and fw.rails.has(fw.frame_path(game.entities[id])) and str(fw.rails.entry(fw.frame_path(game.entities[id])).kind) == "ew": ids.append(id)
		for id in ids:
			var e: Dictionary = game.entities[id]
			var node: Node3D = game.visuals[id]
			var axis: Array = _axis(node)
			if axis.is_empty():
				print("AXIS %d %s no geometry" % [number, fw.frame_path(e).get_file()])
				continue
			var dir: Vector3 = (axis[1] - axis[0])
			dir.y = 0.0
			dir = dir.normalized()
			var yaw := atan2(-dir.x, -dir.z)
			var counts: Array = []
			for side in [0.0, 1.5]:
				var cam: Vector3 = axis[0] - dir * 3.0 + Vector3(-dir.z, 0, dir.x) * side
				var x: float = cam.x / 0.025 + 320.0
				var y: float = cam.z / 0.025 + 200.0
				# Hidden as the game hides a sprite (nodraw; _shoot's update_visual would undo a plain node.visible).
				var saved: Variant = e.get("nodraw", 0)
				e["nodraw"] = 0
				var shown: Image = await _shoot(x, y, yaw, -0.02)
				e["nodraw"] = 1
				var hidden: Image = await _shoot(x, y, yaw, -0.02)
				e["nodraw"] = saved
				game._update_visual(id)
				var differ := 0
				for yy in shown.get_height():
					for xx in shown.get_width():
						var a := shown.get_pixel(xx, yy)
						var b := hidden.get_pixel(xx, yy)
						if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06: differ += 1
				counts.append(differ)
			print("AXIS %d %d %s on_axis=%d side=%d" % [number, int(id), fw.frame_path(e).get_file(), counts[0], counts[1]])

# A railing's axis: two points on the bottom edge of its card (world metres), from the geometry the build made.
func _axis(node: Node3D) -> Array:
	var rail := node.get_node_or_null("Rail")
	if rail != null:
		for c in rail.get_children():
			if c is MeshInstance3D and c.name == "Rope":
				var v: PackedVector3Array = ((c as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
				return [node.global_transform * v[0], node.global_transform * v[1]]
	var model := node.get_node_or_null("Model")
	if model is Sprite3D:
		var t: Transform3D = (model as Sprite3D).global_transform
		return [t.origin, t.origin + t.basis.x]
	return []
