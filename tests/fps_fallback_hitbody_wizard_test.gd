extends SceneTree
# Isolated interaction fixture: skips campaign startup/progression. The approach
# and wizard pose reproduce INTEGRATE's earned map6 save; E uses real input.
class ProbeGame extends "res://scripts/fps_game.gd":
 var talks: Array[int] = []
 func _run_event(id: int, event: String) -> void:
  if event == "talk": talks.append(id)
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
 if not ok: failures.append(label)
func editor_id(game, index: int) -> int:
 for id in game.entities:
  if int(game.entities[id].get("editor_num",-1)) == index: return int(id)
 return 0
func key(code: int, pressed: bool):
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 Input.parse_input_event(event)
 Input.flush_buffered_events()
 await process_frame
 await physics_frame
func run():
 var game := ProbeGame.new()
 game.test_mode = true
 root.add_child(game)
 await process_frame
 await game._new_game()
 game.vm.cancel_all()
 game.load_map(6,false)
 game.vm.cancel_all()
 game.ui.close_menu()
 var wizard := editor_id(game,23)
 var shelf := editor_id(game,18)
 check(wizard != 0 and shelf != 0,"authored wizard and shelf exist")
 if wizard != 0 and shelf != 0:
  game.entities[wizard].y = 135.082992553711
  game.entities[wizard].frozen = true
  game.fp_world.update_visual(wizard)
  game.entities[1].x = 440.025939941406
  game.entities[1].y = 196.82275390625
  game.entities[1].frozen = false
  game.entities[1].nocontrol = 0
  game.playing = true
  game.changing = false
  game.fps_yaw = -6.28276515787632
  game.fps_pitch = -0.08
  game._sync_fps_camera()
  game._fps_set_facing_from_camera()
  for i in 3: await physics_frame
  check(not game._blocked(game._position2(1),1),"approach starts in free source space")
  check(game._fps_ray_reaches(wizard),"approach ray reaches wizard past bookshelf")
  await key(KEY_E,true)
  await key(KEY_E,false)
  check(wizard in game.talks,"approach E dispatches wizard TALK")
  # A visible foreign occluder must still stop the ray (aim, melee); it no longer stops TALK.
  var blocker := StaticBody3D.new()
  blocker.collision_layer = 1
  blocker.collision_mask = 0
  blocker.position = game.fp_world.point(440,170)+Vector3.UP
  var shape := CollisionShape3D.new()
  var box := BoxShape3D.new()
  box.size = Vector3(4,4,0.2)
  shape.shape = box
  blocker.add_child(shape)
  var face := MeshInstance3D.new()
  var mesh := BoxMesh.new()
  mesh.size = box.size
  face.mesh = mesh
  blocker.add_child(face)
  game.scene_root.add_child(blocker)
  await physics_frame
  check(not game._fps_ray_reaches(wizard),"visible foreign solid blocks wizard")
  game.talks.clear()
  await key(KEY_E,true)
  await key(KEY_E,false)
  # Talk has no occlusion in FreeDink (freedink.cpp:240-305, a point-in-box test only): the
  # solid still blocks the ray, kept for aim and melee, but not Talk.
  check(wizard in game.talks,"foreign solid does not stop wizard TALK (original has no occlusion)")
 game.queue_free()
 await process_frame
 if failures.is_empty(): print("FALLBACK WIZARD PASS")
 else: print("FALLBACK WIZARD FAILURES: ",failures)
 quit(0 if failures.is_empty() else 1)
