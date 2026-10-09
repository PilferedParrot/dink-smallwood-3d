extends RefCounted
# Bridge railings stand; decks lie on the water and take rays (docs/DIRECTION.md, October 2, M3 unit U1).
#
# The art draws a bridge's rope railings inside its deck's own sprite (brdge-06, 08, 10: the far railing above the
# planks; brdge-01..03: the side rails of the north-south deck) or as a sprite of their own (brdge-04, 07, 09, 11: the
# near railing). In the original's projection a point at height Y over the ground point (x, z) is drawn at (x, z - Y), so
# a railing that stands on a line is exactly the art's pixels above that line. tools/bridge_split.py finds the line, the
# posts and the rail's pixels in the art (prototype/bridges.json: the reading is its docstring); this builds them:
#   "ew"   the far railing: a card standing on the line the posts' feet lie on (the deck is drawn a little turned, so
#          the line is not level: each column's pixels are taken from its own base, so the card is a vertical plane
#          along the line and its picture is the art's above it), its posts as prisms. The planks stay in the ground.
#   "near" the near railing, as the far one: a card standing on the line its posts' feet lie on (not at its hotspot,
#          which the artist put anywhere: 11's is 23 px above its feet), its posts as prisms (a card is a sliver from
#          its own axis).
# A prism is as deep as it is wide, behind its front face (which is in the card's plane). The original draws a top face that
# deep as that many rows above its front edge, so the art's post is the prism's front face under its top `wide` rows as
# the top face: the prism stands `wide` px lower than the picture and projects, from the original camera, to the art's
# own pixels. Its other faces sample the post's own edge columns.
# The railing is cut from the art as it is (world.sprite_image), not from the card texture that drops isolated black pixels
# as shadow dither: a rope's outline has such pixels.
# North-south sections use ns_bridge_rails.gd: deck-bounded spans, terminal
# supports reconstructed from 01, shared joins including screen-edge copies, and
# source-projected textures borrowed across adjacent sections. 02's tail stays grounded.
# Every deck also takes a thin body on the ray layer (the layer arrows and rays use; as the houses' ray_body), where
# its planks are: walking is unchanged (it is the source's hardness, game.gd).
const SCALE := 0.025
const MIN_POST := 3.0 # px: a post cut by its sprite's edge is at least this wide
const PLATE := 0.05 # m: the deck's ray plate
const NS_RAILS := preload("res://scripts/ns_bridge_rails.gd")

var world # fp_world.gd
var data: Dictionary = {}
var plank_cache: Dictionary = {} # path:tag:size -> the deck's planks (Image): "ground" as painted, "plate" for the ray body
var mesh_cache: Dictionary = {} # path -> [[Mesh, texture], ...] built once per art
var plate_cache: Dictionary = {} # path -> the ray plate's hull points (PackedVector3Array)
var raw_cache: Dictionary = {} # path -> the art as it is, with mipmaps (ImageTexture)
var material_cache: Dictionary = {}
var ns_rails

func setup(fp_world) -> void:
	world = fp_world
	var path := "res://prototype/bridges.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	data = parsed if parsed is Dictionary else {}
	ns_rails = NS_RAILS.new(self)

func entry(path: String) -> Dictionary:
	var e: Variant = data.get(path, {})
	return e if e is Dictionary else {}

# Whether the art has a railing to stand (a deck with its own railing, or a near railing).
func has(path: String) -> bool:
	return not entry(path).is_empty()

func _grid(runs: Array, w: int, h: int) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(w*h)
	for r in runs:
		var y := int(r[0])
		if y < 0 or y >= h: continue
		for x in range(maxi(int(r[1]),0),mini(int(r[2]),w-1)+1): grid[y*w+x] = 1
	return grid

# --- the planks ---------------------------------------------------------------------------------------------
# A deck's sprite as painted into the ground: without the railing that stands now (the railing's pixels are above the
# planks, so nothing is left to fill). A deck with no entry (the north-south decks, the stone bridge) is painted whole.
func plank_image(path: String, source: Image) -> Image:
	return _planks(path,source,"ground")

func _planks(path: String, source: Image, tag: String) -> Image:
	var e := entry(path)
	if e.is_empty() or str(e.kind) == "near": return source
	if str(e.kind) == "ns" and tag == "plate": return source # retain the original ray footprint
	var key := path+":"+tag+":"+str(source.get_width())+"x"+str(source.get_height())
	if plank_cache.has(key): return plank_cache[key]
	var w := source.get_width()
	var h := source.get_height()
	var image: Image = source.duplicate()
	var grid := _grid(e.card,w,h)
	for y in h:
		for x in w:
			if grid[y*w+x] != 1: continue
			var fill := Color.TRANSPARENT
			if str(e.kind) == "ns" and y >= int(e.planks[2]) and y < int(e.planks[3]):
				# Only the narrow side strips are inpainted. Copy the nearest uncovered
				# opaque pixel on this same plank row, including its dark seam.
				for radius in w:
					for nx in [x-radius,x+radius]:
						if nx < 0 or nx >= w or grid[y*w+nx] == 1: continue
						var color := source.get_pixel(nx,y)
						if color.a >= 0.5:
							fill = color
							break
					if fill.a >= 0.5: break
			image.set_pixel(x,y,fill)
	plank_cache[key] = image
	return image

# --- a deck's railing and ray plate -------------------------------------------------------------------------
func add_deck(node: Node3D, e: Dictionary, id: int, collision: bool, screen: int = -1) -> void:
	var path: String = world.frame_path(e)
	var df: Vector2i = world.display_frame(e)
	var d: Dictionary = world.host._frame(df.x,df.y)
	if has(path) and str(entry(path).kind) == "ns": ns_rails.add(node,e,d,screen)
	elif has(path) and str(entry(path).kind) != "near": _add_rail(node,path,d)
	if collision: node.add_child(_plate(path,d,id))

# The railing's meshes (built once per art) as a "Rail" child of the sprite's node.
func _add_rail(node: Node3D, path: String, d: Dictionary) -> void:
	if not mesh_cache.has(path): mesh_cache[path] = _deck_meshes(path,entry(path),d)
	var rail := Node3D.new()
	rail.name = "Rail"
	node.add_child(rail)
	for pair in mesh_cache[path]:
		var instance := MeshInstance3D.new()
		instance.name = str(pair[2])
		instance.mesh = pair[0]
		instance.material_override = _material(pair[1])
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		rail.add_child(instance)

func _with_mipmaps(image: Image) -> Image:
	var copy: Image = image.duplicate()
	copy.generate_mipmaps()
	return copy

func _material(texture: Texture2D) -> StandardMaterial3D:
	var key := texture.get_rid().get_id()
	if material_cache.has(key): return material_cache[key]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.albedo_texture = texture
	material_cache[key] = material
	return material

# The railing is cut from the art as it is (the sprite the ground is painted from), not from the cleaned card texture:
# the cleaning takes isolated pure-black pixels for shadow dither, and a rope's outline has such pixels.
func _deck_meshes(path: String, info: Dictionary, d: Dictionary) -> Array:
	var image: Image = world.sprite_image(path)
	if image == null: return []
	var sprite := ImageTexture.create_from_image(_with_mipmaps(image))
	var kind := str(info.kind)
	var out: Array = []
	var dx := float(d.get("dx",0))
	var dy := float(d.get("dy",0))
	if kind == "ew" or kind == "near":
		var card = _ew_card(info,image,dx,dy)
		if card != null: out.append(card)
	var posts = _posts_mesh(info,sprite,dx,dy,kind)
	if posts != null: out.append([posts,sprite,"Posts"])
	return out

# The picture of a standing card: the art's pixels `mask` selects, with each column's pixels counted up from its
# own base row, so a card on a line that is not level has a level picture.
func _ew_card(info: Dictionary, image: Image, dx: float, dy: float) -> Variant:
	var w := image.get_width()
	var h := image.get_height()
	var a := float(info.line[0])
	var s := float(info.line[1])
	var base := PackedInt32Array()
	for x in w: base.append(int(roundf(a+s*(float(x)+0.5))))
	var in_post := _post_grid(info.posts,w,h)
	# The card is as tall as its highest pixel stands over the line (the posts are their own prisms).
	var tall := 1
	for r in info.card:
		var y := int(r[0])
		for x in range(int(r[1]),int(r[2])+1):
			if in_post[y*w+x] == 0: tall = maxi(tall,base[x]-y)
	var picture := Image.create(w,tall,false,Image.FORMAT_RGBA8)
	for r in info.card:
		var y := int(r[0])
		for x in range(int(r[1]),int(r[2])+1):
			if in_post[y*w+x] == 1: continue
			var ty := y-base[x]+tall
			if ty >= 0 and ty < tall: picture.set_pixel(x,ty,image.get_pixel(x,y))
	picture.generate_mipmaps()
	var texture := ImageTexture.create_from_image(picture)
	var mesh := ArrayMesh.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := (a-dy)*SCALE
	var z1 := (a+s*float(w)-dy)*SCALE
	var left := -dx*SCALE
	var right := (float(w)-dx)*SCALE
	var top := float(tall)*SCALE
	# Corners: bottom-left, bottom-right, top-right, top-left of the vertical plane along the line.
	_quad(tool,Vector3(left,0,z0),Vector3(right,0,z1),Vector3(right,top,z1),Vector3(left,top,z0),Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0))
	tool.commit(mesh)
	return [mesh,texture,"Rope"]

func _post_grid(posts: Array, w: int, h: int) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(w*h)
	for p in posts:
		for y in range(maxi(int(p[2]),0),mini(int(p[3]),h-1)+1):
			for x in range(maxi(int(p[0]),0),mini(int(p[1]),w-1)+1): grid[y*w+x] = 1
	return grid

func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for pair in [[a,ua],[b,ub],[c,uc],[a,ua],[c,uc],[d,ud]]:
		tool.set_uv(pair[1])
		tool.add_vertex(pair[0])

# The posts as prisms standing where the art draws them: as wide as they are drawn and as deep. `kind` says where the
# post's foot is: on the railing's line.
func _posts_mesh(info: Dictionary, sprite: Texture2D, dx: float, dy: float, kind: String) -> Variant:
	var posts: Array = info.get("posts",[])
	if posts.is_empty(): return null
	var w := float(sprite.get_width())
	var h := float(sprite.get_height())
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := 0.0
	var s := 0.0
	if kind == "ew" or kind == "near":
		a = float(info.line[0])
		s = float(info.line[1])
	for p in posts:
		var x0 := float(p[0])
		var x1 := float(p[1])+1.0
		var y0 := float(p[2])
		var y1 := float(p[3])+1.0
		var wide := maxf(x1-x0,MIN_POST)
		var xc := (x0+x1)*0.5
		var foot_z := 0.0 # the depth of the post's front face, from the hotspot
		var y_bottom := 0.0
		var y_top := 0.0
		if kind == "ew" or kind == "near":
			foot_z = (a+s*xc-dy)*SCALE
			y_top = (a+s*xc-y0-wide)*SCALE # the line's row less the post's top row, less the top face's rows (below)
		var along := Vector3(1,0,s).normalized()
		var toward := Vector3(-s,0,1).normalized()
		var centre := Vector3((xc-dx)*SCALE,0,foot_z)
		var half := along*(wide*0.5*SCALE)
		var back := -toward*(wide*SCALE)
		var fl := centre-half
		var fr := centre+half
		var bl := fl+back
		var br := fr+back
		var lo := Vector3(0,y_bottom,0)
		var hi := Vector3(0,y_top,0)
		# The prism is `wide` deep, behind its front face. In the original's projection a top face `wide` deep is drawn as
		# `wide` rows above its front edge, so the art's top `wide` rows are the top face and the rows under them the front:
		# the prism stands `wide` px lower than the art's post is tall and projects to the same pixels. Front: the post's own
		# pixels from row y0+wide. Sides: its edge columns stretched. Back: as the front. Top: the rows above, front edge down.
		var yf := minf(y0+wide,y1-1.0)
		var uf0 := Vector2(x0/w,(y1)/h)
		var uf1 := Vector2(x1/w,(y1)/h)
		var uf2 := Vector2(x1/w,yf/h)
		var uf3 := Vector2(x0/w,yf/h)
		_quad(tool,fl+lo,fr+lo,fr+hi,fl+hi,uf0,uf1,uf2,uf3)
		_quad(tool,br+lo,bl+lo,bl+hi,br+hi,uf0,uf1,uf2,uf3)
		var ul := Vector2(x0/w,y1/h)
		_quad(tool,bl+lo,fl+lo,fl+hi,bl+hi,ul,Vector2((x0+1.0)/w,y1/h),Vector2((x0+1.0)/w,yf/h),Vector2(x0/w,yf/h))
		_quad(tool,fr+lo,br+lo,br+hi,fr+hi,Vector2((x1-1.0)/w,y1/h),Vector2(x1/w,y1/h),Vector2(x1/w,yf/h),Vector2((x1-1.0)/w,yf/h))
		_quad(tool,fl+hi,fr+hi,br+hi,bl+hi,Vector2(x0/w,yf/h),Vector2(x1/w,yf/h),Vector2(x1/w,y0/h),Vector2(x0/w,y0/h))
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	return mesh

# A near railing: a card on the line its posts' feet lie on, its posts prisms, and the body on the source's hardbox it
# always had (rays; walking is the source's hardness, game.gd).
func add_near(node: Node3D, e: Dictionary, id: int, collision: bool) -> void:
	var path: String = world.frame_path(e)
	var df: Vector2i = world.display_frame(e)
	var d: Dictionary = world.host._frame(df.x,df.y)
	if world.clean_texture(path) == null: return
	_add_rail(node,path,d)
	var factor := maxf(0.01,float(e.get("size",100))/100.0)
	var height := maxf(0.2,world.sprite_height(e)*SCALE*factor)
	node.set_meta("height",height)
	if not collision or e.get("warp") != null: return
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 2 if not str(e.get("script","")).is_empty() else 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var rect: Rect2 = world.hard_rect(e)
	box.size = Vector3(maxf(0.2,rect.size.x*SCALE),height,maxf(0.2,rect.size.y*SCALE))
	shape.position = world.point(rect.get_center().x,rect.get_center().y)-node.position
	shape.position.y = height*0.5
	shape.shape = box
	body.add_child(shape)
	node.add_child(body)

# --- the ray plate -------------------------------------------------------------------------------------------
# A thin static body where the deck's planks are, on the layer rays use (collision_layer 1, no mask: as ray_body),
# so a downward ray hits the deck. The footprint is the convex hull of the planks' rows' ends (without the shadow dither).
func _plate(path: String, d: Dictionary, id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 1
	body.collision_mask = 0
	var points := _plate_points(path,d)
	if points.size() < 4: return body
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)
	return body

# A pixel of wooden planks: warm brown (the rule bridge_split.py reads the planks by).
func _warm(c: Color) -> bool:
	return c.a >= 0.5 and (c.r-c.g)*255.0 >= 24.0 and (c.g-c.b)*255.0 >= 10.0

# The hull's points: the rows' ends of the planks the shadow dither is cleaned from (clean_texture), once per art. A deck
# with no entry that is mostly wood (the north-south decks, painted whole) takes only its plank rows (rows that are at least
# 40 percent warm brown across the sprite) and their wooden pixels: its end posts above the planks (brdge-01's are brown
# too) and the rope's tail past them are not deck. The stone bridge is not wood, so all its opaque pixels count.
func _plate_points(path: String, d: Dictionary) -> PackedVector3Array:
	if plate_cache.has(path): return plate_cache[path]
	var points := PackedVector3Array()
	var texture: Texture2D = world.clean_texture(path)
	if texture == null: return points
	var image := _planks(path,texture.get_image(),"plate")
	var wood_only := false
	if not has(path) or str(entry(path).get("kind","")) == "ns":
		var wood := 0
		var opaque := 0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x,y)
				if c.a >= 0.5: opaque += 1
				if _warm(c): wood += 1
		wood_only = opaque > 0 and float(wood) >= 0.4*float(opaque)
	var dx := float(d.get("dx",0))
	var dy := float(d.get("dy",0))
	for y in image.get_height():
		var lo := -1
		var hi := -1
		var warm_count := 0
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			if _warm(c): warm_count += 1
			if (_warm(c) if wood_only else c.a > 0.5):
				if lo < 0: lo = x
				hi = x
		if lo < 0 or (wood_only and float(warm_count) < 0.4*float(image.get_width())): continue
		for yy in [float(y),float(y)+1.0]:
			for xx in [float(lo),float(hi)+1.0]:
				points.append(Vector3((xx-dx)*SCALE,0,(yy-dy)*SCALE))
				points.append(Vector3((xx-dx)*SCALE,PLATE,(yy-dy)*SCALE))
	plate_cache[path] = points
	return points
