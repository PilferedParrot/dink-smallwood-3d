extends SceneTree
const GAME = preload("res://scripts/game.gd")
var game
var failures: Array = []

func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(2.0).timeout
	check(int(game.vm.globals.get("story",0)) == 1,"Opening conversation advances story")
	var sack: int = await game.dink_call("sp",[52],{})
	check(sack>1,"Sack present in opening room")
	check(int(game.entities[sack].get("touch_damage",0)) == -1,"Sack script installs pickup")
	game.entities[1].x = game.entities[sack].x
	game.entities[1].y = game.entities[sack].y
	game.warp_cooldown = 0
	game._transitions()
	await process_frame
	check(game.items.any(func(item): return item.script == "item-pig"),"Touching sack gives pig feed")
	game.entities[1].x = 325
	game.entities[1].y = 398
	game.warp_cooldown = 0
	game._transitions()
	check(game.current_screen == 439,"Home exit follows original warp to village 439")
	game.vm.cancel_all()
	game.load_map(1,false)
	check(not game.entities.values().any(func(e): return int(e.get("editor_num",0)) == 52),"Collected feed stays collected on return")
	await game.dink_call("add_item",["item-sw1",438,3],{})
	await game._equip(game.items.size()-1,false)
	var strength: int = game.vm.globals.strength
	check(strength == 7,"Sword applies original +4 strength bonus")
	check(game._frame(71,1).get("path","").contains("sword"),"Sword replaces walking frames")
	for i in range(3):
		check(game._save_game("user://adventure-test.json"),"Can save equipped sword")
		check(game._load_game("user://adventure-test.json"),"Can reload equipped sword")
		check(int(game.vm.globals.strength) == strength,"Save/load does not stack sword stats")
	DirAccess.remove_absolute("user://adventure-test.json")
	game.vm.cancel_all()
	for number in game.world.screens:
		game.load_map(int(number),false)
		check(game.entities.has(1),"Player exists on screen "+str(number))
		await process_frame
	check(game.unknown.is_empty(),"No unknown commands during opening adventure")
	game.vm.cancel_all()
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("ADVENTURE PASS: opening quest, pickup persistence, original exit, equipment, repeated saves, all 644 screens")
	quit(0 if failures.is_empty() else 1)
