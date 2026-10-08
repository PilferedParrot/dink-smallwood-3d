extends SceneTree
# Exposes the geometry the loaded game actually built for its two castle doors. The Python test independently reads
# the source art, map placements and fitted castle faces, then checks these world-pixel vertices. Controls move a
# surface to the wrong face or stand the lowered leaf up after construction; the same assertions must reject them.
const GAME = preload("res://scripts/fps_game.gd")
const SCALE := 0.025
const CASES := [[402, "cdoor-01.png"], [80, "cdoor-06.png"]]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var control := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--control="): control = arg.trim_prefix("--control=")
	var game = GAME.new()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await game._new_game()
	await create_timer(1.0).timeout
	for spec in CASES:
		game.vm.cancel_all()
		game.vm.globals["vision"] = 0
		game.load_map(int(spec[0]), false)
		await create_timer(0.5).timeout
		game.vm.cancel_all()
		var row := {"screen": int(spec[0]), "name": str(spec[1]), "parts": {}, "chain_vertices": {}, "chain_centers": {}, "chain_rings": {}, "chain_colors": {}, "chain_color_counts": {}, "chain_segments": {}, "chain_vertex_color": {}, "chain_projected_vertices": {}}
		for id in game.entities.keys():
			if id == 1: continue
			var e: Dictionary = game.entities[id]
			if not game.fp_world.frame_path(e).ends_with(str(spec[1])): continue
			var node: Node3D = game.visuals[id]
			var model := node.get_node_or_null("Model")
			row["kind"] = "card" if model is Sprite3D else ("mesh" if model is Node3D else "missing")
			row["x"] = int(e.get("x",0))
			row["y"] = int(e.get("y",0))
			var hard: Rect2 = game.fp_world.hard_rect(e)
			var origin: Vector2 = game.fp_world.screen_origin(int(spec[0]))
			row["hardbox"] = [origin.x+hard.get_center().x,origin.y+hard.get_center().y,hard.size.x,hard.size.y]
			var body: StaticBody3D = node.get_node_or_null("HitBody")
			if body != null and body.get_child_count() > 0:
				var shape := body.get_child(0) as CollisionShape3D
				if shape != null and shape.shape is BoxShape3D:
					var center: Vector3 = shape.global_position
					var box := shape.shape as BoxShape3D
					row["ray_body"] = [origin.x+320.0+center.x/SCALE,origin.y+200.0+center.z/SCALE,box.size.x/SCALE,box.size.z/SCALE]
			if model is Node3D and not model is Sprite3D:
				if control == "wrong-face":
					var face_part: MeshInstance3D = model.get_node_or_null("Panel" if int(spec[0]) == 402 else "Arch")
					if face_part != null: face_part.position.z += 0.10 # 10 cm, much farther than the 2 cm rail
				if control == "standing-leaf" and int(spec[0]) == 80:
					var leaf: MeshInstance3D = model.get_node_or_null("Leaf")
					if leaf != null: leaf.rotation_degrees.x = 90.0
				if control == "chain-gap" and int(spec[0]) == 80:
					var chain: MeshInstance3D = model.get_node_or_null("ChainRight")
					if chain != null: chain.position.y += 0.30
				for child in model.get_children():
					if not child is MeshInstance3D: continue
					var part := child as MeshInstance3D
					var verts: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					if str(part.name).begins_with("Chain"):
						row["parts"][str(part.name)] = []
						row["chain_vertices"][str(part.name)] = verts.size()
						var material: StandardMaterial3D = part.get_surface_override_material(0)
						row["chain_vertex_color"][str(part.name)] = material != null and material.vertex_color_use_as_albedo
						var color_values: PackedColorArray = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
						var colors := {}
						var counts := {}
						for color in color_values:
							var rgb := [roundi(color.r*255.0),roundi(color.g*255.0),roundi(color.b*255.0)]
							colors[str(rgb)] = rgb
							counts[str(rgb)] = int(counts.get(str(rgb),0))+1
						row["chain_colors"][str(part.name)] = colors.values()
						row["chain_color_counts"][str(part.name)] = counts.values()
						var arc := int(part.get_meta("chain_arc_sections",12))
						var tube := int(part.get_meta("chain_tube_sections",6))
						row["chain_segments"][str(part.name)] = [arc,tube]
						if control == "" and str(part.name) == "ChainRight":
							var projected: Array = []
							var source_origin: Vector2 = game.fp_world.screen_origin(int(spec[0]))
							for vertex in verts:
								var world_vertex: Vector3 = part.to_global(vertex)
								projected.append([source_origin.x+320.0+world_vertex.x/SCALE,source_origin.y+200.0+(world_vertex.z-world_vertex.y)/SCALE])
							row["chain_projected_vertices"][str(part.name)] = projected
						var ring_vertices := arc*tube*6
						var quarter := int(arc/4)*tube*6
						var half := int(arc/2)*tube*6
						var three_quarter := int(3*arc/4)*tube*6
						var inner := int(tube/2)*6
						var centers: Array = []
						var rings: Array = []
						for first in range(0,verts.size(),ring_vertices):
							if first+ring_vertices > verts.size(): break
							var center := Vector3.ZERO
							for j in range(first,first+ring_vertices): center += part.to_global(verts[j])
							center /= float(ring_vertices)
							var screen_origin: Vector2 = game.fp_world.screen_origin(int(spec[0]))
							centers.append([screen_origin.x+320.0+center.x/SCALE,center.y/SCALE,screen_origin.y+200.0+center.z/SCALE])
							var side0 := (part.to_global(verts[first+quarter])+part.to_global(verts[first+quarter+inner]))*0.5
							var side1 := (part.to_global(verts[first+three_quarter])+part.to_global(verts[first+three_quarter+inner]))*0.5
							var major0 := (part.to_global(verts[first])+part.to_global(verts[first+inner]))*0.5
							var major1 := (part.to_global(verts[first+half])+part.to_global(verts[first+half+inner]))*0.5
							var minor_vector := (side0-side1)*0.5/SCALE
							var wire := part.to_global(verts[first+quarter]).distance_to(part.to_global(verts[first+quarter+inner]))*0.5/SCALE
							rings.append({"minor": [minor_vector.x,minor_vector.y,minor_vector.z], "major": major0.distance_to(major1)*0.5/SCALE, "wire": wire})
						row["chain_centers"][str(part.name)] = centers
						row["chain_rings"][str(part.name)] = rings
						continue
					var coordinates: Array = []
					for v in verts:
						var world: Vector3 = part.to_global(v)
						var screen_origin: Vector2 = game.fp_world.screen_origin(int(spec[0]))
						coordinates.append([screen_origin.x+320.0+world.x/SCALE, world.y/SCALE, screen_origin.y+200.0+world.z/SCALE])
					row["parts"][str(part.name)] = coordinates
			break
		print("DOORJSON ", JSON.stringify(row))
	game.queue_free()
	await process_frame
	quit(0)
