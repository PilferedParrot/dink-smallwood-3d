extends SceneTree

const GAME = preload("res://scripts/fps_game.gd")
var failures: Array[String] = []

class ScriptGame extends GAME:
	var arrival_checked := false
	var arrival_visible := false
	var arrived_at := Vector2.ZERO
	func _dialogue(text: String, speaker: int, context: Dictionary, binding: String = "say_stop") -> int:
		if str(context.get("script","")) == "s1-bul" and "lookie" in text:
			arrival_checked=true
			arrived_at=_position2(speaker)
			var visual: Node3D=visuals.get(speaker)
			arrival_visible=is_instance_valid(visual) and visual.get_node_or_null("Model") is Sprite3D and float(visual.get_meta("height",0))>1.0 and not visual.get_meta("seam_hidden",false)
		return await super._dialogue(text,speaker,context,binding)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text);push_error(text)

func _run() -> void:
	var game=ScriptGame.new();game.test_mode=true;root.add_child(game)
	await process_frame
	await game._new_game();await create_timer(0.5).timeout
	game.vm.cancel_all();game.ui.close_menu()
	# Explicit quest/item/position fixture skips progression; actual mouse
	# input runs item-pig.use, which creates and moves Milder through s1-bul.
	game.vm.globals["story"]=1;game.vm.globals["pig_story"]=0
	game.items.append({"script":"item-pig","name":"Pig Feed","seq":437,"frame":1})
	game._equip(game.items.size()-1,false);game.load_map(407,true)
	game.entities[1].x=320.0;game.entities[1].y=270.0
	game.entities[1].frozen=false;game.entities[1].nocontrol=0
	game.fps_yaw=0.0;game.fps_pitch=-.08;game._sync_fps_camera()
	game.playing=true;game.changing=false
	Engine.time_scale=8.0
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;Input.parse_input_event(event)
	for _i in 2: await physics_frame
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false;Input.parse_input_event(event)
	await create_timer(35.0).timeout
	check(game.arrival_checked,"The real feed script reaches the first Milder line")
	check(game.arrival_visible,"Milder spawned beyond the screen retains original sprite geometry when he walks in")
	check(absf(game.arrived_at.x-542.0)<1.1 and game.arrived_at.y>330.0,"Original diagonal entry movement is preserved: %s" % game.arrived_at)
	check(int(game.vm.globals.get("pig_story",0))==1,"Original Milder interaction completes")
	game.vm.cancel_all();game.queue_free();await process_frame
	print("FPS MILDER SCRIPT PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
