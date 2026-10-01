extends SceneTree
# Sprites against buildings in the game (docs/DIRECTION.md, "Trees against buildings in the game").
# A sprite whose hotspot lies within its half-width of a house's walls takes a depth shift in its own
# shader (fp_world.gd depth_rule): pulled toward the camera when it is over the house, pushed away when
# it is under, over or under as the original draws it (y order) seen from the original's camera and as
# the depth along the view says from any other. Two parts, both run by tests/test_fps_trees.py:
#
#   --dump=251,497,...   (headless is enough) for each screen, load it and print one line per sprite
#                        "NODE screen x y key shift_px" (shift_px > 0 pushed, < 0 pulled, 0 plain),
#                        which the pytest compares with an independent reading of the map data.
#   --render             (rendered, under xvfb, Dummy audio) the pixel checks below, for each CASE.
#
# Pixel checks, per camera, all from the same scene by switching what is drawn:
#   noise     two renders of the scene as built must be identical: the instrument's own noise.
#   control   with every depth shift at 0 the picture equals the plain sprites' (shader off): mean |d| 0.
#   draw order  H = the houses hidden, N = the houses and the target sprite hidden, V = only the sprite
#             hidden. TM = where the sprite shows with no house. "over": the sprite is whole, R equals
#             H on TM (no tree cut by a wall). "under": where the house shows too, R equals V (the house
#             hides the canopy), and elsewhere on TM R equals H (the trunk's foot is not under the ground).
#   wrong controls  the same check on a plausible wrong rule must FAIL: the sides swapped; the original's
#             order held whatever the camera sees (the prototype's: a tree south of a house is pulled onto
#             its back wall from the north); the push without its ground cap (the foot goes under the
#             ground). A check that cannot go red on these is blind.
#   rail      a camera with no sprite flagged: the rule changes nothing (R equals plain).
# Actors (tenth pass) are settled like any sprite: a case with "move" is scenario setup that moves a pig (the
# map has no actor within its half-width of a wall: fp_world.depth_rule over every outdoor screen's actors,
# vision 0 and 1, finds none) to stand against a house's wall. Its draw-order check is the trees' (over from the
# open side, under from behind the house), plus two more: the "off" control (the actor as before, left out of the
# rule) must be cut by the wall from the open side, and the actor's frame changes with the camera, which must keep
# its depth shader, its shadow twin and its reach in step with the new frame.
# Verdict: written 2026-10-01 (Sonnet 5.5 subagent); runs 1-2 min under xvfb.
const GAME = preload("res://scripts/fps_game.gd")
const FP = preload("res://scripts/fp_world.gd")
const EPS := 3 # max channel difference counted as a changed pixel (0..255)

# screen the camera loads, the target sprite as [screen, x, y] in the map's own coordinates, its kind,
# and cameras [x, y, yaw, pitch] in the loaded screen's source pixels. "rail": no target.
const CASES := [
	{"name": "251 tree-08 over the cabin", "screen": 251, "target": [251, 153, 374], "kind": "over",
		"cams": [[153, 520, 0.0, -0.05, "over"], [260, 500, 0.25, -0.05, "over"], [153, 74, 3.14, -0.05, "under"], [-59, 162, -2.36, -0.05, "under"]]},
	{"name": "528 tree-04 over home-07", "screen": 528, "target": [528, 752, 40], "kind": "over",
		"cams": [[700, 330, -0.3, -0.05, "over"]]},
	{"name": "497 tree-04 under home-07", "screen": 497, "target": [497, 8, 235], "kind": "under",
		"cams": [[60, 430, -0.1, -0.05, "under"], [120, 480, 0.3, -0.05, "under"], [8, -65, 3.14, -0.05, "over"]]},
	# Scenario setup: the pig of the pen (289, 302) stands at the south corner of the village house of screen 439, 11 px
	# from its south-east wall (the pig is 56 px wide: its half is 28), south of the house: over it, from the open side.
	{"name": "407 pig at the house's corner (scenario)", "screen": 407, "target": [407, 290, 728], "kind": "over", "move": {"from": [289, 302], "to": [290, 728]},
		"cams": [[420, 728, 1.5708, -0.05, "over"], [260, 854, -0.234, -0.05, "over"], [150, 700, -1.7682, -0.05, "under"]]},
	{"name": "407 the pigpen: nothing flagged in view", "screen": 407, "target": [], "kind": "rail",
		"cams": [[300, 470, 0.0, -0.05, ""]]},
]

var game
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)

func _run() -> void:
	var dump: Array = []
	var render := false
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			for s in arg.trim_prefix("--dump=").split(",", false): dump.append(int(s))
		if arg == "--render": render = true
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	for n in dump:
		await _load(int(n))
		_dump(int(n))
	if render:
		for c in CASES: await _case(c, out_dir)
	if failures.is_empty():
		print("FPS TREES PASS")
		quit(0)
	else:
		print("FPS TREES FAIL ", failures.size())
		quit(1)

func _load(screen: int) -> void:
	game.vm.cancel_all()
	game.vm.globals["vision"] = 0
	game.load_map(screen, false)
	await create_timer(0.6).timeout
	game.vm.cancel_all()
	game.playing = false
	game.ui.close_menu()
	game.ui.toast.text = ""

func _sprites(node: Node, out: Array) -> void:
	if node is Sprite3D and node.get_parent() != null and node.get_parent().has_meta("billboard"): out.append(node)
	for child in node.get_children(): _sprites(child, out)

func _dump(screen: int) -> void:
	var sprites: Array = []
	_sprites(game.scene_root, sprites)
	for sp in sprites:
		if int(sp.get_meta("screen", -1)) != screen: continue
		if not (sp.get_parent() as Node3D).visible: continue # never drawn (an invisible editor sprite, type 2): not the rule's
		var shift: float = sp.get_meta("depth_px", 0.0)
		var at := Vector3(0, 0, 0)
		if sp.has_meta("depth_sig"): at = sp.get_meta("depth_sig")
		else:
			var e: Dictionary = game.entities.get(int(sp.get_parent().get_meta("entity_id", 0)), {})
			at = Vector3(float(e.get("x", 0)), float(e.get("y", 0)), 0)
		print("NODE %d %d %d %s %.2f" % [screen, int(at.x), int(at.y), sp.get_parent().get_meta("model_key", ""), shift])

# --- the pixel checks ---------------------------------------------------------------------------
func _flagged() -> Array:
	var all: Array = []
	_sprites(game.scene_root, all)
	var out: Array = []
	for sp in all:
		if sp.material_override is ShaderMaterial: out.append(sp)
	return out

func _find_target(spec: Array) -> Sprite3D:
	for sp in _flagged():
		var at: Vector3 = sp.get_meta("depth_sig")
		if int(sp.get_meta("screen")) == int(spec[0]) and absf(at.x - float(spec[1])) < 1.0 and absf(at.y - float(spec[2])) < 1.0: return sp
	return null

func _houses(node: Node, out: Array) -> void:
	if node.has_meta("fitted"): out.append(node)
	for child in node.get_children(): _houses(child, out)

func _set_camera(c: Array) -> void:
	game.entities[1].x = float(c[0])
	game.entities[1].y = float(c[1])
	game.fps_yaw = float(c[2])
	game.fps_pitch = float(c[3])
	game._sync_fps_camera()
	# The viewmodel sways with time: out of the picture, so it is not taken for the rule.
	for model in [game.fps_viewmodel, game.fps_hand]:
		if is_instance_valid(model): model.visible = false
	game.ui.show_hud(game.vm.globals.merged({"location": game._location(), "weapon": "Bow"}))

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

# The pixels where a and b differ by more than EPS in any channel, 1 per pixel.
func _changed(a: Image, b: Image) -> PackedByteArray:
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(da.size() / 3)
	for i in out.size():
		var o := i * 3
		out[i] = 1 if (absi(da[o] - db[o]) > EPS or absi(da[o + 1] - db[o + 1]) > EPS or absi(da[o + 2] - db[o + 2]) > EPS) else 0
	return out

func _max_diff(a: Image, b: Image) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var m := 0
	for i in da.size(): m = maxi(m, absi(da[i] - db[i]))
	return m

func _count(mask: PackedByteArray) -> int:
	var n := 0
	for v in mask: n += v
	return n

func _mean_abs(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	var sum := 0
	for i in da.size(): sum += absi(da[i] - db[i])
	return float(sum) / float(da.size())

# The pixels of mask `where` on which a and b differ.
func _differ_on(a: Image, b: Image, where: PackedByteArray) -> int:
	var changed := _changed(a, b)
	var n := 0
	for i in where.size():
		if where[i] == 1 and changed[i] == 1: n += 1
	return n

func _and(a: PackedByteArray, b: PackedByteArray, invert_b := false) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a.size())
	for i in out.size(): out[i] = 1 if (a[i] == 1 and ((b[i] == 0) if invert_b else (b[i] == 1))) else 0
	return out

# How the depth rule is switched. "rule" as built; "plain" no shader at all, as before the rule; "zero"
# the shader with every reach 0 (the push-at-0 control); "wrong" the sides swapped; "blind" the original's
# order held whatever the camera sees (the prototype's rule); "nocap" the push without its ground cap.
# "off" is "plain" for the draw-order verdict: no rule at all, as an actor was before the tenth pass.
# `shadows` false takes every flagged sprite out of the shadow pass.
var nocap_shader: Shader
var shadows := true
func _mode(sprites: Array, saved: Dictionary, mode: String) -> void:
	for sp in sprites:
		var m: ShaderMaterial = saved[sp][0]
		var p: Dictionary = saved[sp][1]
		var twin := sp.get_node_or_null("ShadowTwin") as Sprite3D
		if mode == "plain":
			sp.material_override = null
			if twin != null and sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y:
				# A billboard casts from its twin, shifted or not (turned to the sun): the twin stays.
				sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				twin.visible = shadows
				continue
			sp.cast_shadow = saved[sp][3] if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if twin != null: twin.visible = false
			continue
		sp.material_override = m
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (twin != null or not shadows) else saved[sp][3]
		if twin != null: twin.visible = shadows
		m.shader = saved[sp][2]
		m.set_shader_parameter("reach", p.reach)
		m.set_shader_parameter("normal", p.normal)
		m.set_shader_parameter("flip", 1.0)
		match mode:
			"zero": m.set_shader_parameter("reach", 0.0)
			"wrong": m.set_shader_parameter("flip", -1.0)
			"blind": m.set_shader_parameter("normal", Vector2.ZERO)
			"nocap": m.shader = nocap_shader

# Scenario setup (labelled: it skips the actor's own movement): the actor of the map at `from` stands at `to`.
func _move_actor(spec: Dictionary) -> void:
	for id in game.entities.keys():
		var e: Dictionary = game.entities[id]
		if id == 1 or absf(float(e.get("x", -999)) - float(spec.from[0])) > 1.0 or absf(float(e.get("y", -999)) - float(spec.from[1])) > 1.0: continue
		if not (game.fp_world.model_key(e) in FP.ACTORS): continue
		e.x = float(spec.to[0])
		e.y = float(spec.to[1])
		game._update_visual(id)
		return
	_fail("no actor stands at %s to be moved" % str(spec.from))

# The actor's frame is the one drawn for its facing as seen from the camera: it changes as the camera turns round
# it, and so does its width, its reach. After each change its depth shader, its shadow twin and its depth_sig must
# hold the new frame (a settled reach of the old frame is a wall's cut left on the new one).
func _actor_frames(c: Dictionary) -> void:
	var target := _find_target(c.target)
	if target == null:
		_fail("%s: the actor is not flagged for its frames" % c.name)
		return
	var id := int(target.get_parent().get_meta("entity_id"))
	var factor := maxf(0.01, float(game.entities[id].get("size", 100)) / 100.0)
	var paths := {}
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0, 0.0]:
		_set_camera([float(c.target[1]) + 200.0 * sin(yaw), float(c.target[2]) + 200.0 * cos(yaw), yaw, -0.05])
		game._update_visual(id)
		var path := str(target.get_meta("path", ""))
		paths[path] = true
		var half := float(target.texture.get_width()) / 2.0 * factor
		var sig: Vector3 = target.get_meta("depth_sig")
		var m := target.material_override as ShaderMaterial
		var twin := target.get_node_or_null("ShadowTwin") as Sprite3D
		var ok: bool = m != null and m.get_shader_parameter("tex") == target.texture and twin != null and twin.texture == target.texture and absf(sig.z - half) < 0.01 and absf(float(m.get_shader_parameter("reach")) - half * 0.025) < 0.0001
		print("  frame %s yaw %.2f: width %d, reach %.4f m, shader texture %s, twin texture %s" % [path.get_file(), yaw, target.texture.get_width(), float(m.get_shader_parameter("reach")) if m != null else -1.0, "ok" if m != null and m.get_shader_parameter("tex") == target.texture else "STALE", "ok" if twin != null and twin.texture == target.texture else "STALE"])
		if not ok: _fail("%s: from yaw %.2f the actor's frame %s is not in step (reach %.1f of %.1f px, shader or twin texture)" % [c.name, yaw, path.get_file(), sig.z, half])
	print("  the actor showed %d different frames" % paths.size())
	if paths.size() < 2: _fail("%s: the actor kept one frame from every side: the frame check is blind" % c.name)

func _case(c: Dictionary, out_dir: String) -> void:
	print("CASE ", c.name)
	await _load(int(c.screen))
	if c.has("move"): _move_actor(c.move)
	var sprites := _flagged()
	var target: Sprite3D = null
	var saved := {}
	for sp in sprites:
		var orig_cast: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sp.get_node_or_null("ShadowTwin") != null else sp.cast_shadow
		var m := sp.material_override as ShaderMaterial
		saved[sp] = [m, {"reach": m.get_shader_parameter("reach"), "normal": m.get_shader_parameter("normal")}, m.shader, orig_cast]
	if nocap_shader == null:
		nocap_shader = Shader.new()
		nocap_shader.code = FP.DEPTH_SHADER.replace("shift = min(off, room);", "shift = off;")
		if nocap_shader.code == FP.DEPTH_SHADER: _fail("the no-cap control did not change the shader")
	var kind: String = c.kind
	if kind == "rail":
		# Houses stand in the scene's block (the village east of the pen), and the rule flags their sprites;
		# the camera below sees none of them.
		print("  flagged in the block: ", sprites.size())
	else:
		target = _find_target(c.target)
		if target == null:
			_fail("%s: the target sprite is not flagged" % c.name)
			return
		var shift: float = target.get_meta("depth_px")
		if (kind == "over" and shift >= 0.0) or (kind == "under" and shift <= 0.0): _fail("%s: shift %.1f px has the wrong sign for '%s'" % [c.name, shift, kind])
		if c.has("move"):
			print("  the actor: %d px wide, shift %.1f px" % [target.texture.get_width(), shift])
			_actor_frames(c)
			# The frames check moved the camera and the actor's frame: settle the saved state again.
			sprites = _flagged()
			saved = {}
			for sp in sprites:
				var m0 := sp.material_override as ShaderMaterial
				saved[sp] = [m0, {"reach": m0.get_shader_parameter("reach"), "normal": m0.get_shader_parameter("normal")}, m0.shader, GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sp.get_node_or_null("ShadowTwin") != null else sp.cast_shadow]
	var houses: Array = []
	_houses(game.scene_root, houses)
	# A tree on the border of two screens is drawn by both: hiding "the target" hides every copy.
	var group: Array = []
	if target != null:
		var all: Array = []
		_sprites(game.scene_root, all)
		for sp in all:
			if sp.global_position.distance_to(target.global_position) < 0.05 and sp.texture == target.texture: group.append(sp)
	var k := 0
	var off_cut := 0 # the most the wall cuts the actor with the rule off, over the "over" cameras
	for cam in c.cams:
		k += 1
		var tag := "%s cam %d" % [str(c.name).get_slice(" ", 0), k]
		var ckind: String = cam[4] if cam.size() > 4 else kind # over or under, for this camera's view
		_set_camera(cam)
		_mode(sprites, saved, "rule")
		var r1 := await _grab()
		var r2 := await _grab()
		var noise := _count(_changed(r1, r2))
		if noise != 0: _fail("%s: two renders of the same scene differ at %d px (instrument noise)" % [tag, noise])
		_mode(sprites, saved, "plain")
		var plain := await _grab()
		_mode(sprites, saved, "zero")
		var zero := await _grab()
		var control := _mean_abs(zero, plain)
		print("  %s: push-at-0 vs plain mean |d| %.6f, %d px over EPS, max %d; rule vs plain %d px changed" % [tag, control, _count(_changed(zero, plain)), _max_diff(zero, plain), _count(_changed(r1, plain))])
		# Float rounding of the shader's own billboard matrix moves a few edge texels by one level.
		if control > 0.001 or _count(_changed(zero, plain)) > 4: _fail("%s: with every shift at 0 the picture differs from the plain sprites' (mean |d| %.6f)" % [tag, control])
		if out_dir != "":
			r1.save_png(out_dir.path_join("%s-%d-rule.png" % [str(c.name).get_slice(" ", 0), k]))
			plain.save_png(out_dir.path_join("%s-%d-plain.png" % [str(c.name).get_slice(" ", 0), k]))
		if kind == "rail":
			var moved := _count(_changed(r1, plain))
			if moved != 0: _fail("%s: no flagged sprite is in view, yet the rule changed %d px" % [tag, moved])
			continue
		# The draw-order property, on the rule as built, then on each wrong rule (which must fail it). Every
		# flagged sprite is out of the shadow pass while its pixels are compared, so a shadow on the ground is
		# not taken for the sprite; its shadow is checked after.
		shadows = false
		_mode(sprites, saved, "rule")
		for h in houses: h.visible = false
		var hidden_houses := await _grab()
		for sp in group: sp.visible = false
		var neither := await _grab()
		for sp in group: sp.visible = true
		for h in houses: h.visible = true
		for sp in group: sp.visible = false
		var no_target := await _grab()
		for sp in group: sp.visible = true
		var seen_alone := _changed(hidden_houses, neither) # TM: where the sprite shows with no house
		var tm := _count(seen_alone)
		var house_shows := _changed(no_target, neither)
		var overlap := _and(seen_alone, house_shows)
		print("  %s: sprite %d px, house shows over it on %d px" % [tag, tm, _count(overlap)])
		if tm < 200: _fail("%s: the target sprite is not in view (%d px)" % [tag, tm])
		var verdicts := {}
		var rule_img: Image = null
		for mode in ["rule", "wrong", "blind", "nocap", "off"]:
			_mode(sprites, saved, "plain" if mode == "off" else mode)
			var m_img := await _grab()
			var bad := 0
			if ckind == "over":
				bad = _differ_on(m_img, hidden_houses, seen_alone) # a wall cutting the sprite
			else:
				bad = _differ_on(m_img, no_target, overlap) # the house must hide the canopy where it shows
				bad += _differ_on(m_img, hidden_houses, _and(seen_alone, house_shows, true)) # and the rest stands whole
			verdicts[mode] = bad
			if mode == "off" and out_dir != "": m_img.save_png(out_dir.path_join(str(c.name).get_slice(" ", 0) + "-" + str(k) + "-OFF.png"))
			if mode == "rule":
				rule_img = m_img
				if out_dir != "":
					var tag_name := str(c.name).get_slice(" ", 0) + "-" + str(k)
					m_img.save_png(out_dir.path_join(tag_name + "-R.png"))
					hidden_houses.save_png(out_dir.path_join(tag_name + "-H.png"))
					no_target.save_png(out_dir.path_join(tag_name + "-V.png"))
					var viz := m_img.duplicate()
					var wrong_px := _changed(m_img, hidden_houses) if ckind == "over" else _changed(m_img, no_target)
					for i in wrong_px.size():
						if wrong_px[i] == 1 and (seen_alone[i] == 1): viz.set_pixel(i % viz.get_width(), i / viz.get_width(), Color(1, 0, 0.8))
					viz.save_png(out_dir.path_join(tag_name + "-viol.png"))
		print("  %s (%s): draw-order violations: rule %d, sides swapped %d, original order held from any camera %d, push without its cap %d, rule off %d" % [tag, ckind, verdicts.rule, verdicts.wrong, verdicts.blind, verdicts.nocap, verdicts.off])
		if c.has("move") and ckind == "over": off_cut = maxi(off_cut, int(verdicts.off))
		var tol := maxi(4, int(0.005 * float(maxi(_count(overlap), tm)))) # raster edges: 0.5% of the area
		if verdicts.rule > tol: _fail("%s: the rule as built violates the draw order at %d px" % [tag, verdicts.rule])
		var informative := ckind == "over" or _count(overlap) > 100
		if verdicts.wrong < 20 and informative: _fail("%s: the swapped-sides control did not fail the check (%d px): the check is blind" % [tag, verdicts.wrong])
		if ckind != kind:
			# Seen from behind the house the original's order is the wrong one: the check must catch it.
			if verdicts.blind < 20: _fail("%s: the camera-blind control did not fail from behind (%d px): the check is blind" % [tag, verdicts.blind])
		elif verdicts.blind > tol: _fail("%s: from the original's side the camera-blind rule differs from the rule (%d px)" % [tag, verdicts.blind])
		if ckind == "under" and verdicts.nocap == 0: print("  note: %s: the uncapped push did not fail here (the foot is not in view)" % tag)
		# A sprite's shadow (a fixed card casts one) must not move with its depth shift. The pixels the rule
		# changes with the shadows off are the sprites' own (every flagged sprite in view, not only the
		# target); a shadow that moved would change pixels beyond them, with the shadows on.
		shadows = false
		_mode(sprites, saved, "plain")
		var plain_ns := await _grab()
		var own := _changed(rule_img, plain_ns)
		# And the rule moves only the order against the houses: the target alone, with the houses and every
		# other sprite hidden, is the same picture with the rule and without (a sprite whose rows under the
		# ground came into view, or one moved against the sky, would change pixels).
		var everything: Array = []
		_sprites(game.scene_root, everything)
		for sp in everything:
			if not group.has(sp): sp.visible = false
		for h in houses: h.visible = false
		_mode(sprites, saved, "rule")
		var alone_rule := await _grab()
		_mode(sprites, saved, "plain")
		var alone_plain := await _grab()
		for sp in everything: sp.visible = true
		for h in houses: h.visible = true
		var alone_moved := _count(_changed(alone_rule, alone_plain))
		print("  %s: the sprite alone, rule vs plain: %d px differ" % [tag, alone_moved])
		if alone_moved > 4: _fail("%s: with no house and no other sprite the rule changed %d px (the ground's order moved)" % [tag, alone_moved])
		shadows = true
		_mode(sprites, saved, "rule")
		var rule_s := await _grab()
		_mode(sprites, saved, "plain")
		var plain_s := await _grab()
		var shadow_moved := _count(_and(_changed(rule_s, plain_s), own, true))
		var shadow_px := _count(_and(_changed(plain_s, plain_ns), own, true))
		if out_dir != "" and shadow_moved > 0:
			var sv := rule_s.duplicate()
			var sm := _and(_changed(rule_s, plain_s), own, true)
			for i in sm.size():
				if sm[i] == 1: sv.set_pixel(i % sv.get_width(), i / sv.get_width(), Color(1, 0, 0.8))
			sv.save_png(out_dir.path_join(str(c.name).get_slice(" ", 0) + "-" + str(k) + "-shadowdiff.png"))
		print("  %s: shadows: %d px of shadow beyond the sprites in view; rule vs plain differ there on %d px" % [tag, shadow_px, shadow_moved])
		if shadow_moved > 16: _fail("%s: the depth shift moved a shadow (%d px)" % [tag, shadow_moved])
		_mode(sprites, saved, "rule")
	if c.has("move"):
		print("  with the rule off the wall cuts the actor at most %d px from the open side" % off_cut)
		# The actor as it was before the tenth pass (left out of the rule) is cut by the wall from the open side.
		if off_cut < 20: _fail("%s: with the rule off no wall cuts the actor (%d px): the check is blind" % [c.name, off_cut])
