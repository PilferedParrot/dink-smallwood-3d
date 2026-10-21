extends SceneTree
# Class census for Talk acquisition. For each talk-able sprite the static audit found on or behind a solid
# (TALK_CENSUS = JSON [[screen, sprite], ...]), stand Dink on a 5 px grid in and around the original's reach
# box, once per cardinal facing, and compare who answers under the old rule (nearest within 90 px, 0.55 cone,
# physics ray to the target's own body: aa783f9) and the new one (FreeDink's box). Report: TALK_CENSUS_OUT.
class ProbeGame extends "res://scripts/fps_game.gd":
 pass
const TALK_ACQUIRE := preload("res://scripts/talk_acquire.gd")
func _initialize(): run.call_deferred()
func editor_id(game, index: int) -> int:
 for id in game.entities:
  if int(game.entities[id].get("editor_num",-1)) == index: return int(id)
 return 0
# The selection of fps_game.gd _talk() at aa783f9, verbatim.
func old_target(game, forward: Vector2) -> int:
 var candidate := 0
 var best := 90.0
 var origin: Vector2 = game._position2(1)
 for id in game.entities.keys():
  if int(id) == 1 or not game.entities.has(id): continue
  var e: Dictionary = game.entities[id]
  if int(e.get("active", 1)) == 0 or int(e.get("type", 1)) != 1 or str(e.get("script", "")).is_empty(): continue
  if game.vm._procedure_code(str(e.script).to_lower(), "talk").is_empty(): continue
  var offset: Vector2 = game._position2(int(id)) - origin
  if offset.length() < best and (offset.length() < 20.0 or offset.normalized().dot(forward) > 0.55) and game._fps_ray_reaches(int(id)):
   candidate = int(id)
   best = offset.length()
 return candidate
func label(game, id: int) -> String:
 if id == 0: return "nobody"
 var e: Dictionary = game.entities[id]
 return "%d:%s" % [int(e.get("editor_num",0)), str(e.get("script",""))]
func source_vision(game, screen: int, sprite: int) -> int:
 for raw in game.world.screens[str(screen)].get("sprites",[]):
  if int(raw.get("index",0)) == sprite: return int(raw.get("vision",0))
 return 0
func run():
 var wanted: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("TALK_CENSUS")))
 var game := ProbeGame.new()
 game.test_mode = true
 root.add_child(game)
 await process_frame
 await game._new_game()
 var report := []
 var pairs := {}
 var dirs := {8: Vector2(0,-1), 2: Vector2(0,1), 6: Vector2(1,0), 4: Vector2(-1,0)}
 var yaws := {8:0.0, 4:PI/2.0, 6:-PI/2.0, 2:PI}
 # One world per (screen, the sprite's own vision): the scroll exists only under vision 1.
 var by_screen := {}
 for pair in wanted:
  var vision := source_vision(game, int(pair[0]), int(pair[1]))
  var key := "%d/%d" % [int(pair[0]), vision]
  if not by_screen.has(key): by_screen[key] = {"screen": int(pair[0]), "vision": vision, "sprites": []}
  by_screen[key].sprites.append(int(pair[1]))
 for key in by_screen.keys():
  var screen: int = by_screen[key].screen
  game.vm.cancel_all()
  game.vm.globals["vision"] = by_screen[key].vision
  game.load_map(screen,false)
  for i in 3: await physics_frame
  game.ui.close_menu()
  var group_pairs := {}
  var seen_poses := {}
  for sprite in by_screen[key].sprites:
   var id := editor_id(game,sprite)
   var row := {"screen": screen, "sprite": sprite}
   if id == 0:
    row["absent"] = true
    report.append(row)
    continue
   var e: Dictionary = game.entities[id]
   row["script"] = str(e.get("script",""))
   row["pos"] = [e.x, e.y]
   row["talk_proc"] = not game.vm._procedure_code(str(e.script).to_lower(), "talk").is_empty()
   var pic: Dictionary = game._frame(int(e.get("pseq",0)), int(e.get("pframe",1)))
   var hardbox: Array = pic.get("hardbox", [0,0,0,0])
   row["hardbox"] = hardbox
   var per_dir := {}
   for dir in dirs.keys():
    var box: Array = TALK_ACQUIRE.reach_box(hardbox, Vector2(float(e.x), float(e.y)), dir)
    var x0 := floorf((box[0] - 20.0) / 5.0) * 5.0
    var y0 := floorf((box[1] - 20.0) / 5.0) * 5.0
    var cells := {"standable": 0, "new_inside": 0, "new_target": 0, "old_target": 0, "both_target": 0, "new_only_target": 0, "old_only_target": 0, "new_other": 0, "old_other": 0, "changed": 0}
    var changes := []
    var y := y0
    while y <= box[3] + 20.0:
     var x := x0
     while x <= box[2] + 20.0:
      var p := Vector2(x, y)
      x += 5.0
      if p.x < 20 or p.x > 619 or p.y < 0 or p.y > 399 or game._blocked(p, 1): continue
      cells.standable += 1
      game.entities[1].x = p.x
      game.entities[1].y = p.y
      game.fps_yaw = yaws[dir]
      game.fps_pitch = -0.08
      game._sync_fps_camera()
      var n: int = game._talk_target(dirs[dir])
      var o := old_target(game, dirs[dir])
      if TALK_ACQUIRE.contains(box, p): cells.new_inside += 1
      if n == id: cells.new_target += 1
      if o == id: cells.old_target += 1
      if n == id and o == id: cells.both_target += 1
      if n == id and o != id: cells.new_only_target += 1
      if o == id and n != id: cells.old_only_target += 1
      if n != 0 and n != id: cells.new_other += 1
      if o != 0 and o != id: cells.old_other += 1
      var pose_key := "%s,%s,%d" % [p.x, p.y, dir]
      if not seen_poses.has(pose_key):
       seen_poses[pose_key] = true
       if n != o:
        var pair_key := "%s -> %s" % [label(game, o), label(game, n)]
        group_pairs[pair_key] = int(group_pairs.get(pair_key, 0)) + 1
      if n != o:
       cells.changed += 1
       if changes.size() < 6: changes.append({"p": [p.x, p.y], "old": label(game, o), "new": label(game, n)})
     y += 5.0
    cells["samples"] = changes
    per_dir[str(dir)] = cells
   row["dirs"] = per_dir
   row["vision"] = by_screen[key].vision
   report.append(row)
  pairs[key] = {"poses": seen_poses.size(), "who_answers_changed": group_pairs}
 var f := FileAccess.open(OS.get_environment("TALK_CENSUS_OUT"), FileAccess.WRITE)
 f.store_string(JSON.stringify({"sprites": report, "pairs": pairs}, " "))
 f.close()
 print("TALK CENSUS DONE ", report.size())
 game.queue_free()
 await process_frame
 quit(0)
