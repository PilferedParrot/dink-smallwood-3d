extends SceneTree
# Source-map construction fixture; script data replaced, progression skipped.
# FreeDink109.6 game_engine.cpp:710-721 constructs a fresh screen script;
# force_vision attaches its caller1000 before rebuilding (bindings:1321-1326).
const GAME=preload("res://scripts/fps_game.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func ref(name: String) -> Dictionary: return {"kind":"ref","name":name}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	var game=GAME.new(); game.test_mode=true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.load_map(439,false)
	game.vm.globals.constructor_entries=0; game.vm.globals.constructor_tails=0
	game.world.screens["439"].script="screen-instance-control"
	game.vm.story.scripts["screen-instance-control"]={"procedures":{"main":{"code":[
		{"op":"inc","target":"&constructor_entries","value":literal(1)},
		{"op":"set","target":"&private_value","expr":literal(17),"declare":"int"},
		{"op":"if","condition":{"kind":"binary","op":"==","left":ref("&constructor_entries"),"right":literal(1)},"then":[
			{"op":"call","name":"force_vision","args":[literal(2)]},
			{"op":"call","name":"wait","args":[literal(20)]},
			{"op":"set","target":"&caller_owner","expr":ref("&current_sprite")},
			{"op":"set","target":"&caller_local","expr":ref("&private_value")},
			{"op":"inc","target":"&constructor_tails","value":literal(1)}],"else":[
			{"op":"set","target":"&private_value","expr":literal(99)}]}]}}}
	game.load_map(439)
	await create_timer(0.1).timeout
	check(game.vm.globals.constructor_entries==2,"Same screen source is constructed twice across force_vision")
	check(game.vm.globals.constructor_tails==1,"Fresh screen constructor does not cancel the existing caller's tail")
	check(game.vm.globals.get("caller_owner")==1000,"force_vision caller retains source pseudo-sprite1000 ownership")
	check(game.vm.globals.get("caller_local")==17,"Rebuilt screen's independent locals cannot overwrite caller locals")
	check(game.vm._live_tasks.is_empty(),"Both screen constructors finish without stacked continuations")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("SCREEN SCRIPT INSTANCE PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
