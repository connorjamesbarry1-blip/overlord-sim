extends Node2D

var _map_w: int = 64
var _map_h: int = 64
var _tile_size: int = 32

func setup(map_w: int, map_h: int, tile_size: int) -> void:
	_map_w = map_w
	_map_h = map_h
	_tile_size = tile_size

func _draw() -> void:
	var bg := Color(0.12, 0.13, 0.14, 1.0)
	var line := Color(0.28, 0.30, 0.32, 0.5)
	draw_rect(Rect2(0, 0, _map_w * _tile_size, _map_h * _tile_size), bg)
	for x in range(_map_w + 1):
		draw_line(Vector2(x * _tile_size, 0), Vector2(x * _tile_size, _map_h * _tile_size), line)
	for y in range(_map_h + 1):
		draw_line(Vector2(0, y * _tile_size), Vector2(_map_w * _tile_size, y * _tile_size), line)
