extends SceneTree

const GAME = preload("res://scripts/game.gd")
const FP = preload("res://scripts/fp_world.gd")
const SOURCE_BODY = preload("res://scripts/source_interaction_body.gd")
const TARGETS = preload("res://scripts/entity_hit_targets.gd")
const SCALE := 0.025
# Source world.json screen:editor-index identities for active scripted ground
# art, and the subset removed from the standing decorative census. The old
# rock 481:2 was outside that census; 192:5 leaves both its thorn/total counts.
const ACTIVE_GROUND := {
	"180:1": [89,9,"s6-hole2",0],
	"192:5": [90,12,"thorn",1],
	"209:4": [89,9,"s1-hole3",0],
	"243:13": [89,9,"s6-hole",0],
	"277:2": [89,9,"s1-hole",0],
	"481:2": [92,1,"s5-sec1",1],
}
const DECORATIVE_DEPARTURES := {
	"180:1": [89,9,"s6-hole2",0],
	"192:5": [90,12,"thorn",1],
	"209:4": [89,9,"s1-hole3",0],
	"243:13": [89,9,"s6-hole",0],
	"277:2": [89,9,"s1-hole",0],
}

class FakeBuildings:
	extends RefCounted
	func castle_fit(_path: String) -> Dictionary:
		return {}

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func close(a: float, b: float) -> bool:
	return absf(a-b) < 0.0001

func _run() -> void:
	var host := GAME.new()
	host.sequences = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json"))["sequences"]
	host.world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var world := FP.new()
	world.host = host
	world.buildings = FakeBuildings.new()
	var helper := SOURCE_BODY.new(world)
	var sample: Dictionary = host.world["screens"]["26"]["sprites"][0].duplicate(true)
	sample["pseq"] = sample["seq"]
	sample["pframe"] = sample["frame"]
	check(sample["script"] == "thorn" and world.model_key(sample) == "grass", "sample is authored thorn class")
	var original_hard := int(sample["hard"])
	var override := sample.duplicate(true)
	override["size"] = 150
	override["hardbox"] = [-2, -3, 6, 9]
	var holder := Node3D.new()
	holder.position = world.point(float(override.x)+13.0,float(override.y)-5.0)
	root.add_child(holder)
	check(helper.handles(override,"grass"), "active scripted standing decoration selected")
	check(helper.add(holder,override,47,"grass",true), "body constructed")
	var body := holder.get_node_or_null("HitBody") as StaticBody3D
	check(body != null, "one named source target")
	if body != null:
		var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		check(shape != null and shape.shape is BoxShape3D, "box collision geometry")
		if shape != null and shape.shape is BoxShape3D:
			var box := shape.shape as BoxShape3D
			var rect: Rect2 = host._hard_rect(override)
			var height := world.sprite_height(override)*SCALE*1.5
			check(close(box.size.x,8.0*1.5*SCALE) and close(box.size.z,12.0*1.5*SCALE),
				"explicit hardbox, uniform source size, no picture-width substitute")
			check(close(box.size.y,height), "actual drawn height and source size")
			check((shape.position-(world.point(rect.get_center().x,rect.get_center().y)
				-holder.position+Vector3.UP*height*0.5)).length() < 0.0001,
				"source hardbox centre survives shifted node origin")
		check(body.collision_layer == 2 and body.collision_mask == 0,
			"ray-only body cannot change movement collider")
		check(int(body.get_meta("entity_id",-1)) == 47, "own source entity id")
	check(helper.add(holder,override,47,"grass",true) and holder.get_child_count() == 1
		and holder.get_node("HitBody") == body,
		"visual refresh updates same target rather than duplicating")
	check(int(sample["hard"]) == original_hard and int(override["hard"]) == original_hard,
		"source hardness unchanged")
	var variants := [
		["empty script", {"script":""}], ["type0", {"type":0}],
		["inactive", {"active":0}], ["warp", {"warp":{"screen":9}}],
		["nodraw", {"nodraw":1}], ["disabled", {"disabled":1}], ["dead", {"dead":true}],
	]
	for pair in variants:
		var e: Dictionary = override.duplicate(true)
		e.merge(pair[1],true)
		check(not helper.handles(e,"grass"), "excluded " + str(pair[0]))
		var absent := Node3D.new()
		check(not helper.add(absent,e,3,"grass",true) and absent.get_child_count() == 0,
			"no body for " + str(pair[0]))
		absent.free()
	var no_copy := Node3D.new()
	check(not helper.add(no_copy,override,3,"grass",false) and no_copy.get_child_count() == 0,
		"backdrop copy cannot own an interaction body")
	no_copy.free()
	var no_rock := Node3D.new()
	check(not helper.add(no_rock,override,3,"rock",true), "nondecorative uses existing body path")
	no_rock.free()
	await physics_frame
	var targets := TARGETS.new()
	var body_bounds := targets.bounds(holder,47)
	var camera_at := body_bounds.get_center()+Vector3(0,0,2.0)
	check(targets.reaches(holder,47,camera_at,root.world_3d.direct_space_state),
		"native physics ray reaches actual source-hardbox surface")
	var moved := override.duplicate(true)
	moved["x"] = int(moved["x"])+19
	moved["y"] = int(moved["y"])+7
	moved["pframe"] = 8
	moved["hardbox"] = [] # current frame metadata, not the previous explicit override
	moved["size"] = 80
	holder.position = world.point(float(moved.x)-4.0,float(moved.y)+11.0)
	check(helper.add(holder,moved,47,"grass",true) and holder.get_node("HitBody") == body,
		"live frame, size and origin reuse the same owned body")
	if body != null:
		var changed_shape := body.get_node("CollisionShape3D") as CollisionShape3D
		var changed_box := changed_shape.shape as BoxShape3D
		var changed_rect: Rect2 = host._hard_rect(moved)
		var changed_height := world.sprite_height(moved)*SCALE*0.8
		check(close(changed_box.size.x,changed_rect.size.x*SCALE)
			and close(changed_box.size.z,changed_rect.size.y*SCALE)
			and close(changed_box.size.y,changed_height),
			"live source frame and size replace previous geometry")
		check((changed_shape.position-(world.point(changed_rect.get_center().x,
			changed_rect.get_center().y)-holder.position+Vector3.UP*changed_height*0.5)).length() < 0.0001,
			"live movement and parent offset update body position")
		for pair in variants:
			var invisible: Dictionary = moved.duplicate(true)
			invisible.merge(pair[1],true)
			check(not helper.add(holder,invisible,47,"grass",true)
				and body.collision_layer == 0 and changed_shape.disabled,
				"owned target disabled after " + str(pair[0]))
			check(helper.add(holder,moved,47,"grass",true)
				and body.collision_layer == 2 and not changed_shape.disabled,
				"owned target restored after " + str(pair[0]))
		check(not helper.add(holder,moved,47,"grass",false) and body.collision_layer == 0,
			"scene-only ownership disables existing target")
		check(helper.add(holder,moved,47,"grass",true), "owner can regain target")
	holder.free()
	var foreign_node := Node3D.new()
	var foreign_body := StaticBody3D.new()
	foreign_body.name = "HitBody"
	foreign_body.collision_layer = 1
	foreign_node.add_child(foreign_body)
	check(not helper.add(foreign_node,override,50,"grass",true)
		and foreign_node.get_child_count() == 1 and foreign_body.collision_layer == 1,
		"foreign normal body is never altered")
	foreign_node.free()
	var thorn_count := 0
	var decorative_count := 0
	var mismatched := 0
	var excluded: Dictionary = {}
	var departures: Dictionary = {}
	var excluded_thorns := 0
	for sn in host.world["screens"]:
		for source in host.world["screens"][sn].get("sprites", []):
			if str(source.get("script","")) == "": continue
			var e: Dictionary = source.duplicate(true)
			e["pseq"] = e["seq"]
			e["pframe"] = e["frame"]
			var key := world.model_key(e)
			if key == "ground_detail" and int(e.get("type",1)) == 1:
				var identity := "%s:%d" % [sn,int(e["index"])]
				excluded[identity] = [int(e.seq),int(e.frame),str(e.script),int(e.hard)]
				if DECORATIVE_DEPARTURES.has(identity):
					departures[identity] = excluded[identity]
					if str(e.script) == "thorn": excluded_thorns += 1
				var flat_node := Node3D.new()
				check(not helper.handles(e,key) and not helper.add(flat_node,e,47,key,true)
					and flat_node.get_child_count() == 0,"ground art has no standing ray body " + identity)
				flat_node.free()
			if not helper.handles(e,key): continue
			decorative_count += 1
			if str(e["script"]) == "thorn": thorn_count += 1
			var node := Node3D.new()
			node.position = world.point(float(e.x),float(e.y))
			var hard_before := int(e.get("hard",-1))
			var added := helper.add(node,e,decorative_count,key,true)
			var own := node.get_node_or_null("HitBody") as StaticBody3D
			if not added or own == null or node.get_child_count() != 1 or int(e.get("hard",-1)) != hard_before:
				mismatched += 1
			else:
				var s := own.get_node_or_null("CollisionShape3D") as CollisionShape3D
				var r: Rect2 = host._hard_rect(e)
				if s == null or not close((s.shape as BoxShape3D).size.x,r.size.x*SCALE) or not close((s.shape as BoxShape3D).size.z,r.size.y*SCALE):
					mismatched += 1
			node.free()
	check(excluded == ACTIVE_GROUND,"itemized active scripted ground placements: " + str(excluded))
	check(departures == DECORATIVE_DEPARTURES,"itemized decorative departures: " + str(departures))
	check(thorn_count == 139-excluded_thorns and decorative_count == 145-departures.size() and mismatched == 0,
		"all scripted decorative placements: thorn=%d decorative=%d mismatch=%d" % [thorn_count,decorative_count,mismatched])
	host.free()
	if failures.is_empty():
		print("SOURCE INTERACTION BODY PASS thorn=%d decorative=%d" % [thorn_count,decorative_count])
		quit(0)
	else:
		for failure in failures: print("SOURCE INTERACTION BODY FAIL ", failure)
		quit(1)
