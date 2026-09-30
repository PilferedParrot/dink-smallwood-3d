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
var facades: Dictionary # sprite path -> fitted house blocks (tools/facade_fit.py)
var env_node: WorldEnvironment
var kit_members: Dictionary = {} # "screen:t|s:index" -> true: pieces a kit building draws
var kits: Array = [] # the kit buildings (facades._kit_buildings entries) in this block
var ground_shade: Array = [] # [shadow image, world top-left] of houses and kit buildings
var house_parts: Dictionary = {} # "screen:index" -> true: sprites a house draws (itself, its details)
var block: Array = [] # the screens built
var buildings: Array = [] # [footprint (world px), original draw key]: houses and parts buildings
var nudged: Array = [] # [Sprite3D, source position, depth offset (m), pixel size]: see _nudge_billboards
var face_id := false # debug (arg "faceid"): each house face flat in its own colour (sprite_buildings.gd)
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")
var builder # scripts/sprite_buildings.gd: the buildings, shared with the game

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
	builder = BUILDINGS.new(sequences, world, facades, S)
	builder.face_id = face_id
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
	for b in kits: _place(builder.kit(b), builder.kit_prepare(b)[2])
	camera.current = true
	camera.fov = 75
	root3d.add_child(camera)
	_capture(out_dir, center, views, shots_file)

func _origin(n: int) -> Vector2:
	return builder.origin(n)

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
	return builder.tex(path)

func frame_data(seq: int, frame: int) -> Dictionary:
	return builder.frame_data(seq, frame)

func _image(path: String) -> Image:
	return builder.image(path)

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
	# Trees and props (wide trees stand as fixed cards, the rest as billboards); not fences or buildings.
	if not str(d.path).contains("/struct/") and not str(d.path).contains("/Fence/"): _flag_nudge(sp, g, float(t.get_width())/2.0 * maxf(0.01, float(s.size)/100.0))
	root3d.add_child(sp)

func _set_anchor(sp: Sprite3D, d: Dictionary, t: Texture2D) -> void:
	var dx := float(d.get("dx",t.get_width()/2.0))
	var dy := float(d.get("dy",t.get_height()-10.0))
	sp.centered = true
	sp.offset = Vector2(t.get_width()/2.0-dx, dy-t.get_height()/2.0)

# A flat billboard whose canopy overlaps a building is cut by its walls or roof where the plane
# through its trunk passes inside. The original draws a sprite whose hotspot lies below the
# building's over it: such a billboard is moved along the view ray toward the camera by its
# half-width and scaled to keep its size on screen, so it stands clear in front of the building,
# as drawn (251). Its trunk, and any collision, stays where the source put it. One drawn under the
# building cannot be moved away along the ray (its trunk sinks below the ground); its depth is pushed
# away instead, in its shader (_push_back).
func _flag_nudge(sp: Sprite3D, g: Vector2, r: float) -> void:
	for b in buildings:
		var hull: PackedVector2Array = b[0]
		var dist := 0.0
		if not Geometry2D.is_point_in_polygon(g, hull):
			dist = INF
			for i in hull.size():
				dist = minf(dist, g.distance_to(Geometry2D.get_closest_point_to_segment(g, hull[i], hull[(i+1) % hull.size()])))
		if dist < r:
			if g.y > float(b[1]): nudged.append([sp, sp.position, r * S, sp.pixel_size])
			else: _push_back(sp, r * S)
			return

# A sprite the original draws under a building its canopy overlaps: drawn where it stands, but its
# depth pushed away from the camera by its half-width, so the building hides the canopy as the
# original does (497). Each fragment's push is capped at 0.9 of its clearance above the ground along
# the view ray, so the trunk's foot never goes under the ground (which moving the sprite did).
# Compatibility renderer: window depth = NDC z * 0.5 + 0.5. Env PUSH_ZERO: every push 0 (a control:
# the images must equal the plain sprites').
var push_shader: Shader
func _push_back(sp: Sprite3D, off: float) -> void:
	if push_shader == null:
		push_shader = Shader.new()
		push_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_nearest_mipmap;
uniform float off = 0.0;
uniform bool bill = true;
void vertex() {
	if (bill) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb;
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dw = ortho ? -INV_VIEW_MATRIX[2].xyz : normalize(wp - INV_VIEW_MATRIX[3].xyz);
	float room = -dw.y > 1e-4 ? 0.9 * max(wp.y, 0.0) / -dw.y : off;
	vec3 dv = ortho ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + dv * min(off, room), 1.0);
	DEPTH = clip.z / clip.w * 0.5 + 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = push_shader
	m.set_shader_parameter("tex", sp.texture)
	m.set_shader_parameter("off", 0.0 if OS.has_environment("PUSH_ZERO") else off)
	m.set_shader_parameter("bill", sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	sp.material_override = m

func _nudge_billboards() -> void:
	for n in nudged:
		var sp: Sprite3D = n[0]
		var a: Vector3 = n[1]
		var off: float = n[2]
		if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			sp.position = a + camera.global_transform.basis.z * off
			sp.pixel_size = n[3]
		else:
			var to_cam := camera.global_position - a
			var d := to_cam.length()
			sp.position = a + to_cam / d * off
			sp.pixel_size = n[3] * (d - off) / d

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
		if sp.material_override is ShaderMaterial: (sp.material_override as ShaderMaterial).set_shader_parameter("tex", t)
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
	_nudge_billboards()

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

# --- Buildings (DIRECTION.md "Buildings" and the passes after it) -------------------------
# The houses, the cabin, the church and the kit buildings are built by scripts/sprite_buildings.gd,
# which the game uses too; this prototype gathers them over its 5x5 block and places them.

# Every house in the block, before any screen adds its sprites: a house near a screen edge
# is placed on both screens, and its details (a chimney, a door) may be on either, so they
# are gathered from every screen in world coordinates (world = screen origin + (x - 20, y)).
func _build_houses() -> void:
	var candidates: Array = [] # [sprite, screen, "screen:index"], vision 0, in block order
	for n in block:
		var list: Array = world.screens[str(n)].sprites
		for idx in list.size():
			var s: Dictionary = list[idx]
			if int(s.get("vision",0)) == 0 and int(s.type) != 2: candidates.append([s, n, "%d:%d" % [n, idx]])
	var built := {}
	for c in candidates:
		var s: Dictionary = c[0]
		if not builder.is_fitted(s): continue
		house_parts[c[2]] = true
		var d := frame_data(int(s.seq), int(s.frame))
		var rect: Rect2 = builder.world_rect(s, int(c[1]))
		var key := "house:%s:%d:%d" % [d.path, int(rect.position.x), int(rect.position.y)]
		if built.has(key): continue
		built[key] = true
		var parts: Dictionary = builder.gather(facades[str(d.path)], rect, candidates, house_parts)
		var h: Dictionary = builder.house(str(d.path), rect, parts)
		if (h.hull as PackedVector2Array).size() >= 3: buildings.append([h.hull, rect.position.y + float(d.dy)])
		ground_shade.append([h.shade, rect.position])
		_place(h.node, rect.position)

func _place(node: Node3D, top_left: Vector2) -> void:
	node.position = Vector3(top_left.x*S, 0, top_left.y*S)
	root3d.add_child(node)

# A kit building with a piece in the block: its pieces leave the screens (kit_members), and its
# drawn shadow goes on the ground.
func _prepare_kit(b: Dictionary) -> void:
	var k: Array = builder.kit_prepare(b)
	kit_members.merge(k[3])
	ground_shade.append([builder.shade(k[0]), k[2]])
	kits.append(b)

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
	_nudge_billboards()
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
