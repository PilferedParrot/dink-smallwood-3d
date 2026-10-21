# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Rendered regression, no campaign progression. Trace every drawn frame, not
## elapsed time, for the source/menu focus cases and native pad layout.
const UI=preload("res://scripts/game_ui.gd")
var ui
var failures:Array[String]=[]
var watched:=0
var source_seen:=0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,message:String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func settle(count:int=6) -> void:
	for _i in count: await process_frame
func watch(target:Control,tag:String) -> void:
	watched+=1
	for frame in range(1,15):
		await RenderingServer.frame_post_draw
		if target==null: target=root.gui_get_focus_owner()
		check(target!=null,tag+": focus exists at drawn frame"+str(frame))
		if target==null: continue
		check(root.gui_get_focus_owner()==target,tag+": selected action stable at drawn frame"+str(frame))
		var parent=target.get_parent()
		while parent!=null and not parent is ScrollContainer: parent=parent.get_parent()
		if parent==null: continue
		var area:Rect2=parent.get_global_rect()
		var rect:Rect2=target.get_global_rect()
		check(area.grow(1).encloses(rect),tag+": focused action whole from first drawn frame, frame"+str(frame))
		print("FOCUS_DRAW ",JSON.stringify({"tag":tag,"frame":frame,"scale":ui.text_scale,"plain":ui.plain_font,"viewport":[area.position.x,area.position.y,area.size.x,area.size.y],"target":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"scroll":parent.scroll_vertical}))
func source_cases() -> void:
	var groups=[
		{"prompt":'( ) ; "A girl is about to die in a cult ritual.  What do you do?"',"answers":["Say something to the effect that you are going to save her","Agree that Mary should be sacrificed","Use brains and stay hidden"]},
		{"prompt":"","answers":["Ask Nadine why her house is such a mess","Offer to find Nadine's girl","Be rude to Nadine","Let her know exactly how fruitless your search has been thus far","Ask Nadine how she and Mary are doing","Leave"]},
		{"prompt":"","answers":["Ask for a date","Belittle her in front of the others to appear macho","Leave"]}]
	for config in [[1280,800,1.5,false],[1280,800,2.0,false],[1280,800,2.0,true],[1920,1080,2.0,false],[1920,1080,2.0,true]]:
		root.size=Vector2i(config[0],config[1])
		ui.set_text_scale(config[2]);ui.set_plain_font(config[3])
		for group in groups:
			ui.show_choices(group.prompt,group.answers)
			await settle()
			for answer in ui.column.get_children():
				answer.grab_focus()
				var selected:bool=answer.text=="Agree that Mary should be sacrificed"
				selected=selected or (not config[3] and config[2]==2.0 and answer.text in ["Let her know exactly how fruitless your search has been thus far","Belittle her in front of the others to appear macho"])
				if selected:
					source_seen+=1
					await watch(answer,"source-"+str(source_seen))
				else: await settle(4)
func menu_cases() -> void:
	for size in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		for plain in [false,true]:
			for scale in [1.5,2.0]:
				ui.set_text_scale(scale);ui.set_plain_font(plain)
				ui.show_credits()
				await watch(null,"credits-"+str(size))
	for config in [[1280,800,false],[1280,800,true],[1920,1080,false]]:
		root.size=Vector2i(config[0],config[1])
		ui.set_text_scale(2.0);ui.set_plain_font(config[2])
		var items:Array=[]
		var spells:Array=[]
		for i in 16: items.append({"name":"Long named weapon %d"%i,"script":"item-fst"})
		for i in 9: spells.append({"name":"Fireball %d"%i,"script":"item-fb"})
		ui.show_hud({"life":12,"lifemax":20,"strength":999,"defense":999,"magic":999,"gold":999999,"exp":99999,"level":99,"cur_weapon":1,"cur_magic":1,"weapon_item":items[0],"spell_item":spells[0],"location":"Stonebrook village"})
		ui.show_inventory(items,spells)
		var magic:Control=ui.column.get_node("EquipmentChest/Magic0")
		magic.grab_focus()
		await watch(magic,"equipment-"+str(root.size))
	root.size=Vector2i(1920,1080)
	ui.set_text_scale(2.0);ui.set_plain_font(false)
	ui.show_controls()
	ui.controls_menu._select_group("menu")
	await settle()
	for node in ui._focusable_children(ui.panel):
		if not node.is_visible_in_tree() or (node is BaseButton and node.disabled): continue
		node.grab_focus()
		await watch(node,"controls-"+str(node.get_meta("controls_token",node.name)))
func run() -> void:
	ui=UI.new();root.add_child(ui)
	await settle()
	await source_cases()
	check(source_seen==9,"Rendered trace retains all nine original source cases")
	await menu_cases()
	check(watched>=21,"Rendered trace retains the twelve menu cases plus source cases")
	ui.queue_free()
	await settle(2)
	print("FOCUS DRAW PASS cases=",watched if failures.is_empty() else "FAIL "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
