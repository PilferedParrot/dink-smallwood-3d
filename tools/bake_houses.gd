extends SceneTree
# Bakes the fitted houses' filled images (scripts/sprite_buildings.gd house_images) into
# game/data/houses/<sha1 of the key>-<i>.bin (lossless WebP), keyed as the game keys them: the house
# and the parts it draws (fp_world.gd bake_key), with the SHA-256 of prototype/facades.json in the
# manifest. The parts are gathered by the game's own plan (fp_world.gd house_plan) with every outdoor
# screen as the current one, at every story layer its sprites use. The game loads a house's images
# instead of composing them (about 110 ms a house, docs/DIRECTION.md eighth pass); a stale bake or a
# house drawn with other parts (a sprite removed by the story) falls back to composing.
# Re-run after tools/facade_fit.py:
#   godot --headless --audio-driver Dummy --path game --script <repo>/tools/bake_houses.gd
# Each file is read back and compared with the composed image before the manifest is written.
# Verdict (2026-09-30, Opus 5.5): used for the first bake; every image read back byte-identical.
const GAME := preload("res://scripts/fps_game.gd")
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	var fw = game.fp_world
	fw.buildings.world = game.world
	fw.buildings.sequences = game.sequences
	var dir := ProjectSettings.globalize_path(BUILDINGS.BAKED_HOUSES)
	DirAccess.make_dir_recursive_absolute(dir)
	var houses := {}
	var ok := true
	var total := 0
	for sn in game.world.screens:
		var n := int(sn)
		if fw.is_inside(n): continue
		var visions := {0: true}
		for sp in game.world.screens[sn].get("sprites", []): visions[int(sp.get("vision", 0))] = true
		for v in visions:
			game.current_screen = n
			game.generation += 1
			game.vm.globals["vision"] = v
			fw.house_plan()
			for hk in fw.plan_parts:
				var parts: Dictionary = fw.plan_parts[hk]
				var id: String = fw.bake_key(hk, fw.parts_signature(parts)).sha1_text()
				if houses.has(id): continue
				var bits: PackedStringArray = str(hk).rsplit(":", true, 2)
				var path := bits[0]
				var size: Vector2 = Vector2(fw.buildings.tex(path).get_width(), fw.buildings.tex(path).get_height())
				var rect := Rect2(Vector2(float(bits[1]), float(bits[2])), size)
				var imgs: Array = fw.buildings.house_images(path, rect, parts)[0]
				for i in imgs.size():
					var bytes: PackedByteArray = (imgs[i] as Image).save_webp_to_buffer(false)
					var file := "%s/%s-%d.bin" % [dir, id, i]
					var f := FileAccess.open(file, FileAccess.WRITE)
					f.store_buffer(bytes)
					f.close()
					total += bytes.size()
					var back := Image.new()
					back.load_webp_from_buffer(FileAccess.get_file_as_bytes(file))
					back.convert(Image.FORMAT_RGBA8)
					if back.get_data() != (imgs[i] as Image).get_data():
						ok = false
						print("MISMATCH ", hk, " ", i)
				houses[id] = imgs.size()
	if not ok:
		print("BAKE FAILED: an image did not read back identically; no manifest written")
		quit(1)
		return
	var manifest := {"facades_sha256": FileAccess.get_sha256(BUILDINGS.FACADES), "format": "webp lossless, RGBA8, before mipmaps",
		"made_by": "tools/bake_houses.gd", "houses": houses}
	var m := FileAccess.open(dir + "/manifest.json", FileAccess.WRITE)
	m.store_string(JSON.stringify(manifest, "  ") + "\n")
	m.close()
	print("BAKE DONE %d houses, %d bytes" % [houses.size(), total])
	game.queue_free()
	await process_frame
	quit()
