extends SceneTree
# Bakes the kit buildings' filled canvases (scripts/sprite_buildings.gd kit_canvases) into
# game/data/kits/<name>-front.bin and -back.bin (lossless WebP), with a manifest holding the SHA-256
# of prototype/facades.json they were made from. The game and the prototype load them instead of
# composing them (1-4 s of per-pixel GDScript per building, docs/DIRECTION.md eighth pass); a stale
# or missing bake falls back to composing. Re-run after tools/facade_fit.py:
#   godot --headless --audio-driver Dummy --path game --script <repo>/tools/bake_kit_canvases.gd
# Each file is read back and compared with the composed image before the manifest is written.
# Verdict (2026-09-30, Opus 5.5): used for the first bake; every image read back byte-identical.
const BUILDINGS := preload("res://scripts/sprite_buildings.gd")

func _initialize() -> void:
	var seqs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sequences.json"))["sequences"]
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var facades: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BUILDINGS.FACADES))
	var b = BUILDINGS.new(seqs, world, facades, 0.025)
	var dir := ProjectSettings.globalize_path(BUILDINGS.BAKED_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var names: Array = []
	var ok := true
	for kb in facades.get("_kit_buildings", []):
		var sides: Array = b.kit_canvases(kb)
		for i in 2:
			var img: Image = sides[i]
			var bytes := img.save_webp_to_buffer(false)
			var path := "%s/%s-%s.bin" % [dir, str(kb.name), ["front", "back"][i]]
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
			var back := Image.new()
			back.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
			back.convert(Image.FORMAT_RGBA8)
			var same := back.get_data() == img.get_data()
			ok = ok and same
			print("BAKED %s %s %dx%d %d bytes, identical: %s" % [kb.name, ["front", "back"][i], img.get_width(), img.get_height(), bytes.size(), same])
		names.append(str(kb.name))
	if not ok:
		print("BAKE FAILED: an image did not read back identically; no manifest written")
		quit(1)
		return
	var manifest := {"facades_sha256": FileAccess.get_sha256(BUILDINGS.FACADES), "format": "webp lossless, RGBA8, before mipmaps",
		"made_by": "tools/bake_kit_canvases.gd", "kits": names}
	var m := FileAccess.open(dir + "/manifest.json", FileAccess.WRITE)
	m.store_string(JSON.stringify(manifest, "  ") + "\n")
	m.close()
	print("BAKE DONE ", names.size(), " kit buildings")
	quit()
