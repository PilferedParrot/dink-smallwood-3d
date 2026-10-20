extends SceneTree
const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func floor_surface(visual: Node3D) -> bool:
	if not visual.has_meta("floor_detail") or not visual.has_meta("floor_art_rect"): return false
	var model := visual.get_node_or_null("Model") as Node3D
	if model == null or model is Sprite3D or visual.get_node_or_null("HitBody") != null: return false
	var surfaces := 0
	var footprint := AABB()
	for child in model.get_children():
		if not child is MeshInstance3D: return false
		var bounds: AABB = model.transform*(child as MeshInstance3D).get_aabb()
		if not is_zero_approx(bounds.size.y): return false
		if child.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
		footprint = bounds if surfaces == 0 else footprint.merge(bounds)
		surfaces += 1
	var rect: Rect2 = visual.get_meta("floor_art_rect")
	return surfaces == 1 and Vector2(footprint.position.x,footprint.position.z).is_equal_approx(rect.position) and Vector2(footprint.size.x,footprint.size.z).is_equal_approx(rect.size)
func run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	# Authored inventory consistency, not a classifier of source pixels.
	# Independent partial shadow cues are checked by the Python wrapper.
	var ground := {89:range(1,11),90:[1,2,3,4,11,12,13,14,15],91:[5],92:[1,2,3,5,6,7,8,9,10,11]}
	var count := 0
	var known_failures := 0
	for seq in [89,90,91,92]:
		var frames: Array = game.sequences[str(seq)].frames
		for index in frames.size():
			var frame := index+1
			var flat: bool = frame in ground[seq]
			var background := {"seq":seq,"frame":frame,"type":0,"x":320,"y":200}
			check(game.fp_world.paints_ground(background,277) == (not flat),"one background/quad owner %d/%d" % [seq,frame])
			for scripted in [false,true]:
				var e := {"seq":seq,"frame":frame,"x":320,"y":200,"size":100,"type":1,"hard":1,"script":"thorn" if scripted else ""}
				var snapshot := JSON.stringify(e)
				var holder := Node3D.new()
				root.add_child(holder)
				var visual: Node3D = game.fp_world.make_entity(e,99001,holder,true,277)
				var planar := floor_surface(visual)
				check(planar == flat,"representation %d/%d scripted=%s expected_ground=%s got=%s" % [seq,frame,scripted,flat,planar])
				if not flat: check(visual.get_node_or_null("Model") is Sprite3D,"upright card preserved %d/%d" % [seq,frame])
				check(JSON.stringify(e)==snapshot,"source behavior/hardness preserved %d/%d" % [seq,frame])
				# Movement uses source hardness, independently of standing ray bodies.
				var saved_entities: Dictionary = game.entities
				game.entities = {99001:e}
				var center: Vector2 = game._hard_rect(e).get_center()
				e.hard = 0
				check(game._blocking_sprite(center,1)==99001,"hard-zero source still blocks %d/%d" % [seq,frame])
				e.hard = 1
				check(game._blocking_sprite(center,1)==0,"hard-one source stays passable %d/%d" % [seq,frame])
				game.entities = saved_entities
				if not scripted:
					print("DETAIL ",seq," ",frame," ",flat," ",planar)
					if frame>=7 and flat and not planar: known_failures+=1
				holder.free()
			count+=1
	var grasses := 0
	for seq in game.sequences:
		var frames: Array = game.sequences[seq].frames
		for index in frames.size():
			if not "/grass/" in str(frames[index].path).to_lower(): continue
			var e := {"seq":int(seq),"frame":index+1,"type":1,"x":320,"y":200}
			check(game.fp_world.model_key(e)=="grass" and not game.fp_world.paints_ground(e,277),"real grass stays upright %s/%d" % [seq,index+1])
			grasses+=1
	check(count==41 and grasses>0,"full inventory and vegetation look-alikes exercised")
	for pair in [[277,2],[192,5]]:
		game.vm.cancel_all()
		game.load_map(pair[0],false)
		var owners := 0
		for e in game.fp_world.background_sprites(pair[0],0):
			if int(e.get("index",0))==pair[1]: owners+=1
		for id in game.entities:
			if int(game.entities[id].get("editor_num",0))==pair[1] and floor_surface(game.visuals[id]): owners+=1
		check(owners==1,"one authored floor owner %s got%d" % [pair,owners])
	# Unearned bomb-hit fixture: the sixth active scripted ground placement
	# was a rock, outside the decorative-body census. Use the native brain-17
	# source-hardbox dispatch, rather than directly calling its hit procedure.
	game.vm.cancel_all()
	game.load_map(481,false)
	var starfish := 0
	for id in game.entities:
		if int(game.entities[id].get("editor_num",0))==2: starfish=int(id)
	check(starfish!=0,"authored bomb-secret starfish exists")
	if starfish!=0:
		check(floor_surface(game.visuals[starfish]) and int(game.entities[starfish].hard)==1,"authored starfish is flat and passable")
		var target: Dictionary = game.entities[starfish]
		var bomb: int = int(await game.dink_call("create_sprite",[target.x,target.y,17,161,1],{}))
		game.entities[bomb].script="dam-bomn"
		game.entities[bomb].range=30;game.entities[bomb].speed=0
		game.entities[bomb].brain_parm=1;game.entities[bomb].brain_parm2=1
		game._update_ai(0.0)
		for _i in 8: await process_frame
		check(int(game.entities[starfish].get("active",1))==0 and int(game.entities[starfish].hard)==1,"native bomb hit executes original starfish secret")
	# Stock scripts, not a made-up transition: secret trees become 89/10.
	# Direct VM invocation skips earning their death; it executes the source die procedure.
	for pair in [[307,"s2-sec1"],[659,"s2-sec3"],[710,"s3-sec1"]]:
		game.vm.cancel_all()
		game.load_map(pair[0],false)
		var subject := 0
		for id in game.entities:
			if str(game.entities[id].get("script",""))==pair[1]: subject=int(id)
		check(subject!=0,"secret-tree source placement exists %s" % [pair])
		if subject==0: continue
		await game.vm.run(pair[1],"die",subject,true)
		game._update_visual(subject)
		check(floor_surface(game.visuals[subject]),"source die reveals a live flat hole %s" % [pair])
		game.playing=true
		check(game._save_game("user://details-test.json") and game._load_game("user://details-test.json"),"isolated transformed-hole save/load")
		check(floor_surface(game.visuals[subject]),"transformed hole stays visible after load %s" % [pair])
	# All ground frames can appear live, move, scale and return to vegetation.
	game.vm.cancel_all()
	game.load_map(277,false)
	var runtime: int = int(await game.dink_call("create_sprite",[320,250,0,32,1],{}))
	for seq in ground:
		for frame in ground[seq]:
			game.entities[runtime].pseq=seq;game.entities[runtime].pframe=frame
			game.entities[runtime].size=50;game.entities[runtime].x=330
			game._update_visual(runtime)
			check(floor_surface(game.visuals[runtime]),"runtime floor/scale %d/%d" % [seq,frame])
			var rect: Rect2 = game.visuals[runtime].get_meta("floor_art_rect",Rect2())
			var image: Image = game.fp_world.sprite_image(str(game._frame(seq,frame).path))
			check(rect.size.is_equal_approx(Vector2(image.get_size())*game.SCALE*.5),"source-derived scaled footprint")
			check(is_equal_approx(game.visuals[runtime].position.x,game.fp_world.point(330,250).x),"live position follows source")
			game.entities[runtime].nodraw=1;game._update_visual(runtime)
			check(not game.visuals[runtime].visible,"hidden ground art is hidden")
			game.entities[runtime].nodraw=0;game.entities[runtime].pseq=32;game.entities[runtime].pframe=1
			game._update_visual(runtime)
			check(game.visuals[runtime].get_node_or_null("Model") is Sprite3D and not game.visuals[runtime].has_meta("floor_art_rect"),"return to upright source art")
			await process_frame
	print("KNOWN_GROUND_FAILURES ",known_failures)
	for failure in failures: print("FAIL ",failure)
	game.vm.cancel_all();game.queue_free()
	await process_frame
	print("GROUND DETAILS PASS" if failures.is_empty() else "GROUND DETAILS FAIL")
	quit(0 if failures.is_empty() else 1)
