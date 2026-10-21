extends "fps_capture.gd"
# Diagnostic fixtures skip progression/scripts. Original views use the same
# cutaway and stable coplanar-wall tie order as P4b's bed_capture.gd.
var records := []

func _shoot(game, view: Dictionary, out_dir: String) -> void:
 # fps_capture enables fog in every perspective view. Production interiors
 # disable it; zero density preserves that actual interior appearance while
 # retaining the shared camera and crop implementation.
 var density: float=game.fp_world.environment.fog_density
 if not bool(view.get("original",false)):game.fp_world.environment.fog_density=0.0
 await super._shoot(game,view,out_dir)
 game.fp_world.environment.fog_density=density
func _overheads(game) -> Array:
 var fw = game.fp_world
 var limits := Rect2(20,0,600,400)
 var found := false
 for e in game.world.screens[str(game.current_screen)].sprites:
  if fw.model_key(e) != "wall": continue
  var r: Rect2 = fw.hard_rect(e)
  limits = limits.merge(r) if found else r
  found = true
 var h: float = fw.solids.room_height(game.current_screen)*0.025
 var expected := [[Vector3(limits.size.x*0.025,0.18,limits.size.y*0.025),fw.point(limits.get_center().x,limits.get_center().y)+Vector3(0,h+0.09,0),"ceiling"]]
 for x in range(int(limits.position.x),int(limits.end.x)+1,75):
  expected.append([Vector3(0.18,0.26,limits.size.y*0.025),fw.point(x,limits.get_center().y)+Vector3(0,h-0.13,0),"beam"])
 var baseline := "--baseline" in OS.get_cmdline_user_args()
 var actual := []
 var removed := 0
 for prediction in expected:
  var matches := []
  for node in game.scene_root.get_children():
   if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.is_equal_approx(prediction[0]) and node.position.is_equal_approx(prediction[1]):matches.append(node)
  if not baseline and prediction[2]=="beam" and game.fp_world.ceilings.room(game.current_screen).get("room",false) and game.fp_world.ceilings.room(game.current_screen).get("beam")==null:
   assert(matches.is_empty(),"Unsupported beam survived")
   removed+=1
   continue
  assert(matches.size()==1,"Missing/ambiguous overhead geometry identity")
  var node: MeshInstance3D=matches[0]
  if baseline:node.add_to_group("interior_overhead")
  assert(node.is_in_group("interior_overhead"))
  actual.append(node)
 if baseline:
  var old_material_nodes := []
  for node in game.scene_root.get_children():
   if node is MeshInstance3D and node.material_override!=null and node.material_override in [fw.materials.get("ceiling"),fw.materials.get("beam")]:old_material_nodes.append(node)
  assert(old_material_nodes.size()==actual.size())
  for node in old_material_nodes:assert(node in actual)
 else:
  var grouped := []
  for node in game.scene_root.get_children():
   if node.is_in_group("interior_overhead"):grouped.append(node)
  assert(grouped.size()==actual.size())
  for node in grouped:assert(node in actual)
 records.append({"screen":game.current_screen,"hidden":actual.size(),"removed_beams":removed,"baseline_expected":expected.size()})
 return actual

func _stable_wall_ties(game) -> void:
 var ids: Array=game.visuals.keys();ids.sort()
 var index:=0
 for id in ids:
  var node: Node3D=game.visuals[id]
  if str(node.get_meta("model_key",""))!="wall":continue
  for mesh in node.find_children("*","MeshInstance3D",true,false):
   for surface in mesh.mesh.get_surface_count():
    assert(index<=Material.RENDER_PRIORITY_MAX)
    var copy: Material=mesh.get_active_material(surface).duplicate()
    copy.render_priority=index
    mesh.set_surface_override_material(surface,copy)
    index+=1

# Source entity order resolves the existing equal-depth overlap between props.
# Keep this fixture-only, identically on base and candidate, as for wall ties.
func _stable_prop_ties(game) -> void:
 var ids: Array=game.visuals.keys();ids.sort()
 var rank:=0
 for id in ids:
  var node: Node3D=game.visuals[id]
  if str(node.get_meta("model_key",""))=="wall":continue
  assert(rank<128,"Prop fixture exceeds renderer priority range")
  for mesh in node.find_children("*","MeshInstance3D",true,false):
   if mesh.material_override!=null:
    var copy: Material=mesh.material_override.duplicate()
    copy.render_priority=rank-128
    mesh.material_override=copy
   elif mesh.mesh!=null:
    for surface in mesh.mesh.get_surface_count():
     var copy: Material=mesh.get_active_material(surface).duplicate()
     copy.render_priority=rank-128
     mesh.set_surface_override_material(surface,copy)
  rank+=1

func _original_setup(game, overhead: Array, shadows: bool) -> void:
 # P4b's fixed player fixture prevents his changing shadow footprint from
 # contaminating a source-camera comparison.
 game.entities[1].x=505.0;game.entities[1].y=340.0
 game.fps_yaw=0.55;game.fps_pitch=-0.03;game._sync_fps_camera()
 for id in game.entities:game.entities[id]["frozen"]=true
 for node in overhead:node.visible=false
 _stable_wall_ties(game)
 _stable_prop_ties(game)
 game.fp_world.light.shadow_enabled=shadows

func _g2_bundle(game, rooms: Array, folder: String) -> void:
 for mode in ["strict-a","strict-b","shadow-a","shadow-b"]:
  var out:=folder.path_join(mode)
  DirAccess.make_dir_recursive_absolute(out)
  for n in rooms:
   game.vm.cancel_all();game.vm.globals["vision"]=0;game.load_map(n,false)
   game.playing=false;game.ui.visible=false
   _original_setup(game,_overheads(game),mode.begins_with("shadow"))
   await _shoot(game,{"name":str(n),"original":true},out)
   print("G2 BUNDLE ",mode," ",n)

func _run() -> void:
 var folder := ""
 var originals := false
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="):folder=arg.trim_prefix("--out-dir=")
  if arg=="--originals":originals=true
 assert(not folder.is_empty())
 DirAccess.make_dir_recursive_absolute(folder)
 var game = GAME.new()
 game.test_mode=true
 root.add_child(game)
 await process_frame
 await game._new_game()
 game.vm.cancel_all();game.set_physics_process(false);game.set_process(false)
 var rooms: Array=[]
 for key in game.world.screens:
  if game.world.screens[key].get("indoor",false):rooms.append(int(key))
 rooms.sort()
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--screens="):
   var selected:=[]
   for n in arg.trim_prefix("--screens=").split(","):selected.append(int(n))
   rooms=selected
 if "--g2-bundle" in OS.get_cmdline_user_args():
  await _g2_bundle(game,rooms,folder)
  var bundle_file:=FileAccess.open(folder.path_join("overheads.json"),FileAccess.WRITE)
  bundle_file.store_string(JSON.stringify(records," "))
  game.queue_free();await process_frame
  print("CEILING CAPTURE DONE ",records.size())
  quit();return
 for n in rooms:
  game.vm.cancel_all();game.vm.globals["vision"]=0
  game.load_map(n,false)
  game.playing=false;game.ui.visible=false
  var overhead := _overheads(game)
  if originals:
   _original_setup(game,overhead,"--shadows-on" in OS.get_cmdline_user_args())
   if "--wall-control" in OS.get_cmdline_user_args() and n==1:
    for node in game.visuals.values():
     if str(node.get_meta("model_key",""))=="wall":
      for mesh in node.find_children("*","MeshInstance3D",true,false):
       var bad:=StandardMaterial3D.new();bad.albedo_color=Color.MAGENTA;bad.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
       mesh.material_override=bad
   await _shoot(game,{"name":str(n),"original":true},folder)
  else:
   # Export actual material texture and shader uniforms; audit every room even
   # when a cached donor is reused. Base untextured materials remain a red.
   var facts:=[]
   for node in overhead:
    var material: Material=node.material_override
    var fact:={"size":[node.mesh.size.x,node.mesh.size.y,node.mesh.size.z],"position":[node.position.x,node.position.y,node.position.z],"role":str(node.get_meta("overhead_role","")),"textured":material is ShaderMaterial}
    if material is ShaderMaterial:
     fact.donor=material.get_meta("overhead_donor")
     fact.metres_per_pixel=material.get_shader_parameter("metres_per_pixel")
     fact.tile_pixels=[material.get_shader_parameter("tile_pixels").x,material.get_shader_parameter("tile_pixels").y]
     fact.shader=material.shader.code
     fact.beam=material.get_shader_parameter("beam")
     var origin: Vector3=material.get_shader_parameter("world_origin")
     fact.world_origin=[origin.x,origin.y,origin.z]
     var texture: Texture2D=material.get_shader_parameter("source_texture")
     var texname:=JSON.stringify(fact.donor).sha256_text()+".png"
     texture.get_image().save_png(folder.path_join(texname));fact.texture=texname
     if str(fact.donor.filter)=="wall-plaster":
      var filtername:=str(fact.donor.path).sha256_text()+"-filtered.png"
      game.fp_world.solids.plaster_texture(str(fact.donor.path)).get_image().save_png(folder.path_join(filtername));fact.filtered_source=filtername
    facts.append(fact)
   records[-1]["faces"]=facts
   # Source/representation classes from the frozen baseline census. All rooms
   # still get material audit above; these are the eye-level witnesses.
   if "--audit-only" not in OS.get_cmdline_user_args() and n in [1,69,70,73,85,86,133,134,164,197,260,514,579]:
    var p:=Vector2(295,225)
    if n==70:p=Vector2(320,335)
    for mode in ["level","up"]:
     await _shoot(game,{"name":"%d-%s" % [n,mode],"x":p.x,"y":p.y,"yaw":0.2,"pitch":0.0 if mode=="level" else 0.9},folder)
    for node in overhead:
     if node.material_override is ShaderMaterial:node.material_override.set_shader_parameter("provenance_tint",true)
    await _shoot(game,{"name":"%d-tint" % n,"x":p.x,"y":p.y,"yaw":0.2,"pitch":0.9},folder)
    for node in overhead:
     if node.material_override is ShaderMaterial:node.material_override.set_shader_parameter("provenance_tint",false)
  if "--audit-only" in OS.get_cmdline_user_args():await process_frame
 var file:=FileAccess.open(folder.path_join("overheads.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(records," "))
 game.queue_free();await process_frame
 print("CEILING CAPTURE DONE ",records.size())
 quit()
