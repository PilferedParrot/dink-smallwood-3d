extends "building_capture.gd"
# The terrain boxes alone, black on white, in the bed fixtures' original camera: what the terrain geometry occupies on screen.
# Run on two trees with the same bundle and diff the pictures: the differing pixels are where the terrain geometry changed,
# derived from geometry only (no other scene content can enter the mask).
func _terrain_only(node: Node) -> void:
	if node.name in ["SolidTerrain","SolidTerrainFill"]:
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color.BLACK
		node.material_override = black
		return
	if node is VisualInstance3D and not node is Light3D: node.visible = false
	if node is CanvasItem: node.visible = false
	for child in node.get_children(): _terrain_only(child)
func _capture_setup(game, _view: Dictionary) -> void:
	_terrain_only(game.scene_root)
	var environment: Environment = game.fp_world.environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.WHITE
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.fog_enabled = false
