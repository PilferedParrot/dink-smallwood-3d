# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Build a complete original seq32/frame1 fir at each retained source crown
# from the partial tree-08/09/10 art. Source parts own scene visibility.
extends RefCounted

const FIT_PATH := "res://prototype/rc5_firs.json"
const SCALE := 0.025

var world: Object
var fit: Dictionary = {}


func _init(fp_world: Object) -> void:
	world = fp_world
	if FileAccess.file_exists(FIT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
		if parsed is Dictionary and str(parsed.get("schema", "")) == "rc5-whole-fir-fit-1":
			fit = parsed


# Both editor layers use the same object ownership. A source edge trim is
# standing foliage even when the old importer painted its type-0 copy flat.
func handles(e: Dictionary) -> bool:
	return not fit.is_empty() and not bool(e.get("runtime_created", false)) \
		and int(e.get("type", 1)) in [0,1] and int(e.get("pseq",e.get("seq",0))) == 32 \
		and int(e.get("pframe",e.get("frame",0))) in [8, 9, 10] and int(e.get("vision", 0)) == 0 \
		and int(e.get("brain", 0)) == 0 and str(e.get("script", "")).is_empty() \
		and absf(float(e.get("size", 100)) - 100.0) < 0.5


# The old two-row-strip ownership remains fp_world's seam_parts untouched.
# Frame 8 has four simultaneous x-crowns, so its old one-card seam result
# cannot decide which crown survives. The source pixel window and measured
# whole-fir foot decide each one in the current real 5x5 scene block.
func parts(e: Dictionary, screen: int) -> Array:
	var frame := int(e.get("pframe",e.get("frame",0)))
	if frame != 8: return world.seam_parts(e,screen)
	var path := str(world.call("frame_path",e))
	var source_parts: Array = fit.get("source_parts",{}).get(path,[])
	if source_parts.size() != 4: return []
	var d: Dictionary = world.host._frame(32,8)
	var result: Array = []
	for k in source_parts.size():
		var part: Dictionary = source_parts[k]
		var rows: Array = part["rows"]
		var shown := _source_visible(e,screen,part,d,path)
		if shown:
			var own_foot := _global_foot(e,screen,part,d)
			var own_inside := _foot_inside(e,screen,part,d)
			shown = not _better_owner(e,screen,k,own_foot,own_inside,path,d)
		result.append([int(rows[0]),int(rows[1]),int(rows[1])-1,shown])
	return result


func _source_visible(e: Dictionary, screen: int, part: Dictionary,
		d: Dictionary, path: String) -> bool:
	if not world.host.world.screens.has(str(screen)) or world.is_inside(screen): return false
	var image: Image = world.art_image(path)
	if image == null: return false
	var window: Array = part["source_window_x_px"]
	var rows: Array = part["rows"]
	var left := int(float(e.get("x",0))-float(d.get("dx",0)))
	var top := int(float(e.get("y",0))-float(d.get("dy",0)))
	var x0 := maxi(int(window[0]),20-left)
	var x1 := mini(int(window[1]),620-left)
	var y0 := maxi(int(rows[0]),-top)
	var y1 := mini(int(rows[1]),400-top)
	if x0 >= x1 or y0 >= y1: return false
	for y in range(y0,y1):
		for x in range(x0,x1):
			var color := image.get_pixel(x,y)
			if color.a > 0.5 and color.r+color.g+color.b >= 0.04: return true
	return false


func _global_foot(e: Dictionary, screen: int, part: Dictionary,
		d: Dictionary) -> Vector2:
	var foot: Array = part["source_foot_in_full_art_px"]
	return world.screen_origin(screen)+Vector2(float(e.get("x",0))-float(d.get("dx",0))+float(foot[0]),
		float(e.get("y",0))-float(d.get("dy",0))+float(foot[1]))


func _foot_inside(e: Dictionary, _screen: int, part: Dictionary,
		d: Dictionary) -> bool:
	var foot: Array = part["source_foot_in_full_art_px"]
	var x := float(e.get("x",0))-float(d.get("dx",0))+float(foot[0])
	var y := float(e.get("y",0))-float(d.get("dy",0))+float(foot[1])
	return x >= 20.0 and x < 620.0 and y >= 0.0 and y < 400.0


func _better_owner(e: Dictionary, screen: int, k: int, own_foot: Vector2,
		own_inside: bool, path: String, d: Dictionary) -> bool:
	var index := int(e.get("index",e.get("editor_num",-1)))
	var column := (screen-1)%32
	var source_parts: Array = fit["source_parts"][path]
	for dz in range(-1,2):
		for dx in range(-1,2):
			if column+dx < 0 or column+dx >= 32: continue
			var other_screen := screen+dx+32*dz
			if not world.host.world.screens.has(str(other_screen)) or world.is_inside(other_screen): continue
			if not world.scene_block.is_empty() and not world.scene_block.has(other_screen): continue
			for other in world.host.world.screens[str(other_screen)].get("sprites",[]):
				if not handles(other) or int(other.get("vision",0)) != int(e.get("vision",0)): continue
				if str(world.host._frame(int(other.get("seq",0)),int(other.get("frame",1))).get("path","")) != path: continue
				var other_index := int(other.get("index",-1))
				for j in source_parts.size():
					if other_screen == screen and other_index == index and j == k: continue
					var other_part: Dictionary = source_parts[j]
					var other_foot := _global_foot(other,other_screen,other_part,d)
					if absf(other_foot.x-own_foot.x) > 3.0 or absf(other_foot.y-own_foot.y) > 3.0: continue
					if not _source_visible(other,other_screen,other_part,d,path): continue
					var other_inside := _foot_inside(other,other_screen,other_part,d)
					if other_inside != own_inside:
						if other_inside: return true
					elif other_screen < screen or (other_screen == screen and
							(other_index < index or (other_index == index and j < k))): return true
	return false


# `node` already stands at e.x/e.y on its source screen. A shown part
# becomes one complete, indivisible visual with its own shadow-only twin.
# The caller supplies seam_parts(e, screen) for THIS scene_block, never a
# full-world fit's baked visibility. Source hardness stays with e.
func add(node: Node3D, e: Dictionary, parts: Array, screen: int, id: int,
		collision: bool) -> void:
	if fit.is_empty() or node == null or world == null: return
	var frame: int = int(e.get("pframe", e.get("frame", 0)))
	var path := str(world.call("frame_path", e))
	var source_parts: Array = fit.get("source_parts", {}).get(path, [])
	if frame not in [8, 9, 10] or source_parts.size() != parts.size(): return
	var d: Dictionary = world.host._frame(32, frame)
	for k in parts.size():
		var r: Array = parts[k]
		if not bool(r[3]):
			node.set_meta("seam_hidden", true)
			continue
		var source: Dictionary = source_parts[k]
		if int(r[0]) != int(source["rows"][0]) or int(r[1]) != int(source["rows"][1]):
			push_error("Whole fir fit does not match source rows: %s part %d" % [path, k])
			continue
		var foot: Array = source["source_foot_in_full_art_px"]
		var local_foot := Vector3((float(foot[0]) - float(d.get("dx", 0))) * SCALE,
			0.0, (float(foot[1]) - float(d.get("dy", 0))) * SCALE)
		var provenance := {"screen": screen, "index": int(e.get("index", -1)),
			"part": k, "path": path, "source_rows": source["rows"].duplicate(),
			"source_foot_in_full_art_px": source["source_foot_in_full_art_px"].duplicate()}
		if source.has("source_window_x_px"):
			provenance["source_window_x_px"] = source["source_window_x_px"].duplicate()
			provenance["source_apex_px"] = source["source_apex_px"].duplicate()
		at_foot(node, local_foot, float(source["uniform_scale"]), provenance,
			collision, id)
		var height := float(fit.template.crown_height_px)*SCALE*float(source.uniform_scale)
		node.set_meta("height",maxf(float(node.get_meta("height",0.0)),height))


# Shared constructor for later forest choices. `foot` is local to `parent`,
# in world units. `uniform_scale` multiplies both art axes equally.
func at_foot(parent: Node3D, foot: Vector3, uniform_scale: float,
		provenance: Dictionary = {}, collision: bool = false, id: int = 0) -> Node3D:
	if fit.is_empty() or parent == null or world == null or uniform_scale <= 0.0: return null
	var template: Dictionary = fit["template"]
	var path := str(template["path"])
	var texture := world.call("clean_texture", path) as Texture2D
	if texture == null: return null
	var anchor: Array = template["source_foot_px"]
	var holder := Node3D.new()
	holder.name = "WholeFir_%s" % str(provenance.get("part", parent.get_child_count()))
	holder.position = foot
	holder.set_meta("model_key", "pine_tree")
	holder.set_meta("whole_fir", true)
	holder.set_meta("source_provenance", provenance.duplicate(true))
	holder.set_meta("template_path", path)
	holder.set_meta("template_height_px", int(template["crown_height_px"]))
	holder.set_meta("uniform_scale", uniform_scale)
	holder.set_meta("entity_id", id)
	parent.add_child(holder)
	var sp := Sprite3D.new()
	sp.name = "Model"
	sp.texture = texture
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sp.pixel_size = SCALE * uniform_scale
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.centered = true
	sp.offset = Vector2(texture.get_width() / 2.0 - float(anchor[0]),
		float(anchor[1]) - texture.get_height() / 2.0)
	sp.set_meta("path", path)
	sp.set_meta("screen", int(provenance.get("screen", -1)))
	holder.add_child(sp)
	world.call("shadow_twin", sp, false)
	var height := float(template["crown_height_px"]) * SCALE * uniform_scale
	holder.set_meta("height", height)
	holder.set_meta("billboard", true)
	if collision:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id", id)
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, height, 0.8)
		shape.position.y = height * 0.5
		shape.shape = box
		body.add_child(shape)
		holder.add_child(body)
	return holder
