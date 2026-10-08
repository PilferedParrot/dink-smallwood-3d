# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# The house interior stands solid (docs/DIRECTION.md, "The interior stands solid"): its walls, the door at the end of the
# corridor, the round table, the beds and the hearth, built from their own sprites' pixels as the houses and huts are.
# tools/interior_fit.py reads each shape from its sprite (data/interior.json); this builds the meshes.
#
# Everything is in the sprite's own frame: a point at ground (X, Z) and height Y is drawn at the sprite pixel (X, Z - Y) by the
# original camera, so a seen face takes its texture by that projection (exact on a plane), and the geometry is placed at the sprite's
# hotspot. Three rules for a face the camera does not see (the facades' rules):
#   - opposite a seen face (the box's far side): the seen face through the box's centre (a point reflection);
#   - edge-on (a box square to the camera has two): the adjacent seen face continued round the shared edge;
#   - a hidden twin (a table's back leg, a pier's far side): its source's picture.
# Shape classes: "wall" (a box over the sprite's hard rectangle, the face its stone, the cap its top), "round" (a table top of
# revolution on legs), "bed" (a box turned on its axis), "frontal" (a body square to the camera, with a stack on its back edge, legs,
# an opening). The depth of what the sprite cannot show (a hearth's, a shelf's) is the distance to the wall behind it.
extends RefCounted

const S := 0.025
const SIDE_MIN := 0.1 # a face is seen by the camera when its outward normal has this much of +Z (the original viewer)
var world # fp_world.gd
var fits: Dictionary = {}
var cache: Dictionary = {}
var materials: Dictionary = {}
var heights: Dictionary = {} # screen -> room height, source px

# A mesh being built: vertices at sprite px (X, Y, Z) shifted by `o` to the hotspot, their texture coordinates in sprite px.
class MB:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var size := Vector2.ONE
	var o := Vector2.ZERO
	func vert(x: float, y: float, z: float, uv: Vector2) -> int:
		verts.append(Vector3(x + o.x, y, z + o.y) * 0.025)
		uvs.append(uv / size)
		return verts.size() - 1
	func quad(a: int, b: int, c: int, d: int) -> void:
		index.append_array(PackedInt32Array([a, b, c, a, c, d]))
	func tri(a: int, b: int, c: int) -> void:
		index.append_array(PackedInt32Array([a, b, c]))
	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

func _init(fp) -> void:
	world = fp
	var path := "res://data/interior.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	fits = parsed if parsed is Dictionary else {}

func fit_of(path: String) -> Dictionary:
	var f: Variant = fits.get(path, {})
	return f if f is Dictionary else {}

# Whether every wall sprite of the screen has a fit (the rooms of the opening: innwalls frames 19 to 30 and 33 to 36). A room with
# any other wall piece keeps its plaster boxes and their 3.6 m: the ceiling, the stone and the walls must agree.
var fitted_screens: Dictionary = {}
func walls_fitted(screen: int) -> bool:
	if fitted_screens.has(screen): return fitted_screens[screen]
	var ok := false
	for e in world.host.world.screens.get(str(screen), {}).get("sprites", []):
		if world.model_key(e) != "wall": continue
		if str(fit_of(world.frame_path(e)).get("kind", "")) != "wall":
			ok = false
			break
		ok = true
	fitted_screens[screen] = ok
	return ok

func handles(e: Dictionary) -> bool:
	if absf(float(e.get("size", 100)) - 100.0) >= 0.5 or fit_of(world.frame_path(e)).is_empty(): return false
	return walls_fitted(world.host.current_screen) or not is_wall(e)

func is_wall(e: Dictionary) -> bool:
	return str(fit_of(world.frame_path(e)).get("kind", "")) == "wall"

# --- Materials and nodes ------------------------------------------------------------------------------------------------------
func material(path: String, repeat: bool = false) -> StandardMaterial3D:
	var key := "%s:%s" % [path, repeat]
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = world.host._texture("res://" + path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = repeat
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	materials[key] = m
	return m

func node_of(surfaces: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "Model"
	for sf in surfaces:
		var mi := MeshInstance3D.new()
		mi.mesh = sf[0]
		mi.set_surface_override_material(0, sf[1])
		node.add_child(mi)
	return node

func hotspot(e: Dictionary) -> Vector2:
	var d: Dictionary = world.host._frame(int(e.get("pseq", e.get("seq", 0))), int(e.get("pframe", e.get("frame", 1))))
	return Vector2(float(d.get("dx", 0)), float(d.get("dy", 0)))

# --- The prism: every box the sprites hold -------------------------------------------------------------------------------------
# `base` the footprint (sprite px (X, Z), around), y0..y1 its height. The texture coordinate of the point (X, Z) at height Y on
# face i, by the three rules at the head of the file. `anchor` shifts the sampled point (a hidden twin takes its source's picture).
func _normal(base: Array, i: int, c: Vector2) -> Vector2:
	var p: Vector2 = base[i]
	var q: Vector2 = base[(i + 1) % base.size()]
	var d := q - p
	var n := Vector2(d.y, -d.x).normalized()
	return -n if n.dot((p + q) * 0.5 - c) < 0.0 else n

func _proj(x: Vector2, y: float, anchor: Vector2) -> Vector2:
	return Vector2(x.x + anchor.x, x.y + anchor.y - y)

func _face_uv(base: Array, i: int, c: Vector2, x: Vector2, y: float, anchor: Vector2) -> Vector2:
	var n := base.size()
	var nrm := _normal(base, i, c)
	if nrm.y > SIDE_MIN: return _proj(x, y, anchor)
	if -nrm.y > SIDE_MIN: return _proj(2.0 * c - x, y, anchor) # the far side: the seen face through the centre
	# edge-on: continue the adjacent seen face round the shared corner
	var best := -2.0
	var shared := Vector2.ZERO
	var away := Vector2.ZERO
	var length := 0.0
	for step in [1, -1]:
		var k := posmod(i + step, n)
		var kn := _normal(base, k, c)
		if kn.y <= best or kn.y <= SIDE_MIN: continue
		best = kn.y
		shared = base[(i + 1) % n] if step == 1 else base[i]
		var far: Vector2 = base[(k + 1) % n] if step == 1 else base[k]
		var edge: Vector2 = far - shared
		length = edge.length()
		away = edge / maxf(length, 0.001)
	if best < 0.0: return _proj(x, y, anchor)
	var s := (x - shared).length()
	return _proj(shared + away * minf(s, length), y, anchor)

func prism(mb: MB, base: Array, y0: float, y1: float, anchor: Vector2 = Vector2.ZERO, top: bool = true) -> void:
	var n := base.size()
	var c := Vector2.ZERO
	for p in base: c += p as Vector2
	c /= float(n)
	for i in n:
		var p: Vector2 = base[i]
		var q: Vector2 = base[(i + 1) % n]
		var a := mb.vert(p.x, y0, p.y, _face_uv(base, i, c, p, y0, anchor))
		var b := mb.vert(q.x, y0, q.y, _face_uv(base, i, c, q, y0, anchor))
		var cc := mb.vert(q.x, y1, q.y, _face_uv(base, i, c, q, y1, anchor))
		var d := mb.vert(p.x, y1, p.y, _face_uv(base, i, c, p, y1, anchor))
		mb.quad(a, b, cc, d)
	if top:
		var ids: Array[int] = []
		for p in base: ids.append(mb.vert((p as Vector2).x, y1, (p as Vector2).y, _proj(p, y1, anchor)))
		for i in range(1, n - 1): mb.tri(ids[0], ids[i], ids[i + 1])

func rect_base(x0: float, x1: float, z0: float, z1: float) -> Array:
	return [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]

# --- The entity: the hook fp_world.make_entity calls ----------------------------------------------------------------------------
func add_entity(node: Node3D, e: Dictionary, id: int, collision: bool, screen: int) -> void:
	var path: String = world.frame_path(e)
	var fit := fit_of(path)
	var o := hotspot(e)
	var surfaces: Array = []
	match str(fit.kind):
		"wall": surfaces = wall_surfaces(e, fit, path, o, screen)
		"round": surfaces = round_surfaces(fit, path, o)
		"bed": surfaces = bed_surfaces(fit, path, o)
		"frontal": surfaces = frontal_surfaces(e, fit, path, o, screen)
		"post": surfaces = post_surfaces(fit, path, o)
	if surfaces.is_empty(): return
	var model := node_of(surfaces)
	node.add_child(model)
	if collision:
		if str(fit.kind) == "wall":
			# a wall's body is its hard rectangle, a box (as the plaster box's was): a point query (the dialogue camera's) rejects a
			# place inside it, which a concave body of faces cannot
			var rect: Rect2 = world.hard_rect(e)
			var h := room_height(screen) * S
			var body := StaticBody3D.new()
			body.name = "HitBody"
			body.set_meta("entity_id", id)
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(0.2, rect.size.x * S), h, maxf(0.2, rect.size.y * S))
			shape.shape = box
			shape.position = Vector3((rect.get_center().x - float(e.get("x", 0))) * S, h * 0.5, (rect.get_center().y - float(e.get("y", 0))) * S)
			body.add_child(shape)
			node.add_child(body)
		else:
			var hit: StaticBody3D = world.ray_body(model, id)
			hit.collision_layer = 2 if not str(e.get("script", "")).is_empty() else 1 # scripted things are what the player talks to (update_visual)
			node.add_child(hit)
	node.set_meta("height", world.model_height(model))
	node.set_meta("interior_solid", true)
	# A wall piece the map marks type 2 (never drawn) is the hardness of a stretch of wall the drawn pieces leave open (the
	# corners): the room's walls stand there as well, as every hard region must show something.
	if str(fit.kind) == "wall": node.set_meta("hard_wall", true)

func new_mb(path: String, fit: Dictionary, o: Vector2) -> MB:
	var mb := MB.new()
	mb.size = Vector2(float(fit.size[0]), float(fit.size[1]))
	mb.o = -o
	return mb

# --- Walls ---------------------------------------------------------------------------------------------------------------------
# A span's frame is its cap (rows above `cap`: the top face) over its face (the stone, the baseboard: the rows to `base`, as high as
# they are many). The box is the sprite's hard rectangle: its seen face (the south side) at the art's own base row where that lies
# inside the rectangle, the far side the same stone turned round, the ends the room's stone (the wall's own picture is its end-on
# strip), the top the cap. A pier (no cap: the frame is a top face seen end-on) shows the room's stone on every side and its own
# picture on top.
func room_stone(screen: int) -> String:
	var counts: Dictionary = {}
	for e in world.host.world.screens.get(str(screen), {}).get("sprites", []):
		var p: String = world.frame_path(e)
		var f := fit_of(p)
		if str(f.get("kind", "")) == "wall" and int(f.get("cap", 0)) > 0 and int(f.size[0]) >= 100:
			counts[p] = int(counts.get(p, 0)) + 1
	var best := ""
	var best_n := 0
	var keys: Array = counts.keys()
	keys.sort()
	for p in keys:
		if int(counts[p]) > best_n:
			best_n = int(counts[p])
			best = p
	return best

func room_height(screen: int) -> float:
	if heights.has(screen): return heights[screen]
	var h := 0.0
	for e in world.host.world.screens.get(str(screen), {}).get("sprites", []):
		var f := fit_of(world.frame_path(e))
		if str(f.get("kind", "")) == "wall": h = maxf(h, float(f.get("height", 0)))
	if h <= 0.0 or not walls_fitted(screen): h = 3.56 / S # the plaster boxes' own: 3.6 m, the ceiling's underside at 3.56
	heights[screen] = h
	return h

func wall_surfaces(e: Dictionary, fit: Dictionary, path: String, o: Vector2, screen: int) -> Array:
	var stone := room_stone(screen)
	if stone.is_empty(): stone = path
	var sfit := fit_of(stone)
	var rect: Rect2 = world.hard_rect(e)
	var top_left := Vector2(float(e.get("x", 0)), float(e.get("y", 0))) - o # the sprite's top-left, screen px
	var x0 := rect.position.x - top_left.x
	var x1 := rect.end.x - top_left.x
	var z0 := rect.position.y - top_left.y
	var z1 := rect.end.y - top_left.y
	var span: bool = int(fit.cap) > 0
	var h := room_height(screen)
	if span:
		var art_front := float(fit.base)
		if art_front > z0 + 2.0 and art_front < z1: z1 = art_front
	var own := new_mb(path, fit, o)
	var rock := new_mb(stone, sfit, o)
	# The faces (south, seen; north, the same turned round): the sprite at its own place where it lies in the footprint, the room's
	# stone on the rest (a jamb's picture is 18 px, its hard rectangle 32 to 47).
	var a := clampf(float(fit.cols[0]), x0, x1) if span else x0
	var b := clampf(float(fit.cols[1]), x0, x1) if span else x0
	for north in [false, true]:
		var z := z0 if north else z1
		var pieces: Array = [[x0, x1, false]]
		if b - a >= 1.0 and not north: pieces = [[x0, a, false], [a, b, true], [b, x1, false]]
		if b - a >= 1.0 and north: pieces = [[x0, x0 + x1 - b, false], [x0 + x1 - b, x0 + x1 - a, true], [x0 + x1 - a, x1, false]]
		for pc in pieces:
			if float(pc[1]) - float(pc[0]) < 0.01: continue
			var mb: MB = own if bool(pc[2]) else rock
			var f: Dictionary = fit if bool(pc[2]) else sfit
			var mirror: float = (x0 + x1) if north else -1.0
			_wall_face(mb, float(pc[0]), float(pc[1]), z, h, f, mirror)
	# the ends: the room's stone running on from the south corner
	_wall_end(rock, x0, z0, z1, h, sfit, 1.0)
	_wall_end(rock, x1, z0, z1, h, sfit, -1.0)
	# the top: the cap (a pier: its own frame, end-on)
	var cap_v := float(fit.cap) if span else float(fit.size[1])
	var tv := [own.vert(x0, h, z1, Vector2(0, cap_v)), own.vert(x1, h, z1, Vector2(float(fit.size[0]), cap_v)),
		own.vert(x1, h, z0, Vector2(float(fit.size[0]), 0.0)), own.vert(x0, h, z0, Vector2(0, 0.0))]
	own.quad(tv[0], tv[1], tv[2], tv[3])
	var out: Array = []
	out.append([own.mesh(), material(path)])
	if rock.verts.size() > 0: out.append([rock.mesh(), material(stone, true)])
	return out

func _wall_v(f: Dictionary, y: float) -> float:
	return float(f.base) - (float(f.base) - float(f.cap)) * y / maxf(float(f.height), 1.0)

# A vertical face of a wall box from xa to xb at depth z, the frame's picture at 1 px a source px (u = x), the face's far side
# (mirror = the box's x0 + x1) turned round.
func _wall_face(mb: MB, xa: float, xb: float, z: float, h: float, f: Dictionary, mirror: float) -> void:
	var ua := xa if mirror < 0.0 else mirror - xa
	var ub := xb if mirror < 0.0 else mirror - xb
	var v0 := _wall_v(f, 0.0)
	var v1 := _wall_v(f, h)
	var p := mb.vert(xa, 0, z, Vector2(ua, v0))
	var q := mb.vert(xb, 0, z, Vector2(ub, v0))
	var r := mb.vert(xb, h, z, Vector2(ub, v1))
	var t := mb.vert(xa, h, z, Vector2(ua, v1))
	mb.quad(p, q, r, t)

# An end of a wall box: the room's stone continued from the corner on its south side, at the stone's own scale (it repeats).
func _wall_end(mb: MB, x: float, z0: float, z1: float, h: float, f: Dictionary, dir: float) -> void:
	var run := z1 - z0
	var u0 := 0.0 if dir > 0.0 else run
	var u1 := run if dir > 0.0 else 0.0
	var a := mb.vert(x, 0, z1, Vector2(u0, _wall_v(f, 0.0)))
	var b := mb.vert(x, 0, z0, Vector2(u1, _wall_v(f, 0.0)))
	var c := mb.vert(x, h, z0, Vector2(u1, _wall_v(f, h)))
	var d := mb.vert(x, h, z1, Vector2(u0, _wall_v(f, h)))
	mb.quad(a, b, c, d)

# The stone of the room without its cap and baseboard, for what the sprites do not draw (the solid blocks the tile hardness leaves
# at the corners): a plain texture the world's own coordinates repeat across, one texture to its own width.
func terrain_material(screen: int) -> StandardMaterial3D:
	var stone := room_stone(screen)
	var sfit := fit_of(stone)
	if stone.is_empty() or not sfit.has("stone"): return null
	var key := "terrain:" + stone
	if materials.has(key): return materials[key]
	var img: Image = world.sprite_image(stone)
	if img == null: return null
	var rows: Array = sfit.stone
	var crop := img.get_region(Rect2i(0, int(rows[0]), img.get_width(), int(rows[1]) - int(rows[0])))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(crop)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / (float(img.get_width()) * S)
	materials[key] = m
	return m

# --- The round table -----------------------------------------------------------------------------------------------------------
const RING := 48
func round_surfaces(fit: Dictionary, path: String, o: Vector2) -> Array:
	var key := "round:" + path
	if cache.has(key):
		return _shifted(cache[key], o)
	var mb := new_mb(path, fit, Vector2.ZERO)
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var rt := float(fit.top.r)
	var ht := float(fit.top.height)
	var ru := float(fit.under.r)
	var hu := float(fit.under.height)
	var ring := func(r: float, y: float, t: float) -> Vector3:
		return Vector3(cx + r * cos(t), y, cz + k * r * sin(t))
	# the picture of ring point t at height y: the front half by projection; the back half the front point across the view
	var pic := func(r: float, y: float, t: float) -> Vector2:
		var s := sin(t)
		var tt := t if s >= 0.0 else -t
		return Vector2(cx + r * cos(tt), cz + k * r * sin(tt) - y)
	var top_centre := mb.vert(cx, ht, cz, Vector2(cx, cz - ht))
	var top_ids: Array[int] = []
	var rim_t: Array[int] = []
	var rim_u: Array[int] = []
	for i in RING + 1:
		var t := TAU * float(i) / RING
		var p: Vector3 = ring.call(rt, ht, t)
		top_ids.append(mb.vert(p.x, p.y, p.z, Vector2(p.x, p.z - ht)))
		rim_t.append(mb.vert(p.x, p.y, p.z, pic.call(rt, ht, t)))
		var q: Vector3 = ring.call(ru, hu, t)
		rim_u.append(mb.vert(q.x, q.y, q.z, pic.call(ru, hu, t)))
	for i in RING:
		mb.tri(top_centre, top_ids[i], top_ids[i + 1])
		mb.quad(rim_t[i], rim_t[i + 1], rim_u[i + 1], rim_u[i])
	# the underside: a fan of the rim's lowest picture
	var under_centre := mb.vert(cx, hu, cz, Vector2(cx, cz - hu))
	var under_ids: Array[int] = []
	for i in RING + 1:
		var t := TAU * float(i) / RING
		var q: Vector3 = ring.call(ru, hu, t)
		under_ids.append(mb.vert(q.x, q.y, q.z, pic.call(ru, hu, t)))
	for i in RING: mb.tri(under_centre, under_ids[i + 1], under_ids[i])
	var legs: Array = fit.legs
	for leg in legs:
		var lt := float(leg.angle)
		var half := float(leg.half)
		var at := Vector2(cx + float(fit.rho) * cos(lt), cz + k * float(fit.rho) * sin(lt))
		var anchor := Vector2.ZERO
		if not bool(leg.seen):
			var src: Dictionary = legs[int(leg.source)]
			var st := float(src.angle)
			anchor = Vector2(cx + float(fit.rho) * cos(st), cz + k * float(fit.rho) * sin(st)) - at
		prism(mb, rect_base(at.x - half, at.x + half, at.y - half, at.y + half), 0.0, hu, anchor, false)
	var surfaces: Array = [[mb.mesh(), material(path)]]
	cache[key] = surfaces
	return _shifted(surfaces, o)

# A cached mesh is built about the sprite's top-left; the node stands at the hotspot, so the model moves by -hotspot.
func _shifted(surfaces: Array, o: Vector2) -> Array:
	var out: Array = []
	for sf in surfaces:
		var mi := ArrayMesh.new()
		var arrays: Array = (sf[0] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		for v in verts: moved.append(v - Vector3(o.x, 0, o.y) * S)
		arrays[Mesh.ARRAY_VERTEX] = moved
		mi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append([mi, sf[1]])
	return out

# --- The bed ------------------------------------------------------------------------------------------------------------------
func bed_surfaces(fit: Dictionary, path: String, o: Vector2) -> Array:
	var mb := new_mb(path, fit, o)
	var base: Array = []
	for p in fit.base: base.append(Vector2(float(p[0]), float(p[1])))
	prism(mb, base, 0.0, float(fit.height))
	return [[mb.mesh(), material(path)]]

# --- Things square to the camera: the hearth, a shelf, a table ----------------------------------------------------------------
# The body: its front face the rows from `split` down, at the plane z_f of the sprite's base row, the top face the rows above (down
# to the stack's foot); its depth the top face's rows, but not past the wall behind it. A stack (the chimney) stands on the body's back
# edge, from the top face up; legs hold a body that does not reach the floor. An opening in the front face is a recess as deep as the
# body, its back the opening's own picture.
func wall_behind(e: Dictionary, x0: float, x1: float, z_f: float, screen: int) -> float:
	var best := -1.0
	for w in world.host.world.screens.get(str(screen), {}).get("sprites", []):
		var f := fit_of(world.frame_path(w))
		if str(f.get("kind", "")) != "wall" or int(f.get("cap", 0)) <= 0: continue
		var d := hotspot(w)
		var left := float(w.get("x", 0)) - d.x
		if left + float(f.size[0]) < x0 + 1.0 or left > x1 - 1.0: continue
		var zw := float(w.get("y", 0)) - d.y + float(f.base)
		if zw < z_f - 1.0: best = maxf(best, zw)
	return best

# The body's place in the sprite's frame: x0..x1, its front plane z_f, its back z_b (the depth: the top face's rows, not past the wall
# behind it), its top y_top (a shelf: its own height, to the room's) and bottom y_bot.
func frontal_dims(e: Dictionary, fit: Dictionary, o: Vector2, screen: int) -> Dictionary:
	var body: Dictionary = fit.body
	var top_left := Vector2(float(e.get("x", 0)), float(e.get("y", 0))) - o
	var z_f := float(fit.base)
	var x0 := float(body.cols[0])
	var x1 := float(body.cols[1])
	var r0 := float(body.rows[0])
	var split := float(body.split)
	var depth := split - r0
	var zw := wall_behind(e, top_left.x + x0, top_left.x + x1, top_left.y + z_f, screen)
	if depth <= 0.0 or zw > 0.0:
		var limit := (top_left.y + z_f - zw) if zw > 0.0 else float(world.hard_rect(e).size.y)
		depth = limit if depth <= 0.0 else minf(depth, limit)
	return {"x0": x0, "x1": x1, "z_f": z_f, "z_b": z_f - depth, "depth": depth, "y_top": minf(z_f - split, room_height(screen)), "y_bot": z_f - float(body.rows[1])}

func frontal_surfaces(e: Dictionary, fit: Dictionary, path: String, o: Vector2, screen: int) -> Array:
	var mb := new_mb(path, fit, o)
	var body: Dictionary = fit.body
	var dims := frontal_dims(e, fit, o, screen)
	var z_f: float = dims.z_f
	var x0: float = dims.x0
	var x1: float = dims.x1
	var r0 := float(body.rows[0])
	var r1 := float(body.rows[1])
	var split := float(body.split)
	var depth: float = dims.depth
	var room := room_height(screen)
	var y_top: float = dims.y_top
	var y_bot: float = dims.y_bot
	var z_b: float = dims.z_b
	var uv_front := func(x: float, y: float) -> Vector2: return Vector2(x, z_f - y)
	# the front face, round the opening
	var opening: Dictionary = fit.get("opening", {})
	var segs: Array = []
	if opening.is_empty():
		segs.append([x0, x1, y_bot, y_top])
	else:
		var ox0 := float(opening.cols[0])
		var ox1 := float(opening.cols[1])
		var oy1 := z_f - float(opening.rows[0]) # the opening's top, in height
		var oy0 := z_f - float(opening.rows[1])
		segs.append([x0, ox0, y_bot, y_top])
		segs.append([ox1, x1, y_bot, y_top])
		if oy1 < y_top: segs.append([ox0, ox1, oy1, y_top])
		if oy0 > y_bot: segs.append([ox0, ox1, y_bot, oy0])
	for sg in segs:
		var a := mb.vert(sg[0], sg[2], z_f, uv_front.call(sg[0], sg[2]))
		var b := mb.vert(sg[1], sg[2], z_f, uv_front.call(sg[1], sg[2]))
		var c := mb.vert(sg[1], sg[3], z_f, uv_front.call(sg[1], sg[3]))
		var d := mb.vert(sg[0], sg[3], z_f, uv_front.call(sg[0], sg[3]))
		mb.quad(a, b, c, d)
	# the rest of the body: back, ends, top by the prism's rules; the front is drawn above, so only the other three faces and the top
	var base := rect_base(x0, x1, z_b, z_f)
	var prism_mb := mb
	var n := base.size()
	var c := Vector2((x0 + x1) * 0.5, (z_b + z_f) * 0.5)
	for i in n:
		var p: Vector2 = base[i]
		var q: Vector2 = base[(i + 1) % n]
		if absf(p.y - z_f) < 0.01 and absf(q.y - z_f) < 0.01: continue # the front face
		var uvs: Array = []
		for pt in [[p, y_bot], [q, y_bot], [q, y_top], [p, y_top]]:
			uvs.append(_face_uv(base, i, c, pt[0], pt[1], Vector2.ZERO))
		var a := prism_mb.vert(p.x, y_bot, p.y, uvs[0])
		var b := prism_mb.vert(q.x, y_bot, q.y, uvs[1])
		var cc := prism_mb.vert(q.x, y_top, q.y, uvs[2])
		var d := prism_mb.vert(p.x, y_top, p.y, uvs[3])
		prism_mb.quad(a, b, cc, d)
	var ids: Array[int] = []
	for p in base: ids.append(mb.vert((p as Vector2).x, y_top, (p as Vector2).y, _proj(p, y_top, Vector2.ZERO)))
	mb.quad(ids[0], ids[1], ids[2], ids[3])
	# the hollow of an opening: the back picture is the opening's pixels, the sides and floor the dark of it
	if not opening.is_empty():
		var ox0 := float(opening.cols[0])
		var ox1 := float(opening.cols[1])
		var oy1 := z_f - float(opening.rows[0])
		var oy0 := z_f - float(opening.rows[1])
		var dark := Vector2((ox0 + ox1) * 0.5, (float(opening.rows[0]) + float(opening.rows[1])) * 0.5)
		var bk := mb.vert(ox0, oy0, z_b, uv_front.call(ox0, oy0))
		var bl := mb.vert(ox1, oy0, z_b, uv_front.call(ox1, oy0))
		var bt := mb.vert(ox1, oy1, z_b, uv_front.call(ox1, oy1))
		var bu := mb.vert(ox0, oy1, z_b, uv_front.call(ox0, oy1))
		mb.quad(bk, bl, bt, bu)
		for sx in [ox0, ox1]:
			var s0 := mb.vert(sx, oy0, z_f, dark)
			var s1 := mb.vert(sx, oy0, z_b, dark)
			var s2 := mb.vert(sx, oy1, z_b, dark)
			var s3 := mb.vert(sx, oy1, z_f, dark)
			mb.quad(s0, s1, s2, s3)
		var f0 := mb.vert(ox0, oy0, z_f, dark)
		var f1 := mb.vert(ox1, oy0, z_f, dark)
		var f2 := mb.vert(ox1, oy0, z_b, dark)
		var f3 := mb.vert(ox0, oy0, z_b, dark)
		mb.quad(f0, f1, f2, f3)
	# the stack(s): a front face on the back edge from the top face up, its rows from the top face's back edge up
	for up in fit.get("above", []):
		var ux0 := float(up.cols[0])
		var ux1 := float(up.cols[1])
		var y_up := minf(z_b - float(up.rows[0]), room)
		var a := mb.vert(ux0, y_top, z_b, Vector2(ux0, z_b - y_top))
		var b := mb.vert(ux1, y_top, z_b, Vector2(ux1, z_b - y_top))
		var cc := mb.vert(ux1, y_up, z_b, Vector2(ux1, z_b - y_up))
		var d := mb.vert(ux0, y_up, z_b, Vector2(ux0, z_b - y_up))
		mb.quad(a, b, cc, d)
		var sbase := rect_base(ux0, ux1, z_b - depth, z_b)
		var sc := Vector2((ux0 + ux1) * 0.5, z_b - depth * 0.5)
		for i in 4:
			var p: Vector2 = sbase[i]
			var q: Vector2 = sbase[(i + 1) % 4]
			if absf(p.y - z_b) < 0.01 and absf(q.y - z_b) < 0.01: continue
			var ua := mb.vert(p.x, y_top, p.y, Vector2(clampf(p.x, ux0, ux1), z_b - y_top))
			var ub := mb.vert(q.x, y_top, q.y, Vector2(clampf(q.x, ux0, ux1), z_b - y_top))
			var uc := mb.vert(q.x, y_up, q.y, Vector2(clampf(q.x, ux0, ux1), z_b - y_up))
			var ud := mb.vert(p.x, y_up, p.y, Vector2(clampf(p.x, ux0, ux1), z_b - y_up))
			mb.quad(ua, ub, uc, ud)
	# legs: the feet are the front legs; the back legs are the front legs a body's depth back
	for leg in fit.get("legs", []):
		var lx0 := float(leg.cols[0])
		var lx1 := float(leg.cols[1])
		var wl := lx1 - lx0
		prism(mb, rect_base(lx0, lx1, z_f - wl, z_f), 0.0, y_bot, Vector2.ZERO, false)
		prism(mb, rect_base(lx0, lx1, z_b, z_b + wl), 0.0, y_bot, Vector2(0.0, depth - wl), false)
	return [[mb.mesh(), material(path)]]

# --- A post --------------------------------------------------------------------------------------------------------------------
# Runs of rows of one extent, from the sprite's fit: the lowest a square footing, the rest slabs as deep as the shaft is wide, stacked
# so each stands on the one below it (a slab's front plane is half its depth in front of the axis, so the heights are carried up, not
# read off the rows). Faces by direct mapping: front rows to the run's height, the back through the axis, the ends the front
# continued round the corner.
func post_surfaces(fit: Dictionary, path: String, o: Vector2) -> Array:
	var mb := new_mb(path, fit, o)
	var runs: Array = fit.runs
	var z_c := float(fit.z_axis)
	var below := 0.0
	for i in range(runs.size() - 1, -1, -1):
		var r: Array = runs[i]
		var x0 := float(r[2])
		var x1 := float(r[3])
		var d := float(fit.footing) if i == runs.size() - 1 else float(fit.shaft)
		var z_f := z_c + d * 0.5
		var z_b := z_c - d * 0.5
		var y1 := z_f - float(r[0])
		var y0 := z_f - float(r[1]) if i == runs.size() - 1 else below
		if y1 <= y0: y1 = y0 + float(r[1]) - float(r[0])
		below = y1
		var v0 := float(r[1])
		var v1 := float(r[0])
		var xm := x0 + x1
		var faces := [
			[Vector3(x0, 0, z_f), Vector3(x1, 0, z_f), Vector2(x0, v0), Vector2(x1, v0), Vector2(x1, v1), Vector2(x0, v1)],
			[Vector3(x1, 0, z_b), Vector3(x0, 0, z_b), Vector2(xm - x1, v0), Vector2(xm - x0, v0), Vector2(xm - x0, v1), Vector2(xm - x1, v1)],
			[Vector3(x0, 0, z_b), Vector3(x0, 0, z_f), Vector2(x0 + d, v0), Vector2(x0, v0), Vector2(x0, v1), Vector2(x0 + d, v1)],
			[Vector3(x1, 0, z_f), Vector3(x1, 0, z_b), Vector2(x1, v0), Vector2(x1 - d, v0), Vector2(x1 - d, v1), Vector2(x1, v1)]]
		for f in faces:
			var a: Vector3 = f[0]
			var b: Vector3 = f[1]
			var ia := mb.vert(a.x, y0, a.z, f[2])
			var ib := mb.vert(b.x, y0, b.z, f[3])
			var ic := mb.vert(b.x, y1, b.z, f[4])
			var id := mb.vert(a.x, y1, a.z, f[5])
			mb.quad(ia, ib, ic, id)
		# the top, by the front's top row
		var t0 := mb.vert(x0, y1, z_b, Vector2(x0, v1))
		var t1 := mb.vert(x1, y1, z_b, Vector2(x1, v1))
		var t2 := mb.vert(x1, y1, z_f, Vector2(x1, v1))
		var t3 := mb.vert(x0, y1, z_f, Vector2(x0, v1))
		mb.quad(t0, t1, t2, t3)
	return [[mb.mesh(), material(path)]]

# --- The door -----------------------------------------------------------------------------------------------------------------
# The exit of a room that runs off the bottom of the screen (a type 2 sprite with a warp, whose hard rectangle ends below the
# screen): the corridor the walls leave round it ends in a door of Dink's own door art (struct/Details/Door/odor1-01: its parallelogram
# is mapped onto an upright rectangle the width of the corridor), the stone of the walls above it.
const DOOR := "assets/graphics/struct/Details/Door/odor1-01.png"
func exits(screen: int) -> Array:
	var out: Array = []
	var sprites: Array = world.host.world.screens.get(str(screen), {}).get("sprites", [])
	for e in sprites:
		if e.get("warp") == null or int(e.get("type", 1)) != 2: continue
		var rect: Rect2 = world.hard_rect(e)
		if rect.end.y <= 400.0: continue # not off the bottom of the screen
		var probe := rect.position.y - 2.0
		var left := -1.0
		var right := 1.0e9
		var base := 1.0e9
		for w in sprites:
			if not is_wall(w): continue
			var wr: Rect2 = world.hard_rect(w)
			if probe < wr.position.y or probe > wr.end.y: continue
			var cx := rect.get_center().x
			var f := fit_of(world.frame_path(w))
			var art := float(w.get("y", 0)) - hotspot(w).y + float(f.base)
			if wr.end.x <= cx and wr.end.x > left:
				left = wr.end.x
				base = minf(base, art)
			if wr.position.x >= cx and wr.position.x < right:
				right = wr.position.x
				base = minf(base, art)
		if left < 0.0 or right > 1.0e8 or right - left < 8.0 or right - left > 90.0: continue
		out.append({"x0": left, "x1": right, "z": base if base < 1.0e8 else 400.0})
	return out

func add_doors(screen: int, parent: Node3D) -> void:
	var fit := fit_of(DOOR)
	if fit.is_empty() or not walls_fitted(screen): return
	var stone := room_stone(screen)
	var sfit := fit_of(stone)
	if stone.is_empty(): return
	var h := room_height(screen)
	for ex in exits(screen):
		var x0: float = ex.x0
		var x1: float = ex.x1
		var z: float = ex.z
		# The door closes the opening: the corridor's width, its picture kept in proportion (the art's own 0.025 m/px makes
		# it 1.32 m, under the 1.65 m eye, and from the doorway it read as a slot under a wall), never above the ceiling.
		var hd := minf(h, (x1 - x0) * float(fit.height) / maxf(float(fit.cols[1]) - float(fit.cols[0]), 1.0))
		var mb := MB.new()
		mb.size = Vector2(float(fit.size[0]), float(fit.size[1]))
		mb.o = Vector2(-320.0, -200.0) # screen px to metres about the screen's centre, as point() does
		var u0 := float(fit.cols[0])
		var u1 := float(fit.cols[1])
		var m := float(fit.slope)
		var line := func(u: float, top: bool) -> float: return (float(fit.top) if top else float(fit.base)) + m * u
		var a := mb.vert(x0, 0, z, Vector2(u0, line.call(u0, false)))
		var b := mb.vert(x1, 0, z, Vector2(u1, line.call(u1, false)))
		var c := mb.vert(x1, hd, z, Vector2(u1, line.call(u1, true)))
		var d := mb.vert(x0, hd, z, Vector2(u0, line.call(u0, true)))
		mb.quad(a, b, c, d)
		var door := MeshInstance3D.new()
		door.name = "ExitDoor"
		door.mesh = mb.mesh()
		door.set_surface_override_material(0, material(DOOR))
		parent.add_child(door)
		# the wall above the door: the room's stone at its own scale, from the door's top to the ceiling
		var sb := MB.new()
		sb.size = Vector2(float(sfit.size[0]), float(sfit.size[1]))
		sb.o = Vector2(-320.0, -200.0)
		var cap := float(sfit.cap)
		var base_row := float(sfit.base)
		var vf := func(y: float) -> float: return base_row - (base_row - cap) * y / maxf(float(sfit.height), 1.0)
		var w := x1 - x0
		var e0 := sb.vert(x0, hd, z, Vector2(0, vf.call(hd)))
		var e1 := sb.vert(x1, hd, z, Vector2(w, vf.call(hd)))
		var e2 := sb.vert(x1, h, z, Vector2(w, vf.call(h)))
		var e3 := sb.vert(x0, h, z, Vector2(0, vf.call(h)))
		sb.quad(e0, e1, e2, e3)
		var lintel := MeshInstance3D.new()
		lintel.name = "ExitLintel"
		lintel.mesh = sb.mesh()
		lintel.set_surface_override_material(0, material(stone, true))
		parent.add_child(lintel)
		parent.set_meta("exit_door", true)

# --- What stands on a surface ---------------------------------------------------------------------------------------------------
# The height of the highest solid top the original camera's ray through world px `foot` meets among the screen's furniture drawn
# before the sprite (its order less than `order`), 0 if none: the table's top disc, a prism's top.
func surface_height(foot: Vector2, order: float, screen: int, vision: int) -> float:
	var best := 0.0
	for e in world.drawn_sprites(screen, vision):
		if not handles(e): continue
		var e_order := float(e.get("que", 0)) if int(e.get("que", 0)) != 0 else float(e.get("y", 0))
		if order <= e_order: continue
		var fit := fit_of(world.frame_path(e))
		var o := hotspot(e)
		var at := foot - (Vector2(float(e.get("x", 0)), float(e.get("y", 0))) - o) # the foot in the sprite's frame
		match str(fit.kind):
			"round":
				var cx := float(fit.cx)
				var cz := float(fit.cz)
				var k := float(fit.k)
				var ht := float(fit.top.height)
				var r := float(fit.top.r)
				var dxr := (at.x - cx) / r
				var dzr := (at.y + ht - cz) / (k * r)
				if dxr * dxr + dzr * dzr <= 1.0: best = maxf(best, ht)
			"frontal":
				if fit.get("legs", []).is_empty(): continue # a table's top; a hearth's or a shelf's is not stood on
				var dims := frontal_dims(e, fit, o, screen)
				if at.x >= float(dims.x0) and at.x <= float(dims.x1) and at.y + float(dims.y_top) >= float(dims.z_b) and at.y + float(dims.y_top) <= float(dims.z_f):
					best = maxf(best, float(dims.y_top))
			"bed":
				var base: Array = []
				for p in fit.base: base.append(Vector2(float(p[0]), float(p[1])))
				var h := float(fit.height)
				if Geometry2D.is_point_in_polygon(Vector2(at.x, at.y + h), PackedVector2Array(base)): best = maxf(best, h)
	return best
