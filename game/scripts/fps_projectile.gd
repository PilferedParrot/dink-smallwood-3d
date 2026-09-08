# First-person projectile bridge.  It intentionally calls the campaign host for
# damage/events so arrows and spells retain the original DinkC consequences.
extends Node3D

var host
var source_id := 1
var damage := 1
var speed := 21.0
var lifetime := 2.2
var direction := Vector3.FORWARD
var spell := false
var source_position := Vector2.ZERO
var travelled := 0.0
var generation := -1

func configure(owner, owner_id: int, origin: Vector3, forward: Vector3, hit_damage: int, is_spell: bool = false) -> void:
	host = owner
	source_id = owner_id
	damage = maxi(1, hit_damage)
	spell = is_spell
	position = origin
	direction = forward.normalized()
	rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	if host != null and host.has_method("_position2"):
		source_position = host._position2(owner_id)
		generation = int(host.generation)
	_make_visual()

func _make_visual() -> void:
	var mesh := MeshInstance3D.new()
	if spell:
		var shape := SphereMesh.new()
		shape.radius = 0.13
		shape.height = 0.26
		mesh.mesh = shape
	else:
		var shape := CylinderMesh.new()
		shape.top_radius = 0.025
		shape.bottom_radius = 0.025
		shape.height = 0.65
		mesh.mesh = shape
		mesh.rotation_degrees.x = 90.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ff6c35") if spell else Color("d7c18e")
	material.emission_enabled = spell
	material.emission = Color("ff3f16")
	material.emission_energy_multiplier = 2.0
	mesh.material_override = material
	add_child(mesh)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(host) or int(host.generation) != generation:
		queue_free()
		return
	if host.ui.modal: return
	var previous := position
	position += direction * speed * delta
	travelled += previous.distance_to(position)
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var query := PhysicsRayQueryParameters3D.create(previous, position, 3)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var collider: Object = hit.get("collider")
	var id := int(collider.get_meta("entity_id", 0)) if collider != null else 0
	if id > 0 and id != source_id and host._fps_targetable(id, Vector2.INF, float(hit.position.y)):
		host._fps_projectile_hit(id, source_id, damage)
	queue_free()
