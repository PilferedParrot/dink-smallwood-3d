# Geometry complements packed frames; it cannot certify art or player experience.
extends SceneTree
const UI = preload("res://scripts/game_ui.gd")
var failures: Array[String] = []
var checked := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	for size in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size = size
		for scale in [1.0,1.3]:
			var ui := UI.new()
			root.add_child(ui)
			ui.set_text_scale(scale)
			ui.show_settings({})
			ui.show_controls()
			for area in ui.bindings.SCOPES:
				ui.controls_menu._select_group(area)
				for i in 6: await process_frame
				var scroll_rect: Rect2 = ui.controls_menu.scroll.get_global_rect()
				var panel_rect: Rect2 = ui.panel.get_global_rect()
				check(ui.controls_menu.footer.get_global_rect().end.y <= panel_rect.end.y,"Pinned footer remains in panel")
				check(ui.controls_menu.footer.get_global_rect().position.y >= scroll_rect.end.y,"Rows cannot overlap pinned footer")
				for token in ui.controls_menu.buttons:
					var button: Button = ui.controls_menu.buttons[token]
					var r := button.get_global_rect()
					check(r.position.x >= panel_rect.position.x and r.end.x <= panel_rect.end.x,"Control remains horizontally in panel: "+token)
					var font := button.get_theme_font("font")
					var fs := button.get_theme_font_size("font_size")
					check(button.size.y <= 3*font.get_height(fs),"No button turns into a tall column of wrapped letters: "+token)
					if token.ends_with("_reset"):
						var style := button.get_theme_stylebox("normal")
						check(font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x <= button.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)+1,"Reset label fits one line")
					checked += 1
			ui.queue_free()
			for i in 3: await process_frame
	print("CONTROLS LAYOUT "+("PASS" if failures.is_empty() else "FAIL")+" buttons="+str(checked))
	quit(0 if failures.is_empty() else 1)
