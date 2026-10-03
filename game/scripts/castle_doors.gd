# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# The two placed castle doors use the wall geometry that carries their picture. Source pixels are projected by
# the original camera as (x, z - height): putting each pixel back on its surface preserves that camera's picture.
extends RefCounted

const PANEL := "assets/graphics/struct/Castle/cdoor-01.png"
const BRIDGE := "assets/graphics/struct/Castle/cdoor-06.png"
const FACE_CLEARANCE := 0.5 # source px = 1.25 cm, in front of the wall to avoid z-fighting
const GROUND_CLEARANCE := 0.4 # source px = 1 cm, above the ground
const LEFT_CHAIN := [Vector2(0,60), Vector2(76,177)]
const RIGHT_CHAIN := [Vector2(48,19), Vector2(124,147)]

var fw
var split_cache: Dictionary = {}

func _init(world) -> void:
	fw = world

func has(path: String) -> bool:
	return path == PANEL or path == BRIDGE

# The nearest visible castle face under the door's drawn foot. For a block, the fitted polygon's winding says
# which edges face the original viewer. A wall's front face is its fitted base line. All positions are world px.
func _face(screen: int, e: Dictionary, d: Dictionary, anchor: Vector2) -> Dictionary:
	var target: Vector2 = fw.screen_origin(screen) + Vector2(float(e.get("x", 0)) - float(d.get("dx", 0)), float(e.get("y", 0)) - float(d.get("dy", 0))) + anchor
	var best := {}
	var best_score := INF
	for piece in fw.castle_pieces():
		var fit: Dictionary = fw.buildings.castle_fit(str(piece[1]))
		if fit.is_empty(): continue
		var at: Vector2 = piece[2]
		for q in fit.parts:
			var edges: Array = []
			if str(q.type) == "wall":
				var x0 := float(q.x0)
				var x1 := float(q.x1)
				var s := float(q.s)
				var c := float(q.c)
				edges.append([at + Vector2(x0, s*x0+c), at + Vector2(x1, s*x1+c), Vector2(-s, 1.0).normalized()])
			elif str(q.type) == "block":
				var poly: Array = q.poly
				var area := 0.0
				for i in poly.size():
					var p: Array = poly[i]
					var r: Array = poly[(i+1) % poly.size()]
					area += float(p[0])*float(r[1]) - float(r[0])*float(p[1])
				var orient := 1.0 if area > 0.0 else -1.0
				for i in poly.size():
					var p := at + Vector2(float(poly[i][0]), float(poly[i][1]))
					var r := at + Vector2(float(poly[(i+1) % poly.size()][0]), float(poly[(i+1) % poly.size()][1]))
					var delta := r-p
					var normal := Vector2(delta.y, -delta.x).normalized()*orient
					if normal.y > 0.05: edges.append([p,r,normal])
			for edge in edges:
				var a: Vector2 = edge[0]
				var b: Vector2 = edge[1]
				if absf(b.x-a.x) < 0.01 or target.x < minf(a.x,b.x)-2.0 or target.x > maxf(a.x,b.x)+2.0: continue
				var z: float = a.y + (target.x-a.x)*(b.y-a.y)/(b.x-a.x)
				var score := absf(z-target.y)
				if score < best_score:
					best_score = score
					best = {"a": a, "b": b, "normal": edge[2], "piece": str(piece[1]), "distance": score}
	# The source image and fit should meet at the foot. A distant face means this art is elsewhere in the map.
	return best if best_score < 16.0 else {}

func _leaf_top(x: float) -> float:
	if x < 20.0: return 142.0-0.7*x
	if x < 60.0: return 128.0-0.425*(x-20.0)
	return 111.0+0.45*(x-60.0)

func _chain_distance(p: Vector2, path: Array) -> float:
	var distance := INF
	for i in range(path.size()-1):
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1])))
	return distance

# The leaf's outline and the chains' paths are traced in the art's own pixel coordinates (see the U34 split
# overlay), never from a screen or camera. Each chain pixel is pulled from the stone/wood image. Where it used to
# cover either surface, the nearest uncovered pixel of that surface fills the space underneath the 3D links.
func _split(path: String) -> Dictionary:
	if split_cache.has(path): return split_cache[path]
	var texture: Texture2D = fw.clean_texture(path)
	var source := texture.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var images := {}
	var flags := PackedByteArray()
	flags.resize(source.get_width()*source.get_height())
	for name in ["Arch", "Leaf", "ChainLeft", "ChainRight"]:
		var img := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		images[name] = img
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x,y)
			if color.a <= 0.0: continue
			var p := Vector2(x+0.5,y+0.5)
			var part := "Leaf" if p.y >= _leaf_top(p.x) else "Arch"
			if _chain_distance(p, LEFT_CHAIN) <= 7.0: part = "ChainLeft"
			elif _chain_distance(p, RIGHT_CHAIN) <= 9.0: part = "ChainRight"
			if part.begins_with("Chain"): flags[y*source.get_width()+x] = 1 if part == "ChainLeft" else 2
			(images[part] as Image).set_pixel(x,y,color)
	# Inpaint the narrow strips under the links from adjacent original pixels of the same surface. The right
	# suspended chain crosses open air, so there is nothing to fill behind it until it reaches the leaf.
	for y in source.get_height():
		for x in source.get_width():
			if flags[y*source.get_width()+x] == 0: continue
			var base := "Leaf" if float(y)+0.5 >= _leaf_top(float(x)+0.5) else "Arch"
			if base == "Arch" and x > 60: continue
			var line: Array = LEFT_CHAIN if flags[y*source.get_width()+x] == 1 else RIGHT_CHAIN
			var along: Vector2 = (line[1]-line[0]).normalized()
			var across := Vector2(-along.y,along.x)
			var sides: Array = []
			for direction in [-1.0,1.0]:
				var got := []
				for radius in range(1, 21):
					var nx := roundi(float(x)+across.x*float(radius)*direction)
					var ny := roundi(float(y)+across.y*float(radius)*direction)
					if nx < 0 or nx >= source.get_width() or ny < 0 or ny >= source.get_height(): continue
					if flags[ny*source.get_width()+nx] != 0: continue
					if ("Leaf" if float(ny)+0.5 >= _leaf_top(float(nx)+0.5) else "Arch") != base: continue
					var neighbour := source.get_pixel(nx,ny)
					if neighbour.a <= 0.5: continue
					got = [neighbour,float(radius)]
					break
				if not got.is_empty(): sides.append(got)
			if sides.size() == 2:
				var blend := float(sides[0][1])/(float(sides[0][1])+float(sides[1][1]))
				(images[base] as Image).set_pixel(x,y,(sides[0][0] as Color).lerp(sides[1][0],blend))
			elif sides.size() == 1:
				(images[base] as Image).set_pixel(x,y,sides[0][0])
	var result := {}
	for name in images:
		(images[name] as Image).generate_mipmaps()
		result[name] = ImageTexture.create_from_image(images[name])
	split_cache[path] = result
	return result

func _material(texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	return mat

func _surface(model: Node3D, name: String, texture: Texture2D, size: Vector2, position: Callable, uv_shift: Vector2 = Vector2.ZERO) -> void:
	var vertices := [position.call(0.0,0.0), position.call(size.x,0.0), position.call(size.x,size.y), position.call(0.0,size.y)]
	var uvs := [Vector2.ZERO, Vector2(size.x,0), size, Vector2(0,size.y)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0,1,2,0,2,3]:
		st.set_uv((uvs[i]+uv_shift)/size)
		st.add_vertex(vertices[i])
	var part := MeshInstance3D.new()
	part.name = name
	part.mesh = st.commit()
	part.set_surface_override_material(0,_material(texture))
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name == "Leaf" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	model.add_child(part)

func _chain_at(points: Array, distance: float) -> Vector3:
	var left := distance
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var span := a.distance_to(b)
		if left <= span or i == points.size()-2: return a.lerp(b,clampf(left/maxf(span,0.0001),0.0,1.0))
		left -= span
	return points[points.size()-1]

func _chain_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for p in [a,b,c,a,c,d]:
		st.set_color(color)
		st.add_vertex(p)

# Narrow links rather than a wide pixel card. Their path is taut between the art's two attachment points; the
# ring plane faces diagonally between the two lateral views, so its width stays legible from either side. Each
# first and last ring straddles its arch/leaf anchor, so no side view can lose the join.
func _chain_links(model: Node3D, name: String, points: Array) -> void:
	var length := 0.0
	for i in range(points.size()-1): length += (points[i] as Vector3).distance_to(points[i+1])
	var count := maxi(2,int(ceil(length/0.14))+1) # a link every 5.6 source px
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for link in count:
		var distance := length*float(link)/float(count-1)
		var center := _chain_at(points,distance)
		var tangent := (_chain_at(points,minf(distance+0.03,length))-_chain_at(points,maxf(distance-0.03,0.0))).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		if side.length() < 0.001: side = tangent.cross(Vector3.RIGHT).normalized()
		side = (side+tangent.cross(side).normalized()).normalized()
		var binormal := tangent.cross(side).normalized()
		var major := 0.11
		var minor := 0.037
		var wire := 0.014
		var color := Color(0.34,0.41,0.49)
		var ring := func(theta: float, phi: float) -> Vector3:
			var around := center + tangent*(major*cos(theta)) + side*(minor*sin(theta))
			var radial := (tangent*(cos(theta)/major)+side*(sin(theta)/minor)).normalized()
			return around + (radial*cos(phi)+binormal*sin(phi))*wire
		for i in 12:
			var t0 := TAU*float(i)/12.0
			var t1 := TAU*float(i+1)/12.0
			for k in 6:
				var p0 := TAU*float(k)/6.0
				var p1 := TAU*float(k+1)/6.0
				_chain_quad(st,ring.call(t0,p0),ring.call(t1,p0),ring.call(t1,p1),ring.call(t0,p1),color)
	var part := MeshInstance3D.new()
	part.name = name
	part.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	part.set_surface_override_material(0,material)
	model.add_child(part)

func add(node: Node3D, e: Dictionary, id: int, path: String, collision: bool, screen: int) -> bool:
	if not has(path) or absf(float(e.get("size",100))-100.0) >= 0.5: return false
	var d: Dictionary = fw.host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var foot: Vector2 = fw.sprite_foot(path)
	var anchor := foot if path == PANEL else Vector2(50.0,120.0) # the arch's lower stone, before the leaf begins
	var face := _face(screen,e,d,anchor)
	if face.is_empty(): return false
	var origin: Vector2 = fw.screen_origin(screen)
	var top_left := origin+Vector2(float(e.get("x",0))-float(d.get("dx",0)),float(e.get("y",0))-float(d.get("dy",0)))
	var node_at := top_left+foot
	node.position = fw.point(node_at.x-origin.x,node_at.y-origin.y)
	var size := Vector2(float(fw.clean_texture(path).get_width()),float(fw.clean_texture(path).get_height()))
	var a: Vector2 = face.a
	var b: Vector2 = face.b
	var normal: Vector2 = face.normal
	var wall_position := func(u: float, v: float) -> Vector3:
		var x := top_left.x+u
		var projected_y := top_left.y+v
		var z := a.y+(x-a.x)*(b.y-a.y)/(b.x-a.x)
		return Vector3(x-node_at.x+normal.x*FACE_CLEARANCE,z-projected_y,z-node_at.y+normal.y*FACE_CLEARANCE)*fw.SCALE
	var ground_position := func(u: float, v: float) -> Vector3:
		return Vector3(top_left.x+u-node_at.x,GROUND_CLEARANCE,top_left.y+v-node_at.y)*fw.SCALE
	var model := Node3D.new()
	model.name = "Model"
	model.set_meta("door_face",face)
	node.add_child(model)
	if path == PANEL:
		_surface(model,"Panel",fw.clean_texture(path),size,wall_position,normal*FACE_CLEARANCE)
	else:
		var parts := _split(path)
		_surface(model,"Arch",parts.Arch,size,wall_position,normal*FACE_CLEARANCE)
		_surface(model,"Leaf",parts.Leaf,size,ground_position,Vector2(0,-GROUND_CLEARANCE))
		# At each chain's upper end, the fitted front face sets the height. At its leaf end the height is zero.
		# z = the original picture's y + height, so each traced point keeps its original-camera projection.
		for chain in [["ChainLeft",LEFT_CHAIN],["ChainRight",RIGHT_CHAIN]]:
			var path_points: Array = chain[1]
			var start: Vector2 = path_points[0]
			var end: Vector2 = path_points[path_points.size()-1]
			var top_x := top_left.x+start.x
			var wall_z := a.y+(top_x-a.x)*(b.y-a.y)/(b.x-a.x)
			var top_height := wall_z-(top_left.y+start.y)
			var points: Array = []
			for source_point in [start,end]:
				var source_at: Vector2 = source_point
				var h := top_height*(end.x-source_at.x)/(end.x-start.x)
				points.append(Vector3(top_left.x+source_at.x-node_at.x,h+GROUND_CLEARANCE,top_left.y+source_at.y+h-node_at.y)*fw.SCALE)
			_chain_links(model,str(chain[0]),points)
	node.set_meta("castle_door",true)
	node.set_meta("height",maxf(0.2,fw.sprite_height(e)*fw.SCALE))
	node.set_meta("surface_position",node.position)
	# Keep the old tower-card ray target on the source hardbox, independent of the projected art's foot.
	# Movement collision also uses that hardbox in game.gd.
	if collision and e.get("warp") == null:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id",id)
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var rect: Rect2 = fw.hard_rect(e)
		box.size = Vector3(maxf(0.2,rect.size.x*fw.SCALE),float(node.get_meta("height")),maxf(0.2,rect.size.y*fw.SCALE))
		shape.position = fw.point(rect.get_center().x,rect.get_center().y)-node.position
		shape.position.y = box.size.y*0.5
		shape.shape = box
		body.add_child(shape)
		node.add_child(body)
	return true
