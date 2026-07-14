extends Node

# Published after every tick. The only thing the render layer is allowed to read.
signal tick_completed(snapshot: Dictionary)

var ledger: ResourceLedger
var population: PopulationTable
var tick_count: int = 0
var starvation_ticks: int = 0

func _ready() -> void:
	var rng_seed := randi()
	seed(rng_seed)
	print("Sim RNG seed: %d" % rng_seed)
	_init_tables()

func _init_tables() -> void:
	var resource_defs: Dictionary = SimUtil.load_json("res://data/resources.json")
	var balance: Dictionary = SimUtil.load_json("res://data/balance.json")
	ledger = ResourceLedger.new(resource_defs)
	population = PopulationTable.new(balance.get("starting_population", 20))
	ledger.add_stock(Sim.Res.FOOD, balance.get("starting_food", 100))
	ledger.add_stock(Sim.Res.WOOD, balance.get("starting_wood", 50))

# Called by TickRunner at the end of each tick (step 12).
func emit_snapshot() -> void:
	if ledger.get_stock(Sim.Res.FOOD) == 0:
		starvation_ticks += 1
	else:
		starvation_ticks = 0

	tick_completed.emit({
		"tick": tick_count,
		"starvation_ticks": starvation_ticks,
		"ledger": ledger.snapshot(),
		"population": population.snapshot(),
	})
