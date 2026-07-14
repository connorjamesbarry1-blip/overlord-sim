extends PanelContainer

signal paint_mode_requested(type: int)

var _worker_summary: Label
var _zone_list: VBoxContainer
var _type_option: OptionButton

func _ready() -> void:
	_build_ui()
	SimState.tick_completed.connect(_on_tick_completed)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var title := Label.new()
	title.text = "ZONES & WORKERS"
	outer.add_child(title)
	outer.add_child(HSeparator.new())

	# Zone creation row
	var create_row := HBoxContainer.new()
	outer.add_child(create_row)
	var type_lbl := Label.new()
	type_lbl.text = "Type: "
	create_row.add_child(type_lbl)
	_type_option = OptionButton.new()
	for key in Sim.ZoneType:
		_type_option.add_item(key)
	create_row.add_child(_type_option)
	var paint_btn := Button.new()
	paint_btn.text = "Paint Zone"
	paint_btn.pressed.connect(_on_paint_pressed)
	create_row.add_child(paint_btn)

	outer.add_child(HSeparator.new())

	_worker_summary = Label.new()
	outer.add_child(_worker_summary)

	outer.add_child(HSeparator.new())

	_zone_list = VBoxContainer.new()
	outer.add_child(_zone_list)

func _on_tick_completed(snapshot: Dictionary) -> void:
	var total_pop := 0
	for row in snapshot.get("population", {}).values():
		total_pop += row["count"]
	var total_assigned: int = snapshot.get("total_assigned_workers", 0)
	_worker_summary.text = "Workers: %d / %d assigned  (%d idle)" % [
		total_assigned, total_pop, total_pop - total_assigned
	]
	_rebuild_zone_list(snapshot.get("zones", {}))

func _rebuild_zone_list(zones: Dictionary) -> void:
	for child in _zone_list.get_children():
		child.queue_free()

	for zone_id in zones:
		var z: Dictionary = zones[zone_id]
		var row := HBoxContainer.new()

		var info := Label.new()
		info.text = "%-10s  eff:%.2f" % [z.get("type_name", "?"), z.get("efficiency", 0.0)]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var minus := Button.new()
		minus.text = "-"
		minus.pressed.connect(_request_set_workers.bind(zone_id, z["assigned_workers"] - 1))
		row.add_child(minus)

		var count_lbl := Label.new()
		count_lbl.text = "%3d" % z["assigned_workers"]
		count_lbl.custom_minimum_size = Vector2(32, 0)
		row.add_child(count_lbl)

		var plus := Button.new()
		plus.text = "+"
		plus.pressed.connect(_request_set_workers.bind(zone_id, z["assigned_workers"] + 1))
		row.add_child(plus)

		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.pressed.connect(_request_destroy_zone.bind(zone_id))
		row.add_child(remove_btn)

		_zone_list.add_child(row)

func _on_paint_pressed() -> void:
	var type_idx: int = _type_option.get_selected_id()
	paint_mode_requested.emit(type_idx)

func _request_set_workers(zone_id: String, count: int) -> void:
	SimState.set_workers_requested.emit(zone_id, count)

func _request_destroy_zone(zone_id: String) -> void:
	SimState.destroy_zone_requested.emit(zone_id)
