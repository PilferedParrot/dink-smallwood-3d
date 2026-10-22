# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Cave terrain classes the survivors T6, T10 and T11 of the 0.3.4 mutant sweep left open (headless: pure functions, the
# Environment resource and the hard-pixel query need no renderer).
#   T6  : the outline walk over every way two bodies can meet at a corner (4 diagonals x 2 rect orders).
#   T10 : the Environment an arrival leaves, over outdoor -> interior -> outdoor -> interior on ONE resource (it outlives the scene).
#   T11 : a hard.dat pixel under a painted replacement gets no column; injected, because no shipped indoor screen has clear_tile_runs.
const HOST = preload("res://../tests/collision_survey_host.gd")
const FW := preload("res://scripts/fp_world.gd")
var failures: Array = []
var finished := 0

class ReplacingHost extends "res://../tests/collision_survey_host.gd":
	var replaced := {}
	func _tile_pixel_replaced(pos: Vector2) -> bool:
		return replaced.has(Vector2i(pos))

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

# Per face, where its picture starts along the outline loop it belongs to (the offset undone back to loop arc).
func face_starts(fw, rects: Array[Rect2i]) -> Array:
	var out: PackedFloat32Array = fw.terrain_outline_offsets(rects)
	var starts := []
	for i in rects.size():
		var r := rects[i]
		for slot in 4:
			var a := 1.0 if slot == 1 or slot == 2 else -1.0
			var along := float(r.position.y + (1 if slot == 0 else 0)) if slot < 2 else float(r.position.x + (1 if slot == 3 else 0))
			var centre := 200.0 if slot < 2 else 320.0
			var arc: float = out[i*4+slot]/fw.SCALE + a*along - a*centre
			var w := r.size.y if slot < 2 else r.size.x
			starts.append(roundi(arc) - ((w-1) if slot == 0 or slot == 3 else 0))
	starts.sort()
	return starts

func t6_pinch(fw) -> void:
	var a := Rect2i(100,100,10,10)
	var others := {"up-left": Rect2i(90,90,10,10), "up-right": Rect2i(110,90,10,10), "down-left": Rect2i(90,110,10,10), "down-right": Rect2i(110,110,10,10)}
	var one_loop := [0,10,20,30,40,50,60,70] # the walk went through the pinch: one figure-eight of 80 edges
	var two_loops := [0,0,10,10,20,20,30,30] # the walk closed the first square before the pinch: two loops of 40
	var chains := 0
	for name in others:
		for order in 2:
			var typed: Array[Rect2i] = []
			typed.append(a if order == 0 else others[name])
			typed.append(others[name] if order == 0 else a)
			var got := face_starts(fw, typed)
			check(got == one_loop or got == two_loops, "T6 %s order %d: the outline restarts mid-loop, face starts %s" % [name, order, got])
			if got == one_loop: chains += 1
	check(chains >= 2, "T6: no variant takes the pinch (%d chains): the branch is not exercised" % chains)
	finished += 1

func t10_environment() -> void:
	var game = HOST.new()
	var holder := WorldEnvironment.new()
	holder.environment = Environment.new()
	holder.environment.background_mode = Environment.BG_COLOR # what game.gd builds first
	holder.environment.background_color = Color("11241d")
	game.add_child(holder)
	var fw = FW.new()
	fw.host = game
	for step in [false, true, false, true]:
		fw.interior = step
		fw.configure_environment()
		var env: Environment = holder.environment
		var label := "T10 interior=%s" % step
		if step:
			check(env.background_mode == Environment.BG_COLOR, label + ": background mode %d" % env.background_mode)
			check(env.background_color == Color.BLACK, label + ": open edge colour %s, not black" % env.background_color)
			check(env.sky == null, label + ": keeps the outdoor sky")
			check(not env.fog_enabled, label + ": fog on indoors")
		else:
			check(env.background_mode == Environment.BG_SKY, label + ": background mode %d" % env.background_mode)
			check(env.sky != null, label + ": no sky outdoors")
			check(env.background_color != Color.BLACK, label + ": outdoor background is black")
	game.free()
	finished += 1

func t11_replaced_pixels() -> void:
	var game = ReplacingHost.new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	var fw = FW.new()
	fw.setup(game)
	fw.interior = true
	var tried := 0
	var checked := 0
	for key in game.world.screens:
		var n := int(key)
		if not bool(game.world.screens[key].indoor): continue
		game.current_screen = n
		game.replaced = {}
		var base: Array[Rect2i] = fw.terrain_wall_rects(game.world.screens[key])
		if base.is_empty(): continue
		tried += 1
		if tried > 6: break # six screens with columns: houses and caves alike
		# replace every pixel the first body covers: that body must vanish, the rest stay
		var target := base[0]
		for y in range(target.position.y, target.end.y):
			for x in range(target.position.x, target.end.x): game.replaced[Vector2i(x,y)] = true
		var after: Array[Rect2i] = fw.terrain_wall_rects(game.world.screens[key])
		var overlap := false
		for r in after:
			if r.intersects(target): overlap = true
		check(not overlap, "T11 screen %d: a replaced pixel still has a column (%s)" % [n, target])
		check(after.size() < base.size(), "T11 screen %d: replacing a whole body removed nothing (%d -> %d)" % [n, base.size(), after.size()])
		game.replaced = {}
		check(fw.terrain_wall_rects(game.world.screens[key]) == base, "T11 screen %d: unreplaced rects change between calls" % n)
		checked += 1
	check(checked >= 3, "T11: only %d screens with columns checked" % checked)
	game.free()
	finished += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fw = FW.new()
	t6_pinch(fw)
	t10_environment()
	t11_replaced_pixels()
	check(finished == 3, "only %d of 3 sections ran to their end" % finished)
	if failures.is_empty():
		print("TERRAIN CLASS PASS")
		quit(0)
	else:
		for f in failures: print("FAIL: ", f)
		print("TERRAIN CLASS FAIL")
		quit(1)
