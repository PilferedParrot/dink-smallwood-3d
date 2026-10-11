extends "../tests/fps_capture.gd"
# Diagnostic-only isolation in the frozen packed game. No source state is saved.
func _shoot(game, view: Dictionary, out_dir: String) -> void:
 var id := 0
 for candidate in game.entities:
  var e: Dictionary=game.entities[candidate]
  if int(e.get("editor_num",-1))==2 and int(e.get("pseq",e.get("seq",0)))==32 and int(e.get("pframe",e.get("frame",0)))==8:
   id=int(candidate)
 if id==0:
  push_error("Source768 editor2 tree08 missing")
  quit(2)
  return
 var visual: Node3D=game.visuals[id]
 var card := visual.get_node("Model") as Sprite3D
 var e: Dictionary=game.entities[id]
 var d: Dictionary=game._frame(32,8)
 var image: Image=game.fp_world.sprite_image(str(d.path))
 var opaque := 0
 var below_ground := 0
 for y in image.get_height():
  for x in image.get_width():
   var color := image.get_pixel(x,y)
   if color.a<=0.5 or color.r+color.g+color.b<11.0/255.0:continue
   opaque+=1
   var local := Vector3((float(x)+0.5-float(d.dx))*card.pixel_size,
    (float(d.dy)-float(y)-0.5)*card.pixel_size,0)
   if (card.global_transform*local).y<0:below_ground+=1
 var bounds := card.get_aabb()
 var report := {"screen":game.current_screen,"editor_index":2,"entity_id":id,
  "source_seq":32,"source_frame":8,"source_xy":[e.x,e.y],"path":d.path,
  "model_key":game.fp_world.model_key(e),"node":str(card.get_path()),
  "texture_size_px":[image.get_width(),image.get_height()],"source_hotspot_px":[d.dx,d.dy],
  "model_origin_world":[card.global_position.x,card.global_position.y,card.global_position.z],
  "local_quad_y_m":[bounds.position.y,bounds.end.y],"pixel_size_m":card.pixel_size,
  "sprite_offset_px":[card.offset.x,card.offset.y],"billboard":card.billboard,
  "region_enabled":card.region_enabled,"depth_shader":card.material_override is ShaderMaterial,
  "opaque_nonshadow_source_pixels":opaque,"nonshadow_source_pixels_below_ground":below_ground,
  "source_fir_constructor":visual.has_meta("whole_fir"),"view":view}
 var file=FileAccess.open(out_dir.path_join(str(view.name)+"-provenance.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t"))
 await super._shoot(game,view,out_dir)
 var shown := card.visible
 card.visible=false
 var hidden := view.duplicate(true)
 hidden.name=str(view.name)+"-without-editor2"
 await super._shoot(game,hidden,out_dir)
 card.visible=shown
 print("CROWN PROVENANCE ",JSON.stringify(report))
