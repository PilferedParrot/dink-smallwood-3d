extends SceneTree

const HOST = preload("res://../tests/collision_survey_host.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); push_error(text)

func _run() -> void:
	# Synthetic editor fixture: no renderer/startup/progression. This isolates
	# diagonal geometry and world-coordinate continuity from authored scenery.
	var game = HOST.new()
	game.world = {"screens":{},"hardness":{"tile_defaults":[],"masks_rle":[]}}
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.vm = game.VM.new(game); game.vm.load_story()
	var tiles: Array = []
	for _i in 96: tiles.append({"tile":0,"hard":0})
	for dz in [-1,0,1]:
		for dx in [-1,0,1]: game.world.screens[str(439+dx+32*dz)]={"tiles":tiles.duplicate(true),"sprites":[],"indoor":false}
	for dx in [-1,1]:
		for dy in [-1,1]:
			var p := Vector2(20.5 if dx < 0 else 619.5,0.5 if dy < 0 else 399.5)
			var delta := Vector2(dx,dy)*2.0
			var target: int = 439+dx+dy*32
			game.load_map(439,false)
			game.entities[1].x=p.x; game.entities[1].y=p.y
			game._move_entity(1,delta)
			var exit: Dictionary=game._edge_destination(game._position2(1))
			var expected: Vector2=p+delta-Vector2(dx*600,dy*400)
			check(exit.screen == target and exit.position.distance_to(expected)<0.001,"Clear corner %s,%s enters diagonal neighbor with exact coordinates" % [dx,dy])
			# A solid covering the landing pixel of the corner crossing (a mover is a point: nothing wider is needed).
			var at := Vector2(619.0 if dx < 0 else 21.0,399.0 if dy < 0 else 1.0)
			game.world.screens[str(target)].sprites=[{"index":1000,"seq":174,"frame":1,"x":at.x,"y":at.y,"hard":0,"hardbox":[-1.5,-1.5,1.5,1.5],"size":100,"type":1,"vision":0}]
			game.survey_states.clear(); game.load_map(439,false)
			game.entities[1].x=p.x; game.entities[1].y=p.y
			game._move_entity(1,delta)
			exit=game._edge_destination(game._position2(1))
			check(exit.screen != target,"Diagonal neighbor hardness prevents corner tunneling %s,%s" % [dx,dy])
			game.world.screens[str(target)].sprites=[]; game.survey_states.clear()
	game.vm.cancel_all(); game.free()
	print("FPS COLLISION CORNERS PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
