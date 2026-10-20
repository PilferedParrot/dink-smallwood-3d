extends SceneTree
## UI-only deterministic regression; no source scripts or campaign progression.
const UI=preload("res://scripts/game_ui.gd")
class TrackingUI extends UI:
	var started:=0
	var pending:=0
	var record:Dictionary={"pending":0}
	func _keep_focus_visible(control: Control, serial: int) -> void:
		started+=1
		pending+=1
		record.pending=pending
		await super._keep_focus_visible(control,serial)
		pending-=1
		record.pending=pending
var failures:Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok:bool,message:String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func settle(count:int=14) -> void:
	for _i in count: await process_frame
func run() -> void:
	root.size=Vector2i(1280,800)
	var ui=TrackingUI.new()
	root.add_child(ui)
	await settle()
	ui.set_text_scale(1.5)
	# Actual cult choice group: first answer is taller than the second. The
	# focus event and adaptive-card change must both request visibility.
	ui.show_choices('( ) ; "A girl is about to die in a cult ritual.  What do you do?"',[
		"Say something to the effect that you are going to save her",
		"Agree that Mary should be sacrificed", "Use brains and stay hidden"])
	await settle()
	var answer:Button=ui.column.get_child(1)
	var before:int=ui.started
	answer.grab_focus()
	ui._fit_dialogue_panel()
	for frame in range(1,15):
		await process_frame
		var area:Rect2=ui.menu_scroll.get_global_rect()
		var bounds:Rect2=answer.get_global_rect()
		print("COMPETING_FOCUS frame=",frame," viewport=",area," answer=",bounds," scroll=",ui.menu_scroll.scroll_vertical)
		if frame in [4,14]:check(area.grow(1).encloses(bounds),"Focused answer wholly visible after competing focus/layout requests at frame"+str(frame))
	check(ui.started-before>=2,"Both real focus signal and adaptive-card change requested visibility")
	check(ui.pending==0,"No pending visibility request after settled focus change")
	await manual_scroll_case(ui)
	await cancellation_cases(ui)
	ui.show_choices("Teardown",["First answer","Second answer"])
	await settle()
	var record:Dictionary=ui.record
	ui._keep_focus_visible(ui.column.get_child(0),ui.page_serial)
	check(ui.pending>0,"UI teardown starts with pending sort wait")
	ui.free()
	await settle(2)
	check(record.pending==0,"UI teardown releases pending waits before owner is freed")
	print("FOCUS REFLOW PASS" if failures.is_empty() else "FOCUS REFLOW FAIL")
	quit(0 if failures.is_empty() else 1)

func cancellation_cases(ui:TrackingUI) -> void:
	for scenario in ["hidden", "close", "page", "new-focus"]:
		ui.show_choices("A prompt",["First answer","Second answer"])
		await settle()
		var first:Button=ui.column.get_child(0)
		ui._keep_focus_visible(first,ui.page_serial)
		check(ui.pending>0,scenario+": native sort wait is pending before cancellation")
		match scenario:
			"hidden": ui.panel.hide()
			"close": ui.close_menu()
			"page": ui.show_pause()
			"new-focus": ui.column.get_child(1).grab_focus()
		await settle()
		check(ui.pending==0,scenario+": canceled sort waits complete without hanging")
		if scenario in ["hidden","close"]:
			check(ui.menu_scroll.scroll_vertical==0,scenario+": stale request did not scroll hidden/closed content")
		else:
			var focus:Control=root.gui_get_focus_owner()
			check(focus!=null and ui.menu_scroll.get_global_rect().grow(1).encloses(focus.get_global_rect()),scenario+": current focus stays wholly visible")
		print("FOCUS_CANCEL ",scenario," pending=",ui.pending)
	# Hidden/out-of-tree calls return before attaching any sort wait.
	var outside=Button.new()
	ui._keep_focus_visible(outside,ui.page_serial)
	check(ui.pending==0,"Out-of-tree target never waits for a missing sort")
	outside.free()
	ui.panel.hide()
	var hidden:Control=ui.column.get_child(0)
	ui._keep_focus_visible(hidden,ui.page_serial)
	check(ui.pending==0,"Already-hidden target never waits for layout")
	for scenario in ["detached","freed","sort-already-completed","sort-already-pending","direct-scroll-child"]:
		var box=ScrollContainer.new()
		box.size=Vector2(200,100)
		var content:Node=box
		if scenario!="direct-scroll-child":
			content=VBoxContainer.new()
			box.add_child(content)
		var button=Button.new()
		button.text="Temporary focus target"
		content.add_child(button)
		ui.root.add_child(box)
		if scenario=="sort-already-completed":
			box.queue_sort()
			await box.sort_children
		button.grab_focus()
		ui._keep_focus_visible(button,ui.page_serial)
		check(ui.pending>0,scenario+": native sort wait attached")
		if scenario=="detached": ui.root.remove_child(box)
		elif scenario=="freed": box.free()
		await settle()
		check(ui.pending==0,scenario+": all waits completed without errors")
		if is_instance_valid(box): box.free()
		await settle(2)
		check(ui.pending==0,scenario+": no wait remains after freeing temporary container")
		print("FOCUS_CANCEL ",scenario," pending=",ui.pending)

func manual_scroll_case(ui:TrackingUI) -> void:
	ui.show_controls()
	await settle()
	check(ui.controls_menu.scroll.follow_focus and ui.controls_menu.scroll.has_meta("focus_scroll_owner"),"Controls viewport has a final owner and native pad neighbor search")
	var answers:Array=[]
	for i in 20: answers.append("Answer "+str(i))
	ui.show_choices("Choose an answer",answers)
	await settle()
	check(ui.menu_scroll.follow_focus and ui.menu_scroll.has_meta("focus_scroll_owner"),"Main reading viewport has a final owner and native pad neighbor search")
	var point:Vector2=root.get_final_transform()*ui.menu_scroll.get_global_rect().get_center()
	for _i in 8:
		var event=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_WHEEL_DOWN
		event.pressed=true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()
	var position:int=ui.menu_scroll.scroll_vertical
	check(position>0,"Real wheel input scrolls away from focused answer")
	await settle()
	check(ui.menu_scroll.scroll_vertical==position,"Manual wheel position persists without focus change")
	ui._keep_focus_visible(root.gui_get_focus_owner(),ui.page_serial)
	await settle()
	check(ui.menu_scroll.scroll_vertical==position,"Late layout request for same focus cannot cancel manual control")
	for pressed in [true,false]:
		var event=InputEventKey.new()
		event.keycode=KEY_DOWN
		event.physical_keycode=KEY_DOWN
		event.pressed=pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()
	var focus:Control=root.gui_get_focus_owner()
	check(focus==ui.column.get_child(1),"Actual Down changes focus after manual scrolling")
	check(ui.menu_scroll.get_global_rect().grow(1).encloses(focus.get_global_rect()),"New focus resumes owned visibility correction")
	print("MANUAL_SCROLL retained=",position," after_new_focus=",ui.menu_scroll.scroll_vertical)
