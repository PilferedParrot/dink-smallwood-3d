extends SceneTree

var game
var failures: Array = []
var samples := 0
var crossings := 0
var rejected := 0
var grids := 0
var report_path := ""
var host_path := "res://../tests/collision_survey_host.gd"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
		if arg.begins_with("--host="): host_path = arg.trim_prefix("--host=")
	_run.call_deferred()

func escapes(p: Vector2) -> bool:
	# One blocked direction is normal. A trap has no move at any normal/sprint
	# step size, including diagonal input through the actual axis movement code.
	for step in [1.0,1.75,2.7125]:
		for d in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized(),Vector2(1,1).normalized()]:
			game.entities[1].x = p.x; game.entities[1].y = p.y
			game._move_entity(1,d*step)
			if game._position2(1).distance_to(p) > 0.001: return true
	return false

func _run() -> void:
	game = load(host_path).new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	var screens: Array[int] = []
	for key in game.world.screens:
		if not game.world.screens[key].get("indoor",false): screens.append(int(key))
	screens.sort()
	for n in screens:
		game.load_map(n,false)
		var exits: Array = []
		for y in range(0,400,5):
			exits.append([Vector2(21,y),Vector2(-2,0)])
			exits.append([Vector2(619,y),Vector2(2,0)])
		for x in range(20,620,5):
			exits.append([Vector2(x,1),Vector2(0,-2)])
			exits.append([Vector2(x,399),Vector2(0,2)])
		for entry in exits:
			var p: Vector2 = entry[0]
			if game._blocked(p,1): continue
			samples += 1
			game.entities[1].x=p.x; game.entities[1].y=p.y
			game._move_entity(1,entry[1])
			var destination: Dictionary = game._edge_destination(game._position2(1))
			var target: int = destination.screen
			if target == n:
				rejected += 1
				if not escapes(game._position2(1)): failures.append({"kind":"rejected_trap","source":n,"p":[p.x,p.y]})
				continue
			if not game.world.screens.has(str(target)) or game.world.screens[str(target)].get("indoor",false): continue
			crossings += 1
			game.load_map(target,false)
			var q: Vector2 = destination.position
			if not escapes(q): failures.append({"kind":"landing_trap","source":n,"target":target,"p":[q.x,q.y]})
			game.load_map(n,false)
		# Every ordinary walkable 10px grid point. No placed point inside a solid
		# is counted as reachable; subpixel boundaries are covered by input cases.
		for y in range(0,400,10):
			for x in range(20,620,10):
				var p := Vector2(x,y)
				if game._blocked(p,1): continue
				grids += 1
				if not escapes(p): failures.append({"kind":"grid_trap","source":n,"p":[p.x,p.y]})
	var result := {"screens":screens.size(),"edge_samples":samples,"crossings":crossings,"rejected":rejected,"grid_samples":grids,"failures":failures,"fixture":"vision0 editor layer; no startup scripts; 5px edge spacing, 10px grid"}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	print("FPS COLLISION SWEEP screens=%d edge_samples=%d crossings=%d rejected=%d grid=%d traps=%d" % [screens.size(),samples,crossings,rejected,grids,failures.size()])
	game.vm.cancel_all()
	game.free()
	quit(0 if failures.is_empty() else 1)
