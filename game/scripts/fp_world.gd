# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Translates campaign coordinates into a solid, first-person world. No Sprite3D.
extends RefCounted
const SCALE := 0.06
const WIDTH := 36.0
const DEPTH := 24.0
var host
var models: Dictionary = {}
var materials: Dictionary = {}
var terrain_cache: Dictionary = {}
var interior_cache: Dictionary = {}
var bounds_cache: Dictionary = {}
var interior := false
var light: DirectionalLight3D
var environment: Environment
var scene_generation := -1
# Fingerprint to the currently live structural node. A node reference lets
# save/load rebuild after the previous visual has been queued for deletion.
var structural_seen: Dictionary = {}
# Buildings fitted from their sprites (tools/facade_fit.py); see fitted_model.
var facades: Dictionary = {}
var fitted_built: Dictionary = {} # world position key -> the node holding it (null: reserved), this scene

func setup(game) -> void:
	host = game
	var path := "res://prototype/facades.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	facades = parsed if parsed is Dictionary else {}

func point(x: float, y: float) -> Vector3:
	return Vector3((x-320.0)*SCALE,0,(y-200.0)*SCALE)

func is_inside(number: int) -> bool:
	if interior_cache.has(number): return interior_cache[number]
	var screen: Dictionary = host.world.screens.get(str(number),{})
	var count := 0
	for e in screen.get("sprites",[]):
		var path := source_path(e)
		if "innwalls" in path or "stnwalls" in path: count += 1
	var result := count >= 3 or bool(screen.get("indoor",false))
	interior_cache[number] = result
	return result

func source_path(e: Dictionary) -> String:
	var seq := int(e.get("pseq",e.get("seq",0)))
	var frame := int(e.get("pframe",e.get("frame",1)))
	return str(host._frame(seq,frame).get("path","")).to_lower()

func model_key(e: Dictionary) -> String:
	if e.has("fps_model"): return str(e.fps_model)
	var p := source_path(e)
	var frame := int(e.get("pframe",e.get("frame",1)))
	if p.is_empty(): return ""
	if "innwalls" in p or "stnwalls" in p: return "wall"
	if "trees" in p:
		if frame in [8,9,10,11,12,13]: return "dead_tree"
		return "pine_tree" if frame == 2 else "oak_tree"
	if "shrubs" in p: return "bush"
	if "rocks" in p: return "rock"
	if "/grass/" in p: return "grass"
	if "/fence/" in p: return "fence"
	if "/garden/" in p:
		if frame >= 23: return "fountain"
		return "flowers" if frame >= 13 else "mushroom"
	if "/landmark/" in p:
		if frame <= 3: return "well"
		return "bridge" if frame <= 6 else "sign"
	if "/home/" in p:
		if frame in [11,12,13]: return "ruin"
		return "cottage" if frame in [1,4,5,6,7,8,9,10] else ""
	if "/outinn/" in p: return "" # Assembled as buildings, not one house per wall fragment.
	if "/cabin/" in p: return "cottage" if frame == 1 else ""
	if "/church/" in p: return "cottage" if frame == 1 else ""
	if "/building/" in p: return "cottage"
	if "/castle/" in p or "/stone/" in p: return "tower"
	if "/bridge/" in p: return "bridge"
	if "/island/" in p: return "rock"
	if "/door/" in p: return "door"
	if "/details/inacc" in p:
		return {1:"shelf",2:"table",3:"bed",4:"shelf",5:"fireplace",6:"cave_entrance"}.get(frame,"table")
	if "/details/table" in p: return "chair" if frame in [4,6,8,10] else "table"
	if "/details/fire" in p: return "torch"
	if "/stairs/" in p: return "stairs"
	if "/pig/" in p: return "pig"
	if "/duck/" in p: return "duck"
	if "/fish/" in p: return "duck"
	if "/pill/" in p: return "pillbug"
	if "/bonca/" in p: return "bonca"
	if "/puddle/" in p: return "slime"
	if "/dragon/" in p: return "dragon"
	if "/stonegnt/" in p: return "bonca"
	if "/slayers/" in p: return "knight"
	if "/goblin/" in p: return "knight"
	if "/people/" in p:
		if "knight" in p or "soldier" in p: return "knight"
		# S1-H1-O's Silver knight uses the imported Peasant2 sequence
		# (c11w1), whose source art is armored despite its folder name.
		if "peasant2" in p: return "knight"
		if "mom" in p or "maiden" in p or "girl" in p: return "woman"
		if "oldman" in p or "gnome" in p: return "wizard"
		return "man"
	if "/dink/" in p: return "man"
	if "/barrels/" in p: return "barrel"
	if "/chest/" in p: return "chest"
	if "/boxes/" in p or "/grain/" in p: return "crate"
	if "/tomb/" in p: return "gravestone"
	if "/save/" in p: return "save"
	if "/bottles/" in p: return "potion"
	if "/coins/" in p: return "coin"
	if "/heart/" in p or "/health/" in p: return "heart"
	if "/food/" in p: return "food"
	if "/paper/" in p or "/inner/" in p: return "sign"
	if "/cup/" in p: return "potion"
	if "/tools/" in p: return "crate"
	if "/effects/fire/" in p or "/damage/fire" in p: return "flame"
	if "/damage/damag" in p: return "burn_scar"
	if "/damage/hole" in p: return "hole"
	if "/effects/arrow/" in p: return "arrow"
	if "/effects/seed/" in p: return "feed_grains"
	if "/effects/" in p: return "effect"
	if "/lands/details/" in p: return "rock" if frame < 7 else "grass"
	if "/teleport/" in p: return "save"
	if "/damage/" in p: return ""
	return "crate" if not str(e.get("script","")).is_empty() else "rock"

func build_ground(screen: Dictionary) -> void:
	scene_generation = host.generation
	structural_seen.clear()
	fitted_built.clear()
	# The current screen's own buildings carry its story state; a neighbour showing the
	# same building (one placed on both screens) leaves it to them.
	for source in screen.get("sprites",[]):
		if int(source.get("vision",0)) != 0 and int(source.vision) != int(host.vm.globals.get("vision",0)): continue
		var key := fitted_key(source,host.current_screen)
		if not key.is_empty(): fitted_built[key] = null
	interior = is_inside(host.current_screen)
	configure_environment()
	add_ground(host.current_screen,host.scene_root,Vector3.ZERO)
	add_terrain_walls(screen)
	if interior:
		add_ceiling(screen)
	else:
		# Only outdoor neighbors are connected. Interior maps live in their own spaces.
		var column: int = (host.current_screen-1)%32
		for dz in range(-1,2):
			for dx in range(-1,2):
				if dx == 0 and dz == 0: continue
				if column+dx < 0 or column+dx >= 32: continue
				var n: int = host.current_screen+dx+dz*32
				var offset := Vector3(dx*WIDTH,0,dz*DEPTH)
				if host.world.screens.has(str(n)) and not is_inside(n):
					add_ground(n,host.scene_root,offset)
					var backdrop := Node3D.new()
					backdrop.name = "Neighbor_%d" % n
					backdrop.position = offset
					host.scene_root.add_child(backdrop)
					var dedup: Dictionary = {}
					for source in host.world.screens[str(n)].get("sprites",[]):
						if int(source.get("vision",0)) != 0 and int(source.vision) != int(host.vm.globals.get("vision",0)): continue
						if int(source.get("type",1)) == 2: continue
						var e: Dictionary = source.duplicate()
						var state: Dictionary = host.editor_state.get("%d:%d" % [n,int(e.get("index",0))],{})
						if state.get("removed",false): continue
						e.merge(state,true)
						var key := model_key(e)
						# Script-controlled actors only become active on their own map.
						if key in ["flame","effect","arrow","man","woman","wizard","knight","pig","duck","pillbug","bonca","slime","dragon",""]: continue
						var fingerprint := "%s:%d:%d" % [key,int(e.x),int(e.y)]
						if dedup.has(fingerprint): continue
						dedup[fingerprint] = true
						make_entity(e,0,backdrop,false,n)
				else:
					add_wilderness(host.scene_root,offset,n)
		add_horizon()

func configure_environment() -> void:
	for child in host.get_children():
		if child is WorldEnvironment: environment = child.environment
		if child is DirectionalLight3D: light = child
	if environment:
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color("548399")
		sky_mat.sky_horizon_color = Color("d4d6af")
		sky_mat.ground_bottom_color = Color("687449")
		sky_mat.ground_horizon_color = Color("b8bea0")
		sky_mat.sun_angle_max = 2.5
		sky.sky_material = sky_mat
		environment.sky = sky
		environment.background_mode = Environment.BG_COLOR if interior else Environment.BG_SKY
		environment.background_color = Color("181916")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("ffe3af") if interior else Color("c6dfef")
		environment.ambient_light_energy = 0.30 if interior else 0.32
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.fog_enabled = not interior
		environment.fog_light_color = Color("b0baa1")
		environment.fog_density = 0.0025
		environment.fog_sky_affect = 0.12
	if light:
		light.rotation_degrees = Vector3(-48,-32,0)
		light.light_color = Color("fff0d9")
		light.light_energy = 0.25 if interior else 0.65
		light.shadow_enabled = true
		light.directional_shadow_max_distance = 65
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

func ground_texture(number: int) -> Texture2D:
	if terrain_cache.has(number): return terrain_cache[number]
	var screen: Dictionary = host.world.screens[str(number)]
	var img := Image.create(600,400,false,Image.FORMAT_RGB8)
	img.fill(Color("677744"))
	var sheets: Dictionary = {}
	var kit_tiles: Dictionary = {}
	for i in host.footprints.get(str(number),{}).get("clear",[]): kit_tiles[int(i)] = true
	for i in range(mini(96,screen.tiles.size())):
		var index := ground_tile(screen.tiles,i,kit_tiles)
		var sheet := int(index/128)+1
		var cell := index%128
		if not sheets.has(sheet):
			var texture: Texture2D = host._texture("res://assets/tiles/ts%02d.png" % sheet)
			if texture == null: texture = host._texture("res://assets/tiles/ts%d.png" % sheet)
			var image: Image = texture.get_image() if texture else null
			if image and image.is_compressed(): image.decompress()
			if image: image.convert(Image.FORMAT_RGB8)
			sheets[sheet] = image
		var source: Image = sheets[sheet]
		if source: img.blit_rect(source,Rect2i((cell%12)*50,int(cell/12)*50,50,50),Vector2i((i%12)*50,int(i/12)*50))
	img.generate_mipmaps()
	var result := ImageTexture.create_from_image(img)
	terrain_cache[number] = result
	return result

# A kit building's own tiles are pictures of its upper storey, which now stands in 3D: the
# ground continues the row they interrupt (ground tiles alternate in pairs, so keep the column
# parity), else the column. As the prototype does (sprite_world_proto.gd _ground_tile).
func ground_tile(tiles: Array, i: int, kit_tiles: Dictionary) -> int:
	if not kit_tiles.has(i): return int(tiles[i].get("tile",0))
	var row := int(i/12)
	var col := i%12
	for dist in range(2,12,2):
		for c in [col-dist,col+dist]:
			var j: int = row*12+c
			if c >= 0 and c < 12 and j < tiles.size() and not kit_tiles.has(j): return int(tiles[j].get("tile",0))
	for dist in range(1,8):
		for rr in [row-dist,row+dist]:
			var j: int = rr*12+col
			if rr >= 0 and rr < 8 and j < tiles.size() and not kit_tiles.has(j): return int(tiles[j].get("tile",0))
	return int(tiles[i].get("tile",0))

func add_ground(number: int, parent: Node3D, offset: Vector3) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Terrain_%d" % number
	var plane := PlaneMesh.new()
	plane.size = Vector2(WIDTH,DEPTH)
	ground.mesh = plane
	ground.position = offset
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ground_texture(number)
	mat.roughness = 0.96
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = mat
	parent.add_child(ground)
	add_kit_buildings(number,parent,offset)
	if not is_inside(number): add_grass(number,parent,offset,mat.albedo_texture.get_image())
	if offset == Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH,0.2,DEPTH)
		shape.shape = box
		body.position.y = -0.1
		body.add_child(shape)
		parent.add_child(body)

func mat(name: String, color: Color) -> StandardMaterial3D:
	if materials.has(name): return materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	materials[name] = m
	return m

func box_mesh(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func add_ceiling(screen: Dictionary) -> void:
	var limits := Rect2(20,0,600,400)
	var found := false
	for e in screen.get("sprites",[]):
		if model_key(e) == "wall":
			var r: Rect2 = hard_rect(e)
			limits = limits.merge(r) if found else r
			found = true
	var center := point(limits.get_center().x,limits.get_center().y)
	box_mesh(host.scene_root,Vector3(limits.size.x*SCALE,0.18,limits.size.y*SCALE),center+Vector3(0,3.65,0),mat("ceiling",Color("665036")))
	var beam_mat := mat("beam",Color("37291c"))
	for x in range(int(limits.position.x),int(limits.end.x)+1,75):
		box_mesh(host.scene_root,Vector3(0.18,0.26,limits.size.y*SCALE),point(x,limits.get_center().y)+Vector3(0,3.45,0),beam_mat)
	var glow := OmniLight3D.new()
	glow.position = center+Vector3(0,2.8,0)
	glow.light_color = Color("ffd395")
	glow.light_energy = 1.8
	glow.omni_range = 22
	host.scene_root.add_child(glow)

func add_grass(number: int, parent: Node3D, offset: Vector3, terrain: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = number*7193
	var transforms: Array[Transform3D] = []
	for i in 300:
		var px := rng.randi_range(0,599)
		var py := rng.randi_range(0,399)
		var color := terrain.get_pixel(px,py)
		if color.g < color.r*1.05 or color.g < 0.19 or color.b > color.g*0.85: continue
		var t := Transform3D.IDENTITY
		t = t.rotated(Vector3.UP,rng.randf()*TAU)
		t = t.scaled(Vector3.ONE*rng.randf_range(0.6,1.5))
		t.origin = point(px+20,py)+offset
		transforms.append(t)
	if transforms.is_empty(): return
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array([Vector3(-0.06,0,0),Vector3(0,0.20,0.03),Vector3(0.05,0,0),Vector3(0,0,-0.05),Vector3(0.02,0.24,0),Vector3(0,0,0.06)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var grass_mat := mat("grass",Color("546f30"))
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,grass_mat)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = multi
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)

func add_wilderness(parent: Node3D, offset: Vector3, seed_number: int) -> void:
	box_mesh(parent,Vector3(WIDTH,0.3,DEPTH),offset-Vector3(0,0.2,0),mat("wilderness",Color("647548")))
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(seed_number)*335
	for i in 12:
		var node := instance_model("oak_tree")
		node.position = offset+Vector3(rng.randf_range(-17,17),0,rng.randf_range(-11,11))
		node.scale *= rng.randf_range(0.8,1.4)
		node.rotation.y = rng.randf()*TAU
		parent.add_child(node)

func add_horizon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987
	for i in 24:
		var hill := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radial_segments = 16
		mesh.rings = 8
		hill.mesh = mesh
		var angle := i*TAU/24
		hill.position = Vector3(cos(angle)*130,-9,sin(angle)*130)
		hill.scale = Vector3(rng.randf_range(35,65),rng.randf_range(20,45),rng.randf_range(35,60))
		hill.material_override = mat("hill%d" % (i%3),Color("637655").lightened((i%3)*0.035))
		host.scene_root.add_child(hill)

func instance_model(key: String) -> Node3D:
	if key == "inn" and not ResourceLoader.exists("res://assets/models/inn.glb"): key = "cottage"
	if not models.has(key):
		var path := "res://assets/models/%s.glb" % key
		models[key] = load(path) if ResourceLoader.exists(path) else null
	if models[key] is PackedScene: return models[key].instantiate()
	return primitive_model(key)

func primitive_model(key: String) -> Node3D:
	var node := Node3D.new()
	var wood := mat("wood",Color("6e4828"))
	var stone := mat("stone",Color("857e6e"))
	match key:
		"feed_grains":
			# Original ITEM-PIG creates these short-lived seed sprites. Keep their
			# script lifetime and position, with grain instead of a glowing orb.
			for i in 18:
				var angle := float(i) * 2.39996
				var radius := 0.15 + float(i % 6) * 0.11
				box_mesh(node, Vector3(0.085, 0.045, 0.13),
					Vector3(cos(angle) * radius, 0.06 + float(i % 3) * 0.055, sin(angle) * radius),
					mat("feed_grain", Color("e4c478")))
		"fence_open":
			# The source hard=1 fence frames are visible gate approaches. Leave a
			# central opening and show short rails/posts at either side.
			box_mesh(node,Vector3(0.12,1.05,1.0),Vector3(-0.48,0.525,0),wood)
			box_mesh(node,Vector3(0.12,1.05,1.0),Vector3(0.48,0.525,0),wood)
			for side in [-1.0,1.0]:
				box_mesh(node,Vector3(0.38,0.10,0.10),Vector3(side*0.72,0.38,0),wood)
				box_mesh(node,Vector3(0.38,0.10,0.10),Vector3(side*0.72,0.72,0),wood)
		"wall":
			box_mesh(node,Vector3(1,3.6,1),Vector3(0,1.8,0),mat("plaster",Color("b1a07b")))
			box_mesh(node,Vector3(1.02,0.15,1.02),Vector3(0,0.25,0),wood)
			box_mesh(node,Vector3(1.02,0.2,1.02),Vector3(0,3.35,0),wood)
		"door":
			box_mesh(node,Vector3(1.8,2.7,0.16),Vector3(0,1.35,0),wood)
			for x in [-1.0,1.0]: box_mesh(node,Vector3(0.2,3.0,0.3),Vector3(x,1.5,0),stone)
			box_mesh(node,Vector3(2.2,0.22,0.3),Vector3(0,2.9,0),stone)
			box_mesh(node,Vector3(0.1,0.16,0.12),Vector3(0.55,1.25,0.12),mat("brass",Color("d9a74a")))
		"shelf":
			box_mesh(node,Vector3(2.8,2.3,0.3),Vector3(0,1.15,0.2),wood)
			for y in [0.3,1.0,1.7,2.3]:
				box_mesh(node,Vector3(2.9,0.1,0.7),Vector3(0,y,0),wood)
				for i in 9: box_mesh(node,Vector3(0.17,0.42,0.3),Vector3(-1.1+i*0.26,y+0.26,0),mat("book%d"% (i%3),[Color("624333"),Color("395650"),Color("9b843e")][i%3]))
		"fireplace":
			box_mesh(node,Vector3(2.8,0.2,1.2),Vector3(0,0.1,0),stone)
			for x in [-1.1,1.1]: box_mesh(node,Vector3(0.5,1.5,1.0),Vector3(x,0.8,0),stone)
			box_mesh(node,Vector3(2.8,1.5,0.9),Vector3(0,2.1,0),stone)
			var fire := primitive_model("flame")
			fire.position = Vector3(0,0.2,0.25)
			node.add_child(fire)
		"ruin":
			# home-11..13 are the source's charred cottage debris pieces. Keep
			# them low and broad so they read as rubble instead of a second house.
			var ash := mat("charred_wood",Color("29251f"))
			var soot := mat("soot_stone",Color("4a4439"))
			box_mesh(node,Vector3(1.55,0.22,0.42),Vector3(0,0.12,0),ash).rotation.y = -0.18
			box_mesh(node,Vector3(1.18,0.18,0.34),Vector3(-0.2,0.34,0.1),ash).rotation.z = 0.38
			box_mesh(node,Vector3(0.48,0.42,0.42),Vector3(0.48,0.3,-0.08),soot).rotation.z = -0.22
			box_mesh(node,Vector3(0.34,0.3,0.3),Vector3(-0.62,0.25,0.02),soot).rotation.z = 0.2
		"burn_scar":
			var ember := mat("burn_scar",Color("321f18"))
			box_mesh(node,Vector3(0.9,0.10,0.24),Vector3(0,0.06,0),ember).rotation.z = -0.2
			box_mesh(node,Vector3(0.48,0.08,0.22),Vector3(0.16,0.14,0.02),mat("burn_edge",Color("6e321d"))).rotation.z = 0.3
		"hole":
			# Vision 2 hole sprites are flat dark openings on the surviving walls.
			var opening := mat("ruin_hole",Color("171817"))
			box_mesh(node,Vector3(0.42,0.08,0.28),Vector3(0,0.24,0),opening)
			box_mesh(node,Vector3(0.24,0.06,0.18),Vector3(0.08,0.34,0.03),mat("hole_edge",Color("65513a"))).rotation.z = -0.35
		"flame":
			# Fire remains a still, readable source-state marker under reduced motion.
			var fire_orange := mat("fire_orange",Color("e85a20"))
			fire_orange.emission_enabled = true
			fire_orange.emission = Color("ff4e1b")
			fire_orange.emission_energy_multiplier = 1.4
			var fire_yellow := mat("fire_yellow",Color("ffc34a"))
			fire_yellow.emission_enabled = true
			fire_yellow.emission = Color("ff9c2e")
			fire_yellow.emission_energy_multiplier = 1.2
			var outer := CylinderMesh.new()
			outer.top_radius = 0.02
			outer.bottom_radius = 0.18
			outer.height = 0.72
			outer.radial_segments = 6
			var outer_mesh := MeshInstance3D.new()
			outer_mesh.mesh = outer
			outer_mesh.material_override = fire_orange
			outer_mesh.position.y = 0.36
			node.add_child(outer_mesh)
			var inner := CylinderMesh.new()
			inner.top_radius = 0.01
			inner.bottom_radius = 0.09
			inner.height = 0.42
			inner.radial_segments = 6
			var inner_mesh := MeshInstance3D.new()
			inner_mesh.mesh = inner
			inner_mesh.material_override = fire_yellow
			inner_mesh.position = Vector3(0,0.27,0.03)
			node.add_child(inner_mesh)
			var lamp := OmniLight3D.new()
			lamp.position.y = 0.42
			lamp.light_color = Color("ff6427")
			lamp.light_energy = 0.75
			lamp.omni_range = 3.5
			node.add_child(lamp)
		"stairs":
			for i in 6: box_mesh(node,Vector3(2.0,0.2*(i+1),0.4),Vector3(0,0.1*(i+1),-i*0.4),stone)
		"grass":
			return node # Ground uses batched blades instead.
		_:
			var visual := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.22
			mesh.height = 0.44
			mesh.radial_segments = 12
			mesh.rings = 6
			visual.mesh = mesh
			visual.position.y = 0.3
			var color := Color("cb9a48")
			if key in ["flame","effect"]: color = Color("ff7c23")
			if key == "heart": color = Color("cf2d36")
			if key == "potion": color = Color("58a5d1")
			if key == "save": color = Color("68d5dd")
			var material := mat(key,color)
			if key in ["flame","effect","save"]:
				material.emission_enabled = true
				material.emission = color
				material.emission_energy_multiplier = 1.6
			visual.material_override = material
			if key == "coin": visual.scale = Vector3(1,1,0.22)
			if key == "flame": visual.scale = Vector3(0.8,2.2,0.8)
			node.add_child(visual)
			if key in ["flame","save"]:
				var lamp := OmniLight3D.new()
				lamp.position.y = 0.8
				lamp.light_color = color
				lamp.light_energy = 1.2
				lamp.omni_range = 5.0
				node.add_child(lamp)
	return node

func model_bounds(key: String, node: Node3D) -> AABB:
	if bounds_cache.has(key): return bounds_cache[key]
	var box := AABB()
	var nodes: Array = [node]
	while not nodes.is_empty():
		var n: Node = nodes.pop_back()
		if n is MeshInstance3D:
			var transform := Transform3D.IDENTITY
			var current: Node3D = n
			while current != node:
				transform = current.transform*transform
				current = current.get_parent()
			var b: AABB = transform*n.get_aabb()
			box = box.merge(b)
		nodes.append_array(n.get_children())
	bounds_cache[key] = box
	return box

func make_entity(e: Dictionary, id: int, parent: Node3D, collision: bool = true, screen: int = -1) -> Node3D:
	var node := Node3D.new()
	var key := model_key(e)
	node.name = "Entity_%d_%s" % [id,key]
	node.set_meta("model_key",key)
	node.set_meta("entity_id",id)
	parent.add_child(node)
	node.position = point(float(e.get("x",320)),float(e.get("y",200)))
	if key.is_empty(): return node
	if screen < 0: screen = host.current_screen
	if key == "cottage" and not fitted_key(e,screen).is_empty():
		add_fitted_building(node,e,id,screen,collision)
		return node
	var passable_fence := key == "fence" and int(e.get("hard",0)) != 0
	# Hard=1 fence artwork marks an opening. Keep a readable gate shape while
	# leaving the center visually open for the source walk corridor.
	var model := instance_model("fence_open" if passable_fence else key)
	model.name = "Model"
	node.add_child(model)
	var bounds := model_bounds("fence_open" if passable_fence else key,model)
	var rect: Rect2 = hard_rect(e)
	var factor := maxf(0.05,float(e.get("size",100))/100.0)
	var structural := key in ["wall","cottage","inn","tower","fence","bridge"]
	if structural:
		var size := rect.size*SCALE
		var desired := Vector3(maxf(0.3,size.x),3.6,maxf(0.3,size.y))
		if key in ["cottage","inn"]: desired.y = 5.8 if key == "cottage" else 7.0
		if key == "tower": desired.y = 8.5
		if key == "fence": desired.y = 1.05
		if key == "bridge": desired.y = 0.4
		model.scale = desired/Vector3(maxf(0.1,bounds.size.x),maxf(0.1,bounds.size.y),maxf(0.1,bounds.size.z))
		node.position = point(rect.get_center().x,rect.get_center().y)
		if key in ["cottage","inn"]: model.rotation.y = PI
		if key == "cottage" and is_story_house(e):
			if int(host.vm.globals.get("vision",0)) == 1:
				add_story_fire(node,size.x)
			elif int(host.vm.globals.get("vision",0)) == 2:
				add_ruin_skin(node,model)
	else:
		model.scale *= factor
		# Damage sprites are decorative map state. Keep their primitive
		# equivalents on the ground instead of creating raised floating debris.
		if key == "flame":
			model.scale *= 1.55
			model.position.y = 1.55
		if key == "burn_scar":
			model.scale *= 1.35
		if key == "hole":
			model.scale *= 1.25
		if key == "ruin":
			model.scale *= 1.18
		if key in ["rock","bush"]:
			var target := clampf(rect.size.x*SCALE,0.3,4.0)
			model.scale *= target/maxf(bounds.size.x,0.1)
		if key in ["oak_tree","pine_tree","dead_tree","bush","rock"]:
			model.rotation.y = fmod(float(e.get("x",0))*1.74+float(e.get("y",0)),TAU)
		if key in ["bed","table","shelf","fireplace"]:
			# Furniture remains human-sized; campaign hardness defines its footprint.
			var size := rect.size*SCALE
			model.scale.x *= clampf(size.x/maxf(bounds.size.x,0.1),0.8,2.8)
			model.scale.z *= clampf(size.y/maxf(bounds.size.z,0.1),0.8,2.8)
			model.rotation.y = PI
		if key == "door" and not interior:
			model.rotation.y = PI
			set_in_wall(node,model,e,screen)
	var height := maxf(0.2,bounds.size.y*model.scale.y)
	node.set_meta("height",height)
	node.set_meta("base_model_position",model.position)
	var actor := key in ["man","woman","wizard","knight","pig","duck","pillbug","bonca","slime","dragon"]
	node.set_meta("actor",actor)
	# Dink uses hard=1 for fence artwork that is a visible opening/decoration.
	# Keep a visible gate mesh but do not turn that source non-solid stretch into
	# an invisible first-person rail. Hard-zero fences
	# retain their structural body for walking and projectile occlusion.
	# Damage/fire sprites are visual state markers in the original map.  They
	# must not add collision on top of the unchanged cottage footprint.
	if collision and not passable_fence and key not in ["grass","flowers","mushroom","effect","feed_grains","flame","burn_scar","hole","ruin","arrow"] and e.get("warp") == null:
		var body := StaticBody3D.new()
		body.name = "HitBody"
		body.set_meta("entity_id",id)
		body.collision_layer = 2 if actor or not str(e.get("script","")).is_empty() else 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if structural:
			box.size = Vector3(maxf(0.2,rect.size.x*SCALE),height,maxf(0.2,rect.size.y*SCALE))
		else:
			box.size = Vector3(maxf(0.3,bounds.size.x*model.scale.x),height,maxf(0.3,bounds.size.z*model.scale.z))
			if key in ["oak_tree","pine_tree","dead_tree"]: box.size = Vector3(0.8,height,0.8)
		shape.shape = box
		shape.position.y = height*0.5
		body.add_child(shape)
		node.add_child(body)
	return node

func create_visual(id: int) -> void:
	if not host.entities.has(id): return
	if id == 1:
		var player := Node3D.new()
		host.scene_root.add_child(player)
		host.visuals[id] = player
		return
	var e: Dictionary = host.entities[id]
	var key := model_key(e)
	var fingerprint := "%s:%s:%s" % [key,e.get("x",0),e.get("y",0)]
	if key in ["cottage","tower","wall"] and structural_seen.has(fingerprint):
		var existing: Node = structural_seen[fingerprint]
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			var duplicate := Node3D.new()
			host.scene_root.add_child(duplicate)
			host.visuals[id] = duplicate
			return
	var node := make_entity(e,id,host.scene_root)
	if key in ["cottage","tower","wall"]: structural_seen[fingerprint] = node
	host.visuals[id] = node
	update_visual(id)

func update_visual(id: int) -> void:
	if not host.entities.has(id) or not host.visuals.has(id): return
	var e: Dictionary = host.entities[id]
	var node: Node3D = host.visuals[id]
	if not is_instance_valid(node): return
	if id == 1:
		node.position = point(float(e.x),float(e.y))
		return
	var visible := int(e.get("active",1)) != 0 and int(e.get("nodraw",0)) == 0 and int(e.get("disabled",0)) == 0 and int(e.get("type",1)) != 2
	node.visible = visible
	var body: StaticBody3D = node.get_node_or_null("HitBody")
	if body: body.collision_layer = (2 if node.get_meta("actor",false) or not str(e.get("script","")).is_empty() else 1) if visible and not e.get("dead",false) else 0
	if not visible: return
	var key: String = node.get_meta("model_key","")
	if key not in ["wall","cottage","inn","tower","fence","bridge"]:
		node.position = point(float(e.get("x",320)),float(e.get("y",200)))
	var model: Node3D = node.get_node_or_null("Model")
	if model == null: return
	if node.get_meta("actor",false):
		var direction: Vector2 = host._dir_vector(int(e.get("dir",2)))
		if not direction.is_zero_approx(): model.rotation.y = atan2(-direction.x,-direction.y)
		var clock := Time.get_ticks_msec()/1000.0
		if e.get("dead",false):
			model.rotation.z = PI*0.5
			model.position.y = 0.25
		else:
			var moving: bool = int(e.get("seq",0)) != 0 and not e.get("frozen",false) and not host.ui.modal
			model.position.y = absf(sin(clock*7.0+id))*0.045 if moving else 0.0
			model.rotation.z = sin(clock*7.0+id)*0.025 if moving else 0.0
			animate_limbs(model,clock,id,moving)
	elif key in ["save","heart","coin","potion"]:
		model.rotation.y = Time.get_ticks_msec()*0.0007
		model.position.y = 0.15+sin(Time.get_ticks_msec()*0.002+id)*0.08

func animate_limbs(model: Node3D, time: float, id: int, moving: bool) -> void:
	# Blender parts retain descriptive names; rotation gives a simple gait in 3D.
	for child in model.get_children():
		if not child is Node3D: continue
		var n := str(child.name).to_lower()
		if "leg" in n or "arm" in n:
			if not child.has_meta("rest_rotation"): child.set_meta("rest_rotation",child.rotation)
			var rest: Vector3 = child.get_meta("rest_rotation")
			child.rotation.x = rest.x + (sin(time*7+id+(PI if "right" in n or "_r" in n or "-1" in n else 0.0))*0.2 if moving else 0.0)

# Solid dungeon/cliff silhouettes follow the imported collision mask. Water
# retains its original surface; it is not mistaken for stone walls.
func add_terrain_walls(_screen: Dictionary) -> void:
	if not interior: return # Outdoor masks also stamp grass, shores and invisible campaign gates.
	var terrain: Image = ground_texture(host.current_screen).get_image()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6,3.7 if interior else 2.8,0.6)
	var material := mat("dungeon_rock" if interior else "cliff_rock",Color("5c5a4d") if interior else Color("82775c"))
	mesh.material = material
	var transforms: Array[Transform3D] = []
	for y in range(5,400,10):
		for x in range(25,620,10):
			if not host._tile_blocked(Vector2(x,y)): continue
			var tile_index := int(_screen.tiles[int(y/50)*12+int((x-20)/50)].get("tile",0))
			if not interior and tile_index < 128: continue # Stamped grass hardness belongs to modeled scenery.
			var color := terrain.get_pixel(x-20,y)
			if color.b > color.r*1.1 and color.b > color.g*0.85: continue
			# Wood flooring and grass are not walls, even on scripted barriers.
			if color.g > color.r*1.12: continue
			if not interior and color.r > color.g*1.4: continue
			var trans := Transform3D.IDENTITY
			trans.origin = point(x,y)+Vector3(0,mesh.size.y*0.5-0.05,0)
			transforms.append(trans)
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "SolidTerrain"
	instance.multimesh = multi
	host.scene_root.add_child(instance)
	var cells: Dictionary = {}
	for trans in transforms:
		cells[Vector2i(roundi((trans.origin.x+17.7)/0.6),roundi((trans.origin.z+11.7)/0.6))] = true
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	for row in 40:
		var column := 0
		while column < 60:
			if not cells.has(Vector2i(column,row)):
				column += 1
				continue
			var start := column
			while column < 60 and cells.has(Vector2i(column,row)): column += 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3((column-start)*0.6,mesh.size.y,0.6)
			shape.shape = box
			shape.position = Vector3(-18.0+(start+column)*0.3,mesh.size.y*0.5-0.05,-11.7+row*0.6)
			body.add_child(shape)
	host.scene_root.add_child(body)


func hard_rect(e: Dictionary) -> Rect2:
	var normalized := e.duplicate()
	if not normalized.has("pseq"): normalized["pseq"] = e.get("seq",0)
	if not normalized.has("pframe"): normalized["pframe"] = e.get("frame",1)
	return host._hard_rect(normalized)

# --- Fitted buildings --------------------------------------------------------------------
# A building sprite is a picture of a 3D building from the original raised camera;
# tools/facade_fit.py recovers the building from its pixels. Its footprint is also what the
# player collides with (game.gd, data/footprints.json), so what stands here is exactly what
# blocks. This build is a stand-in: the fitted faces, each coloured by the sprite pixels it
# covers from the original camera. The projection-textured build of the prototype
# (prototype/sprite_world_proto.gd) replaces it when the world is built from the prototype.

func frame_path(e: Dictionary) -> String:
	var seq := int(e.get("pseq",e.get("seq",0)))
	var frame := int(e.get("pframe",e.get("frame",1)))
	return str(host._frame(seq,frame).get("path",""))

# "path:x:y" of the sprite's top-left in world pixels, or "" when it has no fitted building.
func fitted_key(e: Dictionary, screen: int) -> String:
	if int(e.get("type",1)) == 2: return ""
	var path := frame_path(e)
	if not facades.has(path) or not (facades[path] is Dictionary) or not facades[path].has("faces"): return ""
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var o := screen_origin(screen)
	return "%s:%d:%d" % [path,int(o.x+float(e.get("x",0))-float(d.get("dx",0))),int(o.y+float(e.get("y",0))-float(d.get("dy",0)))]

func screen_origin(n: int) -> Vector2:
	return Vector2(((n-1)%32)*600-20,int((n-1)/32)*400)

func add_fitted_building(node: Node3D, e: Dictionary, id: int, screen: int, collision: bool) -> void:
	var key := fitted_key(e,screen)
	var own: bool = screen == host.current_screen and id != 0
	if fitted_built.has(key):
		var holder: Variant = fitted_built[key]
		if holder == null and not own: return # the current screen builds its own
		# Built once: a house drawn twice (its foot and its top), or on two screens. A save
		# being loaded frees the old visuals, so a stale holder is rebuilt.
		if holder != null and is_instance_valid(holder) and not holder.is_queued_for_deletion(): return
	fitted_built[key] = node
	var path := frame_path(e)
	var d: Dictionary = host._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
	var image := sprite_image(path)
	# The node stands at the centre of the footprint, so story treatments sit on the house.
	var foot := PackedVector2Array()
	for f in facades[path].faces:
		for q in f.pts:
			if absf(float(q[1])) < 0.5: foot.append(Vector2(float(q[0]),float(q[2])))
	var box := Rect2(foot[0],Vector2.ZERO)
	for q in foot: box = box.expand(q)
	var top_left := Vector2(float(e.get("x",0))-float(d.get("dx",0)),float(e.get("y",0))-float(d.get("dy",0)))
	var centre := top_left+box.get_center()
	node.position = point(centre.x,centre.y)
	var model := fitted_model(facades[path].faces,image,box.get_center())
	node.add_child(model)
	if collision: node.add_child(ray_body(model,id))
	node.set_meta("height",float(model.get_meta("height",1.0)))
	node.set_meta("fitted",true)
	if is_story_house(e):
		if int(host.vm.globals.get("vision",0)) == 1: add_story_fire(node,box.size.x*SCALE,model.get_meta("roof_spots",[]))
		elif int(host.vm.globals.get("vision",0)) == 2: add_ruin_skin(node,model)

func sprite_image(path: String) -> Image:
	var texture: Texture2D = host._texture("res://"+path)
	if texture == null: return null
	var image := texture.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

# faces: [{label, block, pts: [[X, Y, Z]]}] in source pixels, (X, Z) on the ground, Y up;
# `origin` is the ground point placed at the node. `image` is the picture the faces were
# fitted to (seen through screen = (X, Z - Y)), or null for fixed stand-in colours.
func fitted_model(faces: Array, image: Image, origin: Vector2) -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var centres := {}
	var counts := {}
	for f in faces:
		var b := int(f.block)
		for q in f.pts:
			centres[b] = centres.get(b,Vector3.ZERO)+Vector3(float(q[0]),float(q[1]),float(q[2]))
			counts[b] = int(counts.get(b,0))+1
	var colours: Array = []
	var sums := {}
	for f in faces:
		var pts := face_points(f)
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for q in pts: mid += q/pts.size()
		if normal.dot(mid-centres[int(f.block)]/counts[int(f.block)]) < 0: normal = -normal
		# Seen by the original camera (looking 45 degrees down from the south)?
		var colour := Color(0,0,0,0)
		if image != null and normal.y+normal.z > 0.1: colour = face_colour(image,pts)
		colours.append(colour)
		if colour.a > 0:
			var k := "%d:%d" % [int(f.block),int(f.label)]
			sums[k] = sums.get(k,[Color(0,0,0,0),0])
			sums[k] = [sums[k][0]+colour,sums[k][1]+1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 0.0
	for i in faces.size():
		var f: Dictionary = faces[i]
		var colour: Color = colours[i]
		if colour.a == 0:
			# Faces the camera never saw take their block's seen faces of the same kind.
			var k := "%d:%d" % [int(f.block),int(f.label)]
			var same_label := ""
			for other in sums:
				if other.ends_with(":%d" % int(f.label)): same_label = other
			if sums.has(k): colour = sums[k][0]/float(sums[k][1])
			elif not same_label.is_empty(): colour = sums[same_label][0]/float(sums[same_label][1])
			else: colour = {1: Color("7d766a"),2: Color("6b6861"),3: Color("5a4030")}.get(int(f.label),Color("7d766a"))
			if int(f.label) == 1 and image == null and int(f.block)%2 == 1: colour = Color("c9bea4") # a kit's upper storey
		colour.a = 1.0
		var pts := face_points(f)
		for j in range(1,pts.size()-1):
			for q in [pts[0],pts[j],pts[j+1]]:
				var v := Vector3((q.x-origin.x)*SCALE,q.y*SCALE,(q.z-origin.y)*SCALE)
				st.set_color(colour)
				st.add_vertex(v)
				top = maxf(top,v.y)
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "Fitted"
	mesh.mesh = st.commit()
	model.add_child(mesh)
	model.set_meta("height",top)
	# Where a roof slope faces +X (the discovery camera's side, add_story_fire): the middle
	# of each such roof face, in the model's space.
	var spots: Array = []
	for f in faces:
		if int(f.label) != 2: continue
		var pts := face_points(f)
		var normal := (pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
		var mid := Vector3.ZERO
		for q in pts: mid += q/pts.size()
		if normal.dot(mid-centres[int(f.block)]/counts[int(f.block)]) < 0: normal = -normal
		if normal.x > 0.3 and spots.size() < 4:
			spots.append(Vector3((mid.x-origin.x)*SCALE,mid.y*SCALE,(mid.z-origin.y)*SCALE))
	model.set_meta("roof_spots",spots)
	return model

# The fitted faces as a body for rays only (aim, projectiles, dialogue cameras); movement
# reads the footprint (game.gd).
func ray_body(model: Node3D, id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "HitBody"
	body.set_meta("entity_id",id)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	var mesh: MeshInstance3D = model.get_node("Fitted")
	concave.set_faces(mesh.mesh.get_faces())
	shape.shape = concave
	body.add_child(shape)
	return body

func face_points(f: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for q in f.pts: pts.append(Vector3(float(q[0]),float(q[1]),float(q[2])))
	return pts

# The mean colour of the picture's opaque pixels inside the face as the original camera saw
# it, leaving out the black dither of the drawn shadow. Alpha 0 when it covers none.
func face_colour(image: Image, pts: Array[Vector3]) -> Color:
	var poly := PackedVector2Array()
	for q in pts: poly.append(Vector2(q.x,q.z-q.y))
	var r := Rect2(poly[0],Vector2.ZERO)
	for q in poly: r = r.expand(q)
	var sum := Color(0,0,0,0)
	var n := 0
	for y in range(maxi(0,int(r.position.y)),mini(image.get_height(),int(r.end.y)+1),2):
		for x in range(maxi(0,int(r.position.x)),mini(image.get_width(),int(r.end.x)+1),2):
			if not Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),poly): continue
			var c := image.get_pixel(x,y)
			if c.a < 0.5 or c.r+c.g+c.b < 0.04: continue
			sum += c
			n += 1
	return Color(0,0,0,0) if n < 4 else Color(sum.r/n,sum.g/n,sum.b/n,1.0)

# Kit buildings (the inn and its kin: seq 33 pieces and building tiles, found over the whole
# map by tools/facade_fit.py) with a piece on screen `number`, built once per scene.
func add_kit_buildings(number: int, parent: Node3D, offset: Vector3) -> void:
	for b in facades.get("_kit_buildings",[]):
		if not (b.screens as Array).any(func(m): return int(m) == number): continue
		var key := "kit:%s" % str(b.name)
		if fitted_built.has(key): continue
		var o := screen_origin(number)
		var rect: Array = b.rect
		var foot := Rect2(Vector2(float(rect[0]),float(rect[1])),Vector2(float(rect[2]),float(rect[3])))
		var node := Node3D.new()
		node.name = "Kit_%s" % str(b.name)
		node.set_meta("model_key","inn")
		parent.add_child(node)
		fitted_built[key] = node
		var centre := foot.get_center()-o
		node.position = point(centre.x,centre.y)+offset
		var model := fitted_model(b.faces,null,foot.size*0.5)
		node.add_child(model)
		if offset == Vector3.ZERO: node.add_child(ray_body(model,0))

# A door drawn on a building stands in its wall: on the nearest footprint edge, turned to it.
func set_in_wall(node: Node3D, model: Node3D, e: Dictionary, screen: int) -> void:
	var at := Vector2(float(e.get("x",0)),float(e.get("y",0)))
	var best := 30.0
	var hit := Vector2.INF
	var along := Vector2.RIGHT
	var outward := Vector2.DOWN
	for p in host.footprints.get(str(screen),{}).get("polys",[]):
		var poly := PackedVector2Array()
		for q in p.pts: poly.append(Vector2(float(q[0]),float(q[1])))
		var mid := Vector2.ZERO
		for q in poly: mid += q/poly.size()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i+1)%poly.size()]
			var c := Geometry2D.get_closest_point_to_segment(at,a,b)
			if c.distance_to(at) < best:
				best = c.distance_to(at)
				hit = c
				along = (b-a).normalized()
				outward = Vector2(-along.y,along.x)
				if outward.dot(c-mid) < 0: outward = -outward
	if hit == Vector2.INF: return
	node.position = point(hit.x,hit.y)
	# The door model faces its local +Z (the knob side); turn that outward.
	model.rotation.y = atan2(outward.x,outward.y)

func is_story_house(e: Dictionary) -> bool:
	# Map 439's home-01 at this anchor is Dink's house.  The other Home and
	# fire sprites on the map are scenery, and must not inherit its story state.
	return host.current_screen == 439 and int(e.get("x",-1)) == 275 and int(e.get("y",-1)) == 234 and source_path(e).ends_with("/home/home-01.png")

func add_story_fire(node: Node3D, house_width: float, roof_spots: Array = []) -> void:
	# The discovery camera approaches from the house's +X side.  Keep flames
	# just beyond that roof plane so they read as attached roof fire rather than
	# being hidden inside the imported cottage mesh.
	node.set_meta("story_house_state","burning")
	var treatment := Node3D.new()
	treatment.name = "StoryHouseFire"
	treatment.set_meta("story_house_treatment",true)
	node.add_child(treatment)
	if not roof_spots.is_empty():
		# A fitted house: flames stand on its own roof slopes that face +X.
		var sizes := [0.95,1.25,1.08,0.88]
		for i in roof_spots.size():
			var fire := primitive_model("flame")
			fire.position = roof_spots[i]
			fire.scale = Vector3.ONE*float(sizes[i%sizes.size()])
			treatment.add_child(fire)
		return
	var face_x := house_width*0.5+0.28
	for spec in [[4.00,-1.70,0.95],[4.72,-0.60,1.25],[4.46,0.72,1.08],[3.92,1.72,0.88]]:
		var fire := primitive_model("flame")
		fire.position = Vector3(face_x,float(spec[0]),float(spec[1]))
		fire.scale = Vector3.ONE*float(spec[2])
		treatment.add_child(fire)

func add_ruin_skin(node: Node3D, model: Node3D) -> void:
	# Vision 2 keeps the original cottage mesh and collision body.  Each mesh
	# surface gets a private charcoal material, preserving its roof/wall geometry
	# across viewpoints instead of placing an opaque facade in front of it.
	node.set_meta("story_house_state","charred")
	var treatment := Node3D.new()
	treatment.name = "StoryHouseRuin"
	treatment.set_meta("story_house_treatment",true)
	node.add_child(treatment)
	var nodes: Array[Node] = [model]
	while not nodes.is_empty():
		var current: Node = nodes.pop_back()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current
			var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
			for surface in surface_count:
				var original := mesh_instance.get_active_material(surface)
				if original is BaseMaterial3D:
					var charred: BaseMaterial3D = original.duplicate()
					# This multiplies the existing wood/stone textures: visibly ash-dark
					# while retaining the original roof seams and wall detail.
					charred.albedo_color = Color("7f6d55")
					charred.emission_enabled = false
					mesh_instance.set_surface_override_material(surface,charred)
		nodes.append_array(current.get_children())
