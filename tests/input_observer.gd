extends Node
var owner_tree
func _input(event: InputEvent) -> void:
	if not owner_tree.watching.is_empty() and event.is_action_pressed(owner_tree.watching):
		owner_tree.seen.append(owner_tree.watching)
