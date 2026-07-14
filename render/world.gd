extends Node2D

const ZONE_COLORS = {
	Sim.ZoneType.FARM:      Color(0.4, 0.7, 0.2, 0.6),
	Sim.ZoneType.LUMBER:    Color(0.5, 0.3, 0.1, 0.6),
	Sim.ZoneType.MINE:      Color(0.5, 0.5, 0.5, 0.6),
	Sim.ZoneType.SMELTER:   Color(0.8, 0.4, 0.0, 0.6),
	Sim.ZoneType.HOUSING:   Color(0.8, 0.8, 0.2, 0.6),
	Sim.ZoneType.BARRACKS:  Color(0.7, 0.1, 0.1, 0.6),
	Sim.ZoneType.WORKSHOP:  Color(0.2, 0.4, 0.8, 0.6),
	Sim.ZoneType.STOCKPILE: Color(0.6, 0.5, 0.3, 0.6),
}

var _tile_size: int = 32
var _map_w: int = 64
var _map_h: int = 64
var _citizen_cap: int = 10
var _citizen_speed: float = 60.0

var _camera: Camera2D
var _zone_layer: Node2D
var _citizen_layer: Node2D

var _painting: bool = false
var _paint_type: int = -1
var _paint_start: Vector2i = Vector2i.ZERO
var _paint_preview: ColorRect

var _zone_sprites: Dictionary = {}
var _citizen_pools: Dictionary = {}

func _ready() -> void:
	var balance: Dictionary = SimUtil.load_json("res://data/balance.json")
	_tile_size = balance.get("tile_size", 32)
	_map_w = balance.get("map_width_tiles", 64)
	_map_h = balance.get("map_height_tiles", 64)
	_citizen_cap = balance.get("citizen_visual_cap_per_zone", 10)
	_citizen_speed = balance.get("citizen_speed", 60.0)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position = Vector2(_map_w * _tile_size / 2.0, _map_h * _tile_size / 2.0)
	add_child(_camera)

	var grid = load("res://render/grid_layer.gd").new()
	grid.name = "GridLayer"
	grid.setup(_map_w, _map_h, _tile_size)
	add_child(grid)

	_zone_layer = Node2D.new()
	_zone_layer.name = "ZoneLayer"
	add_child(_zone_layer)

	_citizen_layer = Node2D.new()
	_citizen_layer.name = "CitizenLayer"
	add_child(_citizen_layer)

	_paint_preview = ColorRect.new()
	_paint_preview.visible = false
	_paint_preview.color = Color(1.0, 1.0, 1.0, 0.25)
	_zone_layer.add_child(_paint_preview)

	SimState.tick_completed.connect(_on_tick_completed)

func enter_paint_mode(type: int) -> void:
	_paint_type = type
	_painting = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			pass
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera.zoom = _camera.zoom * 1.1
			_camera.zoom = _camera.zoom.clamp(Vector2(0.25, 0.25), Vector2(4.0, 4.0))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera.zoom = _camera.zoom * 0.9
			_camera.zoom = _camera.zoom.clamp(Vector2(0.25, 0.25), Vector2(4.0, 4.0))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if _paint_type == -1:
				return
			if mb.pressed:
				_painting = true
				_paint_start = _screen_to_tile(mb.position)
				_paint_preview.visible = true
				_update_preview(_paint_start, _paint_start)
			else:
				if _painting:
					var paint_end := _screen_to_tile(mb.position)
					var tl := Vector2i(min(_paint_start.x, paint_end.x), min(_paint_start.y, paint_end.y))
					var br := Vector2i(max(_paint_start.x, paint_end.x), max(_paint_start.y, paint_end.y))
					var bw := br.x - tl.x + 1
					var bh := br.y - tl.y + 1
					SimState.create_zone_requested.emit(_paint_type, tl.x, tl.y, bw, bh)
				_painting = false
				_paint_type = -1
				_paint_preview.visible = false

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var buttons := mm.button_mask
		if buttons & MOUSE_BUTTON_MASK_MIDDLE or buttons & MOUSE_BUTTON_MASK_RIGHT:
			_camera.position -= mm.relative / _camera.zoom.x
		if _painting and _paint_type != -1:
			var cur_tile := _screen_to_tile(mm.position)
			_update_preview(_paint_start, cur_tile)

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var vp_size := get_viewport().get_visible_rect().size
	var world_pos := _camera.position + (screen_pos - vp_size / 2.0) / _camera.zoom.x
	return Vector2i(int(world_pos.x / _tile_size), int(world_pos.y / _tile_size))

func _update_preview(start: Vector2i, end: Vector2i) -> void:
	var tl := Vector2i(min(start.x, end.x), min(start.y, end.y))
	var br := Vector2i(max(start.x, end.x), max(start.y, end.y))
	_paint_preview.position = Vector2(tl.x * _tile_size, tl.y * _tile_size)
	_paint_preview.size = Vector2((br.x - tl.x + 1) * _tile_size, (br.y - tl.y + 1) * _tile_size)

func _on_tick_completed(snapshot: Dictionary) -> void:
	var zones: Dictionary = snapshot.get("zones", {})

	for zone_id in _zone_sprites.keys():
		if not zone_id in zones:
			_remove_zone_visual(zone_id)

	for zone_id in zones.keys():
		var z: Dictionary = zones[zone_id]
		if not zone_id in _zone_sprites:
			_add_zone_visual(zone_id, z)
		else:
			_update_zone_label(zone_id, z)
		_reconcile_citizens(zone_id, z)

func _add_zone_visual(zone_id: String, z: Dictionary) -> void:
	var b: Dictionary = z.get("bounds", {"x": 0, "y": 0, "w": 1, "h": 1})
	var type_int: int = z.get("type", 0)
	var color: Color = ZONE_COLORS.get(type_int, Color(0.5, 0.5, 0.5, 0.5))

	var rect := ColorRect.new()
	rect.color = color
	rect.position = Vector2(b.x * _tile_size, b.y * _tile_size)
	rect.size = Vector2(b.w * _tile_size, b.h * _tile_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = z.get("type_name", "?")
	label.add_theme_font_size_override("font_size", 10)
	label.position = Vector2(2, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_child(label)

	_zone_layer.add_child(rect)
	_zone_sprites[zone_id] = rect
	_citizen_pools[zone_id] = []

func _update_zone_label(zone_id: String, z: Dictionary) -> void:
	var rect: ColorRect = _zone_sprites[zone_id]
	var label: Label = rect.get_child(0)
	if label:
		label.text = z.get("type_name", "?")

func _remove_zone_visual(zone_id: String) -> void:
	if zone_id in _zone_sprites:
		_zone_sprites[zone_id].queue_free()
		_zone_sprites.erase(zone_id)
	if zone_id in _citizen_pools:
		for c in _citizen_pools[zone_id]:
			c.queue_free()
		_citizen_pools.erase(zone_id)

func _reconcile_citizens(zone_id: String, z: Dictionary) -> void:
	if not zone_id in _citizen_pools:
		_citizen_pools[zone_id] = []
	var pool: Array = _citizen_pools[zone_id]
	var target: int = mini(z.get("assigned_workers", 0), _citizen_cap)
	var current: int = pool.size()

	if target > current:
		var b: Dictionary = z.get("bounds", {"x": 0, "y": 0, "w": 1, "h": 1})
		var bounds_px := Rect2(
			b.x * _tile_size, b.y * _tile_size,
			b.w * _tile_size, b.h * _tile_size
		)
		for _i in range(target - current):
			var c = load("res://render/citizen.gd").new()
			c.init(bounds_px, _citizen_speed)
			_citizen_layer.add_child(c)
			pool.append(c)
	elif target < current:
		for _i in range(current - target):
			var c = pool.pop_back()
			c.queue_free()
