# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
extends SceneTree
## Frames of the speech card and both choice areas for the lead to view (no assertions): a long speech, a long
## prompt and a long answer list at rest, after wheel-sized steps, and the timed scroll mid-way and at its end.
## usage: ... --script speechcard_frames_capture.gd -- --out-dir=DIR
const UI = preload("res://scripts/game_ui.gd")
var out := "/dev/shm/dink-speechcard/frames"

func _initialize() -> void: run.call_deferred()

func settle(count := 14) -> void:
	for _i in count: await process_frame

func shot(ui, surface: String, size: Vector2i, plain: bool, scale: float) -> void:
	await settle(8)
	var image := root.get_texture().get_image()
	var card: Rect2 = ui.panel.get_global_rect().grow(40).intersection(Rect2(Vector2.ZERO, Vector2(size)))
	image = image.get_region(Rect2i(card))
	image.save_png("%s/%s-%d-%s-%d.png" % [out, surface, size.x, "plain" if plain else "dink", roundi(scale * 100)])

func step(scroll: ScrollContainer, notches: int) -> void:
	for _i in notches:
		scroll.scroll_vertical += maxi(1, roundi(scroll.get_v_scroll_bar().page / 8.0))
		await settle(5)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out = arg.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(out)
	var answers := ["Yes, I will help the village.", "Tell me more before I choose; the elder said the road north is unsafe after dark.", "I need some time to think about it.", "No.", "Take me back to the cottage so I can rest and gather my things before I decide anything at all.", "Show me what the stranger left on the table."]
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		for plain in [false, true]:
			for scale in [1.0, 1.5, 2.0]:
				root.size = size
				var ui = UI.new()
				root.add_child(ui)
				ui.set_text_scale(scale)
				ui.set_plain_font(plain)
				ui.show_dialogue("Every line of a long conversation can be read. ".repeat(70), "Conversation")
				await settle()
				await shot(ui, "speech-rest", size, plain, scale)
				await step(ui.menu_scroll, 4)
				await shot(ui, "speech-wheel", size, plain, scale)
				ui.menu_scroll.scroll_vertical = int(ui.menu_scroll.get_v_scroll_bar().max_value)
				await settle()
				await shot(ui, "speech-end", size, plain, scale)
				ui.cancel_speech()
				ui.show_speech("Every line of a long conversation can be read. ".repeat(70), "Conversation", 0, 600000, false)
				await settle()
				var bar: ScrollBar = ui.menu_scroll.get_v_scroll_bar()
				var extent := bar.max_value - bar.page
				ui.timed_phase = 1
				var guard := 0
				while ui.timed_scroll_offset < extent * 0.43 and guard < 20000:
					guard += 1
					ui._advance_timed_speech(0.25)
					await process_frame
				await shot(ui, "speech-timed-mid", size, plain, scale)
				ui.cancel_speech()
				ui.show_choices("Will you help the village? " + "The prompt has its own reading viewport. ".repeat(14), answers)
				await settle()
				await shot(ui, "choice-rest", size, plain, scale)
				await step(ui.choice_prompt_scroll, 3)
				await shot(ui, "choice-prompt-wheel", size, plain, scale)
				await step(ui.menu_scroll, 3)
				await shot(ui, "choice-answers-wheel", size, plain, scale)
				ui.cancel_speech()
				ui.queue_free()
				await process_frame
	print("FRAMES DONE ", out)
	quit(0)
