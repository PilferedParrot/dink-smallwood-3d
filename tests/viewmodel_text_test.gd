# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Real held-model fixture. Items granted directly; VM canceled/physics paused.
const GAME=preload("res://scripts/fps_game.gd")
var game
var failures:Array[String]=[]
var records:Array=[]
var output_dir:=""
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="):output_dir=arg.trim_prefix("--out-dir=")
 run.call_deferred()
func check(ok:bool,message:String):
 if not ok:failures.append(message);push_error(message)
func settle():
 for i in 14:
  game._fps_update_viewmodel(0)
  await process_frame
func projected(node:GeometryInstance3D)->Rect2:
 var box:=node.get_aabb()
 var rect:=Rect2()
 for i in 8:
  var local:=box.position+box.size*Vector3(i&1,(i>>1)&1,(i>>2)&1)
  var point:Vector2=game.camera.unproject_position(node.global_transform*local)
  rect=Rect2(point,Vector2.ZERO) if i==0 else rect.expand(point)
 return rect
func reading_clear(node:GeometryInstance3D,tag:String):
 var rect:=projected(node)
 check(rect.has_area(),tag+": native text/mark has projected area")
 check(root.get_visible_rect().grow(1).encloses(rect),tag+": stays on screen")
 var art:Rect2=game.ui.status_dock.get_global_transform()*game.ui.status_dock.art_rect()
 check(not rect.intersects(art),tag+": clears status art")
 if game.ui.status_dock.readout.visible:check(not rect.intersects(game.ui.status_dock.readout.get_global_rect()),tag+": clears status values")
 if game.ui.hint_backing.visible:check(not rect.intersects(game.ui.hint_backing.get_global_rect()),tag+": clears help")
 if game.ui.panel.visible:check(not rect.intersects(game.ui.panel.get_global_rect()),tag+": clears speech card")
 records.append({"tag":tag,"window":[root.size.x,root.size.y],"scale":game.ui.text_scale,"plain":game.ui.plain_font,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"model_y":game.fps_viewmodel.position.y})
func run():
 game=GAME.new();game.test_mode=true;root.add_child(game)
 await process_frame
 game.set_physics_process(false);game.set_process(false);game.vm.cancel_all()
 game.playing=true;game.ui.close_menu()
 for size in [Vector2i(1280,800),Vector2i(1920,1080)]:
  root.size=size
  for plain in [false,true]:
   for scale in [1.0,1.5,2.0]:
    game.settings.text_scale=scale;game.settings.plain_font=plain;game._apply_settings()
    game.items=[{"name":"Pig feed","script":"item-pig"}];game.vm.globals["cur_weapon"]=1
    game.ui.gameplay_hint_used=true;game.ui.gameplay_hint_deadline_msec=0
    game.ui.close_menu()
    game.ui.show_hud({"life":12,"lifemax":20,"strength":12,"defense":8,"magic":4,"gold":165,"exp":45,"level":2,"location":"Stonebrook"})
    await settle()
    var label:Label3D
    for child in game.fps_viewmodel.get_children():
     if child is Label3D:label=child
    check(label!=null,"real feed helper creates label")
    if label==null:continue
    check(label.font_size==roundi(32*scale),"FEED keeps requested size")
    check(label.font==game.ui.PLAIN_FONT if plain else (label.font==null or label.font==ThemeDB.fallback_font),"FEED keeps requested font")
    if scale==1:check(game.fps_viewmodel.position.is_equal_approx(Vector3(0.35,-0.30,-0.95)),"default FEED pose stays unchanged")
    reading_clear(label,"feed")
    if plain and scale==2 and not output_dir.is_empty():
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png(output_dir.path_join("feed-%d.png"%size.x))
    game.ui.gameplay_hint_deadline_msec=Time.get_ticks_msec()+60000
    await settle();reading_clear(label,"feed-help")
    if plain and scale==2 and not output_dir.is_empty():
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png(output_dir.path_join("feed-help-%d.png"%size.x))
    game.ui.show_speech("Please feed the pigs before you leave.","Mother",1,0,true)
    await settle();reading_clear(label,"feed-speech")
    game.ui.cancel_speech();game.ui.close_menu()
    # A different model and a mesh mark reject a FEED-name-only special case.
    for name in ["Fists","Bow","Sword"]:
     game.items=[{"name":name}];game._fps_update_viewmodel(0);await settle()
     var pose:Vector3=game.fps_viewmodel.position
     await settle()
     check(game.fps_viewmodel.position.is_equal_approx(pose),name+": unmarked model pose remains stable")
    var mark:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2(0.4,0.2);mark.mesh=mesh
    mark.position=Vector3(0,0.1,0.2);mark.set_meta("readable_mark",true)
    game.fps_viewmodel.add_child(mark)
    var nested:=Node3D.new();game.fps_viewmodel.add_child(nested)
    var other:=Label3D.new();other.text="MARK";other.font_size=roundi(32*scale);other.pixel_size=0.0025;other.position=Vector3(0,0.1,0.2);nested.add_child(other)
    await settle();reading_clear(mark,"sword-mark");reading_clear(other,"nested-label")
    mark.queue_free();nested.queue_free()
 print("VIEWMODEL TEXT PASS" if failures.is_empty() else "VIEWMODEL TEXT FAIL "+str(failures.size()))
 if not output_dir.is_empty():
  var file=FileAccess.open(output_dir.path_join("viewmodel.json"),FileAccess.WRITE)
  file.store_string(JSON.stringify({"records":records,"failures":failures,"packed":not FileAccess.file_exists("res://project.godot"),"setup":"Real game/helper; items granted, scripts canceled, physics paused. Injected sword mark/nested label test generic handling."},"\t"))
 game.vm.cancel_all();game.ui.cancel_speech();game.queue_free()
 for i in 4:await process_frame
 quit(0 if failures.is_empty() else 1)
