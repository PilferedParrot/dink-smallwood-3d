extends SceneTree

class TickProbe extends Node:
	signal tick_done
	func _physics_process(_delta: float) -> void: tick_done.emit()

# Observers never call a push procedure: every invocation comes from the real
# keyboard/controller update. These setups are scenarios, not campaign saves.
class ObservedFPS extends "res://scripts/fps_game.gd":
	var pushes: Array = []
	func _run_event(id: int, event: String) -> void:
		var script := str(entities[id].get("script",""))
		if event == "push" and not vm._procedure_code(script,"push").is_empty():
			pushes.append({"script":script,"id":id,"dir":entities[1].dir,"editor":entities[id].get("editor_num",0)})
		super._run_event(id,event)
class Observed2D extends "res://scripts/game.gd":
	var pushes: Array = []
	var touches: Array = []
	func _run_event(id: int, event: String) -> void:
		var script := str(entities[id].get("script",""))
		if event == "touch": touches.append({"id":id,"script":script})
		if event == "push" and not vm._procedure_code(script,"push").is_empty():
			pushes.append({"script":script,"id":id,"dir":entities[1].dir,"editor":entities[id].get("editor_num",0)})
		super._run_event(id,event)
var game
var failures: Array[String] = []
var records: Array = []
var report_path := ""
var rock_only := false
var review_only := false
var corner_only := false
var tick_probe: TickProbe

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
		if arg == "--rock-only": rock_only=true
		if arg == "--review-only": review_only=true
		if arg == "--corner-only": corner_only=true
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message);push_error(message)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func ticks(frames: int) -> void:
	for i in frames: await tick_probe.tick_done

func hold(codes: Array, frames: int) -> void:
	for code in codes: key(code,true)
	await ticks(frames)
	for code in codes: key(code,false)
	await ticks(1)

func prepare(screen: int, vision: int = 0) -> void:
	await game._new_game();game.vm.cancel_all();game.ui.cancel_speech();game.ui.close_menu()
	game.vm.globals.merge({"vision":vision,"strength":4,"rock_placement":0,"story":0,"caveguy":0},true)
	game.load_map(screen,false);game.vm.cancel_all()
	game.entities[1].nocontrol=0;game.entities[1].frozen=false
	game.playing=true;game.changing=false;game.warp_cooldown=0.0;game.attack_cooldown=0.0
	game.pushes.clear()

func place(at: Vector2, yaw: float = 0.0) -> void:
	game.entities[1].x=at.x;game.entities[1].y=at.y
	if game is ObservedFPS:
		game.fps_yaw=yaw;game.fps_pitch=-0.08;game._sync_fps_camera()

func target(script: String) -> int:
	for id in game.entities:
		if game.entities[id].get("script","")==script: return id
	return 0

func record(label: String) -> void:
	records.append({"label":label,"screen":game.current_screen,"player":game.entities[1].duplicate(true),
		"pushes":game.pushes.duplicate(true),"rock_placement":game.vm.globals.get("rock_placement",0),
		"dialogue":game.dialogue_log.duplicate(true)})

func rock_case(label: String, forward: bool = false) -> void:
	await prepare(277)
	place(Vector2(225,181),-PI/2.0 if forward else 0.0)
	await hold([KEY_W if forward else KEY_D],120)
	# The original rock move_stop travels65px at25px/s AFTER the delay.
	# Waiting lets that actual coroutine complete; it never injects state.
	await ticks(180)
	record(label)
	check(game.pushes.size()==1 and game.pushes[0].script=="s1-roc",label+": exactly one real PUSH procedure")
	check(int(game.vm.globals.get("rock_placement",0))==1,label+": script sets rock_placement1")
	check(absf(float(game.entities[target("s1-roc")].x)-350.0)<1.0,label+": script finishes within existing mover tolerance of350")
	check(int(game.entities[1].dir)==6,label+": movement gives original east6")

func class_case(script: String, screen: int, vision: int) -> void:
	await prepare(screen,vision)
	var id:=target(script)
	check(id!=0,script+": actual source placement exists")
	if id==0:return
	var rect: Rect2=game._hard_rect(game.entities[id])
	var found:=false
	var chosen: Array=[]
	# Select a free approach to an original placement, without removing any
	# competing owner, changing hardness, or calling its event ourselves.
	for fraction in [0.5,0.25,0.75]:
		for approach in [
			[Vector2(rect.position.x-5.0,lerpf(rect.position.y,rect.end.y,fraction)),KEY_D],
			[Vector2(rect.end.x+5.0,lerpf(rect.position.y,rect.end.y,fraction)),KEY_A],
			[Vector2(lerpf(rect.position.x,rect.end.x,fraction),rect.end.y+5.0),KEY_W],
			[Vector2(lerpf(rect.position.x,rect.end.x,fraction),rect.position.y-5.0),KEY_S]]:
			var at: Vector2=approach[0]
			if not game._blocked(at,1):
				chosen=approach;found=true;break
		if found:break
	check(found,script+": at least one free real approach")
	if not found:return
	place(chosen[0]);await hold([chosen[1]],110);await ticks(35)
	record("original-"+script)
	var called:=false
	for event in game.pushes:
		if event.script==script:called=true
	check(called,script+": input dispatches actual source PUSH")
	var expected: String={"s1-h1-4":"This table must be bolted to the ground.","s2-idol":"Uh, darn thing won't budge!!","s3-rock":"Ugh, stupid rocks."}[script]
	var said:=false
	for line in game.dialogue_log:
		if expected in str(line):said=true
	check(said,script+": actual procedure produces its dialogue")
	if script=="s2-idol":
		# Nonblocking say permits repeated animation cycles while the same
		# cardinal input remains held; release ends the cycle immediately.
		game.pushes.clear()
		await hold([chosen[1]],180)
		check(game.pushes.size()>=2,"Held input repeats PUSH after animation completion")
		var count: int=game.pushes.size()
		await ticks(90)
		check(game.pushes.size()==count and int(game.entities[1].nocontrol)==0,"Released input stops repetition and releases control")
		record("repeat-and-release")

func tile_with_script_control() -> void:
	# Retain the original current-foot selection even when an anonymous mask,
	# rather than the scripted sprite, owns the collision. This deliberately
	# composed scenario uses an unmodified source PUSH procedure on a soft
	# sprite. It is not evidence of this placement in the original campaign.
	await prepare(378);place(Vector2(75,149.5))
	game.entities[900000]={"x":71.0,"y":149.5,"hardbox":[-2,-2,2,2],"size":100,
		"active":1,"hard":1,"script":"s2-idol","brain":0,"type":1}
	check(not game._blocked(game._position2(1),1),"Tile/script overlap starts on free ground")
	check(game._tile_hardness(Vector2(75,148.625))==1 and game._blocking_sprite(Vector2(75,148.625),1)==0,
		"Anonymous tile alone owns overlap scenario's blocked next step")
	await hold([KEY_W],60);record("tile-plus-soft-script-current-foot")
	check(not game.pushes.is_empty() and game.pushes[0].script=="s2-idol","Current foot selects a soft scripted sprite despite tile-owned blocking")
	check(game.pushes.size()==1,"A single push animation dispatches an overlapping target only once")
	await prepare(378);place(Vector2(75,149.5))
	# Reverse insertion proves source-index order, rather than dictionary order.
	for id in [900001,900000]:
		game.entities[id]={"x":75.0,"y":149.5,"hardbox":[-2,-2,2,2],"size":100,
			"active":1,"hard":1,"script":"s2-idol","brain":0,"type":1}
	await hold([KEY_W],60);record("all-matches-in-index-order")
	check(game.pushes.size()==2 and game.pushes[0].id==900000 and game.pushes[1].id==900001,
		"Every matching candidate runs once, in ascending sprite-index order")
	await prepare(590,1);place(Vector2(258,258))
	# Source selection boxes for editors4/11 overlap here. This is a labelled
	# scenario in the clearance band: input exercises dispatch, not reachability.
	await hold([KEY_D],60);record("original-overlap-draw-rank")
	check(game.pushes.size()==2 and game.pushes[0].editor==11 and game.pushes[1].editor==4,
		"Real overlapping rocks dispatch by original draw rank, not native entity id")

func corner_case() -> void:
	# North-west of the raw box, SE motion keeps pressure on both faces.
	# NE motion would brush the corner and leave before the source delay.
	await prepare(277);place(Vector2(234.25,170.25),-3.0*PI/4.0)
	var started: Vector2=game._position2(1)
	await hold([KEY_W],60);record("fps-true-corner")
	check(game._position2(1).is_equal_approx(started),"The corner control sustains blocked contact on both axes for60 ticks")
	check(game.pushes.is_empty(),"A true raw-box corner retains the original diagonal exclusion")

func review_cases() -> void:
	# Original rock geometry; speed1 keeps a40-degree tangential approach on
	# its24px west face long enough for the source delay. No box enlargement.
	for angle in [10,20,30,40]:
		await prepare(277)
		game.entities[1].speed=1
		place(Vector2(234.25,194),-PI/2.0+deg_to_rad(float(angle)))
		await hold([KEY_W],60);await ticks(180)
		record("fps-face-%d-degrees" % angle)
		check(game.pushes.size()==1 and game.pushes[0].dir==6 and int(game.vm.globals.rock_placement)==1,
			"FPS west-face contact at%d degrees pushes east" % angle)
	await corner_case()
	# Composed DinkC fixture: real PUSH freezes, waits, marks completion and
	# unfreezes without moving the blocker. It exposes repeat cadence directly.
	await prepare(277);place(Vector2(234.25,181))
	game.vm.story.scripts["push-freeze-regression"]={"procedures":{"push":{"code":[
		{"op":"call","name":"freeze","args":[{"kind":"literal","value":1}]},
		{"op":"call","name":"wait","args":[{"kind":"literal","value":800}]},
		{"op":"set","target":"&rock_placement","expr":{"kind":"binary","op":"+","left":{"kind":"ref","name":"&rock_placement"},"right":{"kind":"literal","value":1}}},
		{"op":"call","name":"unfreeze","args":[{"kind":"literal","value":1}]}]}}}
	game.entities[target("s1-roc")].script="push-freeze-regression"
	key(KEY_D,true)
	for i in 180:
		await ticks(1)
		if int(game.vm.globals.rock_placement)>=1:break
	await ticks(2)
	record("freeze-script-repeat")
	check(game.pushes.size()>=2,"Held contact repeats immediately after a freeze-using PUSH releases control")
	key(KEY_D,false);await ticks(1)
	game.vm.cancel_all();game.queue_free();await process_frame
	game=Observed2D.new();root.add_child(game);await process_frame
	await prepare(277)
	var hole:=target("s1-hole")
	check(hole!=0,"Original cave touch target exists")
	if hole!=0:
		place(game._hard_rect(game.entities[hole]).get_center())
		game.entities[hole].touch_cooldown=0.0
		key(KEY_SPACE,true);await ticks(1);key(KEY_SPACE,false)
		record("2d-touch-during-swing")
		check(int(game.entities[1].nocontrol)!=0 and game.attack_cooldown>=0.2,"The2D control is an actual physical-key attack swing")
		check(game.touches.is_empty(),"2D touch retains the baseline control gate during a real attack swing")

func _run() -> void:
	# The SceneTree physics_frame signal precedes game updates. Assertions
	# instead observe completed ticks, as the campaign bridge already does.
	tick_probe=TickProbe.new();tick_probe.process_physics_priority=100;root.add_child(tick_probe)
	game=ObservedFPS.new();root.add_child(game);await process_frame
	if corner_only:
		await corner_case()
	elif review_only:
		await review_cases()
	else:
		await rock_case("fps-strafe-east")
	if not rock_only and not review_only and not corner_only:
		await rock_case("fps-forward-east",true)
		for fixture in [["s1-h1-4",1,0],["s2-idol",579,0],["s3-rock",590,1]]:
			await class_case(fixture[0],fixture[1],fixture[2])
		# No PUSH procedure: collision and push animation still work, but no
		# script runs and quest globals do not change.
		await prepare(277);place(Vector2(225,181))
		game.entities[target("s1-roc")].script=""
		await hold([KEY_D],120);record("hard-without-procedure")
		check(game.pushes.is_empty() and game.entities[1].x<235.0,"Hard sprite without PUSH does nothing new")
		var stopped: Vector2=game._position2(1)
		await hold([KEY_A],12)
		check(game._position2(1).x<stopped.x-10.0 and int(game.entities[1].nocontrol)==0,
			"A wall without PUSH releases animation control and permits ordinary escape")
		# Release is a reset: two short contacts must not add to600ms.
		await prepare(277);place(Vector2(234.25,181))
		await hold([KEY_D],20);await ticks(20);await hold([KEY_D],20)
		record("short-contact-release-reset")
		check(game.pushes.is_empty(),"Contacts under600ms do not accumulate across release")
		await prepare(277);place(Vector2(234.25,181))
		key(KEY_D,true);await ticks(37)
		check(game.pushes.is_empty(),"Strict source delay does not dispatch at exactly600ms after first contact")
		await ticks(2)
		check(game.pushes.size()==1,"Continued contact beyond600ms dispatches PUSH")
		key(KEY_D,false);await ticks(1);record("strict-delay-boundary")
		await prepare(378);place(Vector2(75,160))
		await hold([KEY_W],120);record("tile-only")
		check(game.pushes.is_empty() and game.entities[1].y>149.0,"Anonymous tile strip dispatches no script")
		await tile_with_script_control()
		await prepare(277);place(Vector2(225,181))
		await hold([KEY_D,KEY_W],120);record("fps-brief-sliding-contact")
		check(game.pushes.is_empty(),"Brief sliding contact does not complete the PUSH delay")
		game.vm.cancel_all();game.queue_free();await process_frame
		game=Observed2D.new();root.add_child(game);await process_frame
		await rock_case("2d-east")
		await prepare(277);place(Vector2(225,181))
		await hold([KEY_D,KEY_W],120);record("2d-diagonal")
		check(game.pushes.is_empty(),"Original2D diagonal keyboard input cannot start PUSH")
		game.vm.cancel_all();game.queue_free();await process_frame
		game=ObservedFPS.new();root.add_child(game);await process_frame
		await review_cases()
	game.vm.cancel_all();game.queue_free();await process_frame
	if not report_path.is_empty():
		var f:=FileAccess.open(report_path,FileAccess.WRITE)
		f.store_string(JSON.stringify({"setup":"Labelled scenarios: source maps, startup skipped; no earned progression claimed", "records":records,"failures":failures},"  "));f.close()
	print("PUSH INPUT PASS" if failures.is_empty() else "PUSH INPUT FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
