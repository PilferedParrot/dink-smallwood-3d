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
# The kit buildings' filled canvases, baked by tools/bake_kit_canvases.gd: composing them here takes
# seconds of per-pixel GDScript per building. Used while the manifest's facades.json hash matches.
const BAKED_DIR := "res://data/kits"
const BAKED_HOUSES := "res://data/houses"
const FACADES := "res://prototype/facades.json"
var baked_ok := -1 # -1 unknown, 0 stale or missing, 1 usable

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

# A private copy of the sprite's pixels: callers paint into it (a house's canvas, a chimney's crop). Under
# the headless (dummy) renderer get_image() returns the texture's own stored Image, so painting into it
# changed the sprite for every later caller: the house bake (tools/bake_houses.gd, headless) composed each
# house's back from a canvas that already held its doors, and the game drew those doors on the backs.
func image(path: String) -> Image:
	var t := tex(path)
	if t == null: return null
	var img := t.get_image().duplicate() as Image
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
# `bake_key`: the house's key in the bake (tools/bake_houses.gd), whose images replace composing
# them; `want_shade`: whether to compute the drawn shadow (the prototype paints it on its ground).
func house(path: String, rect: Rect2, parts: Dictionary, cache_key: String = "", bake_key: String = "", want_shade: bool = true) -> Dictionary:
	var fit: Dictionary = facades[path]
	var hull := hull_of(fit, rect)
	if not cache_key.is_empty() and surface_cache.has(cache_key):
		var cached: Array = surface_cache[cache_key]
		return {"node": node_from(cached[0]), "shade": cached[1], "hull": hull}
	var imgs: Array = baked_house(bake_key) if not bake_key.is_empty() else []
	var shade: Image = null
	if imgs.is_empty():
		var made := house_images(path, rect, parts)
		imgs = made[0]
		# The original's shadow: the isolated black dither pixels, which lie on the ground
		# in this projection, for the ground at 50% like the engine's blend.
		if want_shade: shade = _shade(made[1], dither_mask(made[1]))
	var surfaces: Array = []
	var k := 2
	if fit.has("polys"):
		_uv_house(surfaces, fit, [_texture(imgs[0]), _texture(imgs[1]), _texture(imgs[2])])
		k = 3
	else: _block_house(surfaces, fit, _texture(imgs[0]), _texture(imgs[1]))
	for r in parts.roof:
		_roof_piece(surfaces, r, fit, _texture(imgs[k]))
		k += 1
	for g in parts.ground:
		_ground_piece(surfaces, g, rect.position, _texture(imgs[k]))
		k += 1
	if not cache_key.is_empty(): surface_cache[cache_key] = [surfaces, shade]
	return {"node": node_from(surfaces), "shade": shade, "hull": hull}

# The wall footprint of the house fitted as `fit` at world `rect`, in world pixels: the convex hull of
# its wall faces' feet (empty if it has fewer than three). Cheap, so a caller can have it before the
# house is built (the trees' draw order, fp_world.gd depth_shift).
func hull_of(fit: Dictionary, rect: Rect2) -> PackedVector2Array:
	var foot := PackedVector2Array()
	for f in fit.faces:
		if int(f.label) != 1: continue
		for q in f.pts:
			if absf(float(q[1])) < 1e-3: foot.append(rect.position + Vector2(float(q[0]), float(q[2])))
	return Geometry2D.convex_hull(foot) if foot.size() >= 3 else PackedVector2Array()

# The filled images a house's surfaces take, in order: its body's (front and back, or the three
# of a parts building), then one per roof piece and one per ground piece; and the composed canvas.
# This is the costly part, and what the bake stores.
func house_images(path: String, rect: Rect2, parts: Dictionary) -> Array:
	var fit: Dictionary = facades[path]
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
	var srcs: Array = [canvas, back]
	if fit.has("polys"):
		# Upright pieces standing in front of the body (a chimney) are cleared from the body's
		# texture, which is filled from its own pixels there; the pieces keep the full sprite.
		var occ: Array = []
		for poly in fit.get("occluders", []):
			var pv := PackedVector2Array()
			for q in poly: pv.append(Vector2(float(q[0]), float(q[1])))
			occ.append(pv)
		srcs = [_without(canvas, occ), _without(back, occ), canvas]
	for r in parts.roof: srcs.append(_roof_piece_image(r))
	for g in parts.ground: srcs.append(image(str(sprite_frame(g[0]).path)))
	return [fill_all(srcs), canvas]

# The baked images of a house (tools/bake_houses.gd), or [] if it is not in a current bake.
var houses_baked: Variant = null # the manifest's "houses" when current, else {}
func baked_house(key: String) -> Array:
	if houses_baked == null:
		houses_baked = {}
		var path := BAKED_HOUSES + "/manifest.json"
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if manifest is Dictionary and str(manifest.get("facades_sha256", "")) == FileAccess.get_sha256(FACADES):
			houses_baked = manifest.get("houses", {})
		elif FileAccess.file_exists(path):
			push_warning("data/houses is stale for prototype/facades.json: composing houses at run time (tools/bake_houses.gd)")
	var id := key.sha1_text()
	if not (houses_baked as Dictionary).has(id): return []
	var out: Array = []
	for i in int(houses_baked[id]):
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes("%s/%s-%d.bin" % [BAKED_HOUSES, id, i])) != OK: return []
		img.convert(Image.FORMAT_RGBA8)
		out.append(img)
	return out

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
	return _texture(filled(src))

# filled() of each image, on the worker threads: pure Image work on images of their own, so each
# is the same bytes as a call on this thread.
func fill_all(imgs: Array) -> Array:
	var out: Array = []
	out.resize(imgs.size())
	var tasks: Array = []
	for i in imgs.size():
		tasks.append(WorkerThreadPool.add_task(func(): out[i] = filled(imgs[i])))
	for t in tasks: WorkerThreadPool.wait_for_task_completion(t)
	return out

func _texture(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func filled(src: Image) -> Image:
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
	return img

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
# `texs`: the body without its pieces, its back without them, and the full sprite (house_images).
func _uv_house(surfaces: Array, fit: Dictionary, texs: Array) -> void:
	var sts: Array = []
	var used := [false, false, false]
	for k in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var size := Vector2(texs[0].get_width(), texs[0].get_height())
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

# The index of the face ray_hit finds through house-local screen point (x, y), or -1.
func _first_face(fit: Dictionary, x: float, y: float) -> int:
	var best := -1
	var best_y := -INF
	for i in fit.faces.size():
		var pts := pts_of(fit.faces[i])
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		var den := n.y + n.z
		if absf(den) < 1e-6: continue
		var yy := (n.dot(pts[0]) - n.x*x - n.z*y) / den
		if yy > best_y and _inside(pts, n, Vector3(x, yy, y + yy)):
			best = i
			best_y = yy
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
	var first_face := {} # sprite pixel -> the face the original camera sees there (_first_face)
	for fi in fit.faces.size():
		var f: Dictionary = fit.faces[fi]
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
		# Only the texel columns whose point lands inside the piece's sprite: sx = floor(x - at.x)
		# with x = 2c.x - U - 0.5 (the same texels as scanning the whole face, far fewer tried).
		var u0 := maxi(maxi(0, int(lo.x)), int(floor(2.0*cen.x - 0.5 - at.x - w)))
		var u1 := mini(mini(back.get_width(), int(hi.x) + 1), int(ceil(2.0*cen.x - 0.5 - at.x)) + 1)
		for V in range(maxi(0, int(lo.y)), mini(back.get_height(), int(hi.y) + 1)):
			for U in range(u0, u1):
				var x := 2.0*cen.x - (U + 0.5)
				var sz := 2.0*cen.z - (V + 0.5) # y + z on the face
				# n.x x + n.y y + n.z (sz - y) = n.p0
				var y := (n.dot(pts[0]) - n.x*x - n.z*sz) / (n.y - n.z)
				var p := Vector3(x, y, sz - y)
				var sx := int(floor(p.x - at.x))
				var sy := int(floor(p.z - p.y - at.y))
				if sx < 0 or sy < 0 or sx >= w or sy >= h: continue
				if not _inside(pts, n, p): continue
				if sx >= float(rp.top[0][0]) and sx <= float(rp.top[2][0]) and sy <= float(rp.foot[1]): continue
				# Only where the original camera sees this face: behind the ridge the view ray meets
				# the near slope first. Unseen, the wedge's few pixels spread down the whole far slope
				# along the grazing rays and showed at eye level as a dark stripe from ridge to eave.
				# The face seen is read once per sprite pixel, through its centre.
				var key := sy*w + sx
				if not first_face.has(key): first_face[key] = _first_face(fit, at.x + sx + 0.5, at.y + sy + 0.5)
				if int(first_face[key]) != fi: continue
				var col := img.get_pixel(sx, sy)
				if dither[sy*w + sx]: col = Color(0, 0, 0, 0.5)
				if col.a < 0.25: continue
				back.set_pixel(U, V, back.get_pixel(U, V).blend(col))

# A chimney standing on the ground beside a house (tools/facade_fit.py standing_piece): the
# frustum from its foot (on the ground, where the sprite shows it) to its top face (at its height),
# textured by projection like a house; faces the original camera never saw take the point mirror
# about its axis. `house_tl`: the house's world top-left, the node's origin.
func _ground_piece(surfaces: Array, g: Array, house_tl: Vector2, t: ImageTexture) -> void:
	var rp: Dictionary = g[1]
	var tl: Vector2 = g[2]
	var h := float(rp.height)
	var base: Array[Vector3] = []
	for q in rp.base: base.append(Vector3(float(q[0]), 0.0, float(q[1])))
	var top: Array[Vector3] = [] # front, right, back, left, as the base
	for k in [3, 2, 1, 0]: top.append(Vector3(float(rp.top[k][0]), h, float(rp.top[k][1]) + h))
	var cen := Vector3.ZERO
	for q in base: cen += q / 4.0
	var faces: Array = [top]
	for k in 4: faces.append([base[k], base[(k+1) % 4], top[(k+1) % 4], top[k]] as Array[Vector3])
	var size := Vector2(t.get_width(), t.get_height())
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
	surfaces.append([st.commit(), t])

# A roof piece's sprite without its roof-lying parts (its foot's thatch and shadow, painted on the
# roof), for its texture: stone is extended over the gaps when it is filled.
func _roof_piece_image(r: Array) -> Image:
	var rp: Dictionary = r[1]
	var img := image(str(sprite_frame(r[0]).path))
	for y in img.get_height():
		for x in img.get_width():
			if x < float(rp.top[0][0]) or x > float(rp.top[2][0]) or y > float(rp.foot[1]): img.set_pixel(x, y, Color(0,0,0,0))
	return img

func _roof_piece(surfaces: Array, r: Array, fit: Dictionary, t: ImageTexture) -> void:
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
	var size := Vector2(t.get_width(), t.get_height())
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
		var sides := baked_kit(b)
		if sides.is_empty(): sides = kit_canvases(b)
		var surfaces: Array = []
		_block_house(surfaces, b, _texture(sides[0]), _texture(sides[1]))
		for dm in b.get("dormers", []): _dormer(surfaces, dm)
		surface_cache[key] = [surfaces, null]
	return node_from(surface_cache[key][0])

# The kit building's front and back textures, filled, before mipmaps: what the bake stores.
func kit_canvases(b: Dictionary) -> Array:
	var k := kit_prepare(b)
	return [filled(k[0]), filled(k[1])]

# The baked [front, back] of kit building `b`, or [] if there is no current bake.
func baked_kit(b: Dictionary) -> Array:
	if baked_ok < 0:
		baked_ok = 0
		var path := BAKED_DIR + "/manifest.json"
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if manifest is Dictionary and str(manifest.get("facades_sha256", "")) == FileAccess.get_sha256(FACADES):
			baked_ok = 1
		elif FileAccess.file_exists(path):
			push_warning("data/kits is stale for prototype/facades.json: composing kit buildings at run time (tools/bake_kit_canvases.gd)")
	if baked_ok != 1: return []
	var out: Array = []
	for side in ["front", "back"]:
		var file := "%s/%s-%s.bin" % [BAKED_DIR, str(b.name), side]
		if not FileAccess.file_exists(file): return []
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(file)) != OK: return []
		img.convert(Image.FORMAT_RGBA8)
		out.append(img)
	return out

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

# --- The castle (docs/DIRECTION.md, tenth pass) --------------------------------------------------
# A castle sprite (struct/Castle, frames 1-4 and 6-9; M3: the gatehouse 5 and the corner 12) is a piece of wall, a
# tower or a block, fitted by tools/facade_fit.py castle_fit (prototype/facades.json "_walls", by sprite path).
# Vertices are in the sprite's own pixel frame (x east, z = screen y at ground level, Y up) times S, so a piece's
# origin is its sprite's top-left, as a house's. Every face is textured by projecting the sprite back through the
# original camera, UV = (x, z - Y), exact on planes; a face the camera never saw takes the point mirror of the one it
# did (through the prism's centre, the tower's axis), except a wall's far face (below).
#   wall:  a prism on the drawn base line (x, s x + c): the front face up to the walkway at height hw, the
#          walkway (a band tv deep behind it), the far face, the two end cuts (vertical planes x = x0, x1: where the
#          sprite is cut), and the parapet. M3: one wall is one solid. castl-06/08 draw its inner face and 07/09 its
#          outer one, so the far face is the SIBLING sprite's picture (`far`; the point mirror of the front only on
#          the stubs of frames 1-3), and the parapet is a solid strip pt thick on the OUTER edge (parapet "back": behind
#          the walkway; "front": flush with the face, whose walkway comes from the sibling's picture): alpha-cut front,
#          top and back faces of the sprite's own merlon pixels, one alpha for the three (a gap is a gap through).
#   block: a prism on a plan polygon (the gatehouse: its front measured from the lowest drawn pixels, its back from the
#          silhouette, a cornice band that overhangs the wall up to a flat deck; the corner: the end of a wall, cut by a
#          plane the camera never sees). A face the camera cannot see takes a sibling's picture (`far`) or the point
#          mirror; an edge-on face (x = const) is a stripe of the sprite's column. Its picture: castle_edges.
#   tower: an elliptic cylinder (the art draws a ground circle as an ellipse, the 1:1 ground's rhombi
#          again): a narrower plinth (radius a, to h1), the body (radius ar, to the platform at h3), the
#          platform, and the parapet around it (m high, alpha-cut, a ring pt thick). The far half takes the
#          point-mirrored front; the parapet, seen from the inside on the far side, is projected as drawn.
var castle_cache: Dictionary = {} # sprite path -> [[mesh, texture or material], ...]
var castle_textures: Dictionary = {} # sprite path -> [solid ImageTexture, cut ImageTexture]
const CASTLE_SEGMENTS := 48

func castle_fit(path: String) -> Dictionary:
	var walls: Variant = facades.get("_walls", {})
	if walls is Dictionary and (walls as Dictionary).has(path) and walls[path] is Dictionary: return walls[path]
	return {}

# The sprite's texture without holes (the pixels the shadow dither and the empty air leave are filled
# from their nearest drawn neighbours) for the solid faces, and with its own alpha (dither cleared) for
# the parapet's strips: the colours there are the filled ones, so a merlon's edge does not blend with the
# empty pixels' black.
func castle_images(path: String) -> Array:
	if castle_textures.has(path): return castle_textures[path]
	var src := image(path)
	var solid := filled(src)
	var dither := dither_mask(src)
	var cut := solid.duplicate() as Image
	var data := cut.get_data()
	var sd := src.get_data()
	for p in dither.size():
		data[p*4+3] = 255 if sd[p*4+3] >= 128 and dither[p] == 0 else 0
	cut.set_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)
	var out := [_texture(solid), _texture(cut)]
	castle_textures[path] = out
	return out

# A sibling sprite's picture as it is drawn (no fill of the shadow dither and the empty air: that is a per-pixel pass of
# about 0.15 s a sprite), for the faces that lie inside its drawn brick: a wall's far face and the walkway of an outer face.
var castle_raws: Dictionary = {} # sprite path -> ImageTexture
func castle_raw(path: String) -> ImageTexture:
	if not castle_raws.has(path): castle_raws[path] = _texture(image(path))
	return castle_raws[path]

# A block's picture (the gatehouse, the corner): the sprite with the colour of its empty edge pixels borrowed from their
# neighbours (Image.fix_alpha_edges, native), where castle_images fills every empty pixel by a breadth-first pass in
# GDScript (0.15 to 0.5 s a sprite, measured). The block's faces lie inside the drawn body except at its silhouette, a
# one pixel band; the shadow dither below the base stays as drawn.
var castle_edge_textures: Dictionary = {} # sprite path -> ImageTexture
func castle_edges(path: String) -> ImageTexture:
	if not castle_edge_textures.has(path):
		var img: Image = image(path).duplicate()
		img.fix_alpha_edges()
		castle_edge_textures[path] = _texture(img)
	return castle_edge_textures[path]

func _castle_cut_material(t: ImageTexture) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	return m

# One quad (a, b, c, d in order) with each corner's texture coordinate in sprite pixels.
func _castle_quad(st: SurfaceTool, pts: Array, uvs: Array, size: Vector2) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_uv((uvs[k] as Vector2) / size)
		st.add_vertex((pts[k] as Vector3)*S)
	st.set_meta("n", int(st.get_meta("n", 0)) + 1)

# A horizontal polygon `pts` (Vector3, one height) by its triangulation, texture coordinates from `uv`.
func _castle_poly(st: SurfaceTool, pts: Array, uv: Callable, size: Vector2) -> void:
	var flat := PackedVector2Array()
	for p in pts: flat.append(Vector2((p as Vector3).x, (p as Vector3).z))
	var tri := Geometry2D.triangulate_polygon(flat)
	for i in tri:
		st.set_uv((uv.call(pts[i]) as Vector2) / size)
		st.add_vertex((pts[i] as Vector3)*S)
	if tri.size() > 0: st.set_meta("n", int(st.get_meta("n", 0)) + 1)

func _proj(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z - p.y)

# A SurfaceTool for the texture of a sibling sprite (its solid or its alpha-cut picture), made on first use.
func _castle_extra(table: Dictionary, path: String) -> SurfaceTool:
	if not table.has(path):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		table[path] = st
	return table[path]

# A wall: ONE solid however it is seen (docs/DIRECTION.md, M3). castl-06/08 draw its inner face, 07/09 its outer, so
# the sprite's own face is the front and the sibling's art is what belongs on the far face (`far`: the sibling's
# brick, its walkway). The parapet is a solid strip pt thick on the OUTER edge (06/08: behind the walkway, 07/09:
# flush with the face), alpha-cut (the crenels see-through): a front face, a top face and a back face of the sprite's
# own merlon pixels (one alpha for all three: a gap is a gap through the whole thickness).
func _castle_wall(q: Dictionary, size: Vector2, solid: SurfaceTool, cut: SurfaceTool, extra: Dictionary) -> void:
	var x0 := float(q.x0)
	var x1 := float(q.x1)
	var s := float(q.s)
	var c := float(q.c)
	var hw := float(q.hw)
	var tv := float(q.tv)
	var yt := float(q.get("y_top", hw))
	var pt := float(q.get("pt", 0.0))
	var kind := str(q.parapet)
	var depth := float(q.get("depth", tv))
	var xm := (float(q.get("m0", x0)) + float(q.get("m1", x1)))/2.0 # the unclipped centre: the far face's mirror
	var P := func(x: float, y: float, off: float) -> Vector3: return Vector3(x, y, s*x + c - off)
	var has_far := q.has("far")
	var fp := str(q.far.path) if has_far else ""
	var fs := float(q.far.s) if has_far else 0.0
	var fc := float(q.far.c) if has_far else 0.0
	var fsize := Vector2.ZERO
	if has_far:
		var sf := castle_fit(fp)
		fsize = Vector2(float(sf.size[0]), float(sf.size[1]))
	# The front face, to the walkway.
	var f: Array = [P.call(x0, 0.0, 0.0), P.call(x1, 0.0, 0.0), P.call(x1, hw, 0.0), P.call(x0, hw, 0.0)]
	_castle_quad(solid, f, f.map(_proj), size)
	# The far face.
	var b: Array = [P.call(x0, 0.0, depth), P.call(x1, 0.0, depth), P.call(x1, hw, depth), P.call(x0, hw, depth)]
	if has_far and not bool(q.get("mirror_far", false)): # (mirror_far: the test's control, the far side as in the ninth pass)
		# The sibling's face: its brick, its own base line.
		_castle_quad(_castle_extra(extra, fp), b, b.map(func(p: Vector3) -> Vector2: return Vector2(p.x, fs*p.x + fc - p.y)), fsize)
	else:
		var zc := s*xm + c - depth/2.0
		_castle_quad(solid, b, b.map(func(p: Vector3) -> Vector2: return _proj(Vector3(2.0*xm - p.x, p.y, 2.0*zc - p.z))), size)
	# The walkway: its own art on the inner sprites, the sibling's on the outer ones (the same wall seen from its other
	# side: its offset from its own near edge is the distance from this wall's inner face, depth - off).
	var wo := pt if kind == "front" else 0.0 # where the walkway starts behind the face
	var w: Array = [P.call(x0, hw, wo), P.call(x1, hw, wo), P.call(x1, hw, depth), P.call(x0, hw, depth)]
	if q.has("sibling"):
		var walk_uv := func(p: Vector3) -> Vector2:
			var off := s*p.x + c - p.z
			return Vector2(p.x, fs*p.x + fc - (depth - off) - hw)
		_castle_quad(_castle_extra(extra, fp), w, w.map(walk_uv), fsize)
	else:
		_castle_quad(solid, w, w.map(_proj), size)
	# The ends, where the sprite is cut.
	for x in [x0, x1]:
		var e: Array = [P.call(x, 0.0, 0.0), P.call(x, 0.0, depth), P.call(x, hw, depth), P.call(x, hw, 0.0)]
		_castle_quad(solid, e, e.map(_proj), size)
	if kind == "none": return
	# The parapet strip on the outer edge: `o` is its front plane's offset, [o, o + pt] its thickness.
	var o := tv if kind == "back" else 0.0
	var pf: Array = [P.call(x0, hw, o), P.call(x1, hw, o), P.call(x1, yt, o), P.call(x0, yt, o)]
	_castle_quad(cut, pf, pf.map(_proj), size)
	var ptop: Array = [P.call(x0, yt, o), P.call(x1, yt, o), P.call(x1, yt, o + pt), P.call(x0, yt, o + pt)]
	_castle_quad(cut, ptop, ptop.map(_proj), size)
	var pb: Array = [P.call(x0, hw, o + pt), P.call(x1, hw, o + pt), P.call(x1, yt, o + pt), P.call(x0, yt, o + pt)]
	_castle_quad(cut, pb, pb.map(_proj), size)

func _castle_tower(q: Dictionary, size: Vector2, solid: SurfaceTool, cut: SurfaceTool) -> void:
	var cx := float(q.cx)
	var cz := float(q.cz)
	var a := float(q.a)
	var asp := float(q.k) # the ground ellipse's aspect b / a
	var b := asp*a
	var ar := float(q.ar)
	var br := asp*ar
	var h1 := float(q.h1)
	var h3 := float(q.h3)
	var m := float(q.m)
	var pt := float(q.get("pt", 0.0))
	var n := CASTLE_SEGMENTS
	var ring := func(rx: float, rz: float, t: float, y: float) -> Vector3: return Vector3(cx + rx*cos(t), y, cz + rz*sin(t))
	# The texture coordinate of a point of the tower's surface: projected if on the front half (z
	# toward the camera), else through the axis from the front.
	var uv := func(p: Vector3) -> Vector2:
		return _proj(p) if p.z >= cz else _proj(Vector3(2.0*cx - p.x, p.y, 2.0*cz - p.z))
	var flare := float(q.get("flare", 0.0))
	var h2 := h1 + flare
	for i in n:
		var t0 := TAU*float(i)/n
		var t1 := TAU*float(i + 1)/n
		var plinth: Array = [ring.call(a, b, t0, 0.0), ring.call(a, b, t1, 0.0), ring.call(a, b, t1, h1), ring.call(a, b, t0, h1)]
		_castle_quad(solid, plinth, plinth.map(uv), size)
		if flare > 0.0:
			# The corbel: the shaft's radius widening to the crown's.
			var cone: Array = [ring.call(a, b, t0, h1), ring.call(a, b, t1, h1), ring.call(ar, br, t1, h2), ring.call(ar, br, t0, h2)]
			_castle_quad(solid, cone, cone.map(uv), size)
		else:
			# A step: its underside, where the body overhangs the plinth, takes the plinth's own stone just below.
			var under: Array = [ring.call(a, b, t0, h1), ring.call(a, b, t1, h1), ring.call(ar, br, t1, h1), ring.call(ar, br, t0, h1)]
			var below: Array = [ring.call(a, b, t0, h1 - 3.0), ring.call(a, b, t1, h1 - 3.0), ring.call(a, b, t1, h1 - 3.0), ring.call(a, b, t0, h1 - 3.0)]
			_castle_quad(solid, under, below.map(uv), size)
		var body: Array = [ring.call(ar, br, t0, h2), ring.call(ar, br, t1, h2), ring.call(ar, br, t1, h3), ring.call(ar, br, t0, h3)]
		_castle_quad(solid, body, body.map(uv), size)
		# The platform.
		var disc: Array = [Vector3(cx, h3, cz), ring.call(ar, br, t0, h3), ring.call(ar, br, t1, h3)]
		for k in 3:
			solid.set_uv(_proj(disc[k] as Vector3)/size)
			solid.add_vertex((disc[k] as Vector3)*S)
		# The parapet: alpha-cut, projected as drawn on both halves; a ring pt thick (M3): the outer face, the inner
		# face one thickness in, and the top between them.
		var par: Array = [ring.call(ar, br, t0, h3), ring.call(ar, br, t1, h3), ring.call(ar, br, t1, h3 + m), ring.call(ar, br, t0, h3 + m)]
		_castle_quad(cut, par, par.map(_proj), size)
		if pt > 0.0:
			var ri := ar - pt
			var bi := asp*ri
			var inner: Array = [ring.call(ri, bi, t0, h3), ring.call(ri, bi, t1, h3), ring.call(ri, bi, t1, h3 + m), ring.call(ri, bi, t0, h3 + m)]
			_castle_quad(cut, inner, inner.map(_proj), size)
			var topf: Array = [ring.call(ri, bi, t0, h3 + m), ring.call(ri, bi, t1, h3 + m), ring.call(ar, br, t1, h3 + m), ring.call(ar, br, t0, h3 + m)]
			_castle_quad(cut, topf, topf.map(_proj), size)

# A block: a prism on a plan polygon (the gatehouse; the corner's wall cut by the perpendicular wall's plane). The
# polygon's edges are the planes the art draws (tools/facade_fit.py gate_fit); a face the camera never saw (its plan
# normal points away, nz < 0) takes its `far` sibling's art where one is named for its slope, else the point mirror
# of the front through the plan's middle. `hb`: the wall's height, then (poly_ov) the cornice band that overhangs it,
# to `hf`, and the deck. "caps" lists frusta standing on the deck (the gatehouse's vaulted tops): the build is here, but
# nothing fits them yet (the fit leaves it empty), so the deck is a flat picture of them.
func _castle_block(q: Dictionary, size: Vector2, solid: SurfaceTool, extra: Dictionary) -> void:
	var poly: Array = q.poly
	var n := poly.size()
	var area := 0.0
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		area += float(a[0])*float(b[1]) - float(b[0])*float(a[1])
	var orient := 1.0 if area > 0.0 else -1.0
	var hf := float(q.hf)
	var hb: Variant = q.get("hb", null)
	var mirror: Vector2 = Vector2(float(q.mirror[0]), float(q.mirror[1])) if q.has("mirror") else Vector2.ZERO
	var far: Array = q.get("far", [])
	var far_fit := {}
	for f in far:
		var sf := castle_fit(str(f.path))
		far_fit[str(f.plane)] = [str(f.path), float(sf.parts[0].s), float(sf.parts[0].c), Vector2(float(sf.size[0]), float(sf.size[1]))]
	var ov: Variant = q.get("poly_ov", null)
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		var dx := float(b[0]) - float(a[0])
		var dz := float(b[1]) - float(a[1])
		# An edge-on face (x = const: the camera's own shear) is a stripe of the sprite's column, as a wall's end cut.
		var edge_on := absf(dx) < 0.01
		var nz := -dx*orient # the outward normal's z (toward the camera if > 0)
		var slope := dz/dx if not edge_on else 0.0
		var plane := "/" if slope < -0.25 else ("\\" if slope > 0.25 else "-")
		var visible := nz > 0.0 or edge_on
		var target := solid
		var uvf: Callable
		if visible:
			uvf = _proj
		elif far_fit.has(plane):
			var ff: Array = far_fit[plane]
			target = _castle_extra(extra, ff[0])
			var fs: float = ff[1]
			var fc: float = ff[2]
			uvf = func(p: Vector3) -> Vector2: return Vector2(p.x, fs*p.x + fc - p.y)
		else:
			uvf = func(p: Vector3) -> Vector2: return _proj(Vector3(2.0*mirror.x - p.x, p.y, 2.0*mirror.y - p.z))
		var tsize: Vector2 = size if (visible or not far_fit.has(plane)) else (far_fit[plane][3] as Vector2)
		var top := float(hb) if hb != null else hf
		var A := Vector3(float(a[0]), 0.0, float(a[1]))
		var B := Vector3(float(b[0]), 0.0, float(b[1]))
		var face: Array = [A, B, B + Vector3(0, top, 0), A + Vector3(0, top, 0)]
		_castle_quad(target, face, face.map(uvf), tsize)
		if hb != null and ov != null:
			var oa: Array = (ov as Array)[i]
			var ob: Array = (ov as Array)[(i + 1) % n]
			var OA := Vector3(float(oa[0]), top, float(oa[1]))
			var OB := Vector3(float(ob[0]), top, float(ob[1]))
			# The cornice band, on the overhanging plane, from the wall's height to the deck.
			var band: Array = [OA, OB, OB + Vector3(0, hf - top, 0), OA + Vector3(0, hf - top, 0)]
			_castle_quad(target, band, band.map(uvf), tsize)
			# Its underside (seen from the ground): the stone just below the cornice.
			var under: Array = [A + Vector3(0, top, 0), B + Vector3(0, top, 0), OB, OA]
			var below: Array = [A + Vector3(0, top - 3.0, 0), B + Vector3(0, top - 3.0, 0), B + Vector3(0, top - 3.0, 0), A + Vector3(0, top - 3.0, 0)]
			_castle_quad(target, under, below.map(uvf), tsize)
	# The deck (the walkway, on the corner): horizontal, so projected exactly.
	var deck: Array = []
	var src: Array = (ov as Array) if (hb != null and ov != null) else poly
	for p in src: deck.append(Vector3(float(p[0]), hf, float(p[1])))
	_castle_poly(solid, deck, _proj, size)
	# The caps standing on the deck: frustums (a base polygon at y0, the top polygon inset toward its centre).
	for cap in q.get("caps", []):
		_castle_cap(cap, size, solid)

func _castle_cap(cap: Dictionary, size: Vector2, solid: SurfaceTool) -> void:
	var poly: Array = cap.poly
	var y0 := float(cap.y0)
	var y1 := float(cap.y1)
	var inset := float(cap.inset)
	var cx := 0.0
	var cz := 0.0
	for p in poly:
		cx += float(p[0])/poly.size()
		cz += float(p[1])/poly.size()
	var n := poly.size()
	var tops: Array = []
	for p in poly:
		var d := Vector2(float(p[0]) - cx, float(p[1]) - cz)
		var dl := d.length()
		var t := Vector2(cx, cz) + d*maxf(0.0, (dl - inset)/dl)
		tops.append(Vector3(t.x, y1, t.y))
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		var face: Array = [Vector3(float(a[0]), y0, float(a[1])), Vector3(float(b[0]), y0, float(b[1])), tops[(i + 1) % n], tops[i]]
		_castle_quad(solid, face, face.map(_proj), size)
	_castle_poly(solid, tops, _proj, size)

# The surfaces of a fitted castle sprite ([[mesh, texture or material], ...]), cached by path.
func castle_surfaces(path: String, clips: Dictionary = {}) -> Array:
	var cache_key := path + str(clips)
	if castle_cache.has(cache_key): return castle_cache[cache_key]
	var fit := castle_fit(path)
	var is_block: bool = not fit.parts.is_empty() and str((fit.parts[0] as Dictionary).type) == "block"
	var imgs: Array = [castle_edges(path), null] if is_block else castle_images(path) # a block has no alpha-cut strip
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cut := SurfaceTool.new()
	cut.begin(Mesh.PRIMITIVE_TRIANGLES)
	var extra := {} # a sibling's solid picture -> its surface (the far faces, the walkway of an outer face)
	for i in fit.parts.size():
		var q: Dictionary = fit.parts[i]
		if clips.has(i):
			# The part is hidden where a later-drawn piece of the same wall covers it (fp_world.gd castle_clips).
			q = q.duplicate()
			q.m0 = q.x0
			q.m1 = q.x1
			q.x0 = float(clips[i][0])
			q.x1 = float(clips[i][1])
		if str(q.type) == "tower":
			_castle_tower(q, size, solid, cut)
		elif str(q.type) == "block":
			_castle_block(q, size, solid, extra)
		else:
			_castle_wall(q, size, solid, cut, extra)
	var surfaces: Array = [[solid.commit(), imgs[0]]]
	if int(cut.get_meta("n", 0)) > 0: surfaces.append([cut.commit(), _castle_cut_material(imgs[1])])
	for p in extra:
		if int((extra[p] as SurfaceTool).get_meta("n", 0)) > 0: surfaces.append([(extra[p] as SurfaceTool).commit(), castle_raw(p)])
	castle_cache[cache_key] = surfaces
	return surfaces

# The piece as a node: origin at its sprite's top-left. `clips`: part index -> [x0, x1], the span of a wall part
# not hidden by a later-drawn piece (the pieces of a wall overlap where the sprites do: the original draws the
# later over the earlier, and two coplanar faces must not both be drawn).
func castle(path: String, clips: Dictionary = {}) -> Node3D:
	return node_from(castle_surfaces(path, clips))

# --- The island's round huts (docs/DIRECTION.md, M3) -----------------------------------------------
# A hut sprite (struct/Island isle-01..06) is a solid of revolution about a vertical axis, fitted by tools/hut_fit.py
# (prototype/facades.json "_huts", by sprite path): the axis (cx, cz) in the sprite's pixel frame (x east, z = screen y
# at ground level, Y up, times S), the ground ellipse's aspect k (the castle's: one camera) and the profile r(h) at
# nodes up the height. Each node's ring is HUT_SEGMENTS points; the fit also says which of them the original camera
# sees ("vis", a 0/1 string per node). A surface point whose picture the camera has well is textured by projecting the
# sprite back through the camera, UV = (x, z - Y), exact; the rest of the hut (its far side, and the grazing flanks)
# takes the picture of the part seen well, back and forth round the hut (_hut_source); a point of the front hidden by the
# thatch above takes the visible ring just below (the wall under the eave), else above.
var hut_cache: Dictionary = {} # sprite path -> [[mesh, texture], ...]
const HUT_SEGMENTS := 48

func hut_fit(path: String) -> Dictionary:
	var huts: Variant = facades.get("_huts", {})
	if huts is Dictionary and (huts as Dictionary).has(path) and huts[path] is Dictionary: return huts[path]
	return {}

# The ring's columns run from the north (the far side from the original camera) round to the north again, the first and
# last the same point of the surface: the texture may be discontinuous there, and nowhere else.
func _hut_theta(c: int) -> float:
	return -PI/2.0 + TAU*float(c)/HUT_SEGMENTS

# The texture coordinate (sprite px) of each ring column: [node][column 0..HUT_SEGMENTS] -> Vector2.
func _hut_uvs(fit: Dictionary) -> Array:
	var nodes: Array = fit.nodes
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var n := HUT_SEGMENTS
	var proj := func(i: int, j: int) -> Vector2:
		var t := TAU*float(j)/n
		var r := float(nodes[i][1])
		return Vector2(cx + r*cos(t), cz + k*r*sin(t) - float(nodes[i][0]))
	var seen := func(i: int, j: int) -> bool:
		return str(nodes[i][2]).substr(j, 1) == "1"
	var out: Array = []
	for i in nodes.size():
		var row: Array = []
		for c in n + 1:
			var src := _hut_source(_hut_theta(c))
			var uv: Variant = null
			if seen.call(i, src): uv = proj.call(i, src)
			else: # hidden by the thatch above: the nearest ring up or down the wall that shows this point
				for step in [-1, 1]:
					var q: int = i + step
					while uv == null and q >= 0 and q < nodes.size():
						if seen.call(q, src): uv = proj.call(q, src)
						q += step
					if uv != null: break
			row.append(uv if uv != null else proj.call(i, src))
		out.append(row)
	return out

# The ring point (of the fit's HUT_SEGMENTS, counted from the east) whose picture the surface takes at angle theta. The
# original camera sees only the front of a hut, the half towards it (sin t > 0), and the flanks of that at a grazing
# angle where one source pixel spans several of surface; the rest takes the picture of the part seen well. With alpha the
# angle from the front, the picture is the sprite's at s(alpha), a triangle wave of period 4 HUT_GRAZE: the sprite
# as drawn within HUT_GRAZE of the front, then reflected at +-HUT_GRAZE, back and forth round the hut. It is continuous
# everywhere but at the far north, where the wave's phases meet (their pictures differ), and never uses the grazing
# flank. (Reflected across the plane through the axis instead, the east and west views are mirror images of themselves
# about the flank; turned half a turn, a hard seam runs down their middle: both measured on 764 and 680, 2026-10-02.
# Projecting the far-side points the camera does see, the back of the dome, lowered the original-camera colour error by
# about 1.2 but left patch seams on the oblique views, so they take the wave too.)
const HUT_GRAZE := 70.0
func _hut_source(theta: float) -> int:
	var n := HUT_SEGMENTS
	var alpha := rad_to_deg(theta - PI/2.0) # -180 at the first column to 180 at the last: not wrapped, so each of
	var u := fposmod(alpha + HUT_GRAZE, 4.0*HUT_GRAZE) # the seam's two points takes its own side's picture
	if u > 2.0*HUT_GRAZE: u = 4.0*HUT_GRAZE - u
	return posmod(roundi((deg_to_rad(u - HUT_GRAZE) + PI/2.0)/TAU*n), n)

# The hut sprite's picture with its holes filled (the shadow dither and the empty air round the body take the nearest drawn
# colour, so a texel at the body's edge does not blend with black): the bake's (tools/bake_houses.gd, key "hut:" + path,
# the same manifest as the houses' and so current while facades.json is) or, with no current bake, composed (~100 ms a sprite).
func hut_image(path: String) -> Image:
	var baked := baked_house("hut:" + path)
	if not baked.is_empty(): return baked[0]
	return filled(image(path))

# The surfaces of a fitted hut sprite ([[mesh, texture], ...]), cached by path. One vertex per ring point and node, the
# faces as an index buffer: the ring points carry their texture coordinates, so a quad's corners are shared.
func hut_surfaces(path: String) -> Array:
	if hut_cache.has(path): return hut_cache[path]
	var fit := hut_fit(path)
	var size := Vector2(float(fit.size[0]), float(fit.size[1]))
	var nodes: Array = fit.nodes
	var cx := float(fit.cx)
	var cz := float(fit.cz)
	var k := float(fit.k)
	var n := HUT_SEGMENTS
	var uvs := _hut_uvs(fit)
	var verts := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var index := PackedInt32Array()
	var cols := n + 1
	for i in nodes.size():
		var h := float(nodes[i][0])
		var r := float(nodes[i][1])
		for c in cols:
			var t := _hut_theta(c)
			verts.append(Vector3(cx + r*cos(t), h, cz + k*r*sin(t))*S)
			tex_uv.append((uvs[i][c] as Vector2)/size)
	for i in nodes.size() - 1:
		for c in n:
			var a := i*cols + c
			var b := a + 1
			var d := (i + 1)*cols + c
			var e := d + 1
			index.append_array(PackedInt32Array([a, b, e, a, e, d]))
	# The apex: a fan to the axis over the last ring.
	var top := nodes.size() - 1
	var apex := verts.size()
	verts.append(Vector3(cx, float(nodes[top][0]), cz)*S)
	tex_uv.append(Vector2(cx, cz - float(nodes[top][0]))/size)
	for c in n:
		index.append_array(PackedInt32Array([apex, top*cols + c + 1, top*cols + c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = tex_uv
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surfaces: Array = [[mesh, _texture(hut_image(path))]]
	hut_cache[path] = surfaces
	return surfaces

# The hut as a node: origin at its sprite's top-left, as a castle piece.
func hut(path: String) -> Node3D:
	return node_from(hut_surfaces(path))
