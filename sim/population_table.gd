class_name PopulationTable

# Aggregate table. Natural composite key: (race, cohort).
# Exactly one row per pair — update in place, never insert a second HUMAN/ADULT row.
var _rows: Dictionary = {}

func _init(starting_pop: int) -> void:
	_rows[_key(Sim.Race.HUMAN, Sim.Cohort.ADULT)] = {
		"race": Sim.Race.HUMAN,
		"cohort": Sim.Cohort.ADULT,
		"count": starting_pop,
		"health": 1.0,
		"loyalty": 1.0,
		"employment": {},
	}

func _key(race: int, cohort: int) -> String:
	return "%d_%d" % [race, cohort]

func get_count(race: int, cohort: int) -> int:
	return _rows.get(_key(race, cohort), {}).get("count", 0)

func get_total_population() -> int:
	var total := 0
	for row in _rows.values():
		total += row["count"]
	return total

func snapshot() -> Dictionary:
	return _rows.duplicate(true)
