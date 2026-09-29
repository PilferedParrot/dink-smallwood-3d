extends SceneTree
# Direction prototype (docs/DIRECTION.md): the original map rebuilt from original
# pixels only. Ground = original tiles plus type-0 background sprites composited
# as the original engine does; type-1 sprites stand upright at their source
# positions; actors pick their original directional frame from the camera angle.
# Run: godot --path game -s res://prototype/sprite_world_proto.gd -- <out_dir> [center_screen]

const S := 0.025 # metres per source pixel, uniform for ground and sprites
const EYE := 1.6
const COLS := 32
# Dink directions (numpad) -> facing in source space (x right, y toward viewer).
const DIRS := {1: Vector2(-1,1), 2: Vector2(0,1), 3: Vector2(1,1), 4: Vector2(-1,0),
	6: Vector2(1,0), 7: Vector2(-1,-1), 8: Vector2(0,-1), 9: Vector2(1,-1)}

var sequences: Dictionary
var world: Dictionary
var root3d := Node3D.new()
var camera := Camera3D.new()
var actors: Array = [] # [Sprite3D, base_walk, facing Vector2, frame]
var tex_cache: Dictionary = {}
var facades: Dictionary # sprite path -> fitted house blocks (tools/facade_fit.py)
var env_node: WorldEnvironment

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://proto"
	var center := int(args[1]) if args.size() > 1 else 407
	sequences = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json"))["sequences"]
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	facades = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/facades.json"))
	root.add_child(root3d)
	_environment()
	var seen := {}
	for dy in range(-2,3):
		for dx in range(-2,3):
			var n := center + dy*COLS + dx
			if world.screens.has(str(n)) and not bool(world.screens[str(n)].get("indoor",false)):
				_build_screen(n, seen)
	camera.current = true
	camera.fov = 75
	root3d.add_child(camera)
	_capture(out_dir, center)

func _origin(n: int) -> Vector2:
	return Vector2(((n-1)%COLS)*600, int((n-1)/COLS)*400)

var clean_cache: Dictionary = {}

# The original draws shadows as a 50% black checkerboard on the ground plane. Standing
# upright, that dither floats in the air; remove isolated pure-black pixels.
func clean(path: String) -> Texture2D:
	if clean_cache.has(path): return clean_cache[path]
	var img := _image(path)
	if img == null: return null
	var src: Image = img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = src.get_pixel(x,y)
			if c.a > 0.5 and c.r+c.g+c.b < 0.04:
				var dark_neighbours := 0
				for o in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					var q: Vector2i = Vector2i(x,y)+o
					if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height(): continue
					var n: Color = src.get_pixel(q.x,q.y)
					if n.a > 0.5 and n.r+n.g+n.b < 0.04: dark_neighbours += 1
				if dark_neighbours == 0: img.set_pixel(x,y,Color(0,0,0,0))
	img.generate_mipmaps()
	clean_cache[path] = ImageTexture.create_from_image(img)
	return clean_cache[path]

func tex(path: String) -> Texture2D:
	if not tex_cache.has(path):
		tex_cache[path] = load("res://"+path) if ResourceLoader.exists("res://"+path) else null
	return tex_cache[path]

func frame_data(seq: int, frame: int) -> Dictionary:
	var fr: Array = sequences.get(str(seq),{}).get("frames",[])
	return {} if fr.is_empty() else fr[clampi(frame-1,0,fr.size()-1)]

func _image(path: String) -> Image:
	var t := tex(path)
	if t == null: return null
	var img := t.get_image()
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

func _build_screen(n: int, seen: Dictionary) -> void:
	var screen: Dictionary = world.screens[str(n)]
	var ground := Image.create(600,400,false,Image.FORMAT_RGBA8)
	for i in range(mini(96,screen.tiles.size())):
		var index := int(screen.tiles[i].get("tile",0))
		var sheet := _image("assets/tiles/ts%02d.png" % (int(index/128)+1))
		var cell := index%128
		if sheet: ground.blit_rect(sheet,Rect2i((cell%12)*50,int(cell/12)*50,50,50),Vector2i((i%12)*50,int(i/12)*50))
	var o := _origin(n)
	var upright := {}
	# Story state is not simulated here: show the editor's default layer (vision 0),
	# like the original-source reference images.
	var sprites: Array = screen.sprites.filter(func(s): return int(s.get("vision",0)) == 0)
	var consumed := _build_houses(n, sprites, ground, seen)
	for s in sprites:
		if int(s.type) == 1: upright["%d:%d:%d:%d" % [int(s.seq),int(s.frame),int(s.x),int(s.y)]] = true
	for s in sprites:
		if consumed.has(s): continue
		var seq := int(s.seq)
		var d := frame_data(seq,int(s.frame))
		if d.is_empty(): continue
		var t := tex(str(d.path))
		if t == null: continue
		var dx := float(d.get("dx",t.get_width()/2.0))
		var dy := float(d.get("dy",t.get_height()-10.0))
		if int(s.type) == 0 and upright.has("%d:%d:%d:%d" % [seq,int(s.frame),int(s.x),int(s.y)]): continue
		if int(s.type) == 0 and not str(d.path).contains("/struct/"):
			# Background sprite: painted into the ground, exactly as the original draws it.
			var img := _image(str(d.path))
			ground.blend_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i(int(s.x-20-dx),int(s.y-dy)))
			continue
		if int(s.type) == 2: continue # invisible
		var g := o + Vector2(float(s.x)-20.0, float(s.y))
		var key := "%d:%d:%d:%d" % [seq,int(s.frame),int(g.x),int(g.y)]
		if seen.has(key): continue
		seen[key] = true
		_add_sprite(s, d, t, g)
	ground.generate_mipmaps()
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600*S,400*S)
	plane.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(ground)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	plane.material_override = m
	plane.position = Vector3((o.x+300)*S,0,(o.y+200)*S)
	root3d.add_child(plane)

func _add_sprite(s: Dictionary, d: Dictionary, t: Texture2D, g: Vector2) -> void:
	var sp := Sprite3D.new()
	sp.pixel_size = S * maxf(0.01,float(s.size)/100.0)
	t = clean(str(d.path))
	sp.texture = t
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_set_anchor(sp, d, t)
	sp.position = Vector3(g.x*S,0,g.y*S)
	var base := int(s.base_walk)
	var seq := int(s.seq)
	if base > 0 and seq > base and seq <= base+9 and DIRS.has(seq-base):
		actors.append([sp, base, DIRS[seq-base], int(s.frame)])
	elif str(d.path).contains("/Fence/") and t.get_height() > 2*t.get_width():
		var rail := frame_data(93,1)
		var rt := clean(str(rail.path))
		sp.texture = rt
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# The drawn post column spans the segment's depth; cover it with a side-view rail.
		var length := float(t.get_height()) * 0.8
		sp.region_enabled = true
		sp.region_rect = Rect2(0,0,minf(length,rt.get_width()),rt.get_height())
		sp.centered = true
		sp.offset = Vector2(0, rt.get_height()/2.0 - 8.0)
		sp.rotation_degrees.y = 90
		sp.position.z -= (float(d.get("dy",t.get_height())) - t.get_height()/2.0) * S
	elif t.get_width() > 100 or str(d.path).contains("/Fence/") or str(d.path).contains("/struct/"):
		# Structures keep the orientation they were drawn in (facing the original viewer).
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	root3d.add_child(sp)

func _set_anchor(sp: Sprite3D, d: Dictionary, t: Texture2D) -> void:
	var dx := float(d.get("dx",t.get_width()/2.0))
	var dy := float(d.get("dy",t.get_height()-10.0))
	sp.centered = true
	sp.offset = Vector2(t.get_width()/2.0-dx, dy-t.get_height()/2.0)

func _face_actors() -> void:
	var cam := Vector2(camera.position.x, camera.position.z)
	for a in actors:
		var sp: Sprite3D = a[0]
		var to_actor := (Vector2(sp.position.x,sp.position.z)-cam).normalized()
		# Rotate so the camera looks along -y, like the original viewer; then the
		# actor's facing picks the frame drawn for that relative direction.
		var rel: Vector2 = (a[2] as Vector2).normalized().rotated(Vector2(0,-1).angle_to(to_actor) * -1.0)
		var best := 2
		var best_dot := -2.0
		for k in DIRS:
			var dd: float = (DIRS[k] as Vector2).normalized().dot(rel)
			if dd > best_dot and sequences.has(str(int(a[1])+k)):
				best_dot = dd
				best = k
		var d := frame_data(int(a[1])+best, int(a[3]))
		if d.is_empty(): continue
		var t := clean(str(d.path))
		if t == null: continue
		sp.texture = t
		_set_anchor(sp, d, t)

func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("4d7cc4")
	mat.sky_horizon_color = Color("b9d3e6")
	mat.ground_horizon_color = Color("8fa37a")
	sky.sky_material = mat
	e.sky = sky
	e.fog_enabled = true
	e.fog_light_color = Color("b9d3e6")
	e.fog_density = 0.012
	env.environment = e
	env_node = env
	root3d.add_child(env)

func _shot(pos_src: Vector2, look_src: Vector2, center: int) -> void:
	var o := _origin(center)
	var p := Vector3((o.x+pos_src.x-20)*S, EYE, (o.y+pos_src.y)*S)
	camera.position = p
	camera.look_at(Vector3((o.x+look_src.x-20)*S, EYE*0.8, (o.y+look_src.y)*S), Vector3.UP)
	_face_actors()

func _capture(out_dir: String, center: int) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280,720)
	# Shots are in screen 407's source coordinates (may leave the screen); a run centred
	# elsewhere builds a different 5x5 block, so shots outside it show empty ground.
	var shots := [
		["pen-from-south", Vector2(300,470), Vector2(300,220)],
		["pen-inside", Vector2(200,300), Vector2(380,230)],
		["pen-from-east", Vector2(700,240), Vector2(300,240)],
		["toward-cottage", Vector2(300,380), Vector2(560,700)],
		["village-east", Vector2(560,560), Vector2(1000,560)],
		["cottage-front", Vector2(430,800), Vector2(260,640)],
		["cottage-yard", Vector2(560,700), Vector2(280,620)],
		["neighbour-440", Vector2(820,860), Vector2(1000,560)],
		["village-469", Vector2(-330,1170), Vector2(-760,1110)],
		["village-469-west", Vector2(-900,930), Vector2(-1060,1260)],
	]
	await process_frame
	for shot in shots:
		var shift := _origin(407) - _origin(center)
		_shot(shot[1] + shift, shot[2] + shift, center)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out_dir.path_join(str(shot[0])+".png"))
	for n in ([407, 439, 440, 469, 470] if center != 407 else [center]):
		await _original_view(out_dir, n)
	quit()

# --- Buildings (DIRECTION.md "Buildings") -------------------------------------------
# A house sprite is a picture of a 3D house taken by the original camera, which on the
# prototype's 1:1 ground is the projection screen = (X, Z - Y) in source pixels.
# tools/facade_fit.py recovers the house's blocks from the sprite; here each face is
# textured by projecting the sprite back through that camera (UV = (x, z - y), exact on
# planar faces). Faces the original camera never saw take the point-mirrored front face.
# Door, window and damage sprites overlapping the house are composited into its
# texture first, in the original draw order, so they sit on the walls they were drawn on.

func _sprite_rect(s: Dictionary) -> Rect2:
	var d := frame_data(int(s.seq), int(s.frame))
	if d.is_empty(): return Rect2()
	var t := tex(str(d.path))
	if t == null: return Rect2()
	return Rect2(float(s.x) - float(d.dx), float(s.y) - float(d.dy), t.get_width(), t.get_height())

func _build_houses(n: int, sprites: Array, ground: Image, seen: Dictionary) -> Dictionary:
	var consumed := {}
	var o := _origin(n)
	for s in sprites:
		var d := frame_data(int(s.seq), int(s.frame))
		if d.is_empty() or not facades.has(str(d.path)) or int(s.type) == 2: continue
		consumed[s] = true
		var g := o + Vector2(float(s.x)-20.0, float(s.y))
		var key := "house:%s:%d:%d" % [d.path, int(g.x), int(g.y)]
		if seen.has(key): continue
		seen[key] = true
		var rect := _sprite_rect(s)
		var canvas := _image(str(d.path))
		# Details drawn over the house in the original, in its draw order (type 0 first).
		var details: Array = []
		for e in sprites:
			if e == s or consumed.has(e) or int(e.type) == 2: continue
			var ed := frame_data(int(e.seq), int(e.frame))
			if ed.is_empty() or facades.has(str(ed.path)) or not str(ed.path).contains("/struct/"): continue
			if rect.encloses(_sprite_rect(e)): details.append(e)
		details.sort_custom(func(a, b):
			if (int(a.type) == 0) != (int(b.type) == 0): return int(a.type) == 0
			return int(a.y) < int(b.y))
		for e in details:
			consumed[e] = true
			var img := _image(str(frame_data(int(e.seq), int(e.frame)).path))
			var at := _sprite_rect(e).position - rect.position
			canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(at))
		# The original's shadow: the isolated black dither pixels, which lie on the ground
		# in this projection. Paint them into the ground at 50% like the engine's blend.
		var shade := Image.create(canvas.get_width(), canvas.get_height(), false, Image.FORMAT_RGBA8)
		for y in canvas.get_height():
			for x in canvas.get_width():
				if _is_dither(canvas, x, y): shade.set_pixel(x, y, Color(0,0,0,0.5))
		ground.blend_rect(shade, Rect2i(Vector2i.ZERO, shade.get_size()), Vector2i(int(rect.position.x) - 20, int(rect.position.y)))
		_add_house(facades[str(d.path)], _fill_holes(canvas), g - Vector2(float(d.dx), float(d.dy)))
	return consumed

func _is_dither(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	if c.a < 0.5 or c.r + c.g + c.b >= 0.04: return false
	for q in [Vector2i(x+1,y), Vector2i(x-1,y), Vector2i(x,y+1), Vector2i(x,y-1)]:
		if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height(): continue
		var nb := img.get_pixel(q.x, q.y)
		if nb.a >= 0.5 and nb.r + nb.g + nb.b < 0.04: return false
	return true

# Where the fitted geometry reaches past the drawn silhouette, extend the nearest drawn
# pixels outward instead of showing holes or shadow dither.
func _fill_holes(src: Image) -> ImageTexture:
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w*h)
	for y in h:
		for x in w:
			solid[y*w+x] = 0 if (img.get_pixel(x,y).a < 0.5 or _is_dither(src,x,y)) else 1
	var changed := true
	while changed:
		changed = false
		var grown := solid.duplicate()
		for y in h:
			for x in w:
				if solid[y*w+x]: continue
				var sum := Color(0,0,0,0)
				var k := 0
				for q in [Vector2i(x+1,y), Vector2i(x-1,y), Vector2i(x,y+1), Vector2i(x,y-1)]:
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or not solid[q.y*w+q.x]: continue
					sum += img.get_pixel(q.x,q.y)
					k += 1
				if k > 0:
					img.set_pixel(x, y, Color(sum.r/k, sum.g/k, sum.b/k, 1.0))
					grown[y*w+x] = 1
					changed = true
		solid = grown
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _add_house(fit: Dictionary, t: ImageTexture, top_left: Vector2) -> void:
	var size := Vector2(t.get_width(), t.get_height())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in fit.faces:
		var c: Array = fit.centers[int(f.block)]
		var centre := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var pts: Array[Vector3] = []
		for p in f.pts: pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for p in pts: mid += p / pts.size()
		if normal.dot(mid - centre) < 0: normal = -normal
		# Sample whichever of this face and its point mirror the original camera saw more
		# squarely: n.view vs (-nx, ny, -nz).view, i.e. faces turned south use their own
		# pixels; north-turned ones (unseen, or seen at a grazing, smeared angle) the mirror.
		var seen_by_camera := normal.z >= 0.0
		var polys: Array = [[pts, INF]] # [polygon, mirror height for the texture]
		if int(f.label) == 1:
			# The eave hid the top of this wall from the original camera (the view ray
			# drops o/|n.z| crossing the overhang); texture that band from the stone
			# just below it, mirrored, instead of from the eave's thatch.
			var y0 := pts[0].y
			var top := pts[2].y
			var band := float(fit.overhangs[int(f.block)]) / maxf(absf(normal.z), 0.3)
			var hs := maxf(top - band, y0 + 0.5*(top - y0))
			var lo: Array[Vector3] = [pts[0], pts[1], Vector3(pts[1].x, hs, pts[1].z), Vector3(pts[0].x, hs, pts[0].z)]
			var hi: Array[Vector3] = [lo[3], lo[2], pts[2], pts[3]]
			polys = [[lo, INF], [hi, hs]]
		for poly in polys:
			var ps: Array[Vector3] = poly[0]
			var mirror: float = poly[1]
			for i in range(1, ps.size()-1):
				for p in [ps[0], ps[i], ps[i+1]]:
					var q: Vector3 = p if seen_by_camera else Vector3(2*centre.x - p.x, p.y, 2*centre.z - p.z)
					if mirror != INF: q.y = 2*mirror - q.y
					st.set_uv(Vector2(q.x, q.z - q.y) / size)
					st.add_vertex(Vector3((top_left.x + p.x)*S, p.y*S, (top_left.y + p.z)*S))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # light is baked into the art
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root3d.add_child(mi)

# The original camera: orthographic, 45 degrees down; the image is then stretched
# sqrt(2) vertically to give (X, Z - Y). Used to check a screen against its source.
func _original_view(out_dir: String, n: int) -> void:
	var o := _origin(n)
	var target := Vector3((o.x+300)*S, 0, (o.y+200)*S)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# The project's canvas_items stretch fixes the 3D viewport size, so keep the width
	# (600 source px) and crop the height to the screen's 400/sqrt(2) oblique rows.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 600*S
	camera.position = target + Vector3(0, 1, 1).normalized()*40.0
	camera.look_at(target, Vector3.UP)
	camera.far = 200
	env_node.environment.fog_enabled = false
	_face_actors()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var rows := int(round(img.get_width() * (400.0/sqrt(2.0)) / 600.0))
	img = img.get_region(Rect2i(0, (img.get_height()-rows)/2, img.get_width(), rows))
	img.resize(600, 400, Image.INTERPOLATE_LANCZOS)
	img.save_png(out_dir.path_join("original-view-%d.png" % n))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	env_node.environment.fog_enabled = true
