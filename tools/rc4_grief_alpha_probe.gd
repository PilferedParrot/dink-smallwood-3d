extends SceneTree

# PRESERVED EXPERIMENT: the last all-effect/union-visibility extension has NOT
# been executed. Earlier ray and selected-effect alpha stages produced negative
# evidence. The lead stopped grief-camera experimentation; do not run this as a
# routine check or treat any candidate coordinates as an accepted camera fix.
# One read-only diagnosis of the source story-3 home scene. Run with a fresh
# XDG profile; this script does not alter any game source, saves, or settings.
const GAME := preload("res://scripts/fps_game.gd")

var game
var corpse_id: int = 0
var mother_id: int = 0
var safe: Rect2
var ray_rejections: int = 0
var effect_rejections: int = 0
var corpse_targets: Array[Vector3] = []
var corpse_pixels: Array[Vector2i] = []
var effect_images: Dictionary = {}
var best_visibility: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	await process_frame
	game.vm.globals["vision"] = 1
	game.vm.globals["story"] = 3
	game.load_map(1, false)
	await process_frame
	await process_frame
	for id in game.entities:
		var editor: int = int(game.entities[id].get("editor_num", -1))
		if editor == 26: mother_id = int(id)
		if editor == 34: corpse_id = int(id)
	print("FIXTURE screen=", game.current_screen, " mother_id=", mother_id, " corpse_id=", corpse_id)
	if mother_id == 0 or corpse_id == 0:
		_finish(2)
		return
	await game.vm.run("s1-h1-m", "main", mother_id)
	game._update_visual(mother_id)
	print("SOURCE mother_active=", game.entities[mother_id].get("active"), " corpse_visible=", game.visuals[corpse_id].is_visible_in_tree())
	game.playing = true
	game.ui.close_menu()
	game.set_physics_process(false)
	game.test_mode = false
	game.ui.show_dialogue("Mother, you can't die, nooo I  I ...", "Dink")
	var prepared: bool = await game.ui.prepare_dialogue_layout()
	if not prepared:
		print("DIAG_ERROR dialogue layout cancelled")
		_finish(3)
		return
	safe = game.ui.speech_safe_rect()
	print("UI_SAFE ", safe, " viewport=", get_root().get_visible_rect())
	_dump_source_art()
	await _probe("doorway", Vector2(323.0, 370.833333))
	await _probe("bedside", Vector2(203.0, 151.0))
	print("DIAG_DONE ray_rejections=", ray_rejections, " effect_rejections=", effect_rejections)
	_finish(0)

func _dump_source_art() -> void:
	var source: Dictionary = {}
	for e in game.world.screens["1"].get("sprites", []):
		if int(e.get("index", -1)) == 34:
			source = e
			break
	var visual: Node3D = game.visuals[corpse_id]
	var path: String = game.fp_world.frame_path(source)
	var foot: Vector2 = game.fp_world.sprite_foot(path)
	var frame: Dictionary = game._frame(int(source.get("seq", 0)), int(source.get("frame", 1)))
	var hotspot: Vector2 = Vector2(float(frame.get("dx", 0)), float(frame.get("dy", 0)))
	var ground: Vector2 = Vector2(float(source.get("x", 0)), float(source.get("y", 0))) + foot - hotspot
	var order: float = float(source.get("que", 0)) if int(source.get("que", 0)) != 0 else float(source.get("y", 0))
	var support: float = game.fp_world.solids.surface_height(ground, order, 1, 1)
	print("ART path=", path, " source_xy=", Vector2(source.x, source.y), " hotspot=", hotspot,
		" foot=", foot, " ground_foot=", ground, " draw_order=", order, " authored_furniture_support_px=", support)
	print("ART node_position=", visual.global_position, " floor_art_rect=", visual.get_meta("floor_art_rect", Rect2()),
		" ground_painted=", visual.get_meta("ground_painted", false), " model_key=", visual.get_meta("model_key", ""))
	var points: Array[Vector3] = game._fps_visible_points(visual, game.camera.global_position)
	for i in points.size(): print("ART_CORNER ", i, " world=", points[i])
	var image: Image = game.fp_world.sprite_image(path)
	if image != null:
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a <= 0.5: continue
				var local: Vector3 = Vector3((float(x)+0.5-hotspot.x)*GAME.SCALE, 0.0, (float(y)+0.5-hotspot.y)*GAME.SCALE)
				corpse_targets.append(visual.global_transform*local)
				corpse_pixels.append(Vector2i(x, y))
	print("ART_ALPHA_PIXELS threshold=0.5 count=", corpse_targets.size())

func _probe(label: String, player_source: Vector2) -> void:
	game._fps_restore_dialogue_camera()
	game.entities[1]["x"] = player_source.x
	game.entities[1]["y"] = player_source.y
	game._sync_fps_camera()
	var visual: Node3D = game.visuals[corpse_id]
	var initial_points: Array[Vector3] = game._fps_visible_points(visual, game.camera.global_position)
	var target: Vector3 = game._fps_points_center(initial_points)
	var eye: Vector3 = game.camera.global_position
	var away: Vector2 = Vector2(eye.x-target.x, eye.z-target.z)
	if away.length_squared() < 0.04:
		away = Vector2(-game.camera.global_transform.basis.z.x, -game.camera.global_transform.basis.z.z)
	if away.length_squared() < 0.04: away = Vector2.RIGHT
	away = away.normalized()
	var seed: float = game._fps_min_dialogue_distance(initial_points, safe)
	print("PROBE ", label, " player_source=", player_source, " eye=", eye, " target=", target,
		" seed_distance=", seed, " away=", away)
	game._fps_own_dialogue_camera()
	game.fps_dialogue_rejections.clear()
	_probe_candidate(label, "player_eye", eye, initial_points, target)
	for scale in [1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]:
		var distance: float = seed * float(scale)
		for degrees in [0.0, -20.0, 20.0, -40.0, 40.0, -65.0, 65.0, -90.0, 90.0, 180.0]:
			var direction: Vector2 = away.rotated(deg_to_rad(float(degrees)))
			var source: Vector3 = Vector3(target.x+direction.x*distance, GAME.EYE_HEIGHT, target.z+direction.y*distance)
			_probe_candidate(label, "ring=%s angle=%s" % [scale, degrees], source, initial_points, target)
	print("PROBE_COUNTS ", label, " ", game.fps_dialogue_rejections)
	print("BEST_VISIBILITY ", label, " ", best_visibility.get(label, {}))
	game._fps_restore_dialogue_camera()
	await process_frame

func _probe_candidate(label: String, key: String, source: Vector3, initial_points: Array[Vector3], target: Vector3) -> void:
	var before: Dictionary = game.fps_dialogue_rejections.duplicate()
	var accepted: bool = game._fps_try_dialogue_position(source, initial_points, target, corpse_id, safe, true)
	if accepted:
		print("ACCEPT ", label, " ", key, " camera=", source, " bounds=", game._fps_projected_bounds(game._fps_visible_points(game.visuals[corpse_id], source)))
		_track_best_visibility(label,key,corpse_targets.size(),0)
		print("ALPHA_CANDIDATE ", label, " ", key, " union_occluded=0 visible=", corpse_targets.size(), "/", corpse_targets.size(), " first_hit={}")
		return
	var reason: String = "unknown"
	for name in game.fps_dialogue_rejections:
		if int(game.fps_dialogue_rejections[name]) > int(before.get(name, 0)):
			reason = str(name)
			break
	if reason == "rays":
		ray_rejections += 1
		_dump_rays(label, key, source)
	elif reason == "effect":
		effect_rejections += 1
		_dump_effects(label, key, source)
	elif reason == "room":
		var source_pixel: Vector2 = Vector2(source.x/GAME.SCALE+320.0, source.z/GAME.SCALE+200.0)
		var query := PhysicsPointQueryParameters3D.new()
		query.position = source
		query.collision_mask = 3
		var overlaps: Array = game.get_world_3d().direct_space_state.intersect_point(query, 8)
		if overlaps.size() > 0:
			print("ROOM_BLOCK ", label, " ", key, " camera=", source, " source_px=", source_pixel,
				" tile=", game._tile_blocked(source_pixel), " overlap=", _hits_summary(overlaps))

func _dump_rays(label: String, key: String, source: Vector3) -> void:
	var points: Array[Vector3] = game._fps_visible_points(game.visuals[corpse_id], source)
	var center: Vector3 = game._fps_points_center(points)
	var low: float = center.y
	var high: float = center.y
	for point in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	print("RAY_REJECT ", label, " ", key, " camera=", source, " art_center=", center,
		" floor_rect=", game.visuals[corpse_id].get_meta("floor_art_rect", Rect2()))
	for fraction in [0.35, 0.75]:
		var aim: Vector3 = Vector3(center.x, lerpf(low, high, float(fraction)), center.z)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(source, aim, 3))
		print("RAY ", fraction, " from=", source, " to=", aim, " hit=", _hit_summary(hit),
			" end_gap=", (hit["position"] as Vector3).distance_to(aim) if hit.has("position") else -1.0)

func _dump_effects(label: String, key: String, source: Vector3) -> void:
	var subject_points: Array[Vector3] = game._fps_visible_points(game.visuals[corpse_id], source)
	var subject_center: Vector3 = game._fps_points_center(subject_points)
	var subject_bounds: Rect2 = game._fps_projected_bounds(subject_points)
	var subject_distance: float = source.distance_to(subject_center)
	print("EFFECT_REJECT ", label, " ", key, " camera=", source, " subject_distance=", subject_distance,
		" subject_bounds=", subject_bounds)
	for id in game.visuals:
		var visual: Node3D = game.visuals[id]
		if not is_instance_valid(visual) or not visual.visible: continue
		var model_key: String = str(visual.get_meta("model_key", ""))
		if model_key not in ["flame", "effect"]: continue
		var points: Array[Vector3] = game._fps_visible_points(visual, source)
		if points.is_empty(): continue
		var center_distance: float = source.distance_to(game._fps_points_center(points))
		var low_depth: float = INF
		var high_depth: float = -INF
		var corner_text: Array[String] = []
		for i in points.size():
			var depth: float = -game.camera.global_transform.basis.z.dot(points[i]-source)
			low_depth = minf(low_depth, depth)
			high_depth = maxf(high_depth, depth)
			corner_text.append("%d:%s depth=%.4f" % [i, points[i], depth])
		var bounds: Rect2 = game._fps_projected_bounds(points)
		var straddles: bool = low_depth <= game.camera.near and high_depth > game.camera.near
		var entity: Dictionary = game.entities.get(id, {})
		print("EFFECT id=", id, " editor=", entity.get("editor_num", -1), " key=", model_key,
			" center_distance=", center_distance, " depth_min=", low_depth, " depth_max=", high_depth,
			" near=", game.camera.near, " straddles=", straddles, " bounds=", bounds,
			" intersects_subject_bounds=", bounds.has_area() and bounds.intersects(subject_bounds))
		for corner in corner_text: print("EFFECT_CORNER ", id, " ", corner)
	_dump_effect_alpha(label, key, source)

func _dump_effect_alpha(label: String, key: String, source: Vector3) -> void:
	var opaque_effects: Array[int] = []
	var tested_effects: int = 0
	var union_covered := PackedByteArray()
	union_covered.resize(corpse_targets.size())
	var first_hit: Dictionary = {}
	for id in game.visuals:
		if int(id) == corpse_id: continue
		var visual: Node3D = game.visuals[id]
		if not is_instance_valid(visual) or not visual.visible: continue
		if str(visual.get_meta("model_key", "")) not in ["flame", "effect"]: continue
		if bool(visual.get_meta("ground_painted",false)): continue
		tested_effects += 1
		var plane_hits: int = 0
		var image_hits: int = 0
		var opaque_hits: int = 0
		var highest_alpha: float = 0.0
		var first_opaque: Dictionary = {}
		var first_transparent: Dictionary = {}
		var effect_covered := PackedByteArray()
		effect_covered.resize(corpse_targets.size())
		var sprites: Array[Sprite3D] = _effect_sprites(visual)
		for sprite in sprites:
			var threshold: float = sprite.alpha_scissor_threshold if sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD else 0.0
			for i in corpse_targets.size():
				var sample: Dictionary = _sample_sprite_alpha(sprite, source, corpse_targets[i])
				if not bool(sample.get("plane", false)): continue
				plane_hits += 1
				if not bool(sample.get("inside", false)): continue
				image_hits += 1
				var alpha: float = float(sample.get("alpha", 0.0))
				highest_alpha = maxf(highest_alpha, alpha)
				sample["subject_pixel"] = corpse_pixels[i]
				if alpha > threshold:
					if effect_covered[i] == 0:
						effect_covered[i] = 1
						opaque_hits += 1
					union_covered[i] = 1
					if first_opaque.is_empty(): first_opaque = sample
					if first_hit.is_empty():
						first_hit = sample.duplicate()
						first_hit["effect_id"] = int(id)
						first_hit["effect_editor"] = int(game.entities.get(id,{}).get("editor_num",-1))
				elif first_transparent.is_empty(): first_transparent = sample
		if opaque_hits > 0: opaque_effects.append(int(id))
		var entity: Dictionary = game.entities.get(id, {})
		print("ALPHA_EFFECT ", label, " ", key, " id=", id, " editor=", entity.get("editor_num", -1),
			" source_subject_pixels=", corpse_targets.size(), " sprites=", sprites.size(), " plane_hits=", plane_hits,
			" image_hits=", image_hits, " opaque_hits=", opaque_hits, " max_alpha=", highest_alpha,
			" first_opaque=", first_opaque, " first_transparent=", first_transparent)
	var union_occluded: int = 0
	for covered in union_covered:
		if covered != 0: union_occluded += 1
	var visible: int = corpse_targets.size()-union_occluded
	_track_best_visibility(label,key,visible,union_occluded)
	print("ALPHA_CANDIDATE ", label, " ", key, " tested_effects=", tested_effects,
		" opaque_effect_ids=", opaque_effects, " union_occluded=", union_occluded,
		" visible=", visible, "/", corpse_targets.size(), " first_hit=", first_hit)

func _track_best_visibility(label: String, key: String, visible: int, occluded: int) -> void:
	if not best_visibility.has(label) or visible > int(best_visibility[label].get("visible", -1)):
		best_visibility[label] = {"candidate":key,"visible":visible,"occluded":occluded,"of":corpse_targets.size()}

func _effect_sprites(visual: Node3D) -> Array[Sprite3D]:
	var result: Array[Sprite3D] = []
	var pending: Array[Node] = [visual]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node != visual and node is Node3D and not (node as Node3D).visible: continue
		if node is Sprite3D and str(node.name) != "ShadowTwin": result.append(node as Sprite3D)
		for child in node.get_children(): pending.append(child)
	return result

func _sample_sprite_alpha(sprite: Sprite3D, source: Vector3, subject: Vector3) -> Dictionary:
	if sprite.texture == null: return {}
	var texture_id: int = sprite.texture.get_instance_id()
	if not effect_images.has(texture_id): effect_images[texture_id] = sprite.texture.get_image()
	var image: Image = effect_images[texture_id]
	if image == null: return {}
	var right: Vector3 = sprite.global_transform.basis.x.normalized()
	var up: Vector3 = sprite.global_transform.basis.y.normalized()
	if sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y:
		var toward: Vector2 = Vector2(source.x-sprite.global_position.x, source.z-sprite.global_position.z).normalized()
		right = Vector3(toward.y, 0.0, -toward.x)
	elif sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED:
		right = game.camera.global_transform.basis.x.normalized()
		up = game.camera.global_transform.basis.y.normalized()
	var normal: Vector3 = right.cross(up)
	var ray: Vector3 = subject-source
	var denominator: float = normal.dot(ray)
	if absf(denominator) < 0.000001: return {}
	var fraction: float = normal.dot(sprite.global_position-source)/denominator
	if fraction <= 0.000001 or fraction >= 0.999999: return {}
	var intersection: Vector3 = source+ray*fraction
	var depth: float = -game.camera.global_transform.basis.z.dot(intersection-source)
	if depth <= game.camera.near: return {}
	var width: float = sprite.region_rect.size.x if sprite.region_enabled else float(sprite.texture.get_width())
	var height: float = sprite.region_rect.size.y if sprite.region_enabled else float(sprite.texture.get_height())
	var pixel_width: float = sprite.pixel_size*sprite.global_transform.basis.x.length()
	var pixel_height: float = sprite.pixel_size*sprite.global_transform.basis.y.length()
	if pixel_width <= 0.0 or pixel_height <= 0.0: return {}
	var local: Vector3 = intersection-sprite.global_position
	var u: float = local.dot(right)/pixel_width + width*0.5 - sprite.offset.x
	var v: float = height*0.5 + sprite.offset.y - local.dot(up)/pixel_height
	var response: Dictionary = {"plane":true,"inside":false,"world":intersection,"fraction":fraction,"uv":Vector2(u,v),"alpha":0.0}
	if u < 0.0 or u >= width or v < 0.0 or v >= height: return response
	var image_u: int = int(floor(width-1.0-u)) if sprite.flip_h else int(floor(u))
	var image_v: int = int(floor(height-1.0-v)) if sprite.flip_v else int(floor(v))
	if sprite.region_enabled:
		image_u += int(sprite.region_rect.position.x)
		image_v += int(sprite.region_rect.position.y)
	if image_u < 0 or image_u >= image.get_width() or image_v < 0 or image_v >= image.get_height(): return response
	response["inside"] = true
	response["pixel"] = Vector2i(image_u,image_v)
	response["alpha"] = image.get_pixel(image_u,image_v).a
	return response

func _hits_summary(hits: Array) -> Array[String]:
	var result: Array[String] = []
	for hit in hits: result.append(_hit_summary(hit))
	return result

func _hit_summary(hit: Dictionary) -> String:
	if hit.is_empty(): return "none"
	var collider: Object = hit.get("collider")
	var name: String = str(collider.get_path()) if collider is Node else str(collider)
	var entity_id: int = int(collider.get_meta("entity_id", 0)) if collider != null else 0
	return "collider=%s entity=%d position=%s normal=%s shape=%s" % [name, entity_id,
		hit.get("position", Vector3.INF), hit.get("normal", Vector3.INF), hit.get("shape", -1)]

func _finish(code: int) -> void:
	if is_instance_valid(game): game.queue_free()
	quit(code)
