extends Node2D

func _ready() -> void:
	var tick_runner = load("res://sim/tick.gd").new()
	tick_runner.name = "TickRunner"
	add_child(tick_runner)

	var world = load("res://render/world.gd").new()
	world.name = "World"
	add_child(world)

	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	var panel = load("res://render/debug_panel.gd").new()
	panel.name = "DebugPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	canvas.add_child(panel)

	var zone_panel = load("res://render/zone_panel.gd").new()
	zone_panel.name = "ZonePanel"
	zone_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	canvas.add_child(zone_panel)

	zone_panel.paint_mode_requested.connect(world.enter_paint_mode)
