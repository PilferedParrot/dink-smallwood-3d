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

func has(path: String) -> bool:
	return fits.has(path)

# The footprint of the prop on the ground, as (back, front) rows in the meshes' own frame (sprite px): its middle is
# (back + front)/2. A flat prop has none: (0, 0).
func footprint(path: String) -> Vector2:
	var fit: Dictionary = fits.get(path, {})
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
		"flat": out = _flat(path, fit)
	cache[path] = out
	return out

func _texture(path: String) -> ImageTexture:
	return buildings._texture(buildings.filled(buildings.image(path)))

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
	return [[_arrays(verts, tex_uv, index), _texture(path)]]

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
	var proj := func(p: Vector2, y: float) -> Vector2: return Vector2(cx + p.x, cz + k*p.y - y)
	var at := func(p: Vector2, y: float) -> Vector3: return Vector3(cx + p.x, y, zc + p.y)*S
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	for b in fit.get("boxes", [[0, 0, 0]]):
		var g: Array = _box_corners(fit, b)
		var y0 := float(b[2])
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
			faces.append({"nz": normal.y, "pts": [[bl, y0], [br, y0], [br, y0 + hh], [bl, y0 + hh]]})
		var best := 0
		for i in 4:
			if float(faces[i].nz) > float(faces[best].nz): best = i
		for i in 4:
			var src: int = i
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
			verts.append(at.call(p, y0 + hh))
			tex_uv.append((proj.call(p, y0 + hh) as Vector2)/size)
		index.append_array(PackedInt32Array([tb, tb + 1, tb + 2, tb, tb + 2, tb + 3]))
	return [[_arrays(verts, tex_uv, index), _texture(path)]]

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
	return [[_arrays(verts, tex_uv, index), _texture(path)]]

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
