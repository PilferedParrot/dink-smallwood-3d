extends SceneTree
# Talk acquisition by FreeDink's rule (freedink.cpp:240-305), on the earned
# bonca-complete save (tests/fixtures/talk): the wizard's scroll on map 6.
# Part 1 sets only Dink's pose and presses E through the real input path; part 2
# is a table over the box rule, each row cited. TALK_FLIP_ROW=<n> inverts one
# row's expectation to show the table can fail.
const TALK_ACQUIRE := preload("res://scripts/talk_acquire.gd")
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
func press_talk(game) -> Array[int]:
 game.talks.clear()
 await key(KEY_E,true)
 await key(KEY_E,false)
 return game.talks.duplicate()
func place(game, x: float, y: float, dir: int):
 var yaw := {8:0.0, 4:PI/2.0, 6:-PI/2.0, 2:PI}[dir] as float
 game.entities[1].x = x
 game.entities[1].y = y
 game.entities[1].frozen = false
 game.entities[1].nocontrol = 0
 game.playing = true
 game.changing = false
 game.fps_yaw = yaw
 game.fps_pitch = -0.08
 game._sync_fps_camera()
 for i in 2: await physics_frame
 game._fps_set_facing_from_camera()
 check(int(game.entities[1].dir) == dir,"pose (%s,%s) faces dir %d, got %d" % [x,y,dir,int(game.entities[1].dir)])

func run():
 var game := ProbeGame.new()
 game.test_mode = true
 root.add_child(game)
 await process_frame
 await game._new_game()
 game.vm.cancel_all()
 var save := ProjectSettings.globalize_path("res://").path_join("../tests/fixtures/talk/earned-bonca-complete.json").simplify_path()
 check(game._load_game(save),"earned save loads")
 game.vm.cancel_all()
 game.vm.globals["vision"] = 1
 game.load_map(6,true)
 for i in 30: await physics_frame
 game.vm.cancel_all()
 game.ui.close_menu()
 for id in game.entities.keys(): game._update_visual(id)
 var scroll := editor_id(game,24)
 check(scroll != 0 and str(game.entities[scroll].get("script","")) == "s1-mh-f","scroll s1-mh-f (map 6 editor 24) exists")
 if scroll == 0:
  print("TALK ACQUIRE FAILURES: ",failures)
  quit(1)
  return
 # Scroll hardbox [338,185,354,189] (frame 422:1 [-8,-2,8,2] at 346,187). Original box, grown 10:
 # [328,175,364,199]; facing 8 +35 below to y 234; facing 2 -35 above to y 140; facing 6 -50 left to
 # x 278; facing 4 +50 right to x 414. Wizard (440,163) box begins x 415 and y 146.. so poses below are the scroll's alone.
 # G1: inside the box, Talk must reach the scroll. Pose and expectation are written out here from the source rule.
 var inside := [
  ["earned approach, facing N (audit's pose)", 346.020080566406, 233.512420654297, 8],
  ["south, close, facing N", 346.0, 230.0, 8],
  ["south edge y=234 exactly, facing N", 346.0, 234.0, 8],
  ["east, facing W", 398.0, 195.0, 4],
  ["west, facing E", 300.0, 185.0, 6],
  ["north, facing S", 346.0, 165.0, 2],
  ["north-west, facing S", 330.0, 160.0, 2]]
 for row in inside:
  await place(game,row[1],row[2],row[3])
  var got := await press_talk(game)
  check(got == [scroll],"G1 %s: Talk answers %s, expected [scroll %d]" % [row[0],got,scroll])
 # G2: look-alikes 0.5 px outside the same boxes, and poses with the scroll behind Dink.
 var outside := [
  ["0.5 px below the south edge, facing N", 346.0, 234.5, 8],
  ["well south, facing N", 346.0, 250.0, 8],
  ["scroll behind Dink: north of it, facing N", 346.0, 170.0, 8],
  ["scroll behind Dink: south of it, facing S", 346.0, 225.0, 2],
  ["0.5 px west of the facing-E reach", 277.5, 185.0, 6],
  ["0.5 px east of the facing-W reach", 414.5, 185.0, 4],
  ["scroll behind Dink: west of it, facing W", 300.0, 185.0, 4],
  ["scroll behind Dink: east of it, facing E", 398.0, 195.0, 6],
  ["0.5 px west of the lateral edge, facing N", 327.5, 185.0, 8],
  ["0.5 px east of the lateral edge, facing N", 364.5, 200.0, 8]]
 for row in outside:
  await place(game,row[1],row[2],row[3])
  var got := await press_talk(game)
  check(got.is_empty(),"G2 %s: Talk answered %s, expected nobody" % [row[0],got])
 # Slot order and eligibility, at the audit's earned pose. A clone sits later in slot order.
 await place(game,346.020080566406,233.512420654297,8)
 var clone: Dictionary = game.entities[scroll].duplicate(true)
 clone.erase("editor_num")
 var clone_id: int = game.next_entity
 game.next_entity += 1
 game.entities[clone_id] = clone
 var got2 := await press_talk(game)
 check(got2 == [scroll],"two eligible: the earlier slot answers, got %s" % [got2])
 var saved_script: String = str(game.entities[scroll].script)
 game.entities[scroll].script = ""
 got2 = await press_talk(game)
 check(got2 == [clone_id],"a sprite in the box with no script does not end the search, got %s" % [got2])
 game.entities[scroll].script = saved_script
 game.entities[scroll].active = 0
 got2 = await press_talk(game)
 check(got2 == [clone_id],"an inactive sprite is skipped, got %s" % [got2])
 game.entities[scroll].active = 1
 clone.type = 0
 got2 = await press_talk(game)
 check(got2 == [scroll],"background (type 0) sprites hold no live slot (game_engine.cpp:483-506): scroll answers, got %s" % [got2])
 game.entities[scroll].active = 0
 got2 = await press_talk(game)
 check(got2.is_empty(),"a type 0 clone alone answers nobody, got %s" % [got2])
 game.entities[scroll].active = 1
 clone.type = 1
 clone.brain = 8
 got2 = await press_talk(game)
 check(got2 == [scroll],"brain 8 is excluded (freedink.cpp:254), got %s" % [got2])
 game.entities.erase(clone_id)
 # Real data: sprites the editor marks type 0 yet whose script has a TALK procedure (97:35 is one of seven
 # fountain pieces, 446:1 a hut piece). The original gives a type 0 sprite no script and no live slot
 # (game_engine.cpp:483-506, 580-584), so standing on one must answer nobody.
 for pair in [[97,35],[446,1]]:
  game.vm.cancel_all()
  game.vm.globals["vision"] = 0
  game.load_map(pair[0],false)
  for i in 3: await physics_frame
  game.ui.close_menu()
  var background := editor_id(game,pair[1])
  check(background != 0 and int(game.entities[background].get("type",1)) == 0 and not game.vm._procedure_code(str(game.entities[background].get("script","")).to_lower(),"talk").is_empty(),
   "%d:%d is a type 0 sprite with a TALK script" % pair)
  if background == 0: continue
  var spot: Vector2 = game._position2(background)
  for dir in [8,2,6,4]:
   await place(game,spot.x,spot.y,dir)
   var got3 := await press_talk(game)
   check(got3.is_empty(),"type 0 %d:%d, facing %d: Talk answered %s, expected nobody" % [pair[0],pair[1],dir,got3])
 game.queue_free()
 await process_frame
 table()
 if failures.is_empty(): print("TALK ACQUIRE PASS")
 else: print("TALK ACQUIRE FAILURES: ",failures)
 quit(0 if failures.is_empty() else 1)

# Part 2. Hardbox [-8,-2,8,2] at (100,100): grown box [82,88,118,112].
func table():
 var hb := [-8.0,-2.0,8.0,2.0]
 var at := Vector2(100,100)
 # [label, citation, dir, point, expected]
 var rows := [
  ["N: bottom reaches 35 past the grown box", "freedink.cpp:283", 8, Vector2(100,147), true],
  ["N: one half px beyond", "freedink.cpp:283", 8, Vector2(100,147.5), false],
  ["N: no extension at the top", "freedink.cpp:283", 8, Vector2(100,87.5), false],
  ["N: top edge inclusive", "rect.cpp:84-88", 8, Vector2(100,88), true],
  ["S: top reaches 35 past the grown box", "freedink.cpp:278", 2, Vector2(100,53), true],
  ["S: one half px beyond", "freedink.cpp:278", 2, Vector2(100,52.5), false],
  ["S: no extension at the bottom", "freedink.cpp:278", 2, Vector2(100,112.5), false],
  ["S: bottom edge inclusive", "rect.cpp:84-88", 2, Vector2(100,112), true],
  ["E: left reaches 50 past the grown box", "freedink.cpp:268", 6, Vector2(32,100), true],
  ["E: one half px beyond", "freedink.cpp:268", 6, Vector2(31.5,100), false],
  ["E: no extension at the right", "freedink.cpp:268", 6, Vector2(118.5,100), false],
  ["E: right edge inclusive", "rect.cpp:84-88", 6, Vector2(118,100), true],
  ["W: right reaches 50 past the grown box", "freedink.cpp:273", 4, Vector2(168,100), true],
  ["W: one half px beyond", "freedink.cpp:273", 4, Vector2(168.5,100), false],
  ["W: no extension at the left", "freedink.cpp:273", 4, Vector2(81.5,100), false],
  ["W: left edge inclusive", "rect.cpp:84-88", 4, Vector2(82,100), true],
  ["N: lateral edge is the grown 10 only", "freedink.cpp:262", 8, Vector2(81.5,100), false],
  ["N: lateral edge inclusive", "freedink.cpp:262", 8, Vector2(82,100), true],
  ["diagonal 7 extends nothing: below the grown box", "freedink.cpp:267-286", 7, Vector2(100,112.5), false],
  ["diagonal 9 extends nothing: above the grown box", "freedink.cpp:267-286", 9, Vector2(100,87.5), false],
  ["diagonal 3 extends nothing: right of the grown box", "freedink.cpp:267-286", 3, Vector2(118.5,100), false],
  ["diagonal 1 still has the grown box", "freedink.cpp:262", 1, Vector2(82,88), true]]
 var flip := int(OS.get_environment("TALK_FLIP_ROW")) if OS.get_environment("TALK_FLIP_ROW") != "" else -1
 for i in rows.size():
  var row: Array = rows[i]
  var expected: bool = row[4]
  if i == flip: expected = not expected
  var got: bool = TALK_ACQUIRE.contains(TALK_ACQUIRE.reach_box(hb,at,row[2]),row[3])
  check(got == expected,"G3 row %d %s (%s): box test %s, expected %s" % [i,row[0],row[1],got,expected])
 # Facing: the camera's ground heading to the nearest axis; an exact 45 degrees falls to N/S
 # (brain_keyboard.cpp:554-557 freezes 1,3 to 2 and 7,9 to 8).
 var heading := [
  [Vector2(0,-1),8],[Vector2(0,1),2],[Vector2(1,0),6],[Vector2(-1,0),4],
  [Vector2(1,-1),8],[Vector2(1,1),2],[Vector2(-1,-1),8],[Vector2(-1,1),2],
  [Vector2(0.6,-0.5),6],[Vector2(0.5,-0.6),8],[Vector2(-0.6,0.5),4],[Vector2(-0.5,0.6),2]]
 for h in heading:
  check(TALK_ACQUIRE.facing(h[0]) == h[1],"G3 facing %s -> %d, got %d" % [h[0],h[1],TALK_ACQUIRE.facing(h[0])])
