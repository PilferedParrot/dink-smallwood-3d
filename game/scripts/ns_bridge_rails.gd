# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends RefCounted
const SCALE := 0.025
# North-south sections form supported runs, including copies spanning screen edges.
# Source-derived profiles and plank bounds come from bridge_split.py. A rope's
# elevated span occupies its planks' depth, never the whole source strip + height.
# Original projection P=(X,Z-Y) supplies the texture across section boundaries.
# Missing terminal posts (02 and isolated story sections) are reconstructed from
# 01's observed square post. The lower cap's remaining tail stays on the ground.
var rails
# Current NS source placements are static type1/brain0/script-empty/size100.
# Arbitrary runtime moves/removals require state-aware layout/cache invalidation.
var placements: Array = []
var layouts: Dictionary = {}
var meshes: Dictionary = {}
var donor_textures: Dictionary = {}

func _init(owner) -> void:
	rails = owner

func _layout(vision: int) -> Array:
	if layouts.has(vision): return layouts[vision]
	var world = rails.world
	if placements.is_empty():
		for number in world.host.world.screens:
			var screen := int(number)
			for source in world.host.world.screens[number].get("sprites",[]):
				if int(source.get("type",1)) == 2: continue
				var frame: Dictionary = world.host._frame(int(source.get("seq",0)),int(source.get("frame",1)))
				var path := str(frame.get("path",""))
				var info: Dictionary = rails.entry(path)
				if str(info.get("kind","")) != "ns": continue
				var origin: Vector2 = world.screen_origin(screen)+Vector2(float(source.x)-float(frame.dx),float(source.y)-float(frame.dy))
				placements.append({"path":path,"origin":origin,"vision":int(source.get("vision",0)),"info":info})
	var out: Array = []
	var seen := {}
	for part in placements:
		if int(part.vision) != 0 and int(part.vision) != vision: continue
		var key := str(part.path)+":"+str(part.origin)
		if seen.has(key): continue # source copies at 416/448, 448/480, 480/512, 512/544
		seen[key] = true
		out.append(part)
	layouts[vision] = out
	return out

func _aligned(a: Dictionary, b: Dictionary) -> bool:
	var ac: float = a.origin.x+(float(a.info.planks[0])+float(a.info.planks[1]))*0.5
	var bc: float = b.origin.x+(float(b.info.planks[0])+float(b.info.planks[1]))*0.5
	# Placement jitter must be smaller than one rope diameter, as in the offset
	# lower cap on 701. Parallel bridges one deck width apart do not join.
	return absf(ac-bc) <= float(a.info.rope_width)+0.5

func _neighbour(at: Dictionary, layout: Array, forward: bool) -> Dictionary:
	var edge: float = at.origin.y+float(at.info.planks[3 if forward else 2])
	for other in layout:
		if not _aligned(at,other): continue
		var opposite: float = other.origin.y+float(other.info.planks[2 if forward else 3])
		if absf(edge-opposite) <= 0.5: return other
	return {}

func _side(at: Dictionary, other: Dictionary, side: int) -> float:
	var x: float = at.origin.x+float(at.info.side_centers[side])
	if not other.is_empty(): x = (x+float(other.origin.x)+float(other.info.side_centers[side]))*0.5
	return x-float(at.origin.x)

func _picture(at: Dictionary, layout: Array, margin: int) -> ImageTexture:
	var image: Image = rails.world.sprite_image(str(at.path))
	var picture := Image.create(image.get_width(),image.get_height()+margin,false,Image.FORMAT_RGBA8)
	var support: Image = rails.world.sprite_image(str(at.info.support_art))
	for y in picture.get_height():
		for x in picture.get_width():
			var gy: float = at.origin.y+float(y-margin)
			var gx: float = at.origin.x+float(x)
			var color := Color.TRANSPARENT
			for part in [at]+layout:
				if not _aligned(at,part): continue
				var source: Image = rails.world.sprite_image(str(part.path))
				var sx := roundi(gx-float(part.origin.x))
				var sy := roundi(gy-float(part.origin.y))
				if sx < 0 or sy < 0 or sx >= source.get_width() or sy >= source.get_height(): continue
				color = source.get_pixel(sx,sy)
				if color.a > 0.5: break
			# A story layer may begin with 03: no preceding art exists for its
			# top 36 rows. Reconstruct that unseen rope from 01's support pixels.
			if color.a < 0.5 and y < margin:
				color = support.get_pixel(clampi(x,0,support.get_width()-1),posmod(y, int(at.info.support_profiles[0][3])+1))
			picture.set_pixel(x,y,color)
	picture.generate_mipmaps()
	return ImageTexture.create_from_image(picture)

func _donor(side: int) -> ImageTexture:
	if donor_textures.has(side): return donor_textures[side]
	var profile: Dictionary = rails.data["_meta"]["ns_rope_atlases"][side]
	var image := Image.create(int(profile.width),int(profile.height),false,Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var rgba: Array = profile.pixels[y*image.get_width()+x]
			image.set_pixel(x,y,Color(float(rgba[0])/255.0,float(rgba[1])/255.0,float(rgba[2])/255.0,float(rgba[3])/255.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	donor_textures[side] = texture
	return texture

func _rope(info: Dictionary, left: float, right: float, z0: float, z1: float, dx: float, dy: float, margin: int, size: Vector2, origin_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clean := SurfaceTool.new()
	clean.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := float(info.rope_width)*0.5
	var top := float(info.height)
	var bottom := top-2.0*half
	var donor_period := float(rails.data["_meta"]["ns_rope_atlases"][0].height)
	var corners := [Vector3(left-half,bottom,z0),Vector3(left+half,bottom,z0),
		Vector3(left+half,top,z0),Vector3(left-half,top,z0),
		Vector3(right-half,bottom,z1),Vector3(right+half,bottom,z1),
		Vector3(right+half,top,z1),Vector3(right-half,top,z1)]
	for face in [[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4],[0,3,2,1],[4,5,6,7]]:
		for i in [0,1,2,0,2,3]:
			var p: Vector3 = corners[face[i]]
			# Top/end caps keep the source projection. Long sides and bottom
			# use only rope pixels, with shared world-depth phase at every join.
			var projected: bool = face == [3,7,6,2] or face == [0,3,2,1] or face == [4,5,6,7]
			var tool := st if projected else clean
			if projected: tool.set_uv(Vector2(p.x,p.z-p.y+margin)/size)
			else:
				var across := (p.y-bottom)/maxf(top-bottom,0.001)
				if face == [0,1,5,4]: across = 0.0 # unseen underside uses the source shadow
				tool.set_uv(Vector2(across,(origin_y+p.z-float(info.height))/donor_period))
			tool.add_vertex(Vector3(p.x-dx,p.y,p.z-dy)*SCALE)
	var mesh := st.commit()
	clean.commit(mesh)
	return mesh

func _post(st: SurfaceTool, profile: Array, center: float, z0: float, z1: float, height: float, dx: float, dy: float, texture: Texture2D) -> void:
	var width := float(profile[1])-float(profile[0])+1.0
	var x0 := center-width*0.5
	var x1 := center+width*0.5
	var fl := Vector3(x0-dx,0,z1-dy)*SCALE
	var fr := Vector3(x1-dx,0,z1-dy)*SCALE
	var bl := Vector3(x0-dx,0,z0-dy)*SCALE
	var br := Vector3(x1-dx,0,z0-dy)*SCALE
	var up := Vector3(0,height*SCALE,0)
	var u0 := float(profile[0])/float(texture.get_width())
	var u1 := (float(profile[1])+1.0)/float(texture.get_width())
	var v0 := (float(profile[3])+1.0)/float(texture.get_height())
	var v1 := (float(profile[2])+width)/float(texture.get_height())
	for face in [[fl,fr,fr+up,fl+up],[br,bl,bl+up,br+up],[bl,fl,fl+up,bl+up],[fr,br,br+up,fr+up],[fl+up,fr+up,br+up,bl+up]]:
		rails._quad(st,face[0],face[1],face[2],face[3],Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1),Vector2(u0,v1))

func add(node: Node3D, e: Dictionary, frame: Dictionary, screen: int) -> void:
	var world = rails.world
	if screen < 0: screen = world.host.current_screen
	var info: Dictionary = rails.entry(world.frame_path(e))
	var vision := int(world.host.vm.globals.get("vision",0))
	var origin: Vector2 = world.screen_origin(screen)+Vector2(float(e.x)-float(frame.dx),float(e.y)-float(frame.dy))
	var at := {"path":world.frame_path(e),"origin":origin,"info":info}
	var key := str(vision)+":"+str(at.path)+":"+str(origin)
	if not meshes.has(key):
		var layout := _layout(vision)
		var before := _neighbour(at,layout,false)
		var after := _neighbour(at,layout,true)
		var margin := ceili(float(info.height))+2
		var texture := _picture(at,layout,margin)
		var support: Texture2D = world.host._texture("res://"+str(info.support_art))
		var surfaces: Array = []
		var posts := SurfaceTool.new()
		posts.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_posts := false
		for side in 2:
			var x0 := _side(at,before,side)
			var x1 := _side(at,after,side)
			var z0 := float(info.planks[2])
			var z1 := float(info.planks[3])
			var profile: Array = info.support_profiles[side]
			var width := float(profile[1])-float(profile[0])+1.0
			if before.is_empty():
				_post(posts,profile,x0,z0,z0+width,float(info.height),float(frame.dx),float(frame.dy),support)
				z0 += width*0.5
				has_posts = true
			if after.is_empty():
				_post(posts,profile,x1,z1-width,z1,float(info.height),float(frame.dx),float(frame.dy),support)
				z1 -= width*0.5
				has_posts = true
			surfaces.append([_rope(info,x0,x1,z0,z1,float(frame.dx),float(frame.dy),margin,Vector2(texture.get_width(),texture.get_height()),origin.y),[texture,_donor(side)],"RopeLeft" if side == 0 else "RopeRight"])
		if has_posts: surfaces.append([posts.commit(),support,"Posts"])
		meshes[key] = surfaces
	var rail := Node3D.new()
	rail.name = "Rail"
	node.add_child(rail)
	for surface in meshes[key]:
		var part := MeshInstance3D.new()
		part.name = str(surface[2])
		part.mesh = surface[0]
		if surface[1] is Array:
			for index in part.mesh.get_surface_count(): part.set_surface_override_material(index,rails._material(surface[1][index]))
		else: part.material_override = rails._material(surface[1])
		rail.add_child(part)
