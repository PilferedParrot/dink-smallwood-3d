# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Renderer dispatch and seam inventory; no scene, startup scripts, or player profile.
extends SceneTree

const HOST = preload("res://../tests/collision_survey_host.gd")
const WORLD = preload("res://scripts/fp_world.gd")

# This instrument records the pre-migration RC4 collision and rendering rules.
# Keep its basis independent of the production RC5 hooks being evaluated.
class BaselineHost extends "res://../tests/collision_survey_host.gd":
	func _sprite_hardbox_replaced(e: Dictionary) -> bool:
		return footprint_sprites.has(int(e.get("editor_num",0)))
	func _tile_pixel_replaced(_pos: Vector2) -> bool: return false
	func _additional_structure_blocked(_pos: Vector2, _from: Vector2) -> bool: return false

class BaselineWorld extends "res://scripts/fp_world.gd":
	func static_scenery(e: Dictionary) -> bool:
		return not e.get("runtime_created",false) and int(e.get("type",1)) == 1 and str(e.get("script","" )).is_empty() and int(e.get("brain",0)) == 0 and absf(float(e.get("size",100))-100.0) < 0.5

func polygon_runs(host, polys: Array) -> Array:
	var mask := PackedByteArray()
	mask.resize(640*400)
	for poly in polys:
		var bounds := Rect2(poly[0],Vector2.ZERO)
		for p in poly: bounds = bounds.expand(p)
		bounds = bounds.grow(4.0) # the retired 4 px mover band: this census reads the geometry it was written for
		for y in range(maxi(0,ceili(bounds.position.y)),mini(400,floori(bounds.end.y)+1)):
			for x in range(maxi(20,ceili(bounds.position.x)),mini(620,floori(bounds.end.x)+1)):
				if host._in_footprint(Vector2(x,y),poly): mask[y*640+x] = 1
	var runs: Array = []
	for y in 400:
		var start := -1
		for x in range(20,621):
			var occupied := x < 620 and mask[y*640+x] != 0
			if occupied and start < 0: start = x
			elif not occupied and start >= 0:
				runs.append([y,start,x])
				start = -1
	return runs

func footprint_runs(host) -> Array:
	var polys: Array = host.screen_footprints.duplicate()
	for id in host.entities:
		if id == 1: continue
		var e: Dictionary = host.entities[id]
		if int(e.get("active",1)) != 0:
			polys.append_array(host.footprint_sprites.get(int(e.get("editor_num",0)),[]))
	return polygon_runs(host,polys)

func visual_support_runs(host, fw) -> Array:
	fw.house_plan()
	var origin: Vector2 = fw.screen_origin(host.current_screen)
	var polys: Array = []
	for item in fw.plan_hulls:
		var poly := PackedVector2Array()
		for p in item[0]: poly.append(p-origin)
		polys.append(poly)
	# Huts use their actual first mesh ring; source hardness is not a fitted
	# collision polygon and therefore is absent from footprints.json.
	for e in fw.drawn_sprites(host.current_screen,int(host.vm.globals.get("vision",0))):
		if not fw.hut_fitted(e): continue
		var fit: Dictionary = fw.buildings.hut_fit(fw.frame_path(e))
		var d: Dictionary = host._frame(int(e.get("seq",0)),int(e.get("frame",1)))
		var radius := float(fit.nodes[0][1])
		var at := Vector2(float(e.x)-float(d.dx)+float(fit.cx),float(e.y)-float(d.dy)+float(fit.cz))
		var poly := PackedVector2Array()
		for i in fw.buildings.HUT_SEGMENTS:
			var t: float = TAU*float(i)/float(fw.buildings.HUT_SEGMENTS)
			poly.append(at+Vector2(radius*cos(t),float(fit.k)*radius*sin(t)))
		polys.append(poly)
	return polygon_runs(host,polys)

func _initialize() -> void:
	var output := ""
	var only := []
	var current := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--current": current = true
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--screens="):
			for value in arg.trim_prefix("--screens=").split(","): only.append(int(value))
	var host = HOST.new() if current else BaselineHost.new()
	host.world = host._read_json("res://data/world.json")
	host.sequences = host._read_json("res://data/sequences.json").sequences
	host.footprints = host._read_json("res://data/footprints.json").screens
	host.vm = host.VM.new(host)
	var fw = WORLD.new() if current else BaselineWorld.new()
	fw.setup(host)
	if not current: fw.source_firs = null
	fw.interior = false
	var records := {}
	var footprint_layers := {}
	var probes := {}
	var visual_support := {}
	var warps: Array = []
	var indoors := {}
	for key in host.world.screens:
		var n := int(key)
		if fw.is_inside(n): continue
		if not only.is_empty() and n not in only: continue
		var placements: Array = []
		for source in host.world.screens[key].sprites:
			var e: Dictionary = host.editor_entity(n,source,true,int(source.get("vision",0)))
			if e.is_empty(): continue
			var path: String = fw.frame_path(e)
			var category := "billboard_object"
			if int(e.get("type",1)) == 2 or path.is_empty(): category = "nothing"
			elif fw.paints_ground(e,n): category = "ground_picture"
			elif fw.model_key(e) == "wall": category = "sprite_wall"
			elif fw.prop_fitted(e) or fw.hut_fitted(e) or fw.fences.has(path) or not fw.fitted_key(e,n).is_empty() or fw.model_key(e) in fw.BUILT: category = "built_solid"
			var rect: Rect2 = host._hard_rect(e)
			placements.append({"index":int(source.index),"path":path,"category":category,
				"key":fw.model_key(e),"ground":fw.paints_ground(e,n),"parts":fw.seam_parts(e,n),
				"hard_rect":[rect.position.x,rect.position.y,rect.end.x,rect.end.y]})
		records[key] = placements
		var layers := {0:true}
		for e in host.world.screens[key].sprites: layers[int(e.get("vision",0))] = true
		footprint_layers[key] = {}
		probes[key] = {}
		visual_support[key] = {}
		for vision in layers:
			host.current_screen = n
			host._load_footprints(n)
			host.vm.globals["vision"] = int(vision)
			host.entities = {1:{"x":320.0,"y":200.0}}
			var id := 2
			for source in host.world.screens[key].sprites:
				var e: Dictionary = host.editor_entity(n,source,true,int(vision))
				if e.is_empty(): continue
				host.entities[id] = e
				id += 1
			footprint_layers[key][str(vision)] = footprint_runs(host)
			visual_support[key][str(vision)] = visual_support_runs(host,fw)
			var samples: Array = []
			for y in range(7,400,37):
				for x in range(27,620,37): samples.append([x,y,host._blocked(Vector2(x,y),1)])
			probes[key][str(vision)] = samples
	for key in host.world.screens:
		var n := int(key)
		host.current_screen = n
		host._load_footprints(n)
		host.vm.globals["vision"] = 0
		host.entities = {1:{"x":320.0,"y":200.0}}
		var id := 2
		var rects: Array = []
		for source in host.world.screens[key].sprites:
			var e: Dictionary = host.editor_entity(n,source,true,0)
			if e.is_empty(): continue
			host.entities[id] = e
			id += 1
			if int(e.get("hard",1)) == 0 and e.get("warp") == null and not host.footprint_sprites.has(int(e.editor_num)):
				var rect: Rect2 = host._hard_rect(e)
				rects.append([rect.position.x,rect.position.y,rect.end.x,rect.end.y])
			if e.get("warp") == null: continue
			if fw.is_inside(n):
				var portal: Rect2 = fw.solids.portal_rect(n,int(e.editor_num))
				if portal.has_area():
					var at := Vector2(float(e.x),float(e.y))
					var factor := float(e.get("size",100))/100.0
					var a := (portal.position-at)/factor
					var b := (portal.end-at)/factor
					e["hardbox"] = [a.x,a.y,b.x,b.y]
					e["fps_portal"] = true
			var trigger: Rect2 = host._warp_trigger_rect(e)
			var target := int(e.warp.map)
			var position := Vector2(float(e.warp.x),float(e.warp.y))
			if fw.is_inside(target): position = fw.solids.map_player_door_position(target,position,host.ARRIVAL_INSET_PX)
			warps.append({"screen":n,"index":int(e.editor_num),"target":target,
				"trigger":[trigger.position.x,trigger.position.y,trigger.end.x,trigger.end.y],
				"destination":[position.x,position.y],"source_destination":[e.warp.x,e.warp.y]})
		if fw.is_inside(n): indoors[key] = {"hard_rects":rects,"footprint_runs":footprint_runs(host)}
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"rc5-render-dispatch-2","basis":"current RC5 fitted collision and sprite dispatch" if current else "RC4 pre-migration collision and sprite dispatch; explicit baseline adapters","screens":records,
		"footprint_layers":footprint_layers,"collision_probes":probes,"visual_support":visual_support,
		"static_warps":warps,"indoor_collision":indoors}))
	print("RC5 INVENTORY DONE screens=",records.size())
	fw = null
	host.vm = null
	host.free()
	quit()
