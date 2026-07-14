class_name ResourceLedger

# Aggregate table. Natural key: Sim.Res enum value (int).
# Exactly one row per resource — never insert a second FOOD row.
var _rows: Dictionary = {}

func _init(resource_defs: Dictionary) -> void:
	for key in Sim.Res:
		var cap: int = resource_defs.get(key, {}).get("cap", 9999)
		_rows[Sim.Res[key]] = {
			"stock": 0,
			"cap": cap,
			"production_rate": 0.0,
			"consumption_rate": 0.0,
		}

# Used for initialization only — not for tick updates.
func add_stock(res: int, amount: int) -> void:
	var row: Dictionary = _rows[res]
	row["stock"] = clampi(row["stock"] + amount, 0, row["cap"])

func set_production_rate(res: int, rate: float) -> void:
	_rows[res]["production_rate"] = rate

func set_consumption_rate(res: int, rate: float) -> void:
	_rows[res]["consumption_rate"] = rate

# Tick step 4: apply rates and clamp to [0, cap].
func apply_rates() -> void:
	for res in _rows:
		var row: Dictionary = _rows[res]
		var delta := int(row["production_rate"] - row["consumption_rate"])
		row["stock"] = clampi(row["stock"] + delta, 0, row["cap"])

func get_stock(res: int) -> int:
	return _rows[res]["stock"]

func snapshot() -> Dictionary:
	return _rows.duplicate(true)
