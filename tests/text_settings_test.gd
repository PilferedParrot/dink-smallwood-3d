# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Isolated fixture. Actual key events change Settings; process restart proves persistence.
const GAME = preload("res://scripts/fps_game.gd")
var game
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 if not ok: failures.append(message); push_error(message)
func settle() -> void:
 for i in 12: await process_frame
func tap(key: Key) -> void:
 for pressed in [true,false]:
  var event := InputEventKey.new()
  event.physical_keycode=key;event.keycode=key;event.pressed=pressed
  Input.parse_input_event(event);Input.flush_buffered_events()
  await process_frame
 await settle()
func run() -> void:
 root.size=Vector2i(1280,800)
 game=GAME.new();game.test_mode=true
 root.add_child(game)
 await process_frame
 game.set_physics_process(false)
 game.vm.cancel_all()
 var phase := OS.get_cmdline_user_args()[0]
 if phase == "write":
  check(is_equal_approx(game.ui.text_scale,1.0) and not game.ui.plain_font,"Default remains100%/default font")
  game.ui.show_settings(game.settings)
  await settle()
  var font: Button
  var slider: HSlider
  for node in game.ui.column.get_children():
   if node.get_meta("setting_key","") == "plain_font": font=node
   if node.get_meta("setting_key","") == "text_scale": slider=node
  check(font != null and slider != null,"Settings expose independent font and size")
  font.grab_focus()
  await tap(KEY_ENTER)
  check(game.ui.plain_font and bool(game.settings.plain_font),"Real confirmation applies plain font")
  for size in [Vector2i(1280,800),Vector2i(1920,1080)]:
   root.size=size
   for plain in [false,true]:
    game.settings.text_scale=1.0;game.settings.plain_font=plain;game._apply_settings()
    game.ui.show_settings(game.settings)
    await settle()
    for node in game.ui.column.get_children():
     if node.get_meta("setting_key","")=="text_scale":slider=node
     if node.get_meta("setting_key","")=="plain_font":font=node
    slider.grab_focus()
    for i in 20:
     await tap(KEY_RIGHT)
     check(game.ui.menu_scroll.get_global_rect().grow(1).encloses(slider.get_global_rect()),"Live size slider stays fully visible: %s plain=%s scale=%.2f"%[size,plain,game.ui.text_scale])
     check(Rect2(Vector2.ZERO,game.ui.root.size).grow(1).encloses(game.ui.panel.get_global_rect()),"Live resized panel stays on screen")
    check(is_equal_approx(game.ui.text_scale,2.0) and is_equal_approx(float(game.settings.text_scale),2.0),"Real slider input reaches200%")
    font.grab_focus();await tap(KEY_ENTER)
    check(game.ui.plain_font == (not plain),"Real font switch updates font at200%")
    check(game.ui.menu_scroll.get_global_rect().grow(1).encloses(font.get_global_rect()),"Live font button stays fully visible")
  if not game.ui.plain_font:
   font.grab_focus();await tap(KEY_ENTER)
  check(game.ui.plain_font and is_equal_approx(game.ui.text_scale,2.0),"Final persisted settings are200%/plain")
 else:
  check(game.ui.plain_font and is_equal_approx(game.ui.text_scale,2.0),"Both settings restored on new process")
  check(game.ui.heading.get_theme_font("font").get_font_name().contains("Atkinson"),"Theme uses bundled Atkinson font")
  var feed=game._fps_make_feed_viewmodel()
  for node in feed.get_children():
   if node is Label3D:
    check(node.font_size==64 and node.font==game.ui.PLAIN_FONT,"World feed text follows size and font")
  feed.free()
 game.vm.cancel_all();game.ui.cancel_speech();game.queue_free()
 await process_frame
 print("TEXT SETTINGS PASS" if failures.is_empty() else failures)
 quit(0 if failures.is_empty() else 1)
