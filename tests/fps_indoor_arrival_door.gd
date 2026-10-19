# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
# Labelled static, unearned overshoot QUERY fixture using real66→34 door
# geometry. Normal ticks remain47px from the band and load remaps355→348.
const HOST = preload("res://../tests/collision_survey_host.gd")
class UIStub extends RefCounted:
	var modal := false
var game
var presentation
var failures: Array = []
var report_path := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok: failures.append(why)
func state() -> String:
	return JSON.stringify({"screen":game.current_screen,"entities":game.entities,"sprites":game.footprint_sprites,"polys":game.screen_footprints,"tiles":game.footprint_tiles,"interior":presentation.interior})
func _run() -> void:
	game = HOST.new(); game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game); game.vm.load_story(); game.ui = UIStub.new()
	presentation = preload("res://scripts/fp_world.gd").new(); presentation.setup(game); game.fp_world = presentation
	game.playing = true; game.changing = false; game.locked = false
	game.entities = {1:{"x":320.0,"y":0.0,"frozen":false,"disabled":0,"nocontrol":0}}
	game.load_map(34,false); presentation.interior = true; game.warp_cooldown = 1.0
	var target_point := Vector2(320,355); var target_from := Vector2(320,356)
	var target_owner: bool = game._inactive_door_blocks(target_point,target_from)
	check(target_owner,"real bar door16 owns the355<-356 inactive clearance query")
	var remapped: Vector2 = presentation.solids.map_player_door_position(34,target_point,4.0)
	check(remapped == Vector2(320,348),"distinguish queried band from actual load remapping")
	var doors: Array = []
	for key in game.world.screens:
		var n := int(key)
		if not bool(game.world.screens[key].indoor) or not presentation.solids.walls_fitted(n): continue
		for ex in presentation.solids.exits(n):
			doors.append({"screen":n,"editor_index":ex.editor_num,"x0":ex.x0,"x1":ex.x1,"zinner":ex.zinner})
	check(doors.size() == 7 and doors.all(func(ex): return float(ex.zinner) == 352.0),"all7 fitted doors remain47px from ordinary arrival strips")
	var records: Array = []
	for source_indoor in [true,false]:
		# Second case labels a source flag variation, so stale source renderer
		# state cannot suppress checking an indoor TARGET.
		game.world.screens["66"].indoor = source_indoor
		presentation.interior_cache.erase(66)
		for mode in ["cooldown","active-unrendered","inactive-entity","invalid-warp"]:
			game.survey_states.erase(34)
			var arrival: Dictionary = game.neighbour_arrival_state(34).duplicate(true)
			for e in arrival.sprites:
				if int(e.get("editor_num",0)) != 16: continue
				check(not bool(e.get("fps_portal",false)),"arrival cache intentionally has no rendering-added fps_portal flag")
				if mode == "inactive-entity": e.active = 0
				if mode == "invalid-warp": e.warp.map = 999
			game.survey_states[34] = arrival
			game.load_map(66,false); presentation.interior = source_indoor
			game.warp_cooldown = 1.0 if mode == "cooldown" else 0.0
			var before := state()
			var cache_before := JSON.stringify(game.survey_states[34])
			var actual: bool = game._blocked(Vector2(320,-45),1,Vector2(320,-44))
			var reverse: bool = game._blocked(Vector2(320,-44),1,Vector2(320,-45))
			var band_escape: bool = game._blocked(Vector2(320,-45),1,Vector2(320,-46))
			var plane_cross: bool = game._blocked(Vector2(320,-49),1,Vector2(320,-47))
			var expected: bool = mode != "active-unrendered"
			check(actual == expected,"target door query %s source_indoor%s" % [mode,source_indoor])
			check(not reverse and not band_escape,"target door allows retreat from boundary and within clearance %s" % mode)
			check(plane_cross == expected,"translated plane crossing matches target activity %s" % mode)
			check(before == state(),"incoming door check restores source state %s" % mode)
			check(cache_before == JSON.stringify(game.survey_states[34]),"incoming query never mutates target cache %s" % mode)
			records.append({"source_indoor":source_indoor,"mode":mode,"blocked":actual,"expected":expected,"reverse_blocked":reverse,"band_escape_blocked":band_escape,"plane_cross_blocked":plane_cross,"source_restored":before == state(),"cache_restored":cache_before == JSON.stringify(game.survey_states[34])})
	var cumulative: Array = []
	for active in [false,true]:
		game.survey_states.erase(34); game.load_map(66,false); presentation.interior = false
		game.warp_cooldown = 0.0 if active else 1.0
		game.entities[1].x = 320.0; game.entities[1].y = 1.0
		game._move_entity(1,Vector2(0,-58))
		var destination: Dictionary = game._edge_destination(game._position2(1))
		var endpoint: Vector2 = destination.position
		check(int(destination.screen) == 34,"cumulative fixture crosses the logical seam")
		check(endpoint.y == (343.0 if active else 356.0),"cumulative movement respects inactive target plane; active portal remains free")
		cumulative.append({"active":active,"source_endpoint":[game.entities[1].x,game.entities[1].y],"target_endpoint":[endpoint.x,endpoint.y]})
	var result := {"setup":"Static real geometry, injected large overshoot query; no earned progress or ordinary-tick failure claimed. Query34(320,355) from356, load remaps to348.","target_owner":target_owner,"actual_load_mapping":[remapped.x,remapped.y],"doors":doors,"cases":records,"cumulative_unearned_fixtures":cumulative,"failures":failures}
	if not report_path.is_empty():
		var f := FileAccess.open(report_path,FileAccess.WRITE); f.store_string(JSON.stringify(result,"  "))
	print("INDOOR ARRIVAL DOOR PASS" if failures.is_empty() else str(failures))
	game.stone_walls.fp_world = null; game.fp_world = null
	for member in ["buildings","rails","castle_doors","solids","fences","props","source_firs","source_interaction_body","mounted_posters","stone_walls"]: presentation.set(member,null)
	presentation = null; game.free(); quit(0 if failures.is_empty() else 1)
