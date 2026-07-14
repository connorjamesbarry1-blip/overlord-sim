extends Node2D

var _bounds_px: Rect2
var _speed: float = 60.0
var _target: Vector2

func init(bounds_px: Rect2, spd: float) -> void:
	_bounds_px = bounds_px
	_speed = spd
	position = _random_pos()
	_target = _random_pos()

func _process(delta: float) -> void:
	var dir := _target - position
	if dir.length() < 2.0:
		_target = _random_pos()
		return
	position += dir.normalized() * _speed * delta

func _random_pos() -> Vector2:
	var margin := 4.0
	var min_x := _bounds_px.position.x + margin
	var max_x := _bounds_px.end.x - margin
	var min_y := _bounds_px.position.y + margin
	var max_y := _bounds_px.end.y - margin
	if min_x >= max_x: max_x = min_x + 1.0
	if min_y >= max_y: max_y = min_y + 1.0
	return Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))

func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 1.0, 1.0, 0.85))
