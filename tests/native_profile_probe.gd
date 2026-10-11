extends SceneTree

func _initialize() -> void:
	print("NATIVE_PROFILE_DIR ", OS.get_user_data_dir())
	quit(0)
