extends SceneTree
# The baked houses (game/data/houses, tools/bake_houses.gd) are what composing them gives, and composing
# is deterministic: each house the game's plan gathers (every outdoor screen, every story layer its sprites
# use, as the bake gathers them) is composed twice in this one headless run, and both must equal each
# other and the bake. Headless matters: under the dummy renderer a texture's get_image() is its stored
# Image, and the house build once painted doors into it, so every later composition of that sprite (and
# the bake) carried them: doors on the backs of 439, 440 and 409, a phantom door on 409's front.
const GAME := preload("res://scripts/fps_game.gd")

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
	var seen := {}
	var unstable := []
	var stale := []
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
				var key: String = fw.bake_key(hk, fw.parts_signature(parts))
				if seen.has(key): continue
				seen[key] = true
				var bits: PackedStringArray = str(hk).rsplit(":", true, 2)
				var path := bits[0]
				var t: Texture2D = fw.buildings.tex(path)
				var rect := Rect2(Vector2(float(bits[1]), float(bits[2])), Vector2(t.get_width(), t.get_height()))
				var first: Array = fw.buildings.house_images(path, rect, parts)[0]
				var second: Array = fw.buildings.house_images(path, rect, parts)[0]
				var baked: Array = fw.buildings.baked_house(key)
				for i in first.size():
					if (first[i] as Image).get_data() != (second[i] as Image).get_data(): unstable.append("%s #%d" % [hk, i])
					if i >= baked.size() or (first[i] as Image).get_data() != (baked[i] as Image).get_data(): stale.append("%s #%d" % [hk, i])
	print("BAKE TEST houses=%d unstable=%d stale=%d" % [seen.size(), unstable.size(), stale.size()])
	for s in unstable.slice(0, 5): print("  composed twice differs: ", s)
	for s in stale.slice(0, 5): print("  bake differs from composing: ", s)
	if seen.size() > 0 and unstable.is_empty() and stale.is_empty(): print("FPS BAKE PASS")
	game.queue_free()
	await process_frame
	quit(0 if unstable.is_empty() and stale.is_empty() else 1)
