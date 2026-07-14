class_name SimUtil

static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("SimUtil: cannot open " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("SimUtil: " + path + " did not parse to Dictionary")
		return {}
	return parsed
