extends SceneTree
# Exported production game, real key/GUI input and a real isolated save.
# Scenario setup loads768 without campaign/startup progression; interactions
# run the original savebot script. No player profile is read or written.
const GAME = preload("res://scripts/fps_game.gd")
var game
var out_dir := ""
var approach := "south"
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
 if not ok:
  failures.append(message)
  push_error(message)
func key(code: int, pressed: bool) -> void:
 var event := InputEventKey.new()
 event.physical_keycode=code;event.keycode=code;event.pressed=pressed
 Input.parse_input_event(event);Input.flush_buffered_events()
 await process_frame
 await physics_frame
func tap(code: int) -> void:
 await key(code,true)
 await key(code,false)
 for _i in 4:await process_frame
func shot(name: String) -> void:
 if out_dir.is_empty():return
 await process_frame
 await RenderingServer.frame_post_draw
 var img := root.get_texture().get_image()
 check(img!=null and not img.is_empty(),"Rendered frame "+name)
 if img!=null and not img.is_empty():img.save_png(out_dir.path_join(name+".png"))
func wait_choices() -> bool:
 for _i in 180:
  if game.ui.dialogue_mode and game.ui.column.get_child_count()>0:return true
  await process_frame
 return false
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="):out_dir=arg.trim_prefix("--out-dir=")
  if arg.begins_with("--approach="):approach=arg.trim_prefix("--approach=")
 check(approach in ["south","north"],"Supported approach")
 if not out_dir.is_empty():DirAccess.make_dir_recursive_absolute(out_dir)
 root.size=Vector2i(960,540)
 game=GAME.new();game.test_mode=true;root.add_child(game)
 await process_frame
 await game._new_game()
 game.vm.cancel_all();game.ui.close_menu()
 game.load_map(768,false);game.vm.cancel_all();game.ui.close_menu()
 game.entities[1].x=322.0;game.entities[1].y=240.0 if approach=="south" else 20.0
 game.entities[1].frozen=false;game.entities[1].nocontrol=0
 game.playing=true;game.changing=false;game.fps_yaw=0.0 if approach=="south" else PI;game.fps_pitch=-0.45
 # Setup skips startup dialogue; the interaction must use real choice UI.
 game.test_mode=false
 game._sync_fps_camera()
 for _i in 3:await physics_frame
 var start: Vector2=game._position2(1)
 check(not game._blocked(start,1),"Source setup is free")
 await shot("0-approach")
 await key(KEY_W,true)
 var walking_frames := 0
 while (game._position2(1).y>185.0 if approach=="south" else game._position2(1).y<78.0) and walking_frames<120:
  await physics_frame
  walking_frames+=1
 await key(KEY_W,false)
 var stopped: Vector2=game._position2(1)
 check(start.distance_to(stopped)>40.0,"Real forward input walked to machine")
 check(game.current_screen==768 and not game._blocked(stopped,1),"Walk ends on free768ground")
 await shot("1-at-machine")
 var bot := 0
 for id in game.entities:
  if str(game.entities[id].get("script",""))=="savebot" and int(game.entities[id].get("editor_num",-1))==4:bot=int(id)
 check(bot!=0,"Original save machine exists")
 check(bot!=0 and game._fps_ray_reaches(bot),"Own physics surface reached")
 await tap(KEY_E)
 check(await wait_choices(),"Talk input opens original savebot choice")
 await shot("2-save-choice")
 await tap(KEY_ENTER)
 check(await wait_choices(),"GUI input opens save-slot choice")
 await shot("3-slot-choice")
 await tap(KEY_ENTER)
 for _i in 15:await process_frame
 var path := "user://adventure.json"
 check(FileAccess.file_exists(path),"Original save_game writes isolated adventure")
 var saved: Dictionary=game._read_json(path)
 check(int(saved.get("screen",0))==768 and int(saved.get("version",0))==1,"Saved768snapshot has supported format")
 check(not game.entities[1].get("frozen",true),"Save script restores movement")
 await shot("4-saved")
 var position_before_load: Vector2 = game._position2(1)
 game.entities[1].x=position_before_load.x+10.0
 check(game._load_game(path),"Actual save loads")
 check(game.current_screen==768 and game._position2(1).distance_to(position_before_load)<.01,"Load restores saved player position")
 var report := {"setup":"isolated profile; new_game then scripts-off scenario768; normal campaign route/startup skipped", "approach":approach,
  "walk_input":"W","walking_frames":walking_frames,"start_xy":[start.x,start.y],"stopped_xy":[stopped.x,stopped.y],
  "talk_input":"E","save_gui_input":"Enter twice","save_path":ProjectSettings.globalize_path(path),
  "saved_screen":saved.get("screen",0),"reloaded":failures.is_empty(),"failures":failures}
 if not out_dir.is_empty():
  var file=FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
 print("FPS PACKED SAVE PASS" if failures.is_empty() else "FPS PACKED SAVE FAIL",JSON.stringify(report))
 game.vm.cancel_all();game.queue_free();await process_frame
 quit(0 if failures.is_empty() else 1)
