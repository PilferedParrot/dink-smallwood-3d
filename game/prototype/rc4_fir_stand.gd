# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: Disconnected rejected fir layout; no normal world integration.
# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Isolated fir-stand prototype. The caller decides whether the rendered source
# and eye-level views read as the original forest before integrating it.
extends RefCounted

const SCALE := 0.025
const FIT_PATH := "res://prototype/rc4_fir_stand.json"
const ATLAS_PATH := "res://assets/tiles/ts01.png"

static func load_fit() -> Dictionary:
	if not FileAccess.file_exists(FIT_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
	return parsed if parsed is Dictionary else {}


static func fixture(fit: Dictionary, screen: int) -> Dictionary:
	if str(fit.get("schema", "")) != "rc4-fir-stand-prototype-1": return {}
	var fixtures: Dictionary = fit.get("fixtures", {})
	return fixtures.get(str(screen), {})


# Exact source member check. Call this on raw editor sprites in both the upright
# build path and the type-0 background-paint path. A story sprite of another
# vision/type/frame is never suppressed by an index match alone.
static func suppresses_sprite(fit: Dictionary, screen: int, e: Dictionary,
		source_list_index: int = -1) -> bool:
	var data := fixture(fit, screen)
	if data.is_empty(): return false
	var ownership: Dictionary = data.get("ownership", {})
	for member in ownership.get("suppressed_trim_members", []):
		if source_list_index >= 0 and int(member["member"][2]) != source_list_index: continue
		if int(member.get("editor_index", -1)) != int(e.get("editor_num", e.get("index", -1))): continue
		if int(member.get("seq", -1)) != int(e.get("seq", -1)): continue
		if int(member.get("frame", -1)) != int(e.get("frame", -1)): continue
		if int(member.get("type", -1)) != int(e.get("type", -1)): continue
		if int(member.get("vision", -1)) != int(e.get("vision", -1)): continue
		if int(member.get("hard", -1)) != int(e.get("hard", -1)): continue
		if not str(e.get("script", "")).is_empty() or int(e.get("brain", 0)) != 0: continue
		if absf(float(e.get("size", 100)) - 100.0) >= 0.5: continue
		return true
	return false


# Repaint only source pixels owned by the forest-tile mask. The four donor
# cells are original grass, with phase recorded per source tile in the fit.
# Collision and source hard masks are never touched.
static func replacement_ground(source: Texture2D, data: Dictionary) -> Texture2D:
	if source == null or data.is_empty(): return null
	var ownership: Dictionary = data.get("ownership", {})
	if ownership.get("forest_pixel_mask_runs", []).is_empty(): return source
	var image := source.get_image().duplicate() as Image
	if image == null or image.get_size() != Vector2i(600, 400): return null
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var atlas_texture := load(ATLAS_PATH) as Texture2D
	if atlas_texture == null: return null
	var atlas := atlas_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var donors: Dictionary = ownership.get("grass_donor_by_tile_member", {})
	for run in ownership.get("forest_pixel_mask_runs", []):
		var first := int(run[0])
		var end := first + int(run[1])
		for flat in range(first, end):
			var x := flat % 600
			var y := int(flat / 600)
			var tile_index := int(y / 50) * 12 + int(x / 50)
			var key := str(tile_index)
			if not donors.has(key): continue
			var donor := int(donors[key]) % 128
			var sx := (donor % 12) * 50 + x % 50
			var sy := int(donor / 12) * 50 + y % 50
			image.set_pixel(x, y, atlas.get_pixel(sx, sy))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# `world` is the live fp_world helper. Its existing clean_texture,
# sprite_foot, and shadow_twin own the sprite treatment; there is no new
# per-screen shadow or scale rule. `offset` is add_ground's screen offset.
# This adds visual cutouts only, with no collision bodies.
static func build(world: Object, parent: Node3D, offset: Vector3,
		source_ground: Texture2D, fit: Dictionary, screen: int, vision: int = 0) -> Dictionary:
	var data := fixture(fit, screen)
	if data.is_empty() or world == null or parent == null: return {}
	var path := str(fit.get("source", {}).get("whole_fir", ""))
	var texture: Texture2D = world.call("clean_texture", path) as Texture2D
	if texture == null: return {}
	var foot: Vector2 = world.call("sprite_foot", path)
	if foot.y < 0: return {}
	var holder := Node3D.new()
	holder.name = "FirStand_%d" % screen
	holder.position = offset
	holder.set_meta("prototype_owner", "rc4_fir_stand")
	parent.add_child(holder)
	var nodes: Array[Node3D] = []
	for i in data.get("placements", []).size():
		var placement: Dictionary = data["placements"][i]
		if int(placement.get("vision", 0)) != 0 and int(placement.get("vision", 0)) != vision: continue
		var at: Array = placement["foot"]
		var node := Node3D.new()
		node.name = "WholeFir_%d" % i
		node.position = Vector3((float(at[0]) - 300.0) * SCALE, 0.0,
			(float(at[1]) - 200.0) * SCALE)
		node.set_meta("model_key", "pine_tree")
		node.set_meta("prototype_source", placement.get("class", ""))
		holder.add_child(node)
		var sprite := Sprite3D.new()
		sprite.name = "Model"
		sprite.texture = texture
		sprite.shaded = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		sprite.pixel_size = SCALE
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.centered = true
		sprite.offset = Vector2(texture.get_width() / 2.0 - foot.x,
			foot.y - texture.get_height() / 2.0)
		node.add_child(sprite)
		world.call("shadow_twin", sprite, false)
		nodes.append(node)
	return {"holder": holder, "nodes": nodes,
		"ground": replacement_ground(source_ground, data),
		"suppressed_trim_members": data["ownership"]["suppressed_trim_members"]}
