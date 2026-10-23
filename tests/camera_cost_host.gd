extends "res://../tests/collision_survey_host.gd"

# The survey host with a counter on the distance field, so a test can bound the field calls of one camera update.
var field_calls := 0

func _solid_nearest(pos: Vector2, limit: float) -> Array:
	field_calls += 1
	return super._solid_nearest(pos, limit)
