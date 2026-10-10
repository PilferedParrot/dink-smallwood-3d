# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Verdict: reproduces an unresolved tree-10 part; source-hide control identifies its owner.
extends SceneTree

const GAME=preload("res://scripts/fps_game.gd")
var game
var out := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	_run.call_deferred()

func grab(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
	picture.save_png(out.path_join(name+".png"));return picture

func source_parts(node: Node, result: Array) -> void:
	if node is Sprite3D and node.name == "Model" and int(node.get_meta("screen",0)) == 375 and str(node.get_meta("path","")).ends_with("tree-10.png#200-378"):
		var outer: Node=node
		while outer != null and not str(outer.name).begins_with("Entity_"): outer=outer.get_parent()
		if outer != null and (outer as Node3D).position.distance_to(Vector3(2.1,0,-4.05))<0.01: result.append(node)
	for child in node.get_children(): source_parts(child,result)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game=GAME.new();game.test_mode=true;root.add_child(game);await process_frame;await game._new_game();await create_timer(.5).timeout
	game.vm.cancel_all();game.load_map(439,false);game.set_physics_process(false);game.set_process(false)
	game.ui.visible=false;game.entities[1].x=514.2;game.entities[1].y=113.8;game.fps_yaw=-.7854;game.fps_pitch=-.02;game._sync_fps_camera()
	for model in [game.fps_viewmodel,game.fps_hand]:
		if is_instance_valid(model): model.visible=false
	for id in game.entities: game._update_visual(id)
	game.fp_world.face_neighbours()
	var targets: Array=[];source_parts(game.scene_root,targets)
	var before: Image=await grab("half-fir-present")
	var noise: Image=await grab("repeat-control")
	for target in targets: target.visible=false
	var hidden: Image=await grab("source375-index1-part1-hidden")
	var roi:=Rect2i(30,190,32,120)
	var changed:=0;var noise_count:=0
	for y in range(roi.position.y,roi.end.y):
		for x in range(roi.position.x,roi.end.x):
			var a:=before.get_pixel(x,y);var b:=hidden.get_pixel(x,y);var n:=noise.get_pixel(x,y)
			if maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),absf(a.b-b.b))>3.0/255.0: changed+=1
			if maxf(maxf(absf(a.r-n.r),absf(a.g-n.g)),absf(a.b-n.b))>3.0/255.0: noise_count+=1
	var f:=FileAccess.open(out.path_join("attribution.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"status":"open", "setup":"scripts-off frozen screen439, camera(514.2,113.8,-.7854,-.02); no progression; color-pass removal control","source_screen":375,"editor_index":1,"seq":32,"frame":10,"crop":[200,378],"targets":targets.size(),"roi":[30,190,32,120],"changed_roi_pixels":changed,"repeat_roi_noise_pixels":noise_count},"\t"))
	print("OPEN HALF-TREE CAUSE REPRO targets=",targets.size()," changed_roi=",changed," noise=",noise_count)
	game.vm.cancel_all();game.queue_free();await process_frame
	quit(0 if targets.size()==1 and changed>noise_count else 1)
