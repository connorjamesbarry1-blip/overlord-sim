class_name SimUtil

static func generate_uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() % 256
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0],b[1],b[2],b[3], b[4],b[5], b[6],b[7],
		b[8],b[9], b[10],b[11],b[12],b[13],b[14],b[15]
	]

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
