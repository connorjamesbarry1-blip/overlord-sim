extends Node

# Drives the simulation tick. Phase 1: steps 2-4 only.
# Order is load-bearing — do not reorder without updating DESIGN.md §4.

var _balance: Dictionary = {}
var _farm_workers: int = 0
var _lumber_workers: int = 0

func _ready() -> void:
	_balance = SimUtil.load_json("res://data/balance.json")
	_farm_workers = _balance.get("starting_farm_workers", 8)
	_lumber_workers = _balance.get("starting_lumber_workers", 4)

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
	var food_rate := _farm_workers * float(_balance.get("farm_food_per_worker_per_tick", 2))
	var wood_rate := _lumber_workers * float(_balance.get("lumber_wood_per_worker_per_tick", 2))
	SimState.ledger.set_production_rate(Sim.Res.FOOD, food_rate)
	SimState.ledger.set_production_rate(Sim.Res.WOOD, wood_rate)

func _step3_compute_consumption() -> void:
	var pop := SimState.population.get_total_population()
	var food_cons := pop * float(_balance.get("food_per_capita_per_tick", 1))
	SimState.ledger.set_consumption_rate(Sim.Res.FOOD, food_cons)

func _step4_update_ledger() -> void:
	SimState.ledger.apply_rates()
