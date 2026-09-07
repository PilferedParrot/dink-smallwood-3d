extends SceneTree

const Game = preload("res://scripts/game.gd")

class FakeUI extends RefCounted:
	var modal := false
	var dialogue_mode := false
	var notices: Array[String] = []
	func notify(message: String) -> void:
		notices.append(message)

class FakeVM extends RefCounted:
	var globals: Dictionary = {}
	var calls: Array = []
	var procedures: Dictionary = {}
	func _procedure_code(script: String, procedure: String) -> Array:
		return procedures.get(script.to_lower()+":"+procedure.to_lower(),[])
	func run(script: String, procedure: String, sprite_id: int = 0) -> Variant:
		calls.append([script.to_lower(),procedure.to_lower(),sprite_id])
		if script.to_lower() == "lraise" and procedure.to_lower() == "raise":
			globals["level"] = int(globals.get("level",1))+1
			globals["lifemax"] = int(globals.get("lifemax",10))+3
			globals["strength"] = int(globals.get("strength",3))+1
		return 0

var failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _game() -> Node:
	var game := Game.new()
	game.ui = FakeUI.new()
	game.vm = FakeVM.new()
	game.vm.globals = {"life":20,"lifemax":20,"strength":10,"defense":2,"magic":1,"magic_level":0,"magic_cost":100,"level":1,"exp":0,"cur_weapon":0,"cur_magic":0}
	game.entities = {1:{"x":100.0,"y":100.0,"dir":6,"brain":1,"active":1,"size":100,"seq":0,"pseq":0,"pframe":1,"frozen":false,"nocontrol":0}}
	game.sequences = {
		"10":{"frames":[{"delay":1},{"delay":1}]},
		"106":{"frames":[{"delay":75},{"delay":75}]}
	}
	return game

func _init() -> void:
	_test_animation_brains()
	_test_magic_charge_and_gate()
	_test_melee_context_and_defense()
	_test_enemy_touch_and_attack_callback()
	_test_bomb_damage_and_context()
	_test_level_threshold_and_script()
	if failures == 0: print("COMBAT PASS: brains, combat context, magic, and level flow")
	quit(1 if failures else 0)

func _test_animation_brains() -> void:
	var game = _game()
	game.entities[2] = {"active":1,"brain":5,"seq":10,"frame":2,"pseq":0,"pframe":1,"size":100,"anim_time":1.0}
	game._animate(2,0.1)
	_check(int(game.entities[2].active) == 1 and int(game.entities[2].brain) == 0,"brain 5 should retain its final frame")
	_check(int(game.entities[2].seq) == 0 and int(game.entities[2].pseq) == 10 and int(game.entities[2].pframe) == 2,"brain 5 final frame was not retained")
	game.entities[3] = {"active":1,"brain":6,"seq":10,"frame":2,"pseq":10,"pframe":1,"size":100,"anim_time":1.0}
	game._animate(3,0.1)
	_check(int(game.entities[3].active) == 1 and int(game.entities[3].seq) == 10 and int(game.entities[3].frame) == 1,"brain 6 should loop")
	game.entities[4] = {"active":1,"brain":12,"brain_parm":110,"seq":0,"size":100}
	game._animate(4,1.0)
	_check(int(game.entities[4].active) == 0 and int(game.entities[4].size) == 110,"brain 12 should scale to its target and expire")
	game.free()

func _test_magic_charge_and_gate() -> void:
	var game = _game()
	game.magic_items = [{"script":"item-fb"}]
	game.vm.globals.cur_magic = 1
	game._cast()
	_check(game.vm.calls.is_empty(),"uncharged magic should not cast")
	game._animate(1,2.0)
	_check(int(game.vm.globals.magic_level) == 100,"magic gauge did not recharge at the engine tick rate")
	game._cast()
	_check(game.vm.calls == [["item-fb","use",1]],"charged equipped magic should invoke its use procedure")
	game.free()

func _test_melee_context_and_defense() -> void:
	var game = _game()
	game.items = [{"script":"item-fst"}]
	game.vm.globals.cur_weapon = 1
	game.vm.procedures["enemy:hit"] = [{"op":"return"}]
	game.entities[2] = {"x":125.0,"y":100.0,"active":1,"brain":9,"base_attack":-1,"touch_damage":0,"hitpoints":30,"defense":2,"script":"enemy","nohit":0,"size":100,"pseq":0,"pframe":1}
	game._attack()
	_check(int(game.entities[2].hitpoints) < 30 and int(game.entities[2].hitpoints) >= 22,"melee strength/defense damage is outside the original range")
	_check(int(game.vm.globals.enemy_sprite) == 1 and int(game.vm.globals.missle_source) == 1,"melee did not publish attacker context")
	_check(int(game.entities[2].get("target",0)) == 0,"non-attacking scenery/enemies should not acquire a target")
	_check(game.vm.calls.has(["enemy","hit",2]),"melee did not run the victim hit callback")
	game.free()

func _test_enemy_touch_and_attack_callback() -> void:
	var game = _game()
	game.vm.procedures["enemy:attack"] = [{"op":"return"}]
	game.vm.procedures["enemy:touch"] = [{"op":"return"}]
	game.entities[2] = {"x":100.0,"y":100.0,"active":1,"brain":9,"target":1,"base_walk":0,"base_attack":100,"touch_damage":8,"hitpoints":20,"speed":0,"distance":25,"script":"enemy","size":100,"pseq":0,"pframe":1,"noclip":1}
	game._update_ai(0.1)
	_check(int(game.vm.globals.life) == 14,"enemy contact must use touch_damage and player defense")
	_check(int(game.vm.globals.enemy_sprite) == 2 and int(game.entities[1].last_hit) == 2,"enemy contact did not publish source context")
	_check(game.vm.calls.has(["enemy","attack",2]) and game.vm.calls.has(["enemy","touch",2]),"enemy attack/touch callbacks did not run")
	game.free()

func _test_bomb_damage_and_context() -> void:
	var game = _game()
	game.entities[1].x = 200.0
	game.entities[1].y = 200.0
	game.entities[2] = {"x":100.0,"y":100.0,"active":1,"brain":9,"base_attack":100,"touch_damage":1,"hitpoints":30,"defense":2,"script":"","nohit":0,"size":100,"pseq":0,"pframe":1,"noclip":1}
	game.entities[3] = {"x":100.0,"y":100.0,"active":1,"brain":17,"brain_parm":1,"brain_parm2":0,"strength":10,"range":30,"speed":0,"dir":2,"script":"","seq":10,"frame":1,"size":100,"pseq":10,"pframe":1,"noclip":1}
	game._update_ai(0.01)
	_check(int(game.entities[2].hitpoints) < 30,"brain 17 explosion did not damage a nearby target")
	_check(int(game.vm.globals.missile_target) == 2 and int(game.vm.globals.missle_source) == 3,"explosion did not publish missile target/source")
	_check(int(game.entities[2].target) == 1,"explosion did not aggro the damaged enemy toward its owner")
	game.entities[3].frame = 2
	game.entities[3].anim_time = 1.0
	game._animate(3,0.1)
	_check(int(game.entities[3].active) == 0,"brain 17 should expire with its animation")
	game.vm.procedures["arrow:damage"] = [{"op":"return"}]
	game.vm.procedures["target:hit"] = [{"op":"return"}]
	game.entities[4] = {"x":0.0,"y":0.0,"active":1,"brain":0,"base_attack":-1,"touch_damage":0,"hitpoints":20,"defense":1,"script":"target","nohit":0,"size":100,"pseq":0,"pframe":1}
	game.entities[5] = {"x":0.0,"y":0.0,"active":1,"brain":11,"brain_parm":1,"brain_parm2":0,"strength":8,"range":10,"speed":0,"dir":6,"script":"arrow","seq":10,"frame":1,"size":100,"pseq":10,"pframe":1,"noclip":1}
	game._update_ai(0.01)
	_check(int(game.entities[4].hitpoints) < 20,"brain 11 projectile did not damage a dynamic hard target")
	_check(game.vm.calls.has(["arrow","damage",5]) and game.vm.calls.has(["target","hit",4]),"projectile damage/hit callbacks did not receive the collision")
	game.free()

func _test_level_threshold_and_script() -> void:
	var game = _game()
	game.vm.globals.level = 2
	game.vm.globals.exp = 450
	game._check_level()
	_check(int(game.vm.globals.exp) == 50,"level 2 should require 400 experience")
	_check(int(game.vm.globals.level) == 3 and game.vm.calls.has(["lraise","raise",1]),"level-up must run the campaign's attribute-choice script")
	game.free()
