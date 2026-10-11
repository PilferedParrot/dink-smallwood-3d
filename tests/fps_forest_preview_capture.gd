extends "fps_capture.gd"
# External preview-only capture harness. Production never calls the proposal.
# All game simulation and original art come from --main-pack; the proposal
# resource must be included in that export. Default is the unmodified scene.
var preview_configured := false
func _shoot(game, view: Dictionary, out_dir: String) -> void:
 if not preview_configured:
  preview_configured=true
  if "--rc5-forest-preview" in OS.get_cmdline_user_args():
   var proposal=load("res://prototype/rc5_forest_preview.gd")
   if proposal==null:
    push_error("Preview resource is missing from this package")
    quit(2)
    return
   var preview=proposal.new(game.fp_world)
   var group=preview.build(game.scene_root,game.current_screen,true,
    "--rc5-forest-floor" in OS.get_cmdline_user_args())
   if group==null:
    push_error("Preview did not build the requested fixture")
    quit(2)
    return
   print("RC5 FOREST PREVIEW screen=",game.current_screen," children=",group.get_child_count())
 await super._shoot(game,view,out_dir)
