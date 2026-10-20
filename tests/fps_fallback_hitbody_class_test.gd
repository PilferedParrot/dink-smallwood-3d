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
# Independent input oracle: do not call handles(), wall_behind() or frontal_dims().
var source_pixels: Dictionary = {}
var mutation_calibrated := false
func source_anchor(game, e: Dictionary) -> Dictionary:
 var path: String=game.fp_world.frame_path(e)
 if not source_pixels.has(path):
  var image: Image=game.fp_world.sprite_image(path)
  var left:=image.get_width()
  var right:=0
  var foot:=0
  for y in image.get_height():
   for x in image.get_width():
    var c:=image.get_pixel(x,y)
    if c.a>0.5 and c.r+c.g+c.b>=0.04:
     left=mini(left,x)
     right=maxi(right,x+1)
     foot=maxi(foot,y+1)
  source_pixels[path]={"left":left,"right":right,"foot":foot}
 var frame: Dictionary=game._frame(int(e.get("pseq",0)),int(e.get("pframe",1)))
 var pixels: Dictionary=source_pixels[path]
 return {"left":float(e.x)-float(frame.dx)+float(pixels.left),"right":float(e.x)-float(frame.dx)+float(pixels.right),"south":float(e.y)-float(frame.dy)+float(pixels.foot)}
func source_registered(game,e:Dictionary,b:AABB) -> bool:
 var a:=source_anchor(game,e)
 var h:Rect2=game._hard_rect(e)
 var west:=b.position.x/0.025+320.0
 var east:=b.end.x/0.025+320.0
 var south:=b.end.z/0.025+200.0
 # 0.01 source px covers native float transforms. The authored difference
 # between drawn foot and hardness supplies the HB tolerance, not a fitted max.
 var hb_tolerance:=absf(float(a.south)-h.end.y)+0.01
 return absf(south-float(a.south))<0.01 and absf(south-h.end.y)<=hb_tolerance \
  and minf(east,h.end.x)>maxf(west,h.position.x) \
  and absf(west-float(a.left))<0.01 and absf(east-float(a.right))<0.01 \
  and absf(b.position.y/0.025)<0.01
func input_rule(game,e:Dictionary,number:int) -> Dictionary:
 var fp=game.fp_world
 var fit:Dictionary=fp.solids.fit_of(fp.frame_path(e))
 var result:Dictionary={"eligible":false,"backing":-1.0,"gap":-1.0}
 if absf(float(e.get("size",100))-100.0)>=0.5 or fit.is_empty():return result
 if not fp.is_inside(number) and (int(e.get("type",1))!=1 or str(fit.get("kind",""))!="frontal"):return result
 if str(fit.get("kind",""))=="frontal" and fit.get("legs",[]).is_empty() and fit.get("above",[]).is_empty() and float(fit.body.split)<=float(fit.body.rows[0]):
  var frame:Dictionary=game._frame(int(e.pseq),int(e.pframe))
  var left:=float(e.x)-float(frame.dx)
  var front:=float(e.y)-float(frame.dy)+float(fit.base)
  var best:=-1.0
  for w in game.world.screens[str(number)].get("sprites",[]):
   var f:Dictionary=fp.solids.fit_of(fp.frame_path(w))
   if str(f.get("kind",""))!="wall" or int(f.get("cap",0))<=0:continue
   var wf:Dictionary=game._frame(int(w.get("pseq",w.get("seq",0))),int(w.get("pframe",w.get("frame",1))))
   var wx:=float(w.x)-float(wf.dx)
   if wx+float(f.size[0])<left+float(fit.body.cols[0])+1.0 or wx>left+float(fit.body.cols[1])-1.0:continue
   var south:=float(w.y)-float(wf.dy)+float(f.base)
   if south<front-1.0:best=maxf(best,south)
  result.backing=best
  result.gap=front-best-1.0
  if best<0.0 or float(result.gap)>game._hard_rect(e).size.y:return result
 if str(fit.get("kind",""))=="wall":
  var any_wall:=false
  for w in game.world.screens[str(number)].get("sprites",[]):
   if fp.model_key(w)!="wall":continue
   if str(fp.solids.fit_of(fp.frame_path(w)).get("kind",""))!="wall":return result
   any_wall=true
  if not any_wall:return result
 result.eligible=true
 return result
func derived_treatment(game,e:Dictionary,number:int) -> String:
 if int(e.get("type",1))==2:return "unchanged-hidden"
 if game.fp_world.model_key(e) in ["wall","cottage"]:return "unchanged-control"
 if bool(input_rule(game,e,number).eligible):return "reconstruct"
 return "unchanged-followup"
func edge_offsets(b:AABB,h:Rect2) -> Dictionary:
 return {"west":b.position.x/0.025+320.0-h.position.x,"north":b.position.z/0.025+200.0-h.position.y,"east":b.end.x/0.025+320.0-h.end.x,"south":b.end.z/0.025+200.0-h.end.y}
func editor(game,number:int,index:int) -> Dictionary:
 for source in game.world.screens[str(number)].get("sprites",[]):
  if int(source.get("index",0))==index:return game.editor_entity(number,source,true,int(source.get("vision",0)),{})
 return {}
func negative_controls(game):
 var fp=game.fp_world
 var shelf:=editor(game,6,18)
 var far:=shelf.duplicate(true)
 far.y=float(far.y)+game._hard_rect(far).size.y+20.0
 var rule:=input_rule(game,far,6)
 check(float(rule.backing)>=0 and float(rule.gap)>game._hard_rect(far).size.y,"far-wall control still has backing beyond HB depth")
 check(not bool(rule.eligible) and not fp.solids.handles(far,6),"far-wall frontal excluded")
 var outside:=editor(game,366,15)
 var hidden:=outside.duplicate(true)
 hidden.type=2
 check(not bool(input_rule(game,hidden,366).eligible) and not fp.solids.handles(hidden,366),"outdoor type2 frontal excluded")
 var scaled:=outside.duplicate(true)
 scaled.size=70
 check(not bool(input_rule(game,scaled,366).eligible) and not fp.solids.handles(scaled,366),"non100 frontal excluded")
 game.current_screen=365
 fp.interior=false
 for pair in [[366,15],[34,29]]:
  var e:=editor(game,int(pair[0]),int(pair[1]))
  check(not e.is_empty() and bool(input_rule(game,e,int(pair[0])).eligible),"noncurrent fixture eligible absent scope guard")
  var node:Node3D=fp.make_entity(e,0,game.scene_root,false,int(pair[0]))
  check(not node.get_meta("interior_solid",false),"new outdoor solid allowance excludes noncurrent screen "+str(pair[0]))
  node.free()
 # 365->34 is an entry-point scope fixture, not an authored adjacency claim.

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
 if member.is_empty():
  check(model is Sprite3D,identity+" unclassified primitive cannot become a billboard control")
 var treatment: String = derived_treatment(game,e,number) if not member.is_empty() else "unchanged-billboard"
 if not member.is_empty():
  check(treatment==str(member.treatment),identity+" input-derived partition matches recorded membership")
 counts[treatment]=int(counts.get(treatment,0))+1
 if treatment=="reconstruct":
  check(node.get_meta("interior_solid",false),identity+" source reconstruction replaces primitive")
  check(source_registered(game,e,b),identity+" source-pixel foot/X extent and hardness anchor")
  var mutation_path: String=game.fp_world.frame_path(e)
  var original_fit: Dictionary=game.fp_world.solids.fit_of(mutation_path)
  if not mutation_calibrated and not original_fit.get("legs",[]).is_empty():
   var wrong_fit:=original_fit.duplicate(true)
   wrong_fit.base=float(wrong_fit.base)+20.0
   game.fp_world.solids.fits[mutation_path]=wrong_fit
   var wrong:Node3D=game.fp_world.make_entity(e,id+900000,game.scene_root,true,number)
   var wrong_body:=wrong.get_node("HitBody") as StaticBody3D
   var wrong_model:=wrong.get_node("Model") as Node3D
   check(same_faces(mesh_faces(wrong_model),body_faces(wrong_body)),"wrong-fit control remains mesh/collider consistent")
   check(not source_registered(game,e,helper.bounds(wrong,id+900000)),"source gate rejects native fit shifted20px")
   wrong.free()
   game.fp_world.solids.fits[mutation_path]=original_fit
   mutation_calibrated=true
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
 if treatment=="unchanged-followup":
  var defect:Dictionary=member.get("known_defect",{})
  var offsets:=edge_offsets(b,rect)
  check(not str(defect.get("reason","")).is_empty(),identity+" unresolved form needs reason")
  var recorded:Dictionary=defect.get("body_edge_offsets_px",{})
  for edge in ["west","north","east","south"]:
   check(recorded.has(edge) and absf(float(recorded.get(edge,INF))-float(offsets[edge]))<0.01,identity+" unresolved measured "+edge)
  print("UNRESOLVED ",identity," reason=",defect.get("reason","MISSING")," offsets_px=",offsets)
 if treatment=="unchanged-hidden":
  # Exercise the production visibility path: type2 authoring hardness must
  # neither acquire a visible reconstruction nor remain an FPS ray target.
  game.entities[id]=e
  game.visuals[id]=node
  game.fp_world.update_visual(id)
  check(not node.visible and body.collision_layer==0,identity+" hidden look-alike remains invisible and untargetable")
  game.entities.erase(id)
  game.visuals.erase(id)
 rows.append({"screen":number,"editor":e.get("editor_num",0),"vision":e.get("vision",0),"key":node.get_meta("model_key",""),"kind":"reconstructed" if treatment=="reconstruct" else ("primitive" if not member.is_empty() else "billboard"),"treatment":treatment,"path":game.fp_world.frame_path(e),"hardbox":game._frame(int(e.get("pseq",0)),int(e.get("pframe",1))).get("hardbox",[]),"body_center":vector(b.get_center()),"model_center":vector(m.get_center()),"source_center":vector(at),"body_size":vector(b.size),"model_size":vector(m.size),"source_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"known_defect":member.get("known_defect",{})})
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
 negative_controls(game)
 check(mutation_calibrated,"wrong-fit source registration control exercised")
 check(observed.size()==expected.size(),"all baseline337members retained, including explicit follow-ups")
 check(calibrated,"face comparison calibrated on actual reconstructed body")
 check(int(counts.get("reconstruct",0))==37,"all37supported editor-static frontal replacements measured")
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
