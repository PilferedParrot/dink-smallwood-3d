extends SceneTree
# Source-map construction fixture; script data replaced, progression skipped.
# FreeDink109.6 game_engine.cpp:710-721 constructs a fresh screen script;
# force_vision attaches its caller1000 before rebuilding (bindings:1321-1326).
const GAME=preload("res://scripts/fps_game.gd")
class WaitGame extends GAME:
	signal release_script_wait
	var waiting := 0
	func dink_call(command: String,args: Array,context: Dictionary) -> Variant:
		if command.to_lower()=="wait" and context.get("script","") in ["screen-instance-control","screen-victim"]:
			waiting+=1
			await release_script_wait
			return 0
		return await super.dink_call(command,args,context)
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func ref(name: String) -> Dictionary: return {"kind":"ref","name":name}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	var game=WaitGame.new(); game.test_mode=true; root.add_child(game); await process_frame
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
	# The explicit script-wait barrier makes the cancellation point independent
	# of wall-clock scheduling. Only these synthetic fixture scripts use it.
	for frame in range(60):
		if game.waiting==1: break
		await process_frame
	check(game.waiting==1,"Caller reaches its controlled wait after screen construction")
	game.vm.globals.victim_tail=0
	game.vm.story.scripts["screen-victim"]={"procedures":{"main":{"code":[
		{"op":"call","name":"wait","args":[literal(20)]},
		{"op":"inc","target":"&victim_tail","value":literal(1)}]}}}
	game.vm.run("screen-victim","main",0,true)
	for frame in range(60):
		if game.waiting==2: break
		await process_frame
	check(game.waiting==2,"Ordinary screen victim also reaches its controlled wait")
	game.vm.cancel_screen_tasks()
	check(game.vm._live_tasks.size()==1,"Screen cancellation retains only the force_vision caller")
	game.release_script_wait.emit()
	for frame in range(60):
		if game.vm._live_tasks.is_empty(): break
		await process_frame
	check(game.vm.globals.victim_tail==0,"Ordinary screen task tail is cancelled across the same boundary")
	check(game.vm.globals.constructor_entries==2,"Same screen source is constructed twice across force_vision")
	check(game.vm.globals.constructor_tails==1,"Fresh screen constructor does not cancel the existing caller's tail")
	check(game.vm.globals.get("caller_owner")==1000,"force_vision caller retains source pseudo-sprite1000 ownership")
	check(game.vm.globals.get("caller_local")==17,"Rebuilt screen's independent locals cannot overwrite caller locals")
	check(game.vm._live_tasks.is_empty(),"Both screen constructors finish without stacked continuations")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("SCREEN SCRIPT INSTANCE PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
