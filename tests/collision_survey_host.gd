extends "res://scripts/fps_game.gd"

# Static editor-layer survey, deliberately without startup scripts or rendering.
# Runtime/input regressions separately test stateful arrival and real controls.
var survey_states := {}

func neighbour_arrival_state(number: int, _base_state: Dictionary = {}) -> Dictionary:
	if survey_states.has(number): return survey_states[number]
	var sprites: Array = []
	for source in world.screens[str(number)].sprites:
		if int(source.get("vision",0)) != 0: continue
		var e := editor_entity(number,source)
		if not e.is_empty(): sprites.append(e)
	var result := {"sprites":sprites,"vision":0,"random_tape":[],"uncertain":[]}
	survey_states[number] = result
	return result

func load_map(number: int, _run_scripts: bool = true) -> void:
	current_screen = number
	_load_footprints(number)
	var player: Dictionary = entities.get(1,{"x":320.0,"y":200.0})
	entities = {1:player}
	var id := 2
	for e in neighbour_arrival_state(number).sprites:
		entities[id] = e
		id += 1
