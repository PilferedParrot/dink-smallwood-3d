extends "building_capture.gd"
# Settled deterministic art fixture. Campaign and map scripts are skipped.
# Gallery views hide surrounding geometry so all four physical sides can be seen.
var gallery_prop: Node3D=null
var gallery_path: String=""
func _capture_setup(game, view: Dictionary) -> void:
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
func _shoot(game, view: Dictionary, out_dir: String) -> void:
	if game.fp_world.light!=null: game.fp_world.light.shadow_enabled=false
	await super._shoot(game,view,out_dir)
	if bool(view.get("original",false)) and "--bed-bounds-mask" in OS.get_cmdline_user_args():_mask(game,view,out_dir)
