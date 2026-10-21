extends SceneTree

const Game = preload("res://scripts/game.gd")
const UI = preload("res://scripts/game_ui.gd")

# Synthetic rectangles isolate the production visibility arbitration. Existing
# text/speech censuses separately verify real card and help layout.
class ReticleUI extends UI:
	var probe_position := Vector2.ZERO
	func _fit_dialogue_panel() -> void:
		panel.position = probe_position
		panel.size = Vector2(80, 80)

class FakeUI extends RefCounted:
	var closes := 0
	var notices: Array[String] = []
	func close_menu() -> void:
		closes += 1
	func notify(message: String) -> void:
		notices.append(message)

class FakeVM extends RefCounted:
	var globals := {"cur_weapon": 1, "cur_magic": 1}
	var calls: Array = []
	func _procedure_code(_script: String, _procedure: String) -> Array:
		return [{"op": "return"}]
	func run(script: String, procedure: String, sprite_id: int = 0, _new_instance: bool = false, _owner_sprite: int = -1) -> Variant:
		calls.append([script, procedure, sprite_id])
		return 0

var failures: Array[String] = []
var selected_action := ""
var selected_index := -1

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _on_action(action: String, value: Variant) -> void:
	selected_action = action
	selected_index = int(value)

func check_reticle_owners() -> void:
	var probe := ReticleUI.new()
	root.add_child(probe)
	await process_frame
	probe.set_process(false)
	probe.close_menu()
	probe.page = "dialogue"
	probe.modal = false
	probe.dialogue_mode = true
	probe.hint.text = "Help covers this aiming point."
	probe.gameplay_hint_used = true
	probe.gameplay_hint_deadline_msec = Time.get_ticks_msec() + 60000
	probe._process(0)
	# Place the aim inside the actual native help bounds, then vary ownership
	# independently. This is a UI arbitration fixture, not a gameplay pose.
	probe.crosshair.global_position = probe.hint_backing.get_global_rect().get_center()
	var aim := probe.crosshair.get_global_rect()
	for owners in [[true, false], [false, true], [true, true], [false, false]]:
		probe.gameplay_hint_deadline_msec = Time.get_ticks_msec() + 60000 if owners[0] else 0
		probe.probe_position = aim.position - Vector2(20, 20) if owners[1] else Vector2(-10000, -10000)
		probe.panel.show()
		probe._process(0)
		var help_covers := probe.hint_backing.visible and probe.hint_backing.get_global_rect().grow(3).intersects(aim)
		var speech_covers := probe.panel.visible and probe.panel.get_global_rect().grow(3).intersects(aim)
		check(help_covers == owners[0] and speech_covers == owners[1], "Reticle fixture independently realizes both measured owners: " + str(owners))
		check(probe.crosshair.visible == (not owners[0] and not owners[1]), "Reticle visible only when neither owner covers: " + str(owners))
		print("RETICLE OWNERS ", JSON.stringify({"help":help_covers,"speech":speech_covers,"visible":probe.crosshair.visible}))
	# A HIDDEN panel or help plaque whose rectangle still covers the aim owns nothing.
	probe.gameplay_hint_deadline_msec = 0
	probe.probe_position = aim.position - Vector2(20, 20)
	probe.panel.hide()
	probe._process(0)
	check(not probe.panel.visible and probe.panel.get_global_rect().grow(3).intersects(aim), "Hidden speech panel fixture still has a rectangle over the aim")
	check(probe.crosshair.visible, "A hidden speech panel over the aim does not hide the reticle")
	# The help plaque expires (hidden) with its rectangle still where the aim is.
	probe.panel.show()
	probe.probe_position = Vector2(-10000, -10000)
	probe.gameplay_hint_deadline_msec = 0
	probe._process(0)
	check(not probe.hint_backing.visible and probe.hint_backing.get_global_rect().grow(3).intersects(aim), "Hidden help plaque fixture still has a rectangle over the aim")
	check(probe.crosshair.visible, "A hidden help plaque over the aim does not hide the reticle")
	probe.queue_free()
	await process_frame

func _init() -> void:
	await process_frame
	root.size = Vector2i(1280, 800)
	await process_frame
	await check_reticle_owners()
	var ui := UI.new()
	root.add_child(ui)
	ui.action_requested.connect(_on_action)
	await process_frame
	var fists := {"name": "Fists", "script": "item-fst"}
	var bow := {"name": "Bow", "script": "item-b1", "seq": 0}
	var fireball := {"name": "Fireball", "script": "item-fb"}
	var healing := {"name": "Healing", "script": "item-hel"}
	var weapons := [fists, bow]
	var spells := [fireball, healing]
	ui.show_hud({"cur_weapon": 1, "cur_magic": 1, "weapon": "Fists", "weapon_item": fists, "spell_item": fireball})
	check(not ui.hud.text.contains("Weapon:"), "Gameplay heading does not repeat the status dock's equipped weapon")
	check(ui.status_dock._weapon_texture != null and ui.status_dock._spell_texture != null, "Original HUD slots retain weapon and spell icons")
	ui.show_inventory(weapons, spells)
	await process_frame
	await process_frame
	var chest = ui.column.get_node_or_null("EquipmentChest")
	check(chest != null, "Inventory presents the original equipment chest")
	if chest != null:
		var bow_button := chest.get_node_or_null("Item1") as Button
		var fists_button := chest.get_node_or_null("Item0") as Button
		var fireball_button := chest.get_node_or_null("Magic0") as Button
		check(bow_button != null and fists_button != null and fireball_button != null, "Weapon and spell slots are focusable")
		if bow_button != null and fists_button != null and fireball_button != null:
			bow_button.grab_focus()
			await process_frame
			check(ui.heading.text.contains("Fists") and ui.heading.text.contains("Fireball"), "Header names the actual equipped weapon and spell")
			check(not ui.heading.text.contains("Bow"), "Highlighted Bow cannot replace the equipped header")
			check(ui.equipment_name.text.begins_with("Selected:") and ui.equipment_name.text.contains("Bow"), "Cursor description has a separate Selected label")
			check(fists_button.accessibility_description.contains("Equipped") and fireball_button.accessibility_description.contains("Equipped"), "Equipment metadata marks both live slots")
			check(not bow_button.accessibility_description.contains("Equipped"), "Highlighted slot is not marked equipped")
			bow_button.pressed.emit()
			check(selected_action == "equip" and selected_index == 1, "Choosing Bow still sends the real equip action")
	var game := Game.new()
	game.ui = FakeUI.new()
	game.vm = FakeVM.new()
	game.items = weapons
	game.magic_items = spells
	await game._equip(1, false)
	check(game.vm.globals.cur_weapon == 2 and game.vm.globals.cur_magic == 1, "Weapon equip changes only the weapon slot")
	check(game.vm.calls == [["item-fst", "disarm", 1], ["item-b1", "arm", 1]], "Weapon equip preserves disarm and arm scripts")
	await game._equip(1, true)
	check(game.vm.globals.cur_weapon == 2 and game.vm.globals.cur_magic == 2, "Spell equip changes only the spell slot")
	check(game.vm.calls.slice(2) == [["item-fb", "disarm", 1], ["item-hel", "arm", 1]], "Spell equip preserves disarm and arm scripts")
	check(game.ui.closes == 2 and game.ui.notices.is_empty(), "Equip closes the menu without duplicate announcement toasts")
	var live_stats: Dictionary = game.vm.globals.duplicate()
	game._add_equipment_stats(live_stats)
	ui.show_hud(live_stats)
	ui.show_inventory(weapons, spells)
	await process_frame
	check(ui.heading.text.contains("Bow") and ui.heading.text.contains("Healing"), "Reopened inventory reports newly equipped items")
	check(not ui.heading.text.contains("Fists") and not ui.heading.text.contains("Fireball"), "Reopened header does not keep old equipment")
	game.free()
	if failures.is_empty():
		print("UI FEEDBACK OWNERSHIP PASS")
	quit(1 if not failures.is_empty() else 0)
