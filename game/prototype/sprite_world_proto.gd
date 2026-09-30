extends SceneTree
# Direction prototype (docs/DIRECTION.md): the original map rebuilt from original
# pixels only. Ground = original tiles plus type-0 background sprites composited
# as the original engine does; type-1 sprites stand upright at their source
# positions; actors pick their original directional frame from the camera angle.
# Run: godot --path game -s res://prototype/sprite_world_proto.gd -- <out_dir> [center_screen]
#      [screens to render through the original camera...] [shots.json] [faceid]
# shots.json replaces the default eye-level shots: [[name, [x, y], [look x, look y]], ...] in
# world source pixels (world = screen origin + (x - 20, y)).

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
var kit_members: Dictionary = {} # "screen:t|s:index" -> true: pieces a kit building draws
var kits: Array = [] # [fit, canvas, world top-left] of the kit buildings in this block
var ground_shade: Array = [] # [shadow image, world top-left] of houses and kit buildings
var house_parts: Dictionary = {} # "screen:index" -> true: sprites a house draws (itself, its details)
var block: Array = [] # the screens built
var face_id := false # debug (arg "faceid"): each house face flat in its own colour, see _add_house

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://proto"
	var center := int(args[1]) if args.size() > 1 else 407
	# Optional: the screens to render through the original camera (default as before).
	var views: Array = []
	var shots_file := ""
	for a in args.slice(2):
		if str(a) == "faceid": face_id = true
		elif str(a).ends_with(".json"): shots_file = a
		else: views.append(int(a))
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
				block.append(n)
	for b in facades.get("_kit_buildings", []):
		if (b.screens as Array).any(func(m): return block.has(int(m))): _prepare_kit(b)
	_build_houses()
	for n in block:
		_build_screen(n, seen)
	for k in kits:
		_add_house(k[0], _fill_holes(k[1]), k[2], _fill_holes(k[3]))
		for dm in k[0].get("dormers", []): _add_dormer(dm, k[2])
	camera.current = true
	camera.fov = 75
	root3d.add_child(camera)
	_capture(out_dir, center, views, shots_file)

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
		var index := _ground_tile(n, screen.tiles, i)
		var sheet := _image("assets/tiles/ts%02d.png" % (int(index/128)+1))
		var cell := index%128
		if sheet: ground.blit_rect(sheet,Rect2i((cell%12)*50,int(cell/12)*50,50,50),Vector2i((i%12)*50,int(i/12)*50))
	var o := _origin(n)
	for k in ground_shade:
		ground.blend_rect(k[0], Rect2i(Vector2i.ZERO, k[0].get_size()), Vector2i(k[1] - o))
	var upright := {}
	# Story state is not simulated here: show the editor's default layer (vision 0),
	# like the original-source reference images. Pieces of a kit building are drawn by it.
	var sprites: Array = []
	for i in screen.sprites.size():
		var sp: Dictionary = screen.sprites[i]
		if int(sp.get("vision",0)) == 0 and not kit_members.has("%d:s:%d" % [n, i]) and not house_parts.has("%d:%d" % [n, i]):
			sprites.append(sp)
	for s in sprites:
		if int(s.type) == 1: upright["%d:%d:%d:%d" % [int(s.seq),int(s.frame),int(s.x),int(s.y)]] = true
	for s in sprites:
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

func _capture(out_dir: String, center: int, views: Array, shots_file: String) -> void:
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
		["cottage-east", Vector2(640,560), Vector2(280,600)],
		["inn-southwest", Vector2(900,1900), Vector2(1500,1500)],
		["inn-south", Vector2(1723,2150), Vector2(1723,1500)],
		["inn-door", Vector2(1250,1700), Vector2(1400,1480)],
		["inn-east", Vector2(2500,1650), Vector2(1900,1450)],
		["inn-north", Vector2(1500,900), Vector2(1700,1400)],
		["inn-northeast", Vector2(2250,1050), Vector2(1700,1450)],
		["kit538-southwest", Vector2(1900,2300), Vector2(2250,1950)],
	]
	var world_shots := shots_file != ""
	if world_shots:
		shots = []
		for sh in JSON.parse_string(FileAccess.get_file_as_string(shots_file)):
			shots.append([sh[0], Vector2(sh[1][0], sh[1][1]), Vector2(sh[2][0], sh[2][1])])
	await process_frame
	for shot in shots:
		if world_shots:
			# _shot takes the centre screen's source coordinates.
			var local := _origin(center) - Vector2(20, 0)
			_shot(shot[1] - local, shot[2] - local, center)
		else:
			var shift := _origin(407) - _origin(center)
			_shot(shot[1] + shift, shot[2] + shift, center)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out_dir.path_join(str(shot[0])+".png"))
	if views.is_empty(): views = [407, 439, 440, 469, 470] if center != 407 else [center]
	for n in views:
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

# Every house in the block, before any screen adds its sprites: a house near a screen edge
# is placed on both screens, and its details (a chimney, a door) may be on either, so they
# are gathered from every screen in world coordinates (world = screen origin + (x - 20, y)).
func _build_houses() -> void:
	var built := {}
	for n in block:
		var list: Array = world.screens[str(n)].sprites
		for idx in list.size():
			var s: Dictionary = list[idx]
			var d := frame_data(int(s.seq), int(s.frame))
			if int(s.get("vision",0)) != 0 or d.is_empty() or not facades.has(str(d.path)) or int(s.type) == 2: continue
			house_parts["%d:%d" % [n, idx]] = true
			var rect := _world_rect(s, n)
			var key := "house:%s:%d:%d" % [d.path, int(rect.position.x), int(rect.position.y)]
			if built.has(key): continue
			built[key] = true
			_build_house(s, d, rect)

func _world_rect(s: Dictionary, n: int) -> Rect2:
	var r := _sprite_rect(s)
	r.position += _origin(n) - Vector2(20, 0)
	return r

func _build_house(s: Dictionary, d: Dictionary, rect: Rect2) -> void:
	var canvas := _image(str(d.path))
	var fit: Dictionary = facades[str(d.path)]
	# Details drawn over the house in the original, in its draw order (type 0 first).
	# A detail whose foot the view ray finds on the roof stands on the roof (a chimney).
	var details: Array = [] # [sprite, world rect, world hotspot y]
	var roof_pieces: Array = [] # [sprite, fit, house-local position, height of its foot]
	var ground_pieces: Array = [] # [sprite, reading, world top-left]: chimneys standing beside the house
	var pieces_seen := {}
	for m in block:
		var list: Array = world.screens[str(m)].sprites
		for i in list.size():
			var e: Dictionary = list[i]
			if int(e.get("vision",0)) != 0 or int(e.type) == 2 or house_parts.has("%d:%d" % [m, i]): continue
			var ed := frame_data(int(e.seq), int(e.frame))
			if ed.is_empty() or facades.has(str(ed.path)) or not str(ed.path).contains("/struct/"): continue
			var er := _world_rect(e, m)
			if not rect.intersects(er): continue
			var at := er.position - rect.position
			var rp: Dictionary = facades.get("_roof_pieces", {}).get(str(ed.path), {})
			if rp.has("base"): # a chimney standing on the ground beside the house (home-13)
				house_parts["%d:%d" % [m, i]] = true
				var gk := "%s:%d:%d" % [ed.path, int(er.position.x), int(er.position.y)]
				if not pieces_seen.has(gk): ground_pieces.append([e, rp, er.position])
				pieces_seen[gk] = true
				continue
			if not rp.is_empty():
				var hit := _ray_hit(fit, at.x + float(rp.foot[0]), at.y + float(rp.foot[1]))
				if not hit.is_empty() and int(hit[1]) == 2:
					house_parts["%d:%d" % [m, i]] = true
					var pk := "%s:%d:%d" % [ed.path, int(er.position.x), int(er.position.y)]
					if not pieces_seen.has(pk): roof_pieces.append([e, rp, at, float(hit[0])])
					pieces_seen[pk] = true
					continue
			if rect.encloses(er):
				house_parts["%d:%d" % [m, i]] = true
				details.append([e, er, er.position.y + float(ed.dy)])
	details.sort_custom(func(a, b):
		if (int(a[0].type) == 0) != (int(b[0].type) == 0): return int(a[0].type) == 0
		return a[2] < b[2])
	# The back, which the original camera never saw, mirrors the front without its doors.
	var back: Image = canvas.duplicate()
	var doors := {}
	for q in facades.get("_kit", {}).get("doors", []): doors[str(q)] = true
	for dt in details:
		var path := str(frame_data(int(dt[0].seq), int(dt[0].frame)).path)
		var img := _image(path)
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(dt[1].position - rect.position))
		if not doors.has(path):
			back.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(dt[1].position - rect.position))
	for r in roof_pieces: _paint_roof_piece_foot(canvas, r, fit, back)
	# The original's shadow: the isolated black dither pixels, which lie on the ground
	# in this projection. Painted into the ground at 50% like the engine's blend.
	ground_shade.append([_shade(canvas, _dither_mask(canvas)), rect.position])
	if fit.has("polys"): _add_uv_house(fit, canvas, rect.position, back)
	else: _add_house(fit, _fill_holes(canvas), rect.position, _fill_holes(back))
	for r in roof_pieces: _add_roof_piece(r, fit, rect.position)
	for g in ground_pieces: _add_ground_piece(g)

func _dither_mask(img: Image) -> PackedByteArray:
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

func _shade(img: Image, dither: PackedByteArray) -> Image:
	var shade := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for p in dither.size():
		if dither[p]: shade.set_pixel(p % img.get_width(), p / img.get_width(), Color(0,0,0,0.5))
	return shade

# Where the fitted geometry reaches past the drawn silhouette, extend the nearest drawn
# pixels outward instead of showing holes or shadow dither (breadth-first, so each hole
# takes the colour of the nearest drawn pixel).
func _fill_holes(src: Image) -> ImageTexture:
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var dither := _dither_mask(src)
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

# `back`, if given, textures the faces the original camera never saw (see _prepare_kit).
func _add_house(fit: Dictionary, t: ImageTexture, top_left: Vector2, back: ImageTexture = null) -> void:
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
			var fp := _pts(f)
			for i in range(1, fp.size()-1):
				for q in [fp[0], fp[i], fp[i+1]]: fst.add_vertex(Vector3((top_left.x + q.x)*S, q.y*S, (top_left.y + q.z)*S))
			var fm := MeshInstance3D.new()
			fm.mesh = fst.commit()
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = Color8(8*(fi+1), 60*int(f.block), 255)
			fm.material_override = mat
			root3d.add_child(fm)
			continue
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
					out.add_vertex(Vector3((top_left.x + p.x)*S, p.y*S, (top_left.y + p.z)*S))
	_add_mesh(st.commit(), t)
	if n_back > 0: _add_mesh(st_back.commit(), back)

# A building described by parts (tools/facade_fit.py, "General buildings": the cabin, the
# church): every face carries its texture coordinates, and faces the original camera never saw
# sample the back canvas (no doors). Upright pieces standing in front of the body (a chimney)
# are cleared from the body's texture, which is filled from its own pixels there, so the wall
# behind a chimney does not wear the chimney; the pieces keep the full sprite.
func _add_uv_house(fit: Dictionary, canvas: Image, top_left: Vector2, back: Image) -> void:
	var occ: Array = []
	for poly in fit.get("occluders", []):
		var pv := PackedVector2Array()
		for q in poly: pv.append(Vector2(float(q[0]), float(q[1])))
		occ.append(pv)
	var texs := [_fill_holes(_without(canvas, occ)), _fill_holes(_without(back, occ)), _fill_holes(canvas)]
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
				sts[k].add_vertex(Vector3((top_left.x + float(pts[j][0]))*S, float(pts[j][1])*S, (top_left.y + float(pts[j][2]))*S))
	for k in 3:
		if used[k]: _add_mesh(sts[k].commit(), texs[k])

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

func _add_mesh(mesh: ArrayMesh, t: Texture2D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
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

# --- Roof pieces (the chimneys) ------------------------------------------------------
# A chimney sprite is a picture of an upright prism standing on the roof, taken by the same
# camera. tools/facade_fit.py reads its top face (the footprint, as a horizontal face
# projects to itself) and its foot, the lowest stone pixel under its front edge. The view
# ray through the foot meets the house's roof where the chimney stands; that fixes its
# depth, and the top face fixes its height. Its thatch ring and dithered shadow lie on the
# roof, so they are painted onto the roof texture (the shadow at the engine's 50%).

# The nearest face of a fitted house hit by the view ray through house-local screen point
# (x, y); points on that ray are (x, Y, y + Y). Returns [Y, label] or [] if it misses.
func _ray_hit(fit: Dictionary, x: float, y: float) -> Array:
	var best := []
	for f in fit.faces:
		var pts := _pts(f)
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		var den := n.y + n.z
		if absf(den) < 1e-6: continue
		var yy := (n.dot(pts[0]) - n.x*x - n.z*y) / den
		if _inside(pts, n, Vector3(x, yy, y + yy)) and (best.is_empty() or yy > best[0]):
			best = [yy, int(f.label)]
	return best

# Height of the roof above ground point (x, z) in house-local pixels, or NAN.
# As _ray_hit, returning [Y, block, whether the original camera saw the face (normal turned south)].
func _ray_face(fit: Dictionary, x: float, y: float) -> Array:
	var best := []
	for f in fit.faces:
		var pts := _pts(f)
		var n := (pts[1]-pts[0]).cross(pts[2]-pts[0])
		var den := n.y + n.z
		if absf(den) < 1e-6: continue
		var yy := (n.dot(pts[0]) - n.x*x - n.z*y) / den
		if not _inside(pts, n, Vector3(x, yy, y + yy)) or (not best.is_empty() and yy <= best[0]): continue
		var c: Array = fit.centers[int(f.block)]
		var mid := Vector3.ZERO
		for q in pts: mid += q / pts.size()
		if n.dot(mid - Vector3(float(c[0]), float(c[1]), float(c[2]))) < 0: n = -n
		best = [yy, int(f.block), n.z >= 0.0]
	return best

func _roof_height(fit: Dictionary, x: float, z: float) -> float:
	var best := NAN
	for f in fit.faces:
		if int(f.label) != 2: continue
		var pts := _pts(f)
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

func _pts(f: Dictionary) -> Array[Vector3]:
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
	var img := _image(str(frame_data(int(r[0].seq), int(r[0].frame)).path))
	var dither := _dither_mask(img)
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
		var pts := _pts(f)
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
				var col := img.get_pixel(sx, sy)
				if dither[sy*w + sx]: col = Color(0, 0, 0, 0.5)
				if col.a < 0.25: continue
				back.set_pixel(U, V, back.get_pixel(U, V).blend(col))

# A chimney standing on the ground beside a house (tools/facade_fit.py standing_piece): the
# frustum from its foot (on the ground, where the sprite shows it) to its top face (at its height),
# textured by projection like a house; faces the original camera never saw take the point mirror
# about its axis.
func _add_ground_piece(g: Array) -> void:
	var rp: Dictionary = g[1]
	var tl: Vector2 = g[2]
	var img := _image(str(frame_data(int(g[0].seq), int(g[0].frame)).path))
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
				st.add_vertex(Vector3((tl.x + q.x)*S, q.y*S, (tl.y + q.z)*S))
	_add_mesh(st.commit(), _fill_holes(img))

func _add_roof_piece(r: Array, fit: Dictionary, top_left: Vector2) -> void:
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
	var img := _image(str(frame_data(int(r[0].seq), int(r[0].frame)).path))
	for y in img.get_height():
		for x in img.get_width():
			if x < float(rp.top[0][0]) or x > float(rp.top[2][0]) or y > float(rp.foot[1]): img.set_pixel(x, y, Color(0,0,0,0))
	var t := _fill_holes(img)
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
				st.add_vertex(Vector3((top_left.x + p.x)*S, p.y*S, (top_left.y + p.z)*S))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root3d.add_child(mi)

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

func _prepare_kit(b: Dictionary) -> void:
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
			var sheet := _image("assets/tiles/ts%02d.png" % (int(index/128)+1))
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
		canvas.blend_rect(view, Rect2i(0, 0, 600, 400), Vector2i(_origin(n) - top_left))
		back.blend_rect(view_b, Rect2i(0, 0, 600, 400), Vector2i(_origin(n) - top_left))
	kit_members.merge(members)
	_knock_out_background(canvas)
	_knock_out_background(back)
	ground_shade.append([_shade(canvas, _dither_mask(canvas)), top_left])
	kits.append([b, canvas, top_left, back])

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

# The tile to draw on the ground: a kit building's own tiles are pictures of its upper
# storey, so continue the row they interrupt (ground tiles alternate in pairs, so keep the
# column parity), else the column.
func _ground_tile(n: int, tiles: Array, i: int) -> int:
	if not kit_members.has("%d:t:%d" % [n, i]): return int(tiles[i].get("tile", 0))
	var row := int(i / 12)
	var col := i % 12
	for dist in range(2, 12, 2):
		for c in [col - dist, col + dist]:
			var j: int = row*12 + c
			if c >= 0 and c < 12 and j < tiles.size() and not kit_members.has("%d:t:%d" % [n, j]):
				return int(tiles[j].get("tile", 0))
	for dist in range(1, 8):
		for rr in [row - dist, row + dist]:
			var j: int = rr*12 + col
			if rr >= 0 and rr < 8 and j < tiles.size() and not kit_members.has("%d:t:%d" % [n, j]):
				return int(tiles[j].get("tile", 0))
	return int(tiles[i].get("tile", 0))

# --- Dormers ----------------------------------------------------------------------------
# Three kit roof panels have a dormer drawn in. tools/facade_fit.py fits each as a gabled
# prism standing on the roof (its foot found by the view ray, like a chimney's) and lists its
# faces with texture coordinates in the panel's pixels. On the roof, the panel shows its
# plain twin wherever the dormer stood in the original camera's view.

var clean_panels: Dictionary = {}

func _kit_piece(path: String) -> Image:
	var dp: Dictionary = facades.get("_dormer_panels", {}).get(path, {})
	if dp.is_empty(): return _image(path)
	if clean_panels.has(path): return clean_panels[path]
	var img: Image = _image(path).duplicate()
	var twin := _image(str(dp.twin))
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

func _add_dormer(dm: Dictionary, top_left: Vector2) -> void:
	var img: Image = _image(str(dm.path)).duplicate()
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
				st.add_vertex(Vector3((top_left.x + float(pts[k][0]))*S, float(pts[k][1])*S, (top_left.y + float(pts[k][2]))*S))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root3d.add_child(mi)
