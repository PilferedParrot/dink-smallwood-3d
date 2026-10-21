extends SceneTree
# Script-fixture with the ORIGINAL s1-brg2 talk (bridge troll, screen 404, force_vision(0) at its
# line 50); choice answered "Pay the toll", progression skipped. Another waiting screen script
# must be killed by the rebuild (FreeDink109.6 dinkc.cpp:872-892); the troll tail must finish.
const GAME=preload("res://scripts/fps_game.gd")
class TrollGame extends GAME:
	signal release_victim
	var tail: Array[String]=[]
	var victim_waiting := false
	func dink_call(command: String,args: Array,context: Dictionary) -> Variant:
		var who: String=str(context.get("script",""))
		if who=="fv-victim" and command.to_lower()=="wait":
			victim_waiting=true
			await release_victim
			return 0
		if who=="s1-brg2":
			if command in ["force_vision","unfreeze","kill_this_task"]: tail.append(command)
			if command=="choice": return 1
			if command in ["wait","say_stop","move_stop"]: return 0
		return await super.dink_call(command,args,context)
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func literal(value: Variant) -> Dictionary: return {"kind":"literal","value":value}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	var game=TrollGame.new(); game.test_mode=true; root.add_child(game); await process_frame
	await game._new_game(); game.vm.cancel_all(); game.load_map(404,false)
	game.world.screens["404"].script=""
	game.vm.globals.gold=500; game.vm.globals.victim_tail=0
	game.vm.story.scripts["fv-victim"]={"procedures":{"main":{"code":[
		{"op":"call","name":"wait","args":[literal(1)]},
		{"op":"inc","target":"&victim_tail","value":literal(1)}]}}}
	game.vm.run("fv-victim","main",8,true)
	for frame in range(60):
		if game.victim_waiting: break
		await process_frame
	check(game.victim_waiting,"Other screen script is waiting before the troll talks")
	await game.vm.run("s1-brg2","talk",5)
	check(game.tail.has("force_vision"),"Original troll script reaches force_vision")
	check(game.tail.slice(-2)==["unfreeze","kill_this_task"] or game.tail.slice(-1)==["kill_this_task"],"Troll tail beyond force_vision completes: %s" % str(game.tail))
	game.release_victim.emit()
	for frame in range(30): await process_frame
	check(game.vm.globals.victim_tail==0,"Other screen script's tail is killed by the troll's force_vision")
	check(int(game.vm.globals.get("story",0))==7,"Troll set story 7 before force_vision")
	game.vm.cancel_all(); game.queue_free(); await process_frame
	print("FORCE VISION TROLL PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
