extends SceneTree
# Real current FPS collision queries, independent of the Python geometry mask.
const HOST = preload("res://../tests/collision_survey_host.gd")
func _initialize() -> void:
 var path := ""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): path=arg.trim_prefix("--out=")
 var host=HOST.new()
 host.world=host._read_json("res://data/world.json")
 host.sequences=host._read_json("res://data/sequences.json").sequences
 host.footprints=host._read_json("res://data/footprints.json").screens
 host.vm=host.VM.new(host)
 var result := {}
 for key in host.world.screens:
  if bool(host.world.screens[key].get("indoor",false)): continue
  var n := int(key)
  host.load_map(n,false)
  var points := []
  for y in range(7,400,37):
   for x in range(27,620,37): points.append([x,y,host._blocked(Vector2(x,y),1)])
  # Include all four world edges, where wall clearance crosses screen bounds.
  for y in range(0,400,7):
   for x in [20,21,24,615,618,619]:points.append([x,y,host._blocked(Vector2(x,y),1)])
  for x in range(20,620,7):
   for y in [0,1,4,395,398,399]:points.append([x,y,host._blocked(Vector2(x,y),1)])
  result[key]=points
 var f=FileAccess.open(path,FileAccess.WRITE)
 f.store_string(JSON.stringify({"schema":"rc5-native-collision-probes-1","screens":result}))
 print("RC5 CURRENT PROBES DONE screens=",result.size())
 host.vm=null
 host.free()
 quit()
