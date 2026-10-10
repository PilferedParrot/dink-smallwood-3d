extends SceneTree
const GAME = preload("res://scripts/fps_game.gd")
var game
var out := ""
var records: Array = []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()
func grab(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
	records.append({"name":name,"screen":game.current_screen,"player":str(game._position2(1)),"camera":str(game.camera.global_transform),"modal":game.ui.modal,"heading":game.ui.heading.text,"selected":game.ui.equipment_name.text,"version":ProjectSettings.get_setting("application/config/version")})
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game=GAME.new();game.test_mode=true;root.add_child(game);await process_frame
	await game._new_game();game.vm.cancel_all();game.playing=true;game.ui.close_menu();game.set_physics_process(false);game.test_mode=false
	var mother := 0
	for id in game.entities:
		if str(game.entities[id].get("script",""))=="s1-h1-m": mother=int(id)
	game.entities[1].x=323.0;game.entities[1].y=250.0;game._sync_fps_camera()
	game.ui.set_text_scale(1.3)
	game._dialogue("Dink, would you go feed the pigs?",mother,{"script":"s1-h1-m","sprite_id":mother})
	await grab("F1-mother-130pct")
	game.ui._continue_dialogue();for i in 3: await process_frame
	game.ui.set_text_scale(1.0)
	game.vm.globals.vision=0;game.load_map(439,false);game.vm.cancel_all()
	game.entities[1].x=510.0;game.entities[1].y=300.0;game.entities[1].frozen=false;game.fps_yaw=0.0;game.fps_pitch=-0.08;game._sync_fps_camera()
	game.items=[{"name":"Fists","script":"item-fst"},{"name":"Bow","script":"item-b1"}]
	game.magic_items=[{"name":"Fireball","script":"item-fb"}]
	game.vm.globals.cur_weapon=1;game.vm.globals.cur_magic=1
	await game._equip(1,false)
	game._fps_update_viewmodel(0.0)
	var stats: Dictionary=game.vm.globals.duplicate();game._add_equipment_stats(stats);game.ui.show_hud(stats)
	await grab("F2-equipped-hud")
	await game.dink_call("say",["I should find the pigs before Mother gets angry.",1],{})
	await grab("F12-timed-dink-card")
	game.ui.cancel_speech();game.ui.show_inventory(game.items,game.magic_items)
	var chest=game.ui.column.get_node("EquipmentChest")
	for i in 3: await process_frame
	chest.get_node("Item0").grab_focus()
	await grab("F14-selected-fists-equipped-bow")
	var f=FileAccess.open(out.path_join("run.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"setup":"Controlled presentation fixture skips progression; source actors/art and actual equip arm/disarm and dink_call say paths. F1 invokes source line directly, not original script scheduling. F14 intentionally selects Fists while Bow is equipped.","records":records},"\t"))
	game.vm.cancel_all();game.queue_free();await process_frame;quit()
