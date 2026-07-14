extends Node

# Drives the simulation tick. Phase 2: steps 2-4.
# Order is load-bearing — do not reorder without updating DESIGN.md §4.

var _balance: Dictionary = {}

func _ready() -> void:
	_balance = SimUtil.load_json("res://data/balance.json")
	var timer := Timer.new()
	timer.wait_time = float(_balance.get("tick_interval_seconds", 1.0))
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()

func _on_tick() -> void:
	SimState.tick_count += 1
	_step2_compute_production()
	_step3_compute_consumption()
	_step4_update_ledger()
	SimState.emit_snapshot()

func _step2_compute_production() -> void:
	# Zero all rates first so zones that lost workers don't carry stale values.
	for res in Sim.Res.values():
		SimState.ledger.set_production_rate(res, 0.0)
	# Sum production across all zones.
	for zone in SimState.zones.get_all_zones():
		var res_val: int = SimState.zones.get_output_resource(zone["zone_id"])
		if res_val == -1:
			continue
		var prod: float = SimState.zones.compute_zone_production(zone["zone_id"])
		var current: float = SimState.ledger._rows[res_val]["production_rate"]
		SimState.ledger.set_production_rate(res_val, current + prod)

func _step3_compute_consumption() -> void:
	var pop := SimState.population.get_total_population()
	var food_cons := pop * float(_balance.get("food_per_capita_per_tick", 1))
	SimState.ledger.set_consumption_rate(Sim.Res.FOOD, food_cons)

func _step4_update_ledger() -> void:
	SimState.ledger.apply_rates()
