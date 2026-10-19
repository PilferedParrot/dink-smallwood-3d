extends "fps_capture.gd"
# Frozen scenario fixture. No progression or player-profile use.
var dumped_atlases: Dictionary={}
func _dump_atlases(node: Node, folder: String, wanted: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var mat:Material=node.get_active_material(i)
			if mat is StandardMaterial3D and mat.albedo_texture != null:
				var texture:Texture2D=mat.albedo_texture
				var key:String=texture.get_meta("continuation_atlas","")
				if key in wanted and not dumped_atlases.has(key):
					var name:String=key.sha256_text()+".png"
					texture.get_image().save_png(folder.path_join(name))
					dumped_atlases[key]=name
	for child in node.get_children():_dump_atlases(child,folder,wanted)
func _run() -> void:
	var batch := ""
	var out := ""
	var atlas_dump := ""
	var atlas_ids := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bundle="):batch=arg.trim_prefix("--bundle=")
		if arg.begins_with("--out-dir="):out=arg.trim_prefix("--out-dir=")
		if arg.begins_with("--atlas-dump="):atlas_dump=arg.trim_prefix("--atlas-dump=")
		if arg.begins_with("--atlas-ids="):atlas_ids=arg.trim_prefix("--atlas-ids=")
	var wanted:Array=[]
	if not atlas_dump.is_empty():
		DirAccess.make_dir_recursive_absolute(atlas_dump)
		wanted=JSON.parse_string(FileAccess.get_file_as_string(atlas_ids))
	var views: Array=JSON.parse_string(FileAccess.get_file_as_string(batch))
	DirAccess.make_dir_recursive_absolute(out)
	var game=GAME.new()
	game.test_mode=true
	root.add_child(game)
	await process_frame
	await game._new_game()
	game.vm.cancel_all()
	game.settings["fov"]=80.0
	game.neighbour_seed_override=20261019
	game.set_process(false);game.set_physics_process(false)
	game.playing=false
	game.ui.close_menu();game.ui.visible=false
	var previous: String=""
	for view in views:
		var key: String=str(view.screen)+":"+str(view.get("vision",0))
		if previous!=key:
			game.vm.globals["vision"]=int(view.get("vision",0))
			game.load_map(int(view.screen),false)
			game.vm.cancel_all()
			game.set_process(false);game.set_physics_process(false)
			await process_frame
			previous=key
		if bool(view.get("original",false)):
			game.entities[1].x=505.0;game.entities[1].y=340.0
			game.fps_yaw=0.55;game.fps_pitch=-0.03
			game._sync_fps_camera()
		for id in game.entities: game.entities[id]["frozen"]=true
		await _shoot(game,view,out)
		if not atlas_dump.is_empty():_dump_atlases(game,atlas_dump,wanted)
	if not atlas_dump.is_empty():
		var index:=FileAccess.open(atlas_dump.path_join("index.json"),FileAccess.WRITE)
		index.store_string(JSON.stringify(dumped_atlases))
	game.queue_free()
	await process_frame
	quit()
