extends Node

# Published after every tick. The only thing the render layer is allowed to read.
signal tick_completed(snapshot: Dictionary)

# Command signals — fired by the render layer, handled here.
# The render layer emits these signals but never calls sim mutation methods directly.
signal create_zone_requested(type: int, bounds_x: int, bounds_y: int, bounds_w: int, bounds_h: int)
signal destroy_zone_requested(zone_id: String)
signal set_workers_requested(zone_id: String, count: int)

var ledger: ResourceLedger
var population: PopulationTable
var zones: ZoneRegistry
var tick_count: int = 0
var starvation_ticks: int = 0

func _ready() -> void:
	var rng_seed := randi()
	seed(rng_seed)
	print("Sim RNG seed: %d" % rng_seed)
	_init_tables()
	create_zone_requested.connect(_on_create_zone_requested)
	destroy_zone_requested.connect(_on_destroy_zone_requested)
	set_workers_requested.connect(_on_set_workers_requested)

func _init_tables() -> void:
	var resource_defs: Dictionary = SimUtil.load_json("res://data/resources.json")
	var balance: Dictionary = SimUtil.load_json("res://data/balance.json")
	var zone_defs: Dictionary = SimUtil.load_json("res://data/zones.json")
	ledger = ResourceLedger.new(resource_defs)
	population = PopulationTable.new(balance.get("starting_population", 20))
	ledger.add_stock(Sim.Res.FOOD, balance.get("starting_food", 100))
	ledger.add_stock(Sim.Res.WOOD, balance.get("starting_wood", 50))
	zones = ZoneRegistry.new(zone_defs)
	_seed_starting_zones(balance)

func _seed_starting_zones(balance: Dictionary) -> void:
	for entry in balance.get("starting_zones", []):
		var type_name: String = entry.get("type", "FARM")
		var workers: int = entry.get("workers", 0)
		var area: int = entry.get("area", 4)
		var type_val: int = Sim.ZoneType[type_name]
		var zone_id := zones.create_zone(type_val, Rect2i(0, 0, area, 1))
		zones.set_workers(zone_id, workers)

# Command handlers — these are the only functions that mutate zone state.

func _on_create_zone_requested(type: int, bx: int, by: int, bw: int, bh: int) -> void:
	zones.create_zone(type, Rect2i(bx, by, bw, bh))

func _on_destroy_zone_requested(zone_id: String) -> void:
	zones.destroy_zone(zone_id)

func _on_set_workers_requested(zone_id: String, count: int) -> void:
	var total_pop := population.get_total_population()
	var current_for_zone := zones.get_zone(zone_id).get("assigned_workers", 0)
	var assigned_elsewhere := zones.get_total_assigned_workers() - current_for_zone
	var available := total_pop - assigned_elsewhere
	zones.set_workers(zone_id, clampi(count, 0, available))

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
		"zones": zones.snapshot(),
		"total_assigned_workers": zones.get_total_assigned_workers(),
	})
