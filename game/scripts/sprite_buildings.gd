# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Buildings recovered from their sprites (docs/DIRECTION.md, "Buildings" and the passes after it),
# one implementation shared by the game (scripts/fp_world.gd) and the prototype
# (prototype/sprite_world_proto.gd).
#
# A building sprite is a picture of a 3D building taken by the original camera, which on a 1:1
# ground is the projection screen = (X, Z - Y) in source pixels. tools/facade_fit.py recovers the
# building from its pixels (prototype/facades.json); here each face is textured by projecting the
# sprite back through that camera (UV = (x, z - y), exact on planar faces). Faces the original
# camera never saw take the point-mirrored front face, from a back canvas without doors. Door,
# window and damage sprites drawn over the building are composited into its texture first, in the
# original draw order, so they sit on the walls they were drawn on. Chimneys stand up on the roof
# or beside the house; dormers stand up out of kit roofs.
#
# Coordinates: "world" pixels are screen origin + (x - 20, y) (origin() below). Every node built
# here has its origin at the building's top-left in world pixels and its vertices in metres,
# (pixel offset) * S; the caller places it.
extends RefCounted

var S := 0.025 # metres per source pixel
var sequences: Dictionary
var world: Dictionary
var facades: Dictionary
var face_id := false # debug (the prototype's arg "faceid"): each house face flat in its own colour
var tex_cache: Dictionary = {}
var clean_panels: Dictionary = {}
var kit_cache: Dictionary = {} # kit name -> [canvas, back, top-left, members]
var surface_cache: Dictionary = {} # house or kit key -> [[ArrayMesh, Texture2D], ...]

func _init(seqs: Dictionary, map: Dictionary, fits: Dictionary, scale: float) -> void:
	sequences = seqs
	world = map
	facades = fits
	S = scale

func origin(n: int) -> Vector2:
	return Vector2(((n-1)%32)*600, int((n-1)/32)*400)

func tex(path: String) -> Texture2D:
	if not tex_cache.has(path):
		tex_cache[path] = load("res://"+path) if ResourceLoader.exists("res://"+path) else null
	return tex_cache[path]

func frame_data(seq: int, frame: int) -> Dictionary:
	var fr: Array = sequences.get(str(seq),{}).get("frames",[])
	return {} if fr.is_empty() else fr[clampi(frame-1,0,fr.size()-1)]

# A map sprite's picture: the game's entities carry it as pseq/pframe, the map data as seq/frame.
func sprite_frame(s: Dictionary) -> Dictionary:
	return frame_data(int(s.get("pseq",s.get("seq",0))), int(s.get("pframe",s.get("frame",1))))

func image(path: String) -> Image:
	var t := tex(path)
	if t == null: return null
	var img := t.get_image()
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

func sprite_rect(s: Dictionary) -> Rect2:
	var d := sprite_frame(s)
	if d.is_empty(): return Rect2()
	var t := tex(str(d.path))
	if t == null: return Rect2()
	return Rect2(float(s.x) - float(d.dx), float(s.y) - float(d.dy), t.get_width(), t.get_height())

func world_rect(s: Dictionary, n: int) -> Rect2:
	var r := sprite_rect(s)
	r.position += origin(n) - Vector2(20, 0)
	return r

func is_fitted(s: Dictionary) -> bool:
	var d := sprite_frame(s)
	return not d.is_empty() and facades.has(str(d.path)) and facades[str(d.path)] is Dictionary and int(s.get("type",1)) != 2

# --- Houses: the parts drawn over a house ----------------------------------------------------
# `candidates`: [[sprite, screen, key], ...] in the original's screens, already filtered to what
# is drawn (story layer, removed sprites, type 2). `claimed` holds the keys of sprites a house
# already draws (itself, or a part of an earlier house): they are skipped and the new parts added.
# Returns {details: [[sprite, world rect, world hotspot y]], roof: [[sprite, reading, house-local
# top-left, height of its foot]], ground: [[sprite, reading, world top-left]]}.
func gather(fit: Dictionary, rect: Rect2, candidates: Array, claimed: Dictionary) -> Dictionary:
	var details: Array = []
	var roof_pieces: Array = []
	var ground_pieces: Array = []
	var pieces_seen := {}
	for c in candidates:
		if claimed.has(c[2]): continue
		var got := claim(fit, rect, c[0], int(c[1]))
		if got.is_empty(): continue
		claimed[c[2]] = true
		var ed := sprite_frame(c[0])
		if got[0] == "detail":
			details.append([c[0], got[1], got[2]])
			continue
		var er: Rect2 = got[1]
		var pk := "%s:%d:%d" % [ed.path, int(er.position.x), int(er.position.y)]
		if not pieces_seen.has(pk):
			if got[0] == "ground": ground_pieces.append([c[0], got[2], er.position])
			else: roof_pieces.append([c[0], got[2], er.position - rect.position, float(got[3])])
		pieces_seen[pk] = true
	details.sort_custom(func(a, b):
		if (int(a[0].get("type",1)) == 0) != (int(b[0].get("type",1)) == 0): return int(a[0].get("type",1)) == 0
		return a[2] < b[2])
	return {"details": details, "roof": roof_pieces, "ground": ground_pieces}

# Whether the house fitted as `fit` at world `rect` draws sprite `s` of screen `n`, and how:
# [] (no), ["ground", world rect, reading] a chimney standing on the ground beside it (home-13),
# ["roof", world rect, reading, foot height] a chimney whose foot the view ray finds on its roof,
# ["detail", world rect, world hotspot y] a detail drawn on it (doors, windows, damage), composited.
func claim(fit: Dictionary, rect: Rect2, s: Dictionary, n: int) -> Array:
	var ed := sprite_frame(s)
	if ed.is_empty() or facades.has(str(ed.path)) or not str(ed.path).contains("/struct/"): return []
	var er := world_rect(s, n)
	if not rect.intersects(er): return []
	var at := er.position - rect.position
	var rp: Dictionary = facades.get("_roof_pieces", {}).get(str(ed.path), {})
	if rp.has("base"): return ["ground", er, rp]
	if not rp.is_empty():
		var hit := ray_hit(fit, at.x + float(rp.foot[0]), at.y + float(rp.foot[1]))
		if not hit.is_empty() and int(hit[1]) == 2: return ["roof", er, rp, float(hit[0])]
	if rect.encloses(er): return ["detail", er, er.position.y + float(ed.dy)]
	return []

# --- Houses: the build ------------------------------------------------------------------------
# The house drawn by sprite picture `path` at world `rect`, with `parts` from gather().
# Returns {node: Node3D (origin at rect.position), shade: the drawn shadow for the ground,
# hull: its wall footprint in world pixels}. Meshes and textures are cached under `cache_key`
# when one is given (the game rebuilds its scene on every screen change).
func house(path: String, rect: Rect2, parts: Dictionary, cache_key: String = "") -> Dictionary:
	var fit: Dictionary = facades[path]
	var foot := PackedVector2Array()
	for f in fit.faces:
		if int(f.label) != 1: continue
		for q in f.pts:
			if absf(float(q[1])) < 1e-3: foot.append(rect.position + Vector2(float(q[0]), float(q[2])))
	var hull := Geometry2D.convex_hull(foot) if foot.size() >= 3 else PackedVector2Array()
	if not cache_key.is_empty() and surface_cache.has(cache_key):
		var cached: Array = surface_cache[cache_key]
		return {"node": node_from(cached[0]), "shade": cached[1], "hull": hull}
	var canvas := image(path)
	# Details drawn over the house in the original, in its draw order (type 0 first).
	# The back, which the original camera never saw, mirrors the front without its doors.
	var back: Image = canvas.duplicate()
	var doors := {}
	for q in facades.get("_kit", {}).get("doors", []): doors[str(q)] = true
	for dt in parts.details:
		var dpath := str(sprite_frame(dt[0]).path)
		var img := image(dpath)
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(dt[1].position - rect.position))
		if not doors.has(dpath):
			back.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(dt[1].position - rect.position))
	for r in parts.roof: _paint_roof_piece_foot(canvas, r, fit, back)
	# The original's shadow: the isolated black dither pixels, which lie on the ground
	# in this projection, for the ground at 50% like the engine's blend.
	var shade := _shade(canvas, dither_mask(canvas))
	var surfaces: Array = []
	if fit.has("polys"): _uv_house(surfaces, fit, canvas, back)
	else: _block_house(surfaces, fit, fill_holes(canvas), fill_holes(back))
	for r in parts.roof: _roof_piece(surfaces, r, fit)
	for g in parts.ground: _ground_piece(surfaces, g, rect.position)
	if not cache_key.is_empty(): surface_cache[cache_key] = [surfaces, shade]
	return {"node": node_from(surfaces), "shade": shade, "hull": hull}

# One MeshInstance3D per [mesh, texture]: unshaded, as the light is baked into the art.
func node_from(surfaces: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "Building"
	for sf in surfaces:
		var mi := MeshInstance3D.new()
		mi.mesh = sf[0]
		# A surface material, not an override, so a story treatment can override it per node
		# (fp_world.gd add_ruin_skin).
		if sf[1] is Material:
			mi.set_surface_override_material(0, sf[1])
		else:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = sf[1]
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(0, m)
		node.add_child(mi)
	return node

func dither_mask(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var black := PackedByteArray()
	black.resize(w*h)
	for p in w*h:
		black[p] = 1 if data[p*4+3] > 127 and data[p*4] + data[p*4+1] + data[p*4+2] <= 10 else 0
	var out := PackedByteArray()
	out.resize(w*h)
	for y in h:
		for x in w:
			var p := y*w + x
			if not black[p]: continue
			if (x > 0 and black[p-1]) or (x < w-1 and black[p+1]) or (y > 0 and black[p-w]) or (y < h-1 and black[p+w]): continue
			out[p] = 1
	return out

# The drawn shadow in `img` (its isolated black dither pixels) as 50% black, for the ground.
func shade(img: Image) -> Image:
	return _shade(img, dither_mask(img))

func _shade(img: Image, dither: PackedByteArray) -> Image:
	var shade := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for p in dither.size():
		if dither[p]: shade.set_pixel(p % img.get_width(), p / img.get_width(), Color(0,0,0,0.5))
	return shade

# Where the fitted geometry reaches past the drawn silhouette, extend the nearest drawn
# pixels outward instead of showing holes or shadow dither (breadth-first, so each hole
# takes the colour of the nearest drawn pixel).
func fill_holes(src: Image) -> ImageTexture:
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var dither := dither_mask(src)
	var solid := PackedByteArray()
	solid.resize(w*h)
	var queue := PackedInt32Array()
	for p in w*h:
		if data[p*4+3] >= 128 and not dither[p]:
			solid[p] = 1
			queue.append(p)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var x := p % w
		for q in [p-1 if x > 0 else -1, p+1 if x < w-1 else -1, p-w, p+w]:
			if q < 0 or q >= w*h or solid[q]: continue
			solid[q] = 1
			for c in 3: data[q*4+c] = data[p*4+c]
			data[q*4+3] = 255
			queue.append(q)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# A house of hip-roofed blocks (and a kit building): `back`, if given, textures the faces the
# original camera never saw.
func _block_house(surfaces: Array, fit: Dictionary, t: ImageTexture, back: ImageTexture = null) -> void:
	var size := Vector2(t.get_width(), t.get_height())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_back := SurfaceTool.new()
	st_back.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_back := 0
	var roofed := {} # blocks with a roof: their walls stand under an eave, not a jetty
	for f in fit.faces:
		if int(f.label) == 2: roofed[int(f.block)] = true
	var fi := -1
	for f in fit.faces:
		fi += 1
		if face_id: # debug: face fi of this house in colour (8(fi+1), 60 block, 255)
			var fst := SurfaceTool.new()
			fst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var fp := pts_of(f)
			for i in range(1, fp.size()-1):
				for q in [fp[0], fp[i], fp[i+1]]: fst.add_vertex(q*S)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = Color8(8*(fi+1), 60*int(f.block), 255)
			surfaces.append([fst.commit(), mat])
			continue
		var c: Array = fit.centers[int(f.block)]
		var centre := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var pts: Array[Vector3] = pts_of(f)
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for p in pts: mid += p / pts.size()
		if normal.dot(mid - centre) < 0: normal = -normal
		# Sample whichever of this face and its point mirror the original camera saw more
		# squarely: n.view vs (-nx, ny, -nz).view, i.e. faces turned south use their own
		# pixels; north-turned ones (unseen, or seen at a grazing, smeared angle) the mirror.
		var seen_by_camera := normal.z >= 0.0
		var polys: Array = [[pts, INF, 0.0]] # [polygon, mirror height, shift down for the texture]
		if int(f.label) == 1:
			# The eave (or the jetty) hid the top of this wall from the original camera (the
			# view ray drops o/|n.z| crossing the overhang). Under an eave, that band takes the
			# wall one band further down, shifted up: the band just under the eave carries the
			# eave's own marks (rafter holes, the top rail), and mirroring it doubled them into
			# diamonds and chevrons. Under a jetty it takes the stone just below, mirrored.
			var y0 := pts[0].y
			var top := pts[2].y
			var band := float(fit.overhangs[int(f.block)]) / maxf(absf(normal.z), 0.3)
			var hs := maxf(top - band, y0 + 0.5*(top - y0))
			var lo: Array[Vector3] = [pts[0], pts[1], Vector3(pts[1].x, hs, pts[1].z), Vector3(pts[0].x, hs, pts[0].z)]
			var hi: Array[Vector3] = [lo[3], lo[2], pts[2], pts[3]]
			if roofed.has(int(f.block)): polys = [[lo, INF, 0.0], [hi, INF, minf(2.0*(top - hs), hs - y0)]]
			else: polys = [[lo, INF, 0.0], [hi, hs, 0.0]]
		var out: SurfaceTool = st if seen_by_camera or back == null else st_back
		if out == st_back: n_back += 1
		for poly in polys:
			var ps: Array[Vector3] = poly[0]
			var mirror: float = poly[1]
			var shift: float = poly[2]
			for i in range(1, ps.size()-1):
				for p in [ps[0], ps[i], ps[i+1]]:
					var q: Vector3 = p if seen_by_camera else Vector3(2*centre.x - p.x, p.y, 2*centre.z - p.z)
					if mirror != INF: q.y = 2*mirror - q.y
					q.y -= shift
					out.set_uv(Vector2(q.x, q.z - q.y) / size)
					out.add_vertex(p*S)
	if face_id: return
	surfaces.append([st.commit(), t])
	if n_back > 0: surfaces.append([st_back.commit(), back])

# A building described by parts (tools/facade_fit.py, "General buildings": the cabin, the
# church): every face carries its texture coordinates, and faces the original camera never saw
# sample the back canvas (no doors). Upright pieces standing in front of the body (a chimney)
# are cleared from the body's texture, which is filled from its own pixels there, so the wall
# behind a chimney does not wear the chimney; the pieces keep the full sprite.
func _uv_house(surfaces: Array, fit: Dictionary, canvas: Image, back: Image) -> void:
	var occ: Array = []
	for poly in fit.get("occluders", []):
		var pv := PackedVector2Array()
		for q in poly: pv.append(Vector2(float(q[0]), float(q[1])))
		occ.append(pv)
	var texs := [fill_holes(_without(canvas, occ)), fill_holes(_without(back, occ)), fill_holes(canvas)]
	var sts: Array = []
	var used := [false, false, false]
	for k in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var size := Vector2(canvas.get_width(), canvas.get_height())
	for f in fit.polys:
		var k := 2 if bool(f.piece) else (1 if bool(f.back) else 0)
		used[k] = true
		var pts: Array = f.pts
		var uv: Array = f.uv
		for i in range(1, pts.size()-1):
			for j in [0, i, i+1]:
				sts[k].set_uv(Vector2(float(uv[j][0]), float(uv[j][1])) / size)
				sts[k].add_vertex(Vector3(float(pts[j][0]), float(pts[j][1]), float(pts[j][2]))*S)
	for k in 3:
		if used[k]: surfaces.append([sts[k].commit(), texs[k]])

# The image with the pixels inside any of the polygons cleared.
func _without(img: Image, polys: Array) -> Image:
	var out: Image = img.duplicate()
	for pv in polys:
		var r := Rect2(pv[0], Vector2.ZERO)
		for q in pv: r = r.expand(q)
		for y in range(maxi(0, int(r.position.y)), mini(out.get_height(), int(r.end.y) + 1)):
			for x in range(maxi(0, int(r.position.x)), mini(out.get_width(), int(r.end.x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pv): out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out

# --- Roof pieces (the chimneys) ------------------------------------------------------
# A chimney sprite is a picture of an upright prism standing on the roof, taken by the same
# camera. tools/facade_fit.py reads its top face (the footprint, as a horizontal face
# projects to itself) and its foot, the lowest stone pixel under its front edge. The view
# ray through the foot meets the house's roof where the chimney stands; that fixes its
# depth, and the top face fixes its height. Its thatch ring and dithered shadow lie on the
# roof, so they are painted onto the roof texture (the shadow at the engine's 50%).

# The nearest face of a fitted house hit by the view ray through house-local screen point
# (x, y); points on that ray are (x, Y, y + Y). Returns [Y, label] or [] if it misses.
func ray_hit(fit: Dictionary, x: float, y: float) -> Array:
	var best := []
	for f in fit.faces:
		var pts := pts_of(f)
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		var den := n.y + n.z
		if absf(den) < 1e-6: continue
		var yy := (n.dot(pts[0]) - n.x*x - n.z*y) / den
		if _inside(pts, n, Vector3(x, yy, y + yy)) and (best.is_empty() or yy > best[0]):
			best = [yy, int(f.label)]
	return best

# Height of the roof above ground point (x, z) in house-local pixels, or NAN.
func _roof_height(fit: Dictionary, x: float, z: float) -> float:
	var best := NAN
	for f in fit.faces:
		if int(f.label) != 2: continue
		var pts := pts_of(f)
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		if absf(n.y) < 1e-6: continue
		var yy := (n.dot(pts[0]) - n.x*x - n.z*z) / n.y
		if _inside(pts, n, Vector3(x, yy, z)) and (is_nan(best) or yy > best): best = yy
	return best

func _nrm(pts: Array[Vector3]) -> Vector3:
	return (pts[1]-pts[0]).cross(pts[2]-pts[0])

func _ctr(pts: Array[Vector3]) -> Vector3:
	var c := Vector3.ZERO
	for q in pts: c += q / pts.size()
	return c

func pts_of(f: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for p in f.pts: pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return pts

func _inside(pts: Array[Vector3], n: Vector3, q: Vector3) -> bool:
	var sign := 0.0
	for i in pts.size():
		var s := (pts[(i+1) % pts.size()] - pts[i]).cross(q - pts[i]).dot(n)
		if absf(s) < 1e-3 * n.length_squared(): continue
		if sign == 0.0: sign = signf(s)
		elif signf(s) != sign: return false
	return true

# The thatch ring and cast shadow at a chimney's foot, painted into the canvas where the original
# camera saw them. Some land on a face it never saw squarely (the north slope's sliver behind the
# ridge: 98 of the 439 shadow wedge's pixels in a face-ID render, arg "faceid"), which samples the
# back canvas at the point mirror. The sliver is seen at a grazing angle, so neighbouring screen
# pixels sample texels ~10 px apart and single painted texels vanish in its mipmaps; so every back
# texel whose point on such a face projects onto a foot pixel is painted (_paint_unseen).
func _paint_roof_piece_foot(canvas: Image, r: Array, fit: Dictionary, back: Image) -> void:
	var rp: Dictionary = r[1]
	var at: Vector2 = r[2]
	var img := image(str(sprite_frame(r[0]).path))
	var dither := dither_mask(img)
	var xl := float(rp.top[0][0])
	var xr := float(rp.top[2][0])
	for y in img.get_height():
		for x in img.get_width():
			# The body is the column band under the top face, down to the foot.
			if x >= xl and x <= xr and y <= float(rp.foot[1]): continue
			var c := img.get_pixel(x, y)
			if dither[y*img.get_width() + x]: c = Color(0, 0, 0, 0.5)
			if c.a < 0.25: continue
			var q := Vector2i(int(at.x) + x, int(at.y) + y)
			if q.x < 0 or q.y < 0 or q.x >= canvas.get_width() or q.y >= canvas.get_height(): continue
			canvas.set_pixel(q.x, q.y, canvas.get_pixel(q.x, q.y).blend(c))
	_paint_unseen(img, dither, r, fit, back)

# Every back-canvas texel sampled by a face the original camera never saw (normal turned north),
# whose point on that face the original camera shows at a foot pixel of the roof piece: painted
# with that pixel. A face samples (2c.x - x, 2c.z - z - y) at its point (x, y, z), so a texel
# (U, V) is the point with x = 2c.x - U and y + z = 2c.z - V on the face's plane.
func _paint_unseen(img: Image, dither: PackedByteArray, r: Array, fit: Dictionary, back: Image) -> void:
	var rp: Dictionary = r[1]
	var at: Vector2 = r[2]
	var w := img.get_width()
	var h := img.get_height()
	for f in fit.faces:
		var pts := pts_of(f)
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		var c: Array = fit.centers[int(f.block)]
		var cen := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var mid := Vector3.ZERO
		for q in pts: mid += q / pts.size()
		if n.dot(mid - cen) < 0: n = -n
		if n.z >= 0.0 or absf(n.y - n.z) < 1e-6: continue
		# The texels this face samples in the piece's neighbourhood: mirror the piece's rect.
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in pts:
			var uv := Vector2(2.0*cen.x - q.x, 2.0*cen.z - q.z - q.y)
			lo = lo.min(uv)
			hi = hi.max(uv)
		for V in range(maxi(0, int(lo.y)), mini(back.get_height(), int(hi.y) + 1)):
			for U in range(maxi(0, int(lo.x)), mini(back.get_width(), int(hi.x) + 1)):
				var x := 2.0*cen.x - (U + 0.5)
				var sz := 2.0*cen.z - (V + 0.5) # y + z on the face
				# n.x x + n.y y + n.z (sz - y) = n.p0
				var y := (n.dot(pts[0]) - n.x*x - n.z*sz) / (n.y - n.z)
				var p := Vector3(x, y, sz - y)
				if not _inside(pts, n, p): continue
				var sx := int(floor(p.x - at.x))
				var sy := int(floor(p.z - p.y - at.y))
				if sx < 0 or sy < 0 or sx >= w or sy >= h: continue
				if sx >= float(rp.top[0][0]) and sx <= float(rp.top[2][0]) and sy <= float(rp.foot[1]): continue
				# Only where the original camera sees this face: behind the ridge the view ray meets
				# the near slope first. Unseen, the wedge's few pixels spread down the whole far slope
				# along the grazing rays and showed at eye level as a dark stripe from ridge to eave.
				var first := ray_hit(fit, p.x, p.z - p.y)
				if first.is_empty() or absf(float(first[0]) - p.y) > 0.5: continue
				var col := img.get_pixel(sx, sy)
				if dither[sy*w + sx]: col = Color(0, 0, 0, 0.5)
				if col.a < 0.25: continue
				back.set_pixel(U, V, back.get_pixel(U, V).blend(col))

# A chimney standing on the ground beside a house (tools/facade_fit.py standing_piece): the
# frustum from its foot (on the ground, where the sprite shows it) to its top face (at its height),
# textured by projection like a house; faces the original camera never saw take the point mirror
# about its axis. `house_tl`: the house's world top-left, the node's origin.
func _ground_piece(surfaces: Array, g: Array, house_tl: Vector2) -> void:
	var rp: Dictionary = g[1]
	var tl: Vector2 = g[2]
	var img := image(str(sprite_frame(g[0]).path))
	var h := float(rp.height)
	var base: Array[Vector3] = []
	for q in rp.base: base.append(Vector3(float(q[0]), 0.0, float(q[1])))
	var top: Array[Vector3] = [] # front, right, back, left, as the base
	for k in [3, 2, 1, 0]: top.append(Vector3(float(rp.top[k][0]), h, float(rp.top[k][1]) + h))
	var cen := Vector3.ZERO
	for q in base: cen += q / 4.0
	var faces: Array = [top]
	for k in 4: faces.append([base[k], base[(k+1) % 4], top[(k+1) % 4], top[k]] as Array[Vector3])
	var size := Vector2(img.get_width(), img.get_height())
	var off := Vector3(tl.x - house_tl.x, 0.0, tl.y - house_tl.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var pts: Array[Vector3] = face
		var n := _nrm(pts) if pts.size() > 2 else Vector3.UP
		if n.dot(_ctr(pts) - Vector3(cen.x, h/2.0, cen.z)) < 0: n = -n
		for i in range(1, pts.size()-1):
			for q in [pts[0], pts[i], pts[i+1]]:
				var m: Vector3 = q if n.z >= -1e-3 else Vector3(2*cen.x - q.x, q.y, 2*cen.z - q.z)
				st.set_uv(Vector2(m.x, m.z - m.y) / size)
				st.add_vertex((off + q)*S)
	surfaces.append([st.commit(), fill_holes(img)])

func _roof_piece(surfaces: Array, r: Array, fit: Dictionary) -> void:
	var rp: Dictionary = r[1]
	var at: Vector2 = r[2]
	var zf: float = at.y + float(rp.foot[1]) + float(r[3]) # depth of the front edge
	var yt: float = zf - (at.y + float(rp.top[3][1])) # height of the top face
	var top: Array[Vector3] = [] # left, back, right, front
	for c in rp.top: top.append(Vector3(at.x + float(c[0]), yt, at.y + float(c[1]) + yt))
	var yb: float = float(r[3])
	for c in top:
		var h := _roof_height(fit, c.x, c.z)
		if not is_nan(h): yb = minf(yb, h)
	yb -= 3.0 # into the roof, so no gap shows where the fit and the art differ
	# Texture: the sprite without its roof-lying parts, stone extended over the gaps.
	var img := image(str(sprite_frame(r[0]).path))
	for y in img.get_height():
		for x in img.get_width():
			if x < float(rp.top[0][0]) or x > float(rp.top[2][0]) or y > float(rp.foot[1]): img.set_pixel(x, y, Color(0,0,0,0))
	var t := fill_holes(img)
	var size := Vector2(img.get_width(), img.get_height())
	var centre := (top[0] + top[2]) / 2.0
	var faces: Array = [top]
	for k in 4:
		var a := top[k]
		var b := top[(k+1) % 4]
		faces.append([Vector3(a.x, yb, a.z), Vector3(b.x, yb, b.z), b, a] as Array[Vector3])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var pts: Array[Vector3] = face
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for p in pts: mid += p / pts.size()
		if normal.dot(mid - Vector3(centre.x, (yt + yb) / 2.0, centre.z)) < 0: normal = -normal
		for i in range(1, pts.size()-1):
			for p in [pts[0], pts[i], pts[i+1]]:
				# Faces the original camera never saw take the point-mirrored front faces.
				var q: Vector3 = p if normal.z >= -1e-3 else Vector3(2*centre.x - p.x, p.y, 2*centre.z - p.z)
				st.set_uv((Vector2(q.x, q.z - q.y) - at) / size)
				st.add_vertex(p*S)
	surfaces.append([st.commit(), t])

# --- Kit buildings (the inn) ---------------------------------------------------------
# The original assembles some buildings from modular sprites (seq 33: the stone ground
# floor and the roof) plus building tiles (the half-timbered upper storey and the eave).
# tools/facade_fit.py fits the building to the composite of its pieces as the original
# camera saw it and lists those pieces; here the same composite is rebuilt, screen by
# screen and clipped as the engine clips, and projected onto the fitted wings exactly like
# a house sprite. Its tiles leave the ground, which continues the row they interrupted.

func _depth(s: Dictionary) -> float:
	if int(s.type) == 0: return -10000.0 + float(s.y)
	return float(s.que) if int(s.que) != 0 else float(s.y)

func _draw_order(sprites: Array) -> Array:
	var idx: Array = range(sprites.size())
	idx.sort_custom(func(a, b):
		var ka := _depth(sprites[a])
		var kb := _depth(sprites[b])
		return ka < kb or (ka == kb and a < b))
	return idx

# [canvas, back, world top-left, members ("screen:t|s:index" -> true)] of kit building `b`
# (an entry of facades._kit_buildings), from the map's own tiles and sprites.
func kit_prepare(b: Dictionary) -> Array:
	var name := str(b.name)
	if kit_cache.has(name): return kit_cache[name]
	var r: Array = b.rect
	var top_left := Vector2(float(r[0]), float(r[1]))
	var canvas := Image.create(int(r[2]), int(r[3]), false, Image.FORMAT_RGBA8)
	var members := {}
	for m in b.members: members["%d:%s:%d" % [int(m[0]), str(m[1]), int(m[2])]] = true
	# The back, which the original camera never saw, mirrors the front without its doors and
	# signs: door panels show their door-less twins, door and sign sprites are left off.
	var back := Image.create(int(r[2]), int(r[3]), false, Image.FORMAT_RGBA8)
	var kit: Dictionary = facades.get("_kit", {})
	var kit_seqs := {}
	for q in kit.get("seqs", []): kit_seqs[int(q)] = true # JSON numbers are floats
	for sn in b.screens:
		var n := int(sn)
		var screen: Dictionary = world.screens[str(n)]
		var view := Image.create(600, 400, false, Image.FORMAT_RGBA8)
		var view_b := Image.create(600, 400, false, Image.FORMAT_RGBA8)
		for i in range(mini(96, screen.tiles.size())):
			if not members.has("%d:t:%d" % [n, i]): continue
			var index := int(screen.tiles[i].get("tile", 0))
			var sheet := image("assets/tiles/ts%02d.png" % (int(index/128)+1))
			var cell := index % 128
			view.blit_rect(sheet, Rect2i((cell%12)*50, int(cell/12)*50, 50, 50), Vector2i((i%12)*50, int(i/12)*50))
			view_b.blit_rect(sheet, Rect2i((cell%12)*50, int(cell/12)*50, 50, 50), Vector2i((i%12)*50, int(i/12)*50))
		for i in _draw_order(screen.sprites):
			if not members.has("%d:s:%d" % [n, i]): continue
			var s: Dictionary = screen.sprites[i]
			var d := frame_data(int(s.seq), int(s.frame))
			var img := _kit_piece(str(d.path))
			var at := Vector2i(int(s.x) - 20 - int(d.dx), int(s.y) - int(d.dy))
			view.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			if not kit_seqs.has(int(s.seq)): continue
			var bimg := _kit_piece(str(kit.get("back", {}).get(str(d.path), d.path)))
			view_b.blend_rect(bimg, Rect2i(Vector2i.ZERO, bimg.get_size()), at)
		canvas.blend_rect(view, Rect2i(0, 0, 600, 400), Vector2i(origin(n) - top_left))
		back.blend_rect(view_b, Rect2i(0, 0, 600, 400), Vector2i(origin(n) - top_left))
	_knock_out_background(canvas)
	_knock_out_background(back)
	kit_cache[name] = [canvas, back, top_left, members]
	return kit_cache[name]

# The kit building `b` with its dormers: origin at its world top-left.
func kit(b: Dictionary) -> Node3D:
	var key := "kit:%s" % str(b.name)
	if not surface_cache.has(key):
		var k := kit_prepare(b)
		var surfaces: Array = []
		_block_house(surfaces, b, fill_holes(k[0]), fill_holes(k[1]))
		for dm in b.get("dormers", []): _dormer(surfaces, dm)
		surface_cache[key] = [surfaces, null]
	return node_from(surface_cache[key][0])

# Grass and water in the building tiles are what stands behind the building: clear the
# background-coloured regions connected to the outside (enclosed window glass stays).
func _knock_out_background(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var open := PackedByteArray()
	open.resize(w*h)
	for p in w*h:
		var cr := data[p*4]
		var cg := data[p*4+1]
		var cb := data[p*4+2]
		if data[p*4+3] < 128 or (cg > cr + 10 and cg > cb + 10) or (cb > cr + 20 and cb > cg + 10): open[p] = 1
	var seen := PackedByteArray()
	seen.resize(w*h)
	var queue := PackedInt32Array()
	for p in w*h:
		var x := p % w
		var y := p / w
		if (x == 0 or y == 0 or x == w-1 or y == h-1) and open[p]:
			seen[p] = 1
			queue.append(p)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var x := p % w
		for q in [p-1 if x > 0 else -1, p+1 if x < w-1 else -1, p-w, p+w]:
			if q < 0 or q >= w*h or seen[q] or not open[q]: continue
			seen[q] = 1
			queue.append(q)
	for p in w*h:
		if seen[p]: data[p*4+3] = 0
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)

# --- Dormers ----------------------------------------------------------------------------
# Three kit roof panels have a dormer drawn in. tools/facade_fit.py fits each as a gabled
# prism standing on the roof (its foot found by the view ray, like a chimney's) and lists its
# faces with texture coordinates in the panel's pixels. On the roof, the panel shows its
# plain twin wherever the dormer stood in the original camera's view.

func _kit_piece(path: String) -> Image:
	var dp: Dictionary = facades.get("_dormer_panels", {}).get(path, {})
	if dp.is_empty(): return image(path)
	if clean_panels.has(path): return clean_panels[path]
	var img: Image = image(path).duplicate()
	var twin := image(str(dp.twin))
	var polys: Array = []
	for poly in dp.poly:
		var pv := PackedVector2Array()
		for q in poly: pv.append(Vector2(float(q[0]), float(q[1])))
		polys.append(pv)
	for y in img.get_height():
		for x in img.get_width():
			for pv in polys:
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pv):
					img.set_pixel(x, y, twin.get_pixel(x, y))
					break
	clean_panels[path] = img
	return img

func _dormer(surfaces: Array, dm: Dictionary) -> void:
	var img: Image = image(str(dm.path)).duplicate()
	var size := Vector2(img.get_width(), img.get_height())
	img.generate_mipmaps()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in dm.faces:
		var pts: Array = f.pts
		var uv: Array = f.uv
		for i in range(1, pts.size()-1):
			for k in [0, i, i+1]:
				st.set_uv(Vector2(float(uv[k][0]), float(uv[k][1])) / size)
				st.add_vertex(Vector3(float(pts[k][0]), float(pts[k][1]), float(pts[k][2]))*S)
	surfaces.append([st.commit(), ImageTexture.create_from_image(img)])
