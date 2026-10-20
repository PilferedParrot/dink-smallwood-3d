extends SceneTree
# Constructor scenario: editor art, no campaign progression or map scripts.
const GAME = preload("res://scripts/fps_game.gd")
var failures: Array = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: _run.call_deferred()
func encode(surfaces: Array, role: bool = true) -> Array:
	var out: Array = []
	for sf in surfaces:
		var mesh: ArrayMesh = sf[0]
		var arrays := mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var faces: Array = []
		for at in range(0, ix.size(), 6):
			var unique: Array = []
			for i in range(at, mini(at + 6, ix.size())):
				if not ix[i] in unique: unique.append(ix[i])
			unique.sort()
			var points: Array = []
			for i in unique: points.append([uv[i].x*121.0,uv[i].y*93.0])
			faces.append(points)
		var image: Image = sf[1].albedo_texture.get_image()
		if image.is_compressed(): image.decompress()
		image.clear_mipmaps(); image.convert(Image.FORMAT_RGBA8)
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(image.get_data())
		out.append({"part":mesh.resource_name,"role":sf[1].get_meta("bed_role", "legacy") if role else "legacy","faces":faces,"texture_sha256":hash.finish().hex_encode()})
	return out
func _run() -> void:
	var game = GAME.new(); game.test_mode = true; root.add_child(game)
	await process_frame; await game._new_game(); game.vm.cancel_all()
	game.set_process(false); game.set_physics_process(false)
	var solids = game.fp_world.solids
	var path := "assets/graphics/inside/details/inacc-03.png"
	var fit: Dictionary = solids.fit_of(path)
	var canonical: Array = solids.bed_surfaces(fit,path,Vector2.ZERO)
	check(canonical.size()==6,"Bedding, frame and four posts have separate solid surfaces")
	var names: Array = []
	for sf in canonical: names.append(sf[0].resource_name)
	check(names.has("bed:bedding") and names.has("bed:frame") and names.has("bed:post3"),"All source-derived bed parts exist")
	# Same source location along the long axis on both long sides: a whole-point
	# reflection flips this derivative even on an otherwise fully authored patch.
	var top_base: Array = []
	for p in solids.bed_parts.bedding_top: top_base.append(Vector2(float(p[0]),float(p[1])+31.0))
	var centre: Vector2=(top_base[0]+top_base[1]+top_base[2]+top_base[3])/4.0
	var old_a: Vector2=solids._face_uv(top_base,0,centre,top_base[0],31.0,Vector2.ZERO)
	var old_b: Vector2=solids._face_uv(top_base,0,centre,top_base[1],31.0,Vector2.ZERO)
	var new_a: Vector2=solids._face_uv(top_base,0,centre,top_base[0],31.0,Vector2.ZERO,true)
	var new_b: Vector2=solids._face_uv(top_base,0,centre,top_base[1],31.0,Vector2.ZERO,true)
	var axis: Vector2=top_base[1]-top_base[0]
	check((old_b-old_a).dot(axis)<0,"Actual legacy reflection fails the head/foot direction control")
	check((new_b-new_a).dot(axis)>0,"Opposite long sides preserve the source head/foot direction")
	check(is_equal_approx(solids.bed_surface_height(Vector2(115,40)),32.0),"Surface placement uses the measured post cap height")
	check(is_equal_approx(solids.bed_surface_height(Vector2(60,35)),31.0),"Surface placement uses the bedding top")
	check(is_zero_approx(solids.bed_surface_height(Vector2(-20,-20))),"Surface placement rejects space outside the bed")
	var mb = solids.new_mb(path,fit,Vector2.ZERO)
	var base: Array = []
	for p in fit.base: base.append(Vector2(float(p[0]),float(p[1])))
	solids.prism(mb,base,0.0,float(fit.height))
	var legacy: Array = [[mb.mesh(),solids.material(path)]]
	var records: Array = []
	var holder := Node3D.new(); game.scene_root.add_child(holder)
	for screen in game.world.screens:
		var sprites: Array = game.world.screens[screen].get("sprites",[])
		for i in sprites.size():
			var e: Dictionary = sprites[i]
			if game.fp_world.frame_path(e)!=path: continue
			check(solids.handles(e),"Every bed uses its source parts, including scaled instances")
			var node = game.fp_world.make_entity(e,90000+i,holder,true,int(screen))
			var model = node.get_node_or_null("Model")
			var factor := float(e.get("size",100))/100.0
			check(bool(node.get_meta("interior_solid",false)) and model!=null,"Bed routes through fitted parts")
			if model!=null:
				check(model.get_child_count()==6,"Every bed contains all six parts")
				check(model.scale.is_equal_approx(Vector3.ONE*factor),"Source size scales all axes once")
				check(absf(float(node.get_meta("height",0))-32.0*0.025*factor)<0.0001,"Height follows scaled replacement geometry")
				var body = node.get_node_or_null("HitBody")
				var hit = body.get_child(0) if body!=null and body.get_child_count()>0 else null
				check(hit!=null and hit.shape is ConcavePolygonShape3D,"Ray body uses replacement triangles")
				if hit!=null:
					var hi := 0.0
					for v in hit.shape.get_faces(): hi=maxf(hi,v.y)
					check(absf(hi-float(node.get_meta("height",0)))<0.0001,"Ray height and visual height agree")
			var frame: Dictionary=game._frame(int(e.get("seq",0)),int(e.get("frame",1)))
			records.append({"screen":int(screen),"editor_index":i,"x":e.x,"y":e.y,"size":e.get("size",100),"hotspot":[frame.get("dx",0),frame.get("dy",0)]})
			node.queue_free()
	check(records.size()==16,"Census covers all 16 source beds")
	var report := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
	if report!="":
		var file:=FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"setup":"Constructor scenario; campaign progression and scripts skipped","faces":encode(canonical),"legacy_faces":encode(legacy,false),"instances":records,"failures":failures},"  "))
	print("BED PARTS DONE instances=",records.size()," failures=",failures)
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
