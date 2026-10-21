extends SceneTree
# Export helper: capture notices from the exact pinned engine used for packaging.
func _init() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output = argument.trim_prefix("--output=")
	if output.is_empty():
		printerr("Missing --output= directory")
		quit(1)
		return
	var license_file := FileAccess.open(output.path_join("GODOT-LICENSE.txt"), FileAccess.WRITE)
	var third_party := FileAccess.open(output.path_join("GODOT-THIRD-PARTY.json"), FileAccess.WRITE)
	if license_file == null or third_party == null:
		printerr("Unable to write engine notices")
		quit(1)
		return
	license_file.store_string(Engine.get_license_text() + "\n")
	third_party.store_string(JSON.stringify({"engine":Engine.get_version_info().string,
		"copyright":Engine.get_copyright_info(), "licenses":Engine.get_license_info()}, "  ") + "\n")
	print("ENGINE NOTICES: PASS")
	quit()
