extends PanelContainer

# Read-only view of the sim. Connects to SimState.tick_completed signal.
# Must never call anything that mutates sim state.

var _tick_label: Label
var _status_label: Label
var _res_labels: Dictionary = {}
var _pop_label: Label
var _zone_summary: VBoxContainer

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

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "OVERLORD SIM  —  DEBUG PANEL"
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	_tick_label = Label.new()
	vbox.add_child(_tick_label)

	_status_label = Label.new()
	vbox.add_child(_status_label)
	vbox.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "Resource        stock /   cap   +prod  -cons"
	vbox.add_child(header)

	for key in Sim.Res:
		var lbl := Label.new()
		vbox.add_child(lbl)
		_res_labels[Sim.Res[key]] = lbl

	vbox.add_child(HSeparator.new())

	_pop_label = Label.new()
	vbox.add_child(_pop_label)

	vbox.add_child(HSeparator.new())

	var zone_header := Label.new()
	zone_header.text = "Zone        workers   eff"
	vbox.add_child(zone_header)

	_zone_summary = VBoxContainer.new()
	vbox.add_child(_zone_summary)

func _on_tick_completed(snapshot: Dictionary) -> void:
	_tick_label.text = "Tick: %d" % snapshot["tick"]

	var starve: int = snapshot.get("starvation_ticks", 0)
	if starve > 0:
		_status_label.text = "*** STARVATION — %d ticks without food ***" % starve
		_status_label.modulate = Color.RED
	else:
		_status_label.text = "Status: stable"
		_status_label.modulate = Color.GREEN

	var ledger: Dictionary = snapshot["ledger"]
	for key in Sim.Res:
		var res_val: int = Sim.Res[key]
		if ledger.has(res_val):
			var row: Dictionary = ledger[res_val]
			_res_labels[res_val].text = "  %-10s  %5d / %5d   +%-5.0f  -%-5.0f" % [
				key,
				row["stock"],
				row["cap"],
				row["production_rate"],
				row["consumption_rate"],
			]

	var total_pop := 0
	for row in snapshot["population"].values():
		total_pop += row["count"]
	_pop_label.text = "Population: %d" % total_pop

	for child in _zone_summary.get_children():
		child.queue_free()
	for z in snapshot.get("zones", {}).values():
		var lbl := Label.new()
		lbl.text = "  %-10s  %3d wk   %.2f" % [
			z.get("type_name", "?"),
			z["assigned_workers"],
			z.get("efficiency", 0.0),
		]
		_zone_summary.add_child(lbl)
