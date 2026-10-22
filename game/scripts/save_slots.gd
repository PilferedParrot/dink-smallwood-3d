# Copyright 2026 PilferedParrot contributors. SPDX-License-Identifier: Apache-2.0
# Save slots: one file per slot, and the text that says what each slot holds.
# FreeDink109.6 saves ten slots (the source menus list 1-10); dinkc.cpp:766-777
# turns the choice line "&savegameinfo" into "Slot %d - %d:%02d - %s" or
# "Slot %d - Empty". Slot 1 IS the single adventure.json that 0.3.3 and earlier
# wrote: no rewrite, so an existing player's save loads unchanged and a downgrade
# still finds it. Slots 2-10 sit beside it.
extends RefCounted
const COUNT := 10
const LEGACY_PATH := "user://adventure.json"
const INFO_BYTES := 77 # savegame.cpp:375-378 writes save_game_info into 77+1 bytes

static func path(slot: int) -> String:
	return LEGACY_PATH if slot == 1 else "user://adventure-slot-%d.json" % slot

# Two meanings, kept apart. exists(): a file sits in the slot, which is all DinkC's game_exist asks (fopen,
# dinkc_bindings.cpp:1350) and what Save's automatic pick must avoid overwriting, whoever wrote the file (a newer
# build's version-2 save reads Empty here and is still somebody's save). readable(): the file parses as a version-1
# save, which is when label() says it holds a game and so what Continue, Load and the title may offer.
static func exists(slot: int) -> bool:
	return slot >= 1 and FileAccess.file_exists(path(slot))

static func readable(slot: int) -> bool:
	return int(_read(slot).get("version", 0)) == 1

static func any_exists() -> bool:
	for slot in range(1, COUNT + 1):
		if readable(slot): return true
	return false

static func _read(slot: int) -> Dictionary:
	if not exists(slot): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	return parsed if parsed is Dictionary else {}

# When the slot was last written: saved_at, or the file's own time for a save
# made before slots carried one.
static func saved_at(slot: int, data: Dictionary = {}) -> int:
	var d := data if not data.is_empty() else _read(slot)
	if d.has("saved_at"): return int(d.saved_at)
	return int(FileAccess.get_modified_time(path(slot))) if exists(slot) else 0

# Most recently saved readable slot (ties: the lower number), 0 when none is readable.
static func latest() -> int:
	var best := 0
	var best_time := -1
	for slot in range(1, COUNT + 1):
		if not readable(slot): continue
		var at := saved_at(slot)
		if at > best_time: best = slot; best_time = at
	return best

# dinkc.cpp:771-776. minutes is play time in minutes (savegame.cpp play.minutes);
# a save written before slots carried it reads 0:00 and the level it stored.
static func label(slot: int) -> String:
	var d := _read(slot)
	if d.is_empty() or int(d.get("version", 0)) != 1: return "Slot %d - Empty" % slot
	var minutes := int(d.get("minutes", 0))
	var info := str(d.get("info", ""))
	if info.is_empty():
		info = "Level %d" % int(d.get("vm", {}).get("globals", {}).get("level", 1))
	return "Slot %d - %d:%02d - %s" % [slot, minutes / 60, minutes % 60, info]

static func labels() -> Array[String]:
	var out: Array[String] = []
	for slot in range(1, COUNT + 1): out.append(label(slot))
	return out
