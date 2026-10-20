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
		# fit.void_fill: the palette's pure black inside the part is a drawn gap (the outline, the shadow between stones), not a colour
		# a solid can have on every side; it takes the nearest lit pixel of the same part. (Not the posts: see _flatten.)
		var voids := bool(fit.get("void_fill", false))
		for p in img.get_width()*img.get_height():
			if not (bits[p >> 3] >> (7 - (p & 7))) & 1 or (voids and data[p*4] == 0 and data[p*4 + 1] == 0 and data[p*4 + 2] == 0): data[p*4 + 3] = 0
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
		if fit.has("flat"): _flatten(img, fit.flat)
	return buildings._texture(buildings.filled(img))

# A post's wood, one material along its whole height (fit.flat: per post, the columns of its shaded wood and of its lit wood, and the
# rows it is drawn on). The black outline the sprite draws round the post (a pixel convention, not wood) is left out of every donor
# (OUTLINE_LUM: the drawn posts' luminance has its outline below 20 and its wood above 40; the roof's shadow on the post's foot is
# outline-black too), so a lit column is the mean of its wood pixels down the post, one colour per column; the shaded face is the mean of
# the darkest quarter of the wood pixels (the picture's own darkest wood, no tuned shade).
const OUTLINE_LUM := 24.0
func _flatten(img: Image, posts: Array) -> void:
	var w := img.get_width()
	var data := img.get_data()
	var lum := func(o: int) -> float: return 0.299*data[o] + 0.587*data[o + 1] + 0.114*data[o + 2]
	var cols: Dictionary = {} # x -> its wood pixels' mean colour
	var wood: Array = [] # [luminance, colour] of every wood pixel of every post
	for post in posts:
		for x in range(int(post.dark[0]), int(post.lit[1])):
			var sum := Vector3.ZERO
			var n := 0
			for y in range(int(post.rows[0]), int(post.rows[1])):
				var o: int = (y*w + x)*4
				if data[o + 3] < 128 or float(lum.call(o)) <= OUTLINE_LUM: continue
				var c := Vector3(data[o], data[o + 1], data[o + 2])
				sum += c
				n += 1
				wood.append([float(lum.call(o)), c])
			if n > 0: cols[x] = sum/float(n)
	if wood.is_empty(): return
	wood.sort_custom(func(a, b): return a[0] < b[0])
	var quarter := maxi(1, wood.size()/4)
	var shade := Vector3.ZERO
	for i in quarter: shade += wood[i][1]
	shade /= float(quarter)
	for post in posts:
		for x in range(int(post.dark[0]), int(post.lit[1])):
			var c: Vector3 = shade if x < int(post.dark[1]) else cols.get(x, shade)
			for y in img.get_height():
				var o: int = (y*w + x)*4
				data[o] = int(roundf(c.x))
				data[o + 1] = int(roundf(c.y))
				data[o + 2] = int(roundf(c.z))
				data[o + 3] = 255
	img.set_data(w, img.get_height(), false, Image.FORMAT_RGBA8, data)

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
	# The top: its own ring, every point projected as drawn (the whole top is in the picture). A solid with a mouth (fit.mouth.r: the well's,
	# tools/landmark_fit.py) has a rim: an annulus from the drawn rim to the mouth's edge, and no face inside it (_mouth is the shaft below);
	# anything else closes its top with a fan to the axis.
	var top := nodes.size() - 1
	var th := float(nodes[top][0])
	var tr := float(nodes[top][1])
	var base := verts.size()
	for c in n:
		var t: float = buildings._hut_theta(c, n)
		verts.append(Vector3(cx + tr*cos(t), th, zc + tr*sin(t))*S)
		tex_uv.append(Vector2(cx + tr*cos(t), cz + k*tr*sin(t) - th)/size)
	if fit.has("mouth"):
		var mr := float(fit.mouth.r)
		for c in n:
			var t: float = buildings._hut_theta(c, n)
			verts.append(Vector3(cx + mr*cos(t), th, zc + mr*sin(t))*S)
			tex_uv.append(Vector2(cx + mr*cos(t), cz + k*mr*sin(t) - th)/size)
		for c in n:
			var d := (c + 1) % n
			index.append_array(PackedInt32Array([base + c, base + d, base + n + d, base + c, base + n + d, base + n + c]))
	else:
		verts.append(Vector3(cx, th, zc)*S)
		tex_uv.append(Vector2(cx, cz - th)/size)
		for c in n:
			index.append_array(PackedInt32Array([base + n, base + c, base + (c + 1) % n]))
	return [[_arrays(verts, tex_uv, index), _texture(path, fit)]]

# The well's shaft (fit.mouth): the mouth's wall, straight down from the rim to the ground, and its floor, one plain dark colour. The
# sprite draws the mouth as the far inner wall lit and a black lip, with no depth to read: the shaft's depth is the ground plane (named
# inference) and its colour the mean of the DARKEST QUARTER of the mouth's own stone pixels (the picture's darkest stone, no tuned shade;
# the outline's black and the posts excluded as in _flatten), so each frame (the glow differs) darkens from its own picture.
func _mouth(path: String, base: Dictionary) -> Array:
	var cx := float(base.cx)
	var cz := float(base.cz)
	var k := float(base.k)
	var mr := float(base.mouth.r)
	var rim := float(base.nodes[base.nodes.size() - 1][0])
	var zc := cz - (1.0 - k)*float(base.nodes[0][1])
	var img: Image = buildings.image(path)
	var w := img.get_width()
	var data := img.get_data()
	var bits := Marshalls.base64_to_raw(str(base.mask))
	var lums: Array = []
	for y in img.get_height():
		for x in w:
			var p := y*w + x
			var ex := (float(x) + 0.5 - cx)/mr
			var ey := (float(y) + 0.5 - (cz - rim))/(k*mr)
			if ex*ex + ey*ey > 1.0 or not (bits[p >> 3] >> (7 - (p & 7))) & 1 or data[p*4 + 3] < 128: continue
			var l := 0.299*data[p*4] + 0.587*data[p*4 + 1] + 0.114*data[p*4 + 2]
			if l > OUTLINE_LUM: lums.append([l, Vector3(data[p*4], data[p*4 + 1], data[p*4 + 2])])
	var colour := Color(0.04, 0.04, 0.04)
	if not lums.is_empty():
		lums.sort_custom(func(a, b): return a[0] < b[0])
		var quarter := maxi(1, lums.size()/4)
		var sum := Vector3.ZERO
		for i in quarter: sum += lums[i][1]
		sum /= float(quarter)*255.0
		colour = Color(sum.x, sum.y, sum.z)
	else:
		push_warning("well mouth: no stone pixel to take the shaft's colour from")
	var n := 32
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for c in n + 1:
		var t := TAU*float(c)/n
		verts.append(Vector3(cx + mr*cos(t), rim, zc + mr*sin(t))*S)
		verts.append(Vector3(cx + mr*cos(t), 0.0, zc + mr*sin(t))*S)
	for c in n: index.append_array(PackedInt32Array([2*c, 2*c + 1, 2*c + 3, 2*c, 2*c + 3, 2*c + 2]))
	var mid := verts.size()
	verts.append(Vector3(cx, 0.0, zc)*S)
	for c in n: index.append_array(PackedInt32Array([mid, 2*c + 1, 2*c + 3]))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var none := PackedVector2Array()
	none.resize(verts.size())
	return [[_arrays(verts, none, index), m]]

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
			faces.append({"nz": normal.y, "nx": normal.x, "pts": [[bl, y0], [br, y0], [br, y0 + hb], [bl, y0 + hb]]})
		var best := 0
		for i in 4:
			if float(faces[i].nz) > float(faces[best].nz): best = i
		for i in 4:
			var src: int = i
			if fit.has("faces"):
				# fit.faces: the drawn post's columns (px from the box's middle) of its shaded face (dark) and its lit face (lit). A face the
				# camera saw takes its own columns (the one turned to the right, where the sprite's light is, is the lit one), at their drawn
				# width, down the post as it is drawn (a post is a vertical in the picture: the rows of the box's middle); a face it never
				# saw takes the opposite one's (a box's back is its front turned half a round), so every side shows one dark face, one lit.
				var seen_face: int = i if float(faces[i].nz) >= WELL_SEEN else (i + 2) % 4
				var span: Array = fit.faces.lit if float(faces[seen_face].nx) > 0.0 else fit.faces.dark
				var fb := verts.size()
				for j in 4:
					var pt: Array = faces[i].pts[j]
					verts.append(at.call(pt[0], pt[1]))
					tex_uv.append(Vector2(cx + float(b[0]) + float(span[0 if j == 0 or j == 3 else 1]), cz + k*float(b[1]) - float(pt[1]))/size)
				index.append_array(PackedInt32Array([fb, fb + 1, fb + 2, fb, fb + 2, fb + 3]))
				continue
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
	if base.has("mouth"): out.append_array(_mouth(path, base)) # last: the posts and the roof keep their places in the list
	return out

# A gable roof (the well's; tools/landmark_fit.py): two planes from the ridge down to the eaves, a thatch thickness each, on the
# fitted rectangle w x d (yawed; the ridge along its long axis d), the ends closed by the shell's cross-section. The pitch is
# measured from the sprite's own edges (fit.pitch, fit.rise); the open underside is the underside of the thatch. Every face takes the
# straw of the one slope the original camera saw (_thatch: a patch rectified into the slope's own axes): the far slope, the undersides
# and the ends are cut from it (a pitched roof is symmetric about its ridge).
func _gable(path: String, fit: Dictionary) -> Array:
	var cx := float(fit.cx)
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
	# The straw is a rectified patch (_thatch): across it the ridge's direction, down it the slope's, one texel a source pixel, so the
	# faces of the roof cut it by their own two axes (the sprite's pixel grid, seen along a roof yawed 45 degrees, would be diamonds).
	# A vertex's place on it: s down the slope from the ridge, d the depth below the slope's top (the thickness faces), n across the
	# thickness, the plane's normal to the slope. A thickness face takes the straw that far down the slope and into it.
	var slope := sqrt(hw*hw + rise*rise)
	var sa := rise/slope
	var ca := hw/slope
	var patch := Vector2(ceilf(2.0*hd), ceilf(slope + thick*sa))
	var straw := _thatch(path, fit, patch, slope, seen)
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	for qi in quads.size():
		var quad: Array = quads[qi]
		var base := verts.size()
		for c in quad:
			var q: Vector2 = lat.call(c[0], c[1])
			verts.append(Vector3(cx + q.x, c[2], zc + q.y)*S)
			var d: float = float(top.call(float(c[0]))) - float(c[2])
			var eave: bool = qi % 5 == 2 # the eave's edge: a vertical cut across the straw, a band of it from the slope's middle
			var s_down := slope/2.0 + d if eave else absf(float(c[0]))/ca + d*sa
			# An end is a plane the camera saw edge-on, and there is no picture of a cross-section of the straw: it takes a band of the
			# patch down its middle, as wide as the thickness, cut as the slope cuts it.
			var across_patch: float = (patch.x - thick)/2.0 + d*ca if ends.has(qi) else (float(c[1]) + hd)*patch.x/(2.0*hd)
			tex_uv.append(Vector2(across_patch, s_down*patch.y/(slope + thick*sa))/patch)
		index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return [[_arrays(verts, tex_uv, index), buildings._texture(straw)]]

# The seen slope of the roof as a patch of straw (patch px: across by the ridge's length, down by the slope's, one texel a source
# pixel): each texel reads the sprite where the original camera drew that point of the slope (bilinear), from the pixels that are
# straw: the roof's lit planks (fit.mask) one pixel in from their edge, so the outline and the shaded rim are not straw. What the
# camera never drew (the overhang, a post's knob, the rim) is the straw itself: the largest rectangle of the patch that is drawn is
# repeated, mirrored at each edge, over the whole patch (straw is the same cloth everywhere; a mirror leaves no seam and no streak).
func _thatch(path: String, fit: Dictionary, patch: Vector2, slope: float, seen: float) -> Image:
	var img: Image = buildings.image(path)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var bits := Marshalls.base64_to_raw(str(fit.mask))
	var inside := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < w and y < h and (bits[(y*w + x) >> 3] >> (7 - ((y*w + x) & 7))) & 1 != 0
	var straw := PackedByteArray()
	straw.resize(w*h)
	for y in h:
		for x in w:
			straw[y*w + x] = 1 if inside.call(x, y) and inside.call(x - 1, y) and inside.call(x + 1, y) and inside.call(x, y - 1) and inside.call(x, y + 1) else 0
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var hw := float(fit.w)/2.0
	var hd := float(fit.d)/2.0
	var ridge := float(fit.ridge)
	var rise := float(fit.rise)
	var centre := Vector2(float(fit.boxes[0][0]), float(fit.boxes[0][1]))
	var across := Vector2(cos(float(fit.yaw)), sin(float(fit.yaw)))
	var along := Vector2(-across.y, across.x)
	var ca := hw/slope
	var sa := rise/slope
	var tw := int(patch.x)
	var th := int(patch.y)
	var colour: Array = []
	var drawn := PackedByteArray()
	colour.resize(tw*th)
	drawn.resize(tw*th)
	for j in th:
		var s := (float(j) + 0.5)*(slope + float(fit.h)*sa)/float(th)
		for i in tw:
			if s > slope: continue
			var v := -hd + (float(i) + 0.5)*2.0*hd/float(tw)
			var q := centre + seen*s*ca*across + v*along
			var fx := cx + q.x - 0.5
			var fy := cz + k*q.y - (ridge - s*sa) - 0.5
			var x0 := int(floorf(fx))
			var y0 := int(floorf(fy))
			var ok := true
			for dy in 2:
				for dx in 2:
					var xx := x0 + dx
					var yy := y0 + dy
					if xx < 0 or yy < 0 or xx >= w or yy >= h or straw[yy*w + xx] == 0: ok = false
			if not ok: continue
			var tx := fx - float(x0)
			var ty := fy - float(y0)
			var rgb := Vector3.ZERO
			for dy in 2:
				for dx in 2:
					var o := ((y0 + dy)*w + x0 + dx)*4
					rgb += Vector3(data[o], data[o + 1], data[o + 2])*((tx if dx == 1 else 1.0 - tx)*(ty if dy == 1 else 1.0 - ty))
			colour[j*tw + i] = rgb
			drawn[j*tw + i] = 1
	# the largest all-drawn rectangle (rows of run heights, every left edge)
	var best := Rect2i(0, 0, 0, 0)
	var run := PackedInt32Array()
	run.resize(tw)
	for j in th:
		for i in tw: run[i] = run[i] + 1 if drawn[j*tw + i] == 1 else 0
		for i0 in tw:
			var hmin := 1 << 20
			for i1 in range(i0, tw):
				hmin = mini(hmin, run[i1])
				if hmin == 0: break
				if (i1 - i0 + 1)*hmin > best.size.x*best.size.y: best = Rect2i(i0, j - hmin + 1, i1 - i0 + 1, hmin)
	var out := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	if best.size.x < 4 or best.size.y < 4:
		push_warning("well roof: no drawn patch of straw to repeat")
		return out
	var mirror := func(m: int, n: int) -> int:
		var r := posmod(m, 2*n)
		return r if r < n else 2*n - 1 - r
	for j in th:
		for i in tw:
			var rgb: Vector3 = colour[(best.position.y + mirror.call(j - best.position.y, best.size.y))*tw + best.position.x + mirror.call(i - best.position.x, best.size.x)]
			out.set_pixel(i, j, Color8(int(roundf(rgb.x)), int(roundf(rgb.y)), int(roundf(rgb.z)), 255))
	return out

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
