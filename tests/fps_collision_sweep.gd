extends SceneTree

var game
var failures: Array = []
var samples := 0
var crossings := 0
var rejected := 0
var grids := 0
var indoor_landings := 0
var indoor_landing_traps := 0
var only_sources: Array[int] = []
var edge_coverage := {
	"west": {"candidates":0,"walkable":0,"crossings":0,"rejected":0,"x_sum":0,"y_sum":0},
	"east": {"candidates":0,"walkable":0,"crossings":0,"rejected":0,"x_sum":0,"y_sum":0},
	"north": {"candidates":0,"walkable":0,"crossings":0,"rejected":0,"x_sum":0,"y_sum":0},
	"south": {"candidates":0,"walkable":0,"crossings":0,"rejected":0,"x_sum":0,"y_sum":0},
}
var report_path := ""
var host_path := "res://../tests/collision_survey_host.gd"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sources="):
			for value in arg.trim_prefix("--sources=").split(",",false): only_sources.append(int(value))
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
	if not only_sources.is_empty():
		var filtered: Array[int] = []
		for n in screens:
			if n in only_sources: filtered.append(n)
		screens = filtered
	for n in screens:
		game.load_map(n,false)
		var exits: Array = []
		# Visit every integer source cell on each boundary independently.
		# The source-edge cells x=21/619 and y=1/399 leave the map after
		# the same two-pixel input used by the existing transition survey.
		for y in range(400):
			exits.append(["west",Vector2(21,y),Vector2(-2,0)])
			exits.append(["east",Vector2(619,y),Vector2(2,0)])
		for x in range(20,620):
			exits.append(["north",Vector2(x,1),Vector2(0,-2)])
			exits.append(["south",Vector2(x,399),Vector2(0,2)])
		for entry in exits:
			var side: String = entry[0]
			var p: Vector2 = entry[1]
			var coverage: Dictionary = edge_coverage[side]
			coverage.candidates += 1
			coverage.x_sum += int(p.x)
			coverage.y_sum += int(p.y)
			if game._blocked(p,1): continue
			coverage.walkable += 1
			samples += 1
			game.entities[1].x=p.x; game.entities[1].y=p.y
			game._move_entity(1,entry[2])
			var destination: Dictionary = game._edge_destination(game._position2(1))
			var target: int = destination.screen
			if target == n:
				rejected += 1
				coverage.rejected += 1
				if not escapes(game._position2(1)): failures.append({"kind":"rejected_trap","source":n,"p":[p.x,p.y]})
				continue
			if not game.world.screens.has(str(target)): continue
			var indoor: bool = bool(game.world.screens[str(target)].get("indoor",false))
			if indoor: indoor_landings += 1
			crossings += 1
			coverage.crossings += 1
			game.load_map(target,false)
			var q: Vector2 = destination.position
			if not escapes(q):
				if indoor: indoor_landing_traps += 1
				failures.append({"kind":"landing_trap","source":n,"target":target,"indoor":indoor,"p":[q.x,q.y]})
			game.load_map(n,false)
		# Every ordinary walkable 10px grid point. No placed point inside a solid
		# is counted as reachable; subpixel boundaries are covered by input cases.
		for y in range(0,400,10):
			for x in range(20,620,10):
				var p := Vector2(x,y)
				if game._blocked(p,1): continue
				grids += 1
				if not escapes(p): failures.append({"kind":"grid_trap","source":n,"p":[p.x,p.y]})
	var result := {"host":host_path,"requested_sources":only_sources,"screens":screens.size(),"edge_coverage":edge_coverage,"edge_samples":samples,"crossings":crossings,"rejected":rejected,"grid_samples":grids,"indoor_landings":indoor_landings,"indoor_landing_traps":indoor_landing_traps,"failures":failures,"fixture":"vision0 editor layer; no startup scripts; outdoor source screens, all admitted target types; every 1px edge cell, 10px interior grid"}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	print("FPS COLLISION SWEEP screens=%d edge_samples=%d crossings=%d rejected=%d grid=%d traps=%d" % [screens.size(),samples,crossings,rejected,grids,failures.size()])
	game.vm.cancel_all()
	game.free()
	quit(0 if failures.is_empty() else 1)
