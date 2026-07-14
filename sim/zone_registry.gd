class_name ZoneRegistry

# Entity table. Surrogate key: UUID string.
# Zones are created and destroyed by the player.
# This is NOT an aggregate table — multiple FARM zones are valid and expected.

var _rows: Dictionary = {}       # zone_id (String) -> row dict
var _zone_defs: Dictionary = {}  # loaded from data/zones.json

func _init(zone_defs: Dictionary) -> void:
	_zone_defs = zone_defs

# Creates a new zone and returns its zone_id. Workers default to 0.
func create_zone(type: int, bounds: Rect2i) -> String:
	var id := SimUtil.generate_uuid()
	_rows[id] = {
		"zone_id": id,
		"type": type,
		"bounds": bounds,
		"assigned_workers": 0,
		"deposit_ref": "",
	}
	return id

func destroy_zone(zone_id: String) -> void:
	_rows.erase(zone_id)

func set_workers(zone_id: String, count: int) -> void:
	if _rows.has(zone_id):
		_rows[zone_id]["assigned_workers"] = count

func get_zone(zone_id: String) -> Dictionary:
	return _rows.get(zone_id, {})

func get_all_zones() -> Array:
	return _rows.values()

func get_total_assigned_workers() -> int:
	var total := 0
	for z in _rows.values():
		total += z["assigned_workers"]
	return total

# Returns the Sim.Res value this zone type outputs, or -1 if none.
func get_output_resource(zone_id: String) -> int:
	var zone: Dictionary = _rows.get(zone_id, {})
	if zone.is_empty():
		return -1
	var type_key: String = Sim.ZoneType.keys()[zone["type"]]
	var output_name = _zone_defs.get("zone_types", {}).get(type_key, {}).get("output_resource", null)
	if output_name == null or not Sim.Res.has(output_name):
		return -1
	return Sim.Res[output_name]

# Resource production for one zone this tick.
func compute_zone_production(zone_id: String) -> float:
	var zone: Dictionary = _rows.get(zone_id, {})
	if zone.is_empty():
		return 0.0
	var base_rate: float = _get_def(zone["type"], "base_rate_per_worker", 0.0)
	return base_rate * float(zone["assigned_workers"]) * _compute_efficiency(zone)

# Efficiency is derived state — never stored in the row, recomputed each call.
func _compute_efficiency(zone: Dictionary) -> float:
	if zone["assigned_workers"] == 0:
		return 0.0
	var type_int: int = zone["type"]
	var optimal_density: float = _get_def(type_int, "optimal_workers_per_tile", 1.0)
	var exponent: float = _get_def(type_int, "saturation_exponent", 1.0)
	var terrain_quality: float = _zone_defs.get("terrain_quality_default", 1.0)
	var min_eff: float = _zone_defs.get("min_efficiency", 0.05)
	var area: int = (zone["bounds"] as Rect2i).get_area()
	if area == 0:
		return 0.0
	var optimal_workers: float = float(area) * optimal_density
	var density_ratio: float = float(zone["assigned_workers"]) / optimal_workers
	var saturation: float = pow(clampf(density_ratio, 0.0, 1.0), exponent)
	return maxf(saturation * terrain_quality, min_eff)

func _get_def(type_int: int, key: String, default: float) -> float:
	var type_key: String = Sim.ZoneType.keys()[type_int]
	return float(_zone_defs.get("zone_types", {}).get(type_key, {}).get(key, default))

# Deep copy snapshot with efficiency injected and Rect2i converted to plain dict.
func snapshot() -> Dictionary:
	var out := {}
	for id in _rows:
		var z: Dictionary = _rows[id].duplicate()
		z["efficiency"] = _compute_efficiency(_rows[id])
		var b: Rect2i = _rows[id]["bounds"]
		z["bounds"] = {"x": b.position.x, "y": b.position.y, "w": b.size.x, "h": b.size.y}
		z["type_name"] = Sim.ZoneType.keys()[_rows[id]["type"]]
		out[id] = z
	return out
