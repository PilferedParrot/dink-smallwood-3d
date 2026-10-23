extends SceneTree

# Dumps the live mover's blocked mask of source screens (x 20..619, y 0..399, one byte per integer cell, 1 = blocked)
# for tools/clearance_passages.py. Same editor-layer fixture as collision_survey_host (no startup scripts, no render).
# Usage: godot --headless --path game --script tests/clearance_mask_dump.gd -- --screens=2,3 --out=DIR [--host=PATH]

func _initialize() -> void:
	var screens: Array = []
	var out := ""
	var host_path := "res://../tests/collision_survey_host.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screens="):
			for value in arg.trim_prefix("--screens=").split(",", false): screens.append(int(value))
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--host="): host_path = arg.trim_prefix("--host=")
	var game = load(host_path).new()
	game.world = game._read_json("res://data/world.json")
	game.sequences = game._read_json("res://data/sequences.json").sequences
	game.footprints = game._read_json("res://data/footprints.json").screens
	game.vm = game.VM.new(game)
	game.vm.load_story()
	for n in screens:
		game.load_map(n, false)
		var bytes := PackedByteArray()
		bytes.resize(600 * 400)
		for y in 400:
			for x in 600:
				bytes[y * 600 + x] = 1 if game._blocked(Vector2(20 + x, y), 1) else 0
		var file := FileAccess.open("%s/live-%d.bin" % [out, n], FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		print("DUMPED %d blocked=%d" % [n, bytes.count(1)])
	game.vm.cancel_all()
	game.free()
	quit(0)
