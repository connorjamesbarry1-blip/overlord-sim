extends Node2D

func _ready() -> void:
	var tick_runner = load("res://sim/tick.gd").new()
	tick_runner.name = "TickRunner"
	add_child(tick_runner)

	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	var panel = load("res://render/debug_panel.gd").new()
	panel.name = "DebugPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	canvas.add_child(panel)
