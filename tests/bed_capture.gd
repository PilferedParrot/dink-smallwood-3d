extends "building_capture.gd"
# Settled deterministic art fixture. Campaign and map scripts are skipped.
# Gallery views hide surrounding geometry so all four physical sides can be seen.
var gallery_prop: Node3D=null
var gallery_path: String=""
func _cutaway(node: Node, world) -> void:
	if node is MeshInstance3D and node.material_override!=null and node.material_override in [world.materials.get("ceiling"),world.materials.get("beam")]: node.visible=false
	for child in node.get_children():_cutaway(child,world)
# Fixture-only: source wall faces have pre-existing equal-depth overlaps whose
# opaque winner otherwise follows recycled renderer resource slots. Keep that
# nuisance variable fixed on BOTH packs; production materials are not modified.
func _stable_wall_ties(game) -> void:
	var ids: Array=game.visuals.keys();ids.sort()
	var surfaces: Array=[]
	for id in ids:
		var visual: Node3D=game.visuals[id]
		if str(visual.get_meta("model_key",""))!="wall":continue
		for mesh in _meshes(visual):
			for surface in mesh.mesh.get_surface_count():surfaces.append([mesh,surface])
	assert(surfaces.size()<=Material.RENDER_PRIORITY_MAX+1,"Fixture wall order exceeds renderer priority range")
	for index in surfaces.size():
		var mesh: MeshInstance3D=surfaces[index][0]
		var surface: int=surfaces[index][1]
		var original: Material=mesh.get_active_material(surface)
		var copy: Material=original.duplicate()
		copy.render_priority=index
		mesh.set_surface_override_material(surface,copy)
# Diagnostic tint classification only; it never changes the production atlas.
# Cyan = measured visible source face with an unchanged authored sample.
# Magenta = continued texel, reverse/underside face, or inferred rear-post side.
func _bed_provenance(node: Node, solids) -> void:
	for mesh in _meshes(node):
		var part:=str(mesh.mesh.resource_name)
		for face in mesh.mesh.get_surface_count():
			var old: StandardMaterial3D=mesh.get_active_material(face)
			var domain: String=str(old.get_meta("bed_domain",""))
			if not solids.bed_parts.textures.has(domain):continue
			var donors: Array=solids.bed_parts.textures[domain].donors
			var image:=Image.create(121,93,false,Image.FORMAT_RGBA8)
			var visible_face:=face in [1,2,4]
			if part=="bed:frame" and face==4:visible_face=false
			if part=="bed:post1" and face!=4:visible_face=false
			for y in 93:
				for x in 121:
					var authored:=visible_face and int(donors[y*121+x])==y*121+x
					image.set_pixel(x,y,Color.CYAN if authored else Color.MAGENTA)
			var mat: StandardMaterial3D=old.duplicate()
			mat.albedo_texture=ImageTexture.create_from_image(image)
			mesh.set_surface_override_material(face,mat)
func _capture_setup(game, view: Dictionary) -> void:
	if bool(view.get("stable_wall_ties",false)):_stable_wall_ties(game)
	if bool(view.get("original",false)) and not bool(view.get("retain_ceiling",false)):_cutaway(game.scene_root,game.fp_world)
	var wanted: Node=null
	if view.has("prop_path"):
		if gallery_path!=str(view.prop_path):
			if is_instance_valid(gallery_prop):gallery_prop.free()
			gallery_prop=game.fp_world.props.node(str(view.prop_path))
			game.scene_root.add_child(gallery_prop)
			gallery_path=str(view.prop_path)
			var box:=_model_box(gallery_prop)
			gallery_prop.position=-Vector3(box.get_center().x,box.position.y,box.get_center().z)
		wanted=gallery_prop
	elif view.has("target_x"):
		for id in game.entities:
			var e: Dictionary=game.entities[id]
			if absf(float(e.get("x",-999))-float(view.target_x))<0.1 and absf(float(e.get("y",-999))-float(view.target_y))<0.1:wanted=game.visuals.get(id)
	if view.has("target_x") or view.has("prop_path"):
		assert(is_instance_valid(wanted),"Missing gallery prop")
		_gallery(game.scene_root,wanted)
		if bool(view.get("bed_provenance",false)):
			game.fp_world.environment.fog_enabled=false
			_bed_provenance(wanted,game.fp_world.solids)
func _model_box(node: Node3D) -> AABB:
	var found:=false;var out:=AABB()
	for child in node.get_children():
		if child is MeshInstance3D:
			var box: AABB=child.transform*child.get_aabb()
			out=out.merge(box) if found else box;found=true
	return out
func _gallery(node: Node, wanted: Node) -> void:
	if node is GeometryInstance3D or node is SpriteBase3D:
		var inside := node==wanted or wanted.is_ancestor_of(node)
		var ground := str(node.name).begins_with("Terrain_")
		node.visible=inside or ground
	for child in node.get_children(): _gallery(child,wanted)
func _corners(box: AABB, transform: Transform3D) -> Array:
	var out: Array=[]
	for i in 8:
		out.append(transform*(box.position+box.size*Vector3(float(i&1),float((i>>1)&1),float((i>>2)&1))))
	return out
func _mesh_corners(node: Node) -> Array:
	var out: Array=[]
	if node is MeshInstance3D: out.append_array(_corners(node.get_aabb(),node.global_transform))
	for child in node.get_children():out.append_array(_mesh_corners(child))
	return out
func _mask(game, view: Dictionary, folder: String) -> void:
	var size: Vector2i=root.size
	var rows:=int(round(float(size.x)*(400.0/sqrt(2.0))/600.0))
	var crop: int=(size.y-rows)/2
	var mask:=Image.create(size.x,rows,false,Image.FORMAT_L8);mask.fill(Color.BLACK)
	var boxes: Array=[]
	for id in game.entities:
		var e: Dictionary=game.entities[id]
		var visual: Node3D=game.visuals.get(id)
		if visual==null or str(visual.get_meta("model_key",""))!="bed": continue
		if view.has("target_x") and (absf(float(e.x)-float(view.target_x))>0.1 or absf(float(e.y)-float(view.target_y))>0.1):continue
		var corners:=_mesh_corners(visual)
		# Candidate envelope is derived from the source measurements, before any
		# after-render: x=0..121, y=0..32, z=31..93 source pixels. Include the
		# baseline's actual model bounds too, notably the 70% stand-in model.
		var frame: Dictionary=game._frame(int(e.get("pseq",e.get("seq",0))),int(e.get("pframe",e.get("frame",1))))
		var factor:=float(e.get("size",100))/100.0
		var origin:=Vector3(float(e.x)-320.0-float(frame.dx)*factor,0,float(e.y)-200.0-float(frame.dy)*factor)*GAME.SCALE
		var transform:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*factor*GAME.SCALE),origin)
		corners.append_array(_corners(AABB(Vector3(0,0,31),Vector3(121,32,62)),transform))
		var lo:=Vector2.INF;var hi:=Vector2(-INF,-INF)
		for point in corners:
			var p: Vector2=game.camera.unproject_position(point)-Vector2(0,crop)
			lo=lo.min(p);hi=hi.max(p)
		var rect:=Rect2i(Vector2i(floor(lo.x)-1,floor(lo.y)-1),Vector2i(ceil(hi.x)-floor(lo.x)+3,ceil(hi.y)-floor(lo.y)+3)).intersection(Rect2i(0,0,size.x,rows))
		for yy in range(rect.position.y,rect.end.y):
			for xx in range(rect.position.x,rect.end.x):mask.set_pixel(xx,yy,Color.WHITE)
		boxes.append({"entity":id,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	mask.save_png(folder.path_join(str(view.name)+"-mask-native.png"))
	var file:=FileAccess.open(folder.path_join(str(view.name)+"-bounds.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(boxes,"  "))
func _meshes(node: Node) -> Array:
	var out: Array=[]
	if node is MeshInstance3D:out.append(node)
	for child in node.get_children():out.append_array(_meshes(child))
	return out
func _white_alpha(old: Material) -> Material:
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.albedo_color=Color.WHITE
	if old is StandardMaterial3D and old.albedo_texture!=null:
		var img: Image=old.albedo_texture.get_image()
		if img.is_compressed():img.decompress()
		img.clear_mipmaps();img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():img.set_pixel(x,y,Color(1,1,1,img.get_pixel(x,y).a))
		mat.albedo_texture=ImageTexture.create_from_image(img)
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold=0.5
	return mat
func _visibility(game, view: Dictionary, folder: String) -> void:
	_blacken_for_source_mask(game)
	game.fp_world.environment.background_mode=Environment.BG_COLOR
	game.fp_world.environment.background_color=Color.BLACK
	game.fp_world.environment.fog_enabled=false
	var records: Array=[]
	for id in game.entities:
		var e: Dictionary=game.entities[id]
		var visual: Node3D=game.visuals.get(id)
		if visual==null or str(visual.get_meta("model_key",""))!="bed":continue
		if view.has("target_x") and (absf(float(e.x)-float(view.target_x))>0.1 or absf(float(e.y)-float(view.target_y))>0.1):continue
		var meshes:=_meshes(visual);var saved: Array=[]
		for mesh in meshes:
			var mats: Array=[]
			for i in mesh.mesh.get_surface_count():mats.append(mesh.get_active_material(i))
			saved.append([mesh.material_override,mats])
			if mesh.material_override!=null:mesh.material_override=_white_alpha(mesh.material_override)
			else:
				for i in mesh.mesh.get_surface_count():mesh.set_surface_override_material(i,_white_alpha(mats[i]))
		await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
		var img:=root.get_texture().get_image();var count:=0
		var rows:=int(round(float(img.get_width())*(400.0/sqrt(2.0))/600.0))
		img=img.get_region(Rect2i(0,(img.get_height()-rows)/2,img.get_width(),rows))
		for y in img.get_height():
			for x in img.get_width():
				var c:=img.get_pixel(x,y)
				if c.r>0.8 and c.g>0.8 and c.b>0.8:count+=1
		img.save_png(folder.path_join(str(view.name)+"-visible-"+str(id)+".png"))
		var record: Dictionary={"entity":id,"x":e.x,"y":e.y,"pixels":count}
		if count==0 and bool(view.get("retain_ceiling",false)):record.occlusion="retained ceiling control"
		if count==0 and not view.has("target_x") and not bool(view.get("retain_ceiling",false)):
			var corners:=_mesh_corners(visual);var centre:=Vector3.ZERO
			for point in corners:centre+=point/float(corners.size())
			await physics_frame
			var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position,centre,3))
			if not hit.is_empty():
				var owner: int=int(hit.collider.get_meta("entity_id",-1))
				var first: Node3D=game.visuals.get(owner)
				record.first_hit_entity=owner;record.first_hit_key=first.get_meta("model_key","") if first!=null else str(hit.collider.name)
		records.append(record)
		for j in meshes.size():
			if meshes[j].material_override!=saved[j][0]:meshes[j].material_override=saved[j][0]
			for i in saved[j][1].size():meshes[j].set_surface_override_material(i,saved[j][1][i])
	var file:=FileAccess.open(folder.path_join(str(view.name)+"-visibility.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	print("BED VISIBILITY ",view.name," ",records)
func _shoot(game, view: Dictionary, out_dir: String) -> void:
	# A rendered material mutation belongs to one fresh scenario. Rebuild before
	# every such view rather than restoring default/null material overrides.
	if "--bed-visibility" in OS.get_cmdline_user_args():
		game.vm.globals["vision"]=int(view.get("vision",0))
		game.load_map(int(view.screen),false);game.vm.cancel_all()
		game.set_process(false);game.set_physics_process(false);game.playing=false;game.ui.visible=false
		game.entities[1].x=505.0;game.entities[1].y=340.0
		game.fps_yaw=0.55;game.fps_pitch=-0.03;game._sync_fps_camera()
		for id in game.entities:game.entities[id]["frozen"]=true
		await process_frame
	if game.fp_world.light!=null: game.fp_world.light.shadow_enabled=false
	await super._shoot(game,view,out_dir)
	if bool(view.get("original",false)) and "--bed-bounds-mask" in OS.get_cmdline_user_args():_mask(game,view,out_dir)
	if bool(view.get("original",false)) and "--bed-visibility" in OS.get_cmdline_user_args():await _visibility(game,view,out_dir)
