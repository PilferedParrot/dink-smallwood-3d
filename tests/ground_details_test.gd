extends SceneTree
const GAME := preload("res://scripts/fps_game.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.vm.cancel_all()
	# Independent inventory from inspected source pixels. Raised thorn loops,
	# skull faces and logs remain upright; the thin loose thorn pieces lie down.
	var ground := {89:range(1,11),90:[1,2,3,4,11,12,13,14,15],91:[1,5],92:range(1,12)}
	var count := 0
	var known_failures := 0
	for seq in [89,90,91,92]:
		var frames: Array = game.sequences[str(seq)].frames
		for index in frames.size():
			var frame := index+1
			var flat: bool = frame in ground[seq]
			var background := {"seq":seq,"frame":frame,"type":0,"x":320,"y":200}
			check(game.fp_world.paints_ground(background,277),"existing background stays painted %d/%d" % [seq,frame])
			for scripted in [false,true]:
				var e := {"seq":seq,"frame":frame,"x":320,"y":200,"size":100,"type":1,"hard":1,"script":"thorn" if scripted else ""}
				var snapshot := JSON.stringify(e)
				var paints: bool = game.fp_world.paints_ground(e,277)
				check(paints == flat,"representation %d/%d scripted=%s expected_ground=%s got=%s" % [seq,frame,scripted,flat,paints])
				var holder := Node3D.new()
				root.add_child(holder)
				var visual: Node3D = game.fp_world.make_entity(e,99001,holder,true,277)
				check(visual.has_meta("ground_painted") == flat,"visual owner %d/%d" % [seq,frame])
				if flat:
					check(visual.get_child_count()==0,"ground has no upright card/body/shadow %d/%d" % [seq,frame])
					check(visual.has_meta("floor_art_rect"),"floor camera footprint %d/%d" % [seq,frame])
				else:
					check(visual.get_node_or_null("Model") is Sprite3D,"upright card preserved %d/%d" % [seq,frame])
				check(JSON.stringify(e)==snapshot,"source behavior/hardness preserved %d/%d" % [seq,frame])
				if not scripted:
					print("DETAIL ",seq," ",frame," ",flat," ",paints)
					if frame>=7 and flat and not paints: known_failures+=1
				holder.free()
			count+=1
	# Real grass in a different source family must not join the ground class.
	var grasses := 0
	for seq in game.sequences:
		var frames: Array = game.sequences[seq].frames
		for index in frames.size():
			if not "/grass/" in str(frames[index].path).to_lower(): continue
			var e := {"seq":int(seq),"frame":index+1,"type":1,"x":320,"y":200}
			check(game.fp_world.model_key(e)=="grass" and not game.fp_world.paints_ground(e,277),"real grass stays upright %s/%d" % [seq,index+1])
			grasses+=1
	check(count==41 and grasses>0,"full inventory and vegetation look-alikes exercised")
	# The authored cave portal must have exactly one floor owner, while the
	# raised thorn and the low scripted thorn retain their source behavior.
	for pair in [[277,2],[192,5]]:
		var owners := 0
		for e in game.fp_world.background_sprites(pair[0],0):
			if int(e.get("index",0))==pair[1]: owners+=1
		check(owners==1,"one active ground owner %s got%d" % [pair,owners])
	print("KNOWN_GROUND_FAILURES ",known_failures)
	for failure in failures: print("FAIL ",failure)
	game.queue_free()
	await process_frame
	print("GROUND DETAILS PASS" if failures.is_empty() else "GROUND DETAILS FAIL")
	quit(0 if failures.is_empty() else 1)
