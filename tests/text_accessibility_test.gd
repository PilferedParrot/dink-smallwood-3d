# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## UI fixture, not campaign progression. The same census can render packed resources.
const READING_LAYOUT = preload("text_layout_oracle.gd")
const UI = preload("res://scripts/game_ui.gd")
var ui
var failures: Array[String] = []
var records: Array = []
var output_dir := ""
var capture := false
var case_tag := ""
var only_large := false
var large_window := false

func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out-dir="): output_dir = arg.trim_prefix("--out-dir=")
  if arg == "--capture": capture = true
  if arg == "--large-only": only_large = true
  if arg == "--1080": large_window = true
 run.call_deferred()

func check(ok: bool, message: String) -> void:
 if not ok:
  failures.append(case_tag + ": " + message)
  if failures.size() <= 30: push_error(failures.back())

func settle() -> void:
 for i in 14: await process_frame

func key(code: Key) -> void:
 for pressed in [true,false]:
  var event := InputEventKey.new()
  event.keycode=code;event.physical_keycode=code;event.pressed=pressed
  Input.parse_input_event(event);Input.flush_buffered_events()
  await process_frame
 await settle()

func has_scroll(node: Node) -> bool:
 var parent: Node = node.get_parent()
 while parent != null:
  if parent is ScrollContainer: return true
  parent = parent.get_parent()
 return false

func texts(node: Node, result: Array[Control]) -> void:
 if node is CanvasItem and not node.is_visible_in_tree(): return
 if (node is Label or node is Button) and not node.text.is_empty(): result.append(node)
 for child in node.get_children(): texts(child, result)

func visible_rect(node: Control, viewport: Rect2) -> Rect2:
 var rect := node.get_global_rect().intersection(viewport)
 var parent: Node = node.get_parent()
 while parent != null:
  if parent is ScrollContainer: rect = rect.intersection(parent.get_global_rect())
  parent = parent.get_parent()
 return rect

# Intentionally uses public engine minima rather than the builder's layout variables.
func defects(nodes: Array[Control], viewport: Rect2) -> Array[String]:
 var found: Array[String] = []
 for node in nodes:
  var rect := node.get_global_rect()
  var minimum := node.get_combined_minimum_size()
  if rect.size.x + 1 < minimum.x or rect.size.y + 1 < minimum.y:
   found.append("text below native minimum: " + node.text.left(65))
  if not has_scroll(node) and not viewport.grow(1).encloses(rect):
   found.append("text outside viewport: " + node.text.left(65))
  if node.get_parent() is Control:
   var parent: Rect2 = node.get_parent().get_global_rect()
   if rect.position.x < parent.position.x - 1 or rect.end.x > parent.end.x + 1:
    found.append("text outside parent's width: " + node.text.left(65))
 for i in nodes.size():
  for j in range(i + 1, nodes.size()):
   var a: Control = nodes[i]
   var b: Control = nodes[j]
   if a.is_ancestor_of(b) or b.is_ancestor_of(a): continue
   var ra := visible_rect(a, viewport)
   var rb := visible_rect(b, viewport)
   if ra.size.x > 2 and ra.size.y > 2 and rb.size.x > 2 and rb.size.y > 2 and ra.grow(-1).intersects(rb.grow(-1)):
    found.append("visible text overlaps: " + a.text.left(30) + " / " + b.text.left(30))
 return found

func calibrate() -> void:
 var parent := Control.new()
 root.add_child(parent)
 parent.size = Vector2(600,200)
 var first := Label.new()
 first.text = "Known good readable label"
 first.position = Vector2(20,20)
 parent.add_child(first)
 first.size = first.get_combined_minimum_size()
 var second := Label.new()
 second.text = "Independent look-alike"
 second.position = Vector2(20,100)
 parent.add_child(second)
 second.size = second.get_combined_minimum_size()
 var pair: Array[Control] = [first, second]
 check(defects(pair,Rect2(Vector2.ZERO,root.size)).is_empty(),"calibration accepts nonoverlapping look-alike")
 second.position = first.position
 check(not defects(pair,Rect2(Vector2.ZERO,root.size)).is_empty(),"calibration rejects overlap")
 second.position = Vector2(590,100)
 check(not defects(pair,Rect2(Vector2.ZERO,root.size)).is_empty(),"calibration rejects parent overflow")
 parent.free()

func scan(tag: String, save := true) -> void:
 case_tag = tag
 await settle()
 var nodes: Array[Control] = []
 texts(ui.root,nodes)
 var found := defects(nodes,Rect2(Vector2.ZERO,ui.root.size))
 for defect in found: check(false,defect)
 if ui.panel.visible:
  check(Rect2(Vector2.ZERO,ui.root.size).grow(1).encloses(ui.panel.get_global_rect()),"panel stays on screen")
  if ui.hint_backing.visible:
   check(not ui.panel.get_global_rect().grow(-1).intersects(ui.hint_backing.get_global_rect().grow(-1)),"hint and panel stay apart")
 if ui.page == "dialogue":
  for defect in READING_LAYOUT.defects(ui): check(false,defect)
  var dock: Rect2 = ui.status_dock.get_global_transform() * ui.status_dock.art_rect()
  var bounds: Rect2 = ui.panel.get_global_rect()
  for vine in [ui.vines_left,ui.vines_right]: bounds = bounds.merge(vine.get_global_rect())
  check(not bounds.intersects(dock),"speech does not cover original status art")
  if ui.status_dock.has_method("readout_top"):
   check(bounds.end.y <= ui.status_dock.readout_top()+1,"speech stays above enlarged status values")
 if ui.status_dock.visible and ui.text_scale > 1.3:
  var art: Rect2 = ui.status_dock.get_global_transform() * ui.status_dock.art_rect()
  check(ui.status_dock.readout.get_global_rect().end.y < art.position.y,"enlarged readout sits above original art")
  for label in ui.status_dock.readout_labels.values():
   check(label.get_theme_font_size("font_size") == roundi(15*ui.status_dock._dock_scale*ui.text_scale),"status keeps requested enlarged font")
 var boxes: Array = []
 for node in nodes:
  if ui.plain_font: check(node.get_theme_font("font").get_font_name().contains("Atkinson"),"plain font reaches " + str(node.get_path()))
  var r := node.get_global_rect()
  boxes.append({"text":node.text,"path":str(node.get_path()),"rect":[r.position.x,r.position.y,r.size.x,r.size.y],"font_size":node.get_theme_font_size("font_size"),"font":node.get_theme_font("font").get_font_name(),"scrolling":has_scroll(node)})
 records.append({"tag":tag,"size":[root.size.x,root.size.y],"scale":ui.text_scale,"plain":ui.plain_font,"boxes":boxes})
 if capture and save:
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output_dir.path_join(tag + ".png"))

func focus_actions(tag: String) -> void:
 var last_scroll := Vector2(-1,-1)
 var frame_index := 0
 for node in ui._focusable_children(ui.panel):
  if not node.is_visible_in_tree() or (node is BaseButton and node.disabled): continue
  if capture:
   var exposed: Rect2 = ui.menu_scroll.get_global_rect()
   if ui.page == "controls": exposed = ui.controls_menu.scroll.get_global_rect()
   # The complete census focuses every action. Packed exposure frames need
   # only move to actions not already fully shown by the preceding frame.
   if exposed.grow(1).encloses(node.get_global_rect()): continue
  node.grab_focus()
  await settle()
  var area: Rect2 = ui.menu_scroll.get_global_rect()
  if ui.page == "controls" and ui.controls_menu.scroll.is_ancestor_of(node): area = ui.controls_menu.scroll.get_global_rect()
  if ui.menu_scroll.is_ancestor_of(node) or (ui.page == "controls" and ui.controls_menu.scroll.is_ancestor_of(node)):
   # Oversize wrapped labels can scroll; each focusable action must fit whole.
   check(area.grow(1).encloses(node.get_global_rect()),tag + " focused action fully visible: " + str(node.get_path()))
  var scroll := Vector2(ui.menu_scroll.scroll_vertical, ui.controls_menu.scroll.scroll_vertical if ui.page == "controls" else 0)
  if capture and scroll != last_scroll:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_jpg(output_dir.path_join(tag + "-scroll-%02d.jpg" % frame_index),0.95)
   frame_index += 1
  last_scroll = scroll
 await scan(tag + "-last",false)
 if ui.page != "dialogue":
  await key(KEY_END)
  if ui.page == "title":
   check(ui.menu_scroll.get_global_rect().grow(1).encloses(ui.control_primer_label.get_global_rect()),"End exposes complete large-font title primer")
  await scan(tag + "-end",capture)

func find_tooltip(node: Node) -> PopupPanel:
 if node is PopupPanel and node.visible: return node
 for child in node.get_children():
  var found := find_tooltip(child)
  if found != null: return found
 return null

func equipment_tooltip() -> void:
 case_tag = "equipment-tooltip"
 var button: Button = ui.column.get_node("EquipmentChest/Item0")
 button.grab_focus()
 await settle()
 var event := InputEventMouseMotion.new()
 event.position = root.get_final_transform() * button.get_global_rect().get_center()
 event.global_position = event.position
 Input.parse_input_event(event);Input.flush_buffered_events()
 await create_timer(0.65).timeout
 var popup := find_tooltip(root)
 check(popup != null,"native hover tooltip opens")
 if popup != null:
  check(Rect2(Vector2.ZERO,root.size).encloses(Rect2(Vector2(popup.position),Vector2(popup.size))),"tooltip stays on screen")
  var nodes: Array[Control] = []
  texts(popup,nodes)
  check(not nodes.is_empty(),"native tooltip contains text")
  for label in nodes:
   check(label.get_theme_font_size("font_size") == roundi(18*ui.text_scale),"tooltip follows text size")
   if ui.plain_font: check(label.get_theme_font("font").get_font_name().contains("Atkinson"),"tooltip follows plain font")
   check(Rect2(Vector2.ZERO,Vector2(popup.size)).grow(1).encloses(label.get_global_rect()),"tooltip text fits its window")
  records.append({"tag":case_tag,"size":[root.size.x,root.size.y],"scale":ui.text_scale,"plain":ui.plain_font,"popup_position":[popup.position.x,popup.position.y],"popup_size":[popup.size.x,popup.size.y],"boxes":[]})
  if capture:
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output_dir.path_join("equipment-tooltip.png"))
 event = InputEventMouseMotion.new()
 event.position = Vector2.ZERO;event.global_position = Vector2.ZERO
 Input.parse_input_event(event);Input.flush_buffered_events()
 await settle()

func status_boundaries() -> void:
 for sample in [
  {"stats":{"life":-3,"lifemax":10,"level":0,"exp":-5},"life":"Life 0 / 10","level":"Lv 1","exp":"EXP 0 / 100"},
  {"stats":{"life":25,"lifemax":10,"level":2,"exp":350},"life":"Life 10 / 10","level":"Lv 2","exp":"EXP 350 / 400"},
  {"stats":{"life":8,"lifemax":0,"level":40,"exp":100000},"life":"Life 1 / 1","level":"Lv 40","exp":"EXP 100000 / 99999"}]:
  ui.status_dock.update_stats(sample.stats)
  for field in ["life","level","exp"]:
   check(ui.status_dock.readout_labels[field].text == sample[field],"status boundary " + field + ": " + str(sample.stats))

func matrix() -> void:
 status_boundaries()
 ui.show_title(true)
 await scan("title")
 await focus_actions("title")
 ui._button_pressed("new_game",null)
 await scan("loading")
 ui.show_pause()
 await scan("pause")
 await focus_actions("pause")
 ui.show_settings({"text_scale":ui.text_scale,"plain_font":ui.plain_font})
 await scan("settings")
 var slider: HSlider
 for node in ui.column.get_children():
  if node.get_meta("setting_key","") == "text_scale": slider = node
 check(slider != null and slider.max_value == 2.0,"Settings offers200%")
 await focus_actions("settings")
 ui.show_controls()
 for group in ui.bindings.SCOPES:
  ui.controls_menu._select_group(group)
  await scan("controls-" + group)
  await focus_actions("controls-" + group)
 ui.controls_menu._select_group("fps")
 ui.controls_menu._capture("attack",0)
 await scan("capture")
 ui.controls_menu.record = ui.INPUT_BINDINGS.key(KEY_SPACE)
 ui.controls_menu._propose()
 await scan("proposal")
 ui.controls_menu._ask_remove()
 await scan("remove")
 ui.controls_menu._ask_reset("")
 await scan("reset")
 ui.controls_menu._finish({"ok":false,"error":"menu_device_required","device":"keyboard"})
 await scan("binding-error")
 ui.show_journal("You have explored Stonebrook.\n\nRecent conversations\n\n" + "A long journal entry remains readable while scrolling. ".repeat(50))
 check(ui.menu_footer.visible,"journal Back stays pinned outside the reading viewport")
 await scan("journal")
 await focus_actions("journal")
 ui.show_credits()
 await scan("credits")
 await focus_actions("credits")
 var items: Array = []
 var spells: Array = []
 for i in 16: items.append({"name":"Long named weapon %d" % i,"script":"item-fst"})
 for i in 9: spells.append({"name":"Fireball %d" % i,"script":"item-fb"})
 ui.show_hud({"life":12,"lifemax":20,"strength":999,"defense":999,"magic":999,"gold":999999,"exp":99999,"level":99,"cur_weapon":1,"cur_magic":1,"weapon_item":items[0],"spell_item":spells[0],"location":"Stonebrook village"})
 ui.show_inventory(items,spells)
 await scan("equipment")
 await focus_actions("equipment")
 await equipment_tooltip()
 var chest = ui.column.get_node("EquipmentChest")
 chest._turn_page(1)
 await scan("equipment-magic-page")
 ui._clear("World map","map")
 var picture := TextureRect.new()
 picture.texture = load("res://assets/tiles/map1.png")
 picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 picture.custom_minimum_size = Vector2(580,400)
 ui.column.add_child(picture)
 ui._button("Return to adventure","resume")
 await scan("map")
 await focus_actions("map")
 ui.show_dialogue("Please feed the pigs before you leave the village.","Mother")
 await scan("speech-short")
 ui.show_dialogue("Every line of a long conversation can be read. ".repeat(70),"Conversation")
 await scan("speech-long")
 ui.show_choices("Will you help the village? " + "The prompt has its own reading viewport. ".repeat(14),["Yes, I will help the village.","Tell me more before I choose.","I need some time to think about it."])
 await scan("choices")
 await focus_actions("choices")
 ui.show_choices("",["Let her know exactly how fruitless your search has been thus far","Leave"])
 await scan("choices-without-prompt")
 await focus_actions("choices-without-prompt")
 if not capture: await real_focus_regressions()
 ui.cancel_speech()
 ui.close_menu()
 ui.show_speech("The last line remains readable.","Dink",1,0,true)
 ui.speech_waits_for_me = true
 await scan("timed-speech")
 ui.cancel_speech()
 ui.close_menu()
 ui.gameplay_hint_deadline_msec = Time.get_ticks_msec()+60000
 await scan("hud-help")
 check(ui.compass_label.get_theme_font_size("font_size") == roundi(18*ui.text_scale),"location respects text size")
 ui.show_hud({"life":12,"lifemax":20,"strength":12,"defense":8,"magic":4,"gold":165,"exp":45,"level":2,"location":"Stonebrook"})
 await scan("hud-normal")
 ui.notify("Adventure saved. You can continue exploring the village.")
 await scan("toast")
 ui.show_pause()
 ui.notify("Could not save the adventure. Try another save location.")
 await scan("modal-feedback")

func run() -> void:
 # Embed the native popup only so viewport captures include the tooltip window.
 root.gui_embed_subwindows = true
 root.size = Vector2i(1920,1080) if large_window else Vector2i(1280,800)
 case_tag="calibration"
 calibrate()
 ui=UI.new()
 root.add_child(ui)
 var sizes := [root.size] if only_large else [Vector2i(1280,800),Vector2i(1920,1080)]
 for size in sizes:
  root.size = size
  for plain in ([true] if only_large else [false,true]):
   for scale in ([2.0] if only_large else [1.0,1.5,2.0]):
    ui.set_text_scale(scale)
    ui.set_plain_font(plain)
    check(is_equal_approx(ui.text_scale,scale),"requested scale preserved")
    await matrix()
    print("TEXT MATRIX ",size," plain=",plain," scale=",scale," failures=",failures.size())
 if not output_dir.is_empty():
  var file := FileAccess.open(output_dir.path_join("geometry.json"),FileAccess.WRITE)
  file.store_string(JSON.stringify({"records":records,"failures":failures,"packed":not FileAccess.file_exists("res://project.godot") and not FileAccess.file_exists("res://scripts/game_ui.gd"),"editor_runtime":OS.has_feature("editor"),"resource_root":ProjectSettings.globalize_path("res://"),"executable":OS.get_executable_path(),"bundled_font":ResourceLoader.exists("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"),"bundled_licence":FileAccess.file_exists("res://assets/fonts/AtkinsonHyperlegible-OFL.txt"),"setup":"UI-only fixture bypasses progression and world scripts; native layout and focus; not campaign proof."},"\t"))
 ui.cancel_speech()
 ui.queue_free()
 await process_frame
 print("TEXT ACCESSIBILITY PASS" if failures.is_empty() else "TEXT ACCESSIBILITY FAIL " + str(failures.size()))
 quit(0 if failures.is_empty() else 1)

func real_focus_regressions() -> void:
 # These real groups contain every one of the nine5101cae source-census clips.
 # Keep them in the same fixture as the twelve menu-focus regressions.
 var groups=[
  {"prompt":'( ) ; "A girl is about to die in a cult ritual.  What do you do?"',"answers":["Say something to the effect that you are going to save her","Agree that Mary should be sacrificed","Use brains and stay hidden"]},
  {"prompt":"","answers":["Ask Nadine why her house is such a mess","Offer to find Nadine's girl","Be rude to Nadine","Let her know exactly how fruitless your search has been thus far","Ask Nadine how she and Mary are doing","Leave"]},
  {"prompt":"","answers":["Ask for a date","Belittle her in front of the others to appear macho","Leave"]}]
 var before:int=failures.size()
 for group in groups:
  ui.cancel_speech()
  ui.show_choices(group.prompt,group.answers)
  await settle()
  for answer in ui.column.get_children():
   answer.grab_focus()
   for _i in 4: await process_frame
   check(ui.menu_scroll.get_global_rect().grow(1).encloses(answer.get_global_rect()),"source-focus-regression "+answer.text)
   check(READING_LAYOUT.defects(ui).is_empty(),"source-focus native reading minima")
 print("SOURCE FOCUS REGRESSIONS scale=",ui.text_scale," plain=",ui.plain_font," new_failures=",failures.size()-before)
