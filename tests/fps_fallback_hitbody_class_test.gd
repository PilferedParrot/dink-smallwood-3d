extends SceneTree
# Factory census on every authored vision; skips campaign/startup scripts.
# The baseline cohort remains explicit when a fallback becomes a fitted model,
# so replacing a representation cannot silently remove it from this test.
const GAME = preload("res://scripts/fps_game.gd")
const TARGETS = preload("res://scripts/entity_hit_targets.gd")
const EPS := 0.0001
var failures: Array[String] = []
var counts: Dictionary = {}
var rows: Array = []
var expected: Dictionary = {}
var observed: Dictionary = {}
var calibrated := false
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
 if not ok: failures.append(label)
func vector(v: Vector3) -> Array: return [v.x,v.y,v.z]
func from_array(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
func mesh_bounds(model: Node3D, holder: Node3D) -> AABB:
 var result := AABB()
 var found := false
 var pending: Array = [model]
 while not pending.is_empty():
  var item: Node = pending.pop_back()
  if item is MeshInstance3D:
   var b: AABB = holder.global_transform.affine_inverse()*item.global_transform*item.get_aabb()
   result = result.merge(b) if found else b
   found = true
  pending.append_array(item.get_children())
 return result
func mesh_faces(model: Node3D) -> PackedVector3Array:
 var result := PackedVector3Array()
 for child in model.get_children():
  if not child is MeshInstance3D: continue
  for point in child.mesh.get_faces(): result.append(child.global_transform*point)
 return result
func body_faces(body: StaticBody3D) -> PackedVector3Array:
 var result := PackedVector3Array()
 for child in body.get_children():
  if not child is CollisionShape3D or not child.shape is ConcavePolygonShape3D: continue
  for point in child.shape.get_faces(): result.append(child.global_transform*point)
 return result
func same_faces(a: PackedVector3Array, b: PackedVector3Array) -> bool:
 if a.is_empty() or a.size()!=b.size(): return false
 for i in a.size():
  if a[i].distance_to(b[i])>EPS: return false
 return true
func measure(game, e: Dictionary, number: int, id: int) -> void:
 var identity := "%d:%d:%d" % [number,int(e.get("editor_num",0)),int(e.get("vision",0))]
 var node: Node3D = game.fp_world.make_entity(e,id,game.scene_root,true,number)
 var model := node.get_node_or_null("Model") as Node3D
 var body := node.get_node_or_null("HitBody") as StaticBody3D
 var member: Dictionary = expected.get(identity,{})
 if not member.is_empty():
  check(not observed.has(identity),identity+" duplicate cohort member")
  observed[identity]=true
  check(model!=null and body!=null,identity+" cohort must retain visible model and body")
 if model==null or body==null:
  node.free()
  return
 if member.is_empty() and (not node.has_meta("base_model_position") or node.has_meta("prop_path")):
  node.free()
  return
 var helper := TARGETS.new()
 var b: AABB = helper.bounds(node,id)
 var m: AABB = model.global_transform*model.get_aabb() if model is Sprite3D else node.global_transform*mesh_bounds(model,node)
 var rect: Rect2 = game.fp_world.hard_rect(e)
 var at: Vector3 = game.fp_world.point(rect.get_center().x,rect.get_center().y)
 var treatment: String = member.get("treatment","unchanged-billboard")
 counts[treatment]=int(counts.get(treatment,0))+1
 if treatment=="reconstruct":
  check(node.get_meta("interior_solid",false),identity+" source reconstruction replaces primitive")
  var visual_faces := mesh_faces(model)
  var collision_faces := body_faces(body)
  check(same_faces(visual_faces,collision_faces),identity+" ray body equals actual model faces")
  check(b.position.distance_to(m.position)<EPS and b.size.distance_to(m.size)<EPS,identity+" aim bounds follow reconstructed mesh")
  if not calibrated and same_faces(visual_faces,collision_faces):
   var shifted := collision_faces.duplicate()
   for i in shifted.size(): shifted[i]+=Vector3(0,0,0.01)
   check(not same_faces(visual_faces,shifted),"instrument rejects shifted collider")
   check(not same_faces(visual_faces,PackedVector3Array()),"instrument rejects absent collider")
   calibrated=true
  var fit: Dictionary = game.fp_world.solids.fit_of(game.fp_world.frame_path(e))
  if fit.get("kind","")=="frontal" and float(fit.body.split)<=float(fit.body.rows[0]):
   var dims: Dictionary=game.fp_world.solids.frontal_dims(e,fit,game.fp_world.solids.hotspot(e),number)
   check(float(dims.depth)<=rect.size.y+0.001,identity+" unobserved depth bounded by source hardness")

 elif not member.is_empty():
  if member.get("support","")=="unmeasured-depth-without-backing-wall":
   check(not game.fp_world.solids.handles(e,number),identity+" unsupported front retains its legacy representation")
  for pair in [[b.get_center(),member.body_center],[m.get_center(),member.model_center],[b.size,member.body_size],[m.size,member.model_size]]:
   check((pair[0] as Vector3).distance_to(from_array(pair[1]))<EPS,identity+" preserved "+treatment)
 if treatment=="unchanged-hidden":
  # Exercise the production visibility path: type2 authoring hardness must
  # neither acquire a visible reconstruction nor remain an FPS ray target.
  game.entities[id]=e
  game.visuals[id]=node
  game.fp_world.update_visual(id)
  check(not node.visible and body.collision_layer==0,identity+" hidden look-alike remains invisible and untargetable")
  game.entities.erase(id)
  game.visuals.erase(id)
 rows.append({"screen":number,"editor":e.get("editor_num",0),"vision":e.get("vision",0),"key":node.get_meta("model_key",""),"kind":"reconstructed" if treatment=="reconstruct" else ("primitive" if not member.is_empty() else "billboard"),"treatment":treatment,"path":game.fp_world.frame_path(e),"hardbox":game._frame(int(e.get("pseq",0)),int(e.get("pframe",1))).get("hardbox",[]),"body_center":vector(b.get_center()),"model_center":vector(m.get_center()),"source_center":vector(at),"body_size":vector(b.size),"model_size":vector(m.size),"source_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
 node.free()
func run():
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../tests/fixtures/fallback-hitbody-baseline.json"))
 for member in fixture.records:
  expected["%d:%d:%d" % [int(member.screen),int(member.editor),int(member.vision)]]=member
 var game=GAME.new()
 game.test_mode=true
 root.add_child(game)
 await process_frame
 var numbers: Array=game.world.screens.keys().map(func(n):return int(n))
 numbers.sort()
 for number in numbers:
  game.current_screen=number
  game.fp_world.interior=game.fp_world.is_inside(number)
  game.fp_world.plan_key=""
  game.fp_world.neighbour_states.clear()
  game.fp_world.scene_block={number:true}
  game._load_footprints(number)
  for source in game.world.screens[str(number)].get("sprites",[]):
   var e: Dictionary=game.editor_entity(number,source,true,int(source.get("vision",0)),{})
   if e.is_empty():continue
   game.vm.globals["vision"]=int(e.get("vision",0))
   game.fp_world.fitted_built.clear()
   measure(game,e,number,100000+rows.size())
  await process_frame
 check(observed.size()==expected.size(),"all baseline337members retained, including explicit follow-ups")
 check(calibrated,"face comparison calibrated on actual reconstructed body")
 check(int(counts.get("reconstruct",0))==37,"all37supported visible frontal replacements measured")
 check(int(counts.get("unchanged-hidden",0))==6,"all6hidden authoring look-alikes retained")
 check(int(counts.get("unchanged-followup",0))==22,"all22unresolved pictures explicitly retained")
 check(int(counts.get("unchanged-control",0))==272,"all272structural look-alikes retained")
 var output:=OS.get_environment("HITBODY_CLASS_REPORT")
 if not output.is_empty():
  var file:=FileAccess.open(output,FileAccess.WRITE)
  file.store_string(JSON.stringify({"screens":numbers.size(),"counts":counts,"rows":rows,"failures":failures},"  "))
 print("FALLBACK CLASS counts=",counts," failures=",failures.size())
 if failures.is_empty():print("FALLBACK CLASS PASS")
 else:print("FALLBACK CLASS FAILURES: ",failures.slice(0,20))
 game.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
