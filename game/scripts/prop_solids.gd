# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# The small props (barrels, sacks, pies, bottles, crates, chests ...) as solids built from their own sprites
# (docs/DIRECTION.md, "The small props are solid"), fitted by tools/prop_fit.py into prototype/props.json (by sprite path).
#
# The sprite is a picture from the original's raised camera: screen = (x, z - Y) in sprite px, a ground circle drawn as an
# ellipse of aspect k. A prop is built in TRUE ground units (a round thing is round: its depth is its width, not k of it,
# which is what made the huts narrow eggs) and textured by projecting the sprite back through that camera,
# UV = (cx + X, cz + k Z - Y), exact for what the camera saw. The front of its footprint stays where the picture draws it
# (its ground contact line, which the source hardbox and the painted shadow are drawn round): the prop grows backwards.
#   round: a solid of revolution, the huts' (sprite_buildings.gd _hut_uvs: the unseen half takes the seen half's picture,
#          back and forth round); its top is the picture of the top, projected as it is drawn.
#   box:   a box yawed about the vertical: the top and the two faces the camera sees are projected; a face it never saw
#          takes the picture of the opposite face (a box's back is its front turned half a round), or, where that is
#          unseen too (a box drawn square on), of the front face.
#   pillow: a thing lying on the ground (a grain bag, a ham, a loaf): an ellipsoid on a yawed elliptic footprint; what the
#          camera saw is projected, the rest takes the picture of the point half a turn round the vertical axis.
#   flat:  a thing lying on the ground (a scroll, a coin pile, splinters): a quad on the ground, its picture 1:1 in the
#          plan, as the game paints every ground sprite (the ground itself is the original's screen, 1:1).
extends RefCounted

const FITS := "res://prototype/props.json"
const LANDMARK_FITS := "res://prototype/landmarks.json" # tools/landmark_fit.py: compound solids (the well)
var buildings # sprite_buildings.gd
var S := 0.025 # metres per source pixel
var fits: Dictionary = {}
var cache: Dictionary = {} # sprite path -> [[mesh, texture or material], ...]
const WELL_SEEN := 0.342 # cos 70 degrees: a face (or ring point) the camera sees within 70 degrees of head-on is seen well (HUT_GRAZE)

func _init(b, scale: float) -> void:
	buildings = b
	S = scale
	if FileAccess.file_exists(FITS):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FITS))
		if parsed is Dictionary: fits = parsed
	if FileAccess.file_exists(LANDMARK_FITS):
		var more: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDMARK_FITS))
		if more is Dictionary: fits.merge(more,true)

func has(path: String) -> bool:
	return fits.has(path)

# The footprint of the prop on the ground, as (back, front) rows in the meshes' own frame (sprite px): its middle is
# (back + front)/2. A flat prop has none: (0, 0).
func footprint(path: String) -> Vector2:
	var fit: Dictionary = fits.get(path, {})
	if str(fit.get("class", "")) == "compound": fit = fit.base # a compound stands on its base
	if str(fit.get("class", "")) == "ring":
		var rz := float(fit.cz) - (1.0 - float(fit.k))*float(fit.rf)
		return Vector2(rz - float(fit.rf), rz + float(fit.rf))
	var k := float(fit.get("k", 0.4878))
	match str(fit.get("class", "")):
		"round":
			var zc := float(fit.cz) - (1.0 - k)*float(fit.nodes[0][1])
			var rmax := 0.0
			for n in fit.nodes: rmax = maxf(rmax, float(n[1]))
			return Vector2(zc - rmax, zc + rmax)
		"box":
			var e := _extent(fit)
			var zc := float(fit.cz) - (1.0 - k)*e.y
			return Vector2(zc + e.x, zc + e.y)
		"pillow":
			var half := _pillow_half(fit)
			var zc := float(fit.cz) - (1.0 - k)*half
			return Vector2(zc - half, zc + half)
	return Vector2.ZERO

func class_of(path: String) -> String:
	return str(fits.get(path, {}).get("class", ""))

# The prop as a node: origin at its sprite's top-left, as a hut.
func node(path: String) -> Node3D:
	return buildings.node_from(surfaces(path))

func surfaces(path: String) -> Array:
	if cache.has(path): return cache[path]
	var fit: Dictionary = fits[path]
	var out: Array = []
	match str(fit["class"]):
		"round": out = _round(path, fit)
		"pillow": out = _pillow(path, fit)
		"box": out = _box(path, fit)
		"compound": out = _compound(path, fit)
		"ring": out = _ring(path, fit)
		"flat": out = _flat(path, fit)
	cache[path] = out
	return out

# The sprite as the texture of one part: a part fitted from some of the sprite's pixels (fit.mask, one bit a pixel, row by row)
# keeps those and takes the rest from their neighbours (filled), so a post's wood does not paint the rim it stands on.
func _texture(path: String, fit: Dictionary = {}) -> ImageTexture:
	var img: Image = buildings.image(path)
	if fit.has("mask"):
		var bits := Marshalls.base64_to_raw(str(fit.mask))
		var data := img.get_data()
		# fit.void_fill: the palette's pure black inside the part is a drawn gap (the outline, the shadow between stones, a post's
		# shaded face), not a colour a solid can have on every side; it takes the nearest lit pixel of the same part.
		var voids := bool(fit.get("void_fill", false))
		for p in img.get_width()*img.get_height():
			if not (bits[p >> 3] >> (7 - (p & 7))) & 1 or (voids and data[p*4] == 0 and data[p*4 + 1] == 0 and data[p*4 + 2] == 0): data[p*4 + 3] = 0
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	return buildings._texture(buildings.filled(img))

func _arrays(verts: PackedVector3Array, uvs: PackedVector2Array, index: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# --- round ----------------------------------------------------------------------------------------------------------
func _round(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var nodes: Array = fit.nodes
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var n := int(fit.ring)
	var zc := cz - (1.0 - k)*float(nodes[0][1]) # the base circle's front stays on the row the picture draws it on
	var uvs: Array = buildings._hut_uvs(fit)
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	var cols := n + 1
	var view := Vector3(0.0, k, 1.0).normalized() # toward the original camera (a ray from the surface to it)
	for i in nodes.size():
		var h := float(nodes[i][0])
		var r := float(nodes[i][1])
		# The wall's slope here: a surface that leans back (a dome, a shoulder) faces the camera over the far side too.
		var lo := maxi(i - 1, 0)
		var hi := mini(i + 1, nodes.size() - 1)
		var slope := -(float(nodes[hi][1]) - float(nodes[lo][1]))/maxf(0.001, float(nodes[hi][0]) - float(nodes[lo][0]))
		for c in cols:
			var t: float = buildings._hut_theta(c, n)
			verts.append(Vector3(cx + r*cos(t), h, zc + r*sin(t))*S)
			var uv: Vector2 = uvs[i][c]
			# Where the camera sees the surface well AND nothing hides it (the fit's "vis"), the picture is exact: use it
			# instead of the hut's reflection (a pie's far crust is in the picture; its far wall is not).
			var j := posmod(c - n/4, n)
			if str(nodes[i][2]).substr(j, 1) == "1":
				var normal := Vector3(cos(t), slope, sin(t)).normalized()
				if normal.dot(view) >= WELL_SEEN: uv = Vector2(cx + r*cos(t), cz + k*r*sin(t) - h)
			tex_uv.append(uv/size)
	for i in nodes.size() - 1:
		for c in n:
			var a := i*cols + c
			var d := (i + 1)*cols + c
			index.append_array(PackedInt32Array([a, a + 1, d + 1, a, d + 1, d]))
	# The top: its own ring, every point projected as drawn (the whole top is in the picture), and a fan to the axis.
	var top := nodes.size() - 1
	var th := float(nodes[top][0])
	var tr := float(nodes[top][1])
	var base := verts.size()
	for c in n:
		var t: float = buildings._hut_theta(c, n)
		verts.append(Vector3(cx + tr*cos(t), th, zc + tr*sin(t))*S)
		tex_uv.append(Vector2(cx + tr*cos(t), cz + k*tr*sin(t) - th)/size)
	verts.append(Vector3(cx, th, zc)*S)
	tex_uv.append(Vector2(cx, cz - th)/size)
	for c in n:
		index.append_array(PackedInt32Array([base + n, base + c, base + (c + 1) % n]))
	return [[_arrays(verts, tex_uv, index), _texture(path, fit)]]

# --- box ------------------------------------------------------------------------------------------------------------
# A box, or a stack of them on one lattice (fit.boxes: each box's offset X, Z of its footprint's middle from the lattice
# origin, true ground units, and the height it stands at).
func _box_corners(fit: Dictionary, b: Array) -> Array:
	var c := cos(float(fit.yaw))
	var s := sin(float(fit.yaw))
	var w := float(fit.w)
	var d := float(fit.d)
	var g: Array = []
	for q in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		g.append(Vector2(float(b[0]) + q[0]*w/2.0*c - q[1]*d/2.0*s, float(b[1]) + q[0]*w/2.0*s + q[1]*d/2.0*c))
	return g

func _front(fit: Dictionary) -> float:
	return _extent(fit).y

# The footprint's back and front (min and max Z of the corners), true ground units from the lattice origin.
func _extent(fit: Dictionary) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for b in fit.get("boxes", [[0, 0, 0]]):
		for p in _box_corners(fit, b):
			lo = minf(lo, (p as Vector2).y)
			hi = maxf(hi, (p as Vector2).y)
	return Vector2(lo, hi)

func _box(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var hh := float(fit.h)
	var zc := cz - (1.0 - k)*_front(fit) # the footprint's front corner stays on the row the picture draws it on
	if fit.has("zc"): zc = float(fit.zc) # a part of a compound stands in its compound's frame
	var proj := func(p: Vector2, y: float) -> Vector2: return Vector2(cx + p.x, cz + k*p.y - y)
	var at := func(p: Vector2, y: float) -> Vector3: return Vector3(cx + p.x, y, zc + p.y)*S
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	var slab: bool = fit.get("slab", false)
	var edge_v := PackedVector3Array() # a slab's edges and underside: one plain colour, below
	var edge_i := PackedInt32Array()
	for b in fit.get("boxes", [[0, 0, 0]]):
		var g: Array = _box_corners(fit, b)
		var y0 := float(b[2])
		var hb := hh if b.size() < 4 else float(b[3]) # a box of its own height (a post ends in the roof's underside)
		# Faces: face i stands on the edge from corner i to i + 1. Its corners as seen from outside: bottom left, bottom
		# right, top right, top left.
		var centre := Vector2(float(b[0]), float(b[1]))
		var faces: Array = []
		for i in 4:
			var p0: Vector2 = g[i]
			var p1: Vector2 = g[(i + 1) % 4]
			var normal := ((p0 + p1)/2.0 - centre).normalized()
			var right := Vector2(normal.y, -normal.x)
			var bl := p0
			var br := p1
			if p0.dot(right) > p1.dot(right):
				bl = p1
				br = p0
			faces.append({"nz": normal.y, "pts": [[bl, y0], [br, y0], [br, y0 + hb], [bl, y0 + hb]]})
		var best := 0
		for i in 4:
			if float(faces[i].nz) > float(faces[best].nz): best = i
		for i in 4:
			var src: int = i
			if slab:
				var eb := edge_v.size()
				for j in 4:
					var pt: Array = faces[i].pts[j]
					edge_v.append(at.call(pt[0], pt[1]))
				edge_i.append_array(PackedInt32Array([eb, eb + 1, eb + 2, eb, eb + 2, eb + 3]))
				continue
			if float(faces[i].nz) < WELL_SEEN:
				src = (i + 2) % 4 if float(faces[(i + 2) % 4].nz) >= WELL_SEEN else best
			var base := verts.size()
			for j in 4:
				var pt: Array = faces[i].pts[j]
				var sp: Array = faces[src].pts[j]
				verts.append(at.call(pt[0], pt[1]))
				tex_uv.append((proj.call(sp[0], sp[1]) as Vector2)/size)
			index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var tb := verts.size()
		for p in g:
			verts.append(at.call(p, y0 + hb))
			tex_uv.append((proj.call(p, y0 + hb) as Vector2)/size)
		index.append_array(PackedInt32Array([tb, tb + 1, tb + 2, tb, tb + 2, tb + 3]))
		if slab:
			var ub := edge_v.size()
			for p in g: edge_v.append(at.call(p, y0))
			edge_i.append_array(PackedInt32Array([ub, ub + 1, ub + 2, ub, ub + 2, ub + 3]))
	var out: Array = [[_arrays(verts, tex_uv, index), _texture(path, fit)]]
	if slab:
		# A slab (a roof: a layer of planks seen from above) shows its top; its edges and underside, which the camera never saw
		# as more than a smear of the planks' grain, are the planks' mean colour.
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _mean_colour(path, fit)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var none := PackedVector2Array()
		none.resize(edge_v.size())
		out.append([_arrays(edge_v, none, edge_i), m])
	return out

# The mean colour of the pixels a part was fitted from (fit.mask).
func _mean_colour(path: String, fit: Dictionary) -> Color:
	var img: Image = buildings.image(path)
	var bits := Marshalls.base64_to_raw(str(fit.mask))
	var data := img.get_data()
	var sum := Vector3.ZERO
	var n := 0
	for p in img.get_width()*img.get_height():
		if (bits[p >> 3] >> (7 - (p & 7))) & 1:
			sum += Vector3(data[p*4], data[p*4 + 1], data[p*4 + 2])
			n += 1
	return Color(sum.x/255.0/maxf(1, n), sum.y/255.0/maxf(1, n), sum.z/255.0/maxf(1, n))

# --- compound -------------------------------------------------------------------------------------------------------
# Several solids of one sprite (tools/landmark_fit.py: the well's stone base, its posts and its roof), each from its own pixels,
# in the base's frame: the base circle's front stays on the row the picture draws it on and the parts keep their place on it.
func _compound(path: String, fit: Dictionary) -> Array:
	var base: Dictionary = fit.base
	var out: Array = _round(path, base)
	var zc := float(base.cz) - (1.0 - float(base.k))*float(base.nodes[0][1])
	for part in fit.parts:
		var p: Dictionary = (part as Dictionary).duplicate()
		p["zc"] = zc
		out.append_array(_gable(path, p) if str(p.get("class", "")) == "gable" else _box(path, p))
	return out

# A gable roof (the well's; tools/landmark_fit.py): two planes from the ridge down to the eaves, a thatch thickness each, on the
# fitted rectangle w x d (yawed; the ridge along its long axis d), the ends closed by the shell's cross-section. The pitch is
# the thatched cottages' (fit.pitch); the open underside is the underside of the thatch. Every vertex takes the picture of the
# top slope the original camera saw (UV = its projection), at the same distance from the ridge and along it: the camera saw
# one slope, so the far slope, the undersides and the ends take that one's thatch (a pitched roof is symmetric about its ridge).
func _gable(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var zc := float(fit.zc)
	var hw := float(fit.w)/2.0
	var hd := float(fit.d)/2.0
	var ridge := float(fit.ridge)
	var rise := float(fit.rise)
	var thick := float(fit.h)
	var centre := Vector2(float(fit.boxes[0][0]), float(fit.boxes[0][1]))
	var across := Vector2(cos(float(fit.yaw)), sin(float(fit.yaw)))
	var along := Vector2(-across.y, across.x)
	var seen := 1.0 if across.y >= 0.0 else -1.0 # the slope whose normal turns to the camera (+Z)
	var top := func(u: float) -> float: return ridge - rise*absf(u)/hw
	var lat := func(u: float, v: float) -> Vector2: return centre + u*across + v*along
	var quads: Array = [] # each: four (u across, v along, height) corners, counter-clockwise seen from outside
	var ends: Array = [] # the indices of the gable ends
	for sgn in [-1.0, 1.0]:
		var ue: float = sgn*hw
		var ye: float = top.call(ue)
		quads.append([[0.0, -hd, ridge], [0.0, hd, ridge], [ue, hd, ye], [ue, -hd, ye]]) # the slope's top
		quads.append([[0.0, -hd, ridge - thick], [ue, -hd, ye - thick], [ue, hd, ye - thick], [0.0, hd, ridge - thick]]) # its underside
		quads.append([[ue, -hd, ye], [ue, hd, ye], [ue, hd, ye - thick], [ue, -hd, ye - thick]]) # the eave's edge
		for v in [-hd, hd]: # the end: the shell's cross-section
			ends.append(quads.size())
			quads.append([[0.0, v, ridge], [ue, v, ye], [ue, v, ye - thick], [0.0, v, ridge - thick]])
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	for qi in quads.size():
		var quad: Array = quads[qi]
		var base := verts.size()
		for c in quad:
			var q: Vector2 = lat.call(c[0], c[1])
			verts.append(Vector3(cx + q.x, c[2], zc + q.y)*S)
			# The picture of the top slope the camera saw: the vertex's own point on it, mirrored to the seen side; a vertex a thatch
			# thickness below the top (the underside, the eave's edge, the ends) takes the point that far up the slope, so the thickness
			# shows thatch, not a sliver of one row stretched down.
			var us := absf(absf(float(c[0])) - (float(top.call(float(c[0]))) - float(c[2]))*cos(atan(rise/hw)))
			# An end is a plane of its own that the camera saw edge-on: its one row of thatch would stretch down it. Its straw is the
			# slope's, read in the end's own plane: across by u, and down the end by the height below the ridge, from the drawn
			# end (the ridge's left end, +v, where the slope lies whole in the picture).
			var lateral: float = hd - (ridge - float(c[2])) if ends.has(qi) else float(c[1])
			var qs: Vector2 = lat.call(seen*us, lateral)
			tex_uv.append(Vector2(cx + qs.x, cz + k*qs.y - float(top.call(us)))/size)
		index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return [[_arrays(verts, tex_uv, index), _texture(path, fit)]]

# --- ring -----------------------------------------------------------------------------------------------------------
# A ring open to the camera (the save machine; tools/landmark_fit.py ring_fit): a grating floor on the ground and a wall on the far
# half, the half whose inside the picture shows. Everything the camera saw is the picture projected back, UV = (cx + X, cz + k Z - Y):
# the floor (Y = 0), the wall's inside and its top. What it never saw takes the picture of what it did: the wall's outside, the
# inside's picture at the same height and angle (the huts' rule: the unseen half is the seen half's), its two ends their own
# projection. Double sided: a ring is seen from both sides of every face.
func _ring(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var rf := float(fit.rf)
	var rw := float(fit.rw)
	var ri := float(fit.ri)
	var hh := float(fit.h)
	var zc := cz - (1.0 - k)*rf # the floor's front stays on the row the picture draws it on
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	var at := func(r: float, t: float, y: float) -> Vector3: return Vector3(cx + r*cos(t), y, zc + r*sin(t))*S
	var proj := func(r: float, t: float, y: float) -> Vector2: return Vector2(cx + r*cos(t), cz + k*r*sin(t) - y)/size
	var lift := 0.4 # px: the floor stands a hair over the ground, not z-fought by it
	var nf := 48
	var centre := verts.size()
	verts.append(at.call(0.0, 0.0, lift))
	tex_uv.append(proj.call(0.0, 0.0, 0.0))
	for c in nf:
		var t := TAU*float(c)/nf
		verts.append(at.call(rf, t, lift))
		tex_uv.append(proj.call(rf, t, 0.0))
	for c in nf: index.append_array(PackedInt32Array([centre, centre + 1 + c, centre + 1 + (c + 1) % nf]))
	var a0 := float(fit.a0)
	var a1 := float(fit.a1)
	var nw := 24
	for i in nw:
		var t0: float = lerpf(a0, a1, float(i)/nw)
		var t1: float = lerpf(a0, a1, float(i + 1)/nw)
		# The inside (exact), the outside (the inside's picture), the top (exact: each corner's own projection).
		for face in 2:
			var r: float = ri if face == 0 else rw
			var b := verts.size()
			for q in [[t0, 0.0], [t1, 0.0], [t1, hh], [t0, hh]]:
				verts.append(at.call(r, q[0], q[1]))
				tex_uv.append(proj.call(ri, q[0], q[1]))
			index.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
		var b := verts.size()
		for q in [[rw, t0], [rw, t1], [ri, t1], [ri, t0]]:
			verts.append(at.call(q[0], q[1], hh))
			tex_uv.append(proj.call(q[0], q[1], hh))
		index.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	for t in [a0, a1]:
		var b := verts.size()
		for q in [[ri, 0.0], [rw, 0.0], [rw, hh], [ri, hh]]:
			verts.append(at.call(q[0], t, q[1]))
			tex_uv.append(proj.call(q[0], t, q[1]))
		index.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _texture(path, fit)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return [[_arrays(verts, tex_uv, index), m]]

# --- pillow ---------------------------------------------------------------------------------------------------------
func _pillow_half(fit: Dictionary) -> float:
	var c := cos(float(fit.yaw))
	var s := sin(float(fit.yaw))
	return sqrt(pow(float(fit.a)*s, 2.0) + pow(float(fit.b)*c, 2.0))

func _pillow(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var A := float(fit.a)
	var B := float(fit.b)
	var C := float(fit.c)
	var c := cos(float(fit.yaw))
	var s := sin(float(fit.yaw))
	var zc := cz - (1.0 - k)*_pillow_half(fit)
	var view := Vector3(0.0, k, 1.0).normalized()
	var nl := 24
	var nm := 16
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	for i in nm + 1:
		var phi := PI*float(i)/nm # 0 at the top
		var cy := cos(phi)
		var ring := sin(phi)
		for j in nl + 1:
			var th := TAU*float(j)/nl
			var a := ring*cos(th)
			var b := ring*sin(th)
			var p := Vector2(A*a*c - B*b*s, A*a*s + B*b*c) # plan offset from the footprint's middle
			var y := C + C*cy
			verts.append(Vector3(cx + p.x, y, zc + p.y)*S)
			var na := a/A
			var nb := b/B
			var ny := cy/C
			var n := Vector3(na*c - nb*s, ny, na*s + nb*c).normalized()
			var seen := n.dot(view)
			var turned := Vector3(-n.x, n.y, -n.z).dot(view)
			var uv := Vector2(cx + p.x, cz + k*p.y - y)
			if seen < WELL_SEEN and turned > seen: uv = Vector2(cx - p.x, cz - k*p.y - y)
			tex_uv.append(uv/size)
	for i in nm:
		for j in nl:
			var a0 := i*(nl + 1) + j
			var d0 := (i + 1)*(nl + 1) + j
			index.append_array(PackedInt32Array([a0, a0 + 1, d0 + 1, a0, d0 + 1, d0]))
	return [[_arrays(verts, tex_uv, index), _texture(path, fit)]]

# --- flat -----------------------------------------------------------------------------------------------------------
func _flat(path: String, fit: Dictionary) -> Array:
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var r0 := float(fit.rows[0])
	var r1 := float(fit.rows[1])
	var c0 := float(fit.cols[0])
	var c1 := float(fit.cols[1])
	var lift := 0.012 # above the ground, so it is not z-fought by it
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	for q in [[c0, r0], [c1, r0], [c1, r1], [c0, r1]]:
		verts.append(Vector3(q[0]*S, lift, q[1]*S))
		tex_uv.append(Vector2(q[0], q[1])/size)
	var img: Image = buildings.image(path)
	var data := img.get_data()
	var dither: PackedByteArray = buildings.dither_mask(img)
	for p in dither.size():
		if dither[p]: data[p*4 + 3] = 0
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = buildings._texture(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return [[_arrays(verts, tex_uv, PackedInt32Array([0, 1, 2, 0, 2, 3])), m]]
