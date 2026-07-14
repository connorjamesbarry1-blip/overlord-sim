# Untitled Management Sim — Systems Design Specification

**Version**: 0.1 (pre-implementation draft)
**Engine**: Godot 4.x / GDScript
**Presentation**: 2D top-down, sprite-based
**Genre**: Aggregate-simulation city management with faction politics layer

---

## 1. Design Pillars

These are the constraints every subsequent decision is checked against. If a proposed feature does not serve one of these, it is cut or deferred.

1. **The simulation is the truth; the sprites are a chart.** Game state lives in aggregate tables. Visual entities are a rendering of those tables and have no authority over them.
2. **The mass is numbers; the named are characters.** Thousands of citizens exist as population aggregates. A small cast of named agents (~12) are individually simulated with memory, motive, and relationships. Story comes from the named cast reacting to the numbers.
3. **Resources are finite and location-bound.** Scarcity drives decisions. Expansion into new deposits carries risk. There is no infinite economy.
4. **Specialization has consequences.** Investing heavily in one axis (agriculture, mining, military) creates real vulnerability on the others. The player should regularly face situations their build is bad at.
5. **Distasteful options must be genuinely tempting.** When the player is weak on defense and raiders arrive, the mercenary deal should be the *correct* play, not a trap. Compromise is a mechanic, not a punishment.

---

## 2. Simulation Architecture

### 2.1 The Two Layers

```
┌─────────────────────────────────────────────┐
│  PRESENTATION LAYER  (read-only)            │
│  - Citizen sprites wandering between zones  │
│  - Building sprites reflecting zone state   │
│  - UI panels reading aggregate tables       │
│  - Named-agent portraits and dialogue       │
└──────────────────┬──────────────────────────┘
                   │ reads (never writes)
┌──────────────────▼──────────────────────────┐
│  SIMULATION LAYER  (source of truth)        │
│  - Population table                         │
│  - Resource ledger                          │
│  - Zone registry                            │
│  - Satisfaction / unrest state              │
│  - Named agent state                        │
│  - Event queue                              │
└─────────────────────────────────────────────┘
```

**Hard rule**: The presentation layer never mutates simulation state. A sprite reaching a destination does not deliver resources — the resource ledger already updated on the tick, and the sprite is a delayed, decorative illustration of that fact. This separation is what makes the game debuggable and performant.

### 2.2 Sprite Fabrication

Given a zone with `n` assigned workers, the renderer spawns `min(n, VISUAL_CAP)` sprites that loop between the zone and a relevant destination (stockpile, housing, etc.). `VISUAL_CAP` exists purely to bound draw calls — likely 150–300 on screen.

Sprites carry no inventory. They have no pathfinding requirements beyond "wander plausibly within and between zones." A* is unnecessary; simple waypoint interpolation with jitter is sufficient and vastly cheaper.

If a sprite is destroyed, despawned, or fails to render, **nothing happens to the simulation**. This is a useful invariant to test explicitly.

---

## 3. Data Model

### 3.0 Keying Model

Not every table needs a surrogate key, and adding one where it doesn't belong is actively harmful. The tables in this design fall into three distinct categories, and the category determines the key.

**Entity tables** model things with independent lifecycles — they are created, they persist, they are destroyed. These need surrogate keys.

**Aggregate tables** model derived state along fixed dimensions. There is exactly one row per dimension value, forever. Their natural key *is* the dimension. A surrogate key here would permit duplicate rows for the same dimension value, which is a bug the schema should make impossible.

**Derived state** is recomputed from scratch every tick and never persisted. Storing it invites drift between the stored value and what the formula would currently produce.

| Table | Key | Category | Rationale |
|---|---|---|---|
| Zone registry | `zone_id` (UUID) | Entity | Zones are created and destroyed by the player |
| Deposits | `deposit_id` (UUID) | Entity | Deposits are discovered and depleted |
| Named agents | `agent_id` (UUID) | Entity | Agents arrive, act, may die |
| Agent memory | `(agent_id, tick, event_type)` | Entity (composite) | FK-anchored to agent; see 5.3 |
| Resource ledger | `resource` (enum) | **Aggregate** | Exactly one STONE row exists, ever |
| Population | `(race, cohort)` | **Aggregate (composite)** | Exactly one HUMAN/ADULT row exists, ever |
| Satisfaction / unrest | — | **Derived** | Recomputed in tick step 8; never stored |

The distinction matters more than it appears. Godot's node model will push toward giving everything an instance ID, and for the entity tables that is correct. For the ledger and population tables it is wrong: `UPDATE ledger SET stock = stock + n WHERE resource = 'STONE'` should be the only write pattern, and the schema should make an accidental `INSERT` of a second STONE row impossible.

### 3.1 Population Table

The core aggregate. Natural composite key: `(race, cohort)`. There is exactly one row per pair — you never insert a second HUMAN/ADULT row, you update the one that exists.

| Field | Type | Notes |
|---|---|---|
| `race` | enum | HUMAN only at v1. ELF, DWARF, ORC, GOBLIN reserved. |
| `cohort` | enum | CHILD, ADULT, ELDER |
| `count` | int | Headcount |
| `employment` | dict[job → int] | Sums to ≤ `count` for ADULT cohort |
| `health` | float 0–1 | Aggregate wellness; drives death rate |
| `loyalty` | float 0–1 | Drives unrest and defection |

Employment is the primary player lever. Assigning adults to jobs is the main allocation decision each turn.

### 3.2 Resource Ledger

Aggregate table. Natural key: `resource`. One row per resource type, permanently.

| Field | Type | Notes |
|---|---|---|
| `resource` | enum | **PK.** FOOD, WOOD, STONE, IRON, STEEL, GEMS, ARCANA |
| `stock` | int | Current stored amount |
| `production_rate` | float | Computed per tick from zones + workers |
| `consumption_rate` | float | Computed per tick from population + buildings |
| `cap` | int | Storage limit; overflow is wasted |

**Tiering**: FOOD and WOOD are baseline. STONE and IRON require deposits. STEEL requires a smelter consuming IRON + WOOD. GEMS and ARCANA are rare, deposit-gated, and feed the crafting system.

### 3.3 Zone Registry

Zones are painted rectangles tagged with a purpose. This is the Songs of Syx model and is dramatically simpler than per-tile placement.

| Field | Type | Notes |
|---|---|---|
| `zone_id` | uuid | |
| `type` | enum | FARM, MINE, LUMBER, SMELTER, HOUSING, BARRACKS, WORKSHOP, STOCKPILE |
| `bounds` | rect | Tile coordinates |
| `assigned_workers` | int | Player-set |
| `deposit_ref` | uuid? | For MINE only — links to a finite deposit |
| `efficiency` | float | Derived: terrain quality × worker saturation |

Production for a zone = `base_rate(type) × assigned_workers × efficiency`. Worker saturation falls off past an optimal density — cramming 200 workers into a small farm does not yield 200× output.

### 3.4 Deposits (Finite Resources)

| Field | Type | Notes |
|---|---|---|
| `deposit_id` | uuid | |
| `resource` | enum | STONE, IRON, GEMS, ARCANA |
| `remaining` | int | Depletes as mined |
| `depth` | int | 0 = surface. Higher = richer *and* more dangerous. |
| `discovered` | bool | Requires survey investment |

**Depth is the risk mechanic.** Deeper deposits yield rarer resources at higher rates, but each depth tier increases the per-tick probability of a `DELVE_INCIDENT` event. This is the "dwarves mined too deep" hook, and it is a *player choice*, not a scripted beat.

### 3.5 Satisfaction & Unrest

**Derived state. Not a table. Not persisted.** Recomputed from scratch in tick step 8 and published in the render snapshot. The only value that carries across ticks is `unrest`, which is an accumulator — and even that is derived from satisfaction rather than authored.

```
food_access    = min(1.0, food_stock / (population × food_need))
shelter_access = min(1.0, housing_capacity / population)
safety         = f(garrison_strength, recent_raid_damage, walls)
prosperity     = f(luxury_goods, crafted_items, surplus)

satisfaction   = weighted_mean(food, shelter, safety, prosperity)
unrest         += (SATISFACTION_THRESHOLD - satisfaction) × UNREST_RATE
```

Unrest above thresholds triggers escalating consequences: productivity penalty → emigration → riot → coup. The coup is a real fail state.

---

## 4. The Tick Loop

Order matters. This is effectively a batch job with dependencies.

```
ON_TICK:
  1.  RESOLVE_EVENTS       — apply queued event effects to state
  2.  COMPUTE_PRODUCTION   — zones × workers × efficiency → resource inflow
  3.  COMPUTE_CONSUMPTION  — population + buildings → resource outflow
  4.  UPDATE_LEDGER        — stock += (production - consumption), clamp to cap
  5.  DEPLETE_DEPOSITS     — subtract mined amounts from deposit.remaining
  6.  UPDATE_HEALTH        — food/shelter shortfall → health decay
  7.  UPDATE_POPULATION    — births, deaths, migration
  8.  RECOMPUTE_SATISFACTION
  9.  UPDATE_UNREST
  10. TICK_NAMED_AGENTS    — each agent observes state, updates opinion, may act
  11. ROLL_EVENT_TABLE     — generate new events based on current state
  12. EMIT_RENDER_STATE    — publish read-only snapshot for presentation layer
```

Steps 1–11 should complete in well under a frame even at high population. Step 12 is the only thing the renderer ever touches.

**Tick rate**: Decouple from framerate. Target 1 sim tick per in-game hour, with player-controllable speed (pause / 1× / 3× / 10×).

---

## 5. Named Agent Layer

This is where the game gets its story. Roughly 8–12 named agents at any time.

### 5.1 Agent State

| Field | Type | Notes |
|---|---|---|
| `agent_id` | uuid | |
| `name` | string | Generated |
| `role` | enum | GUILD_HEAD, COUNCIL, ENVOY, MERC_CAPTAIN, RIVAL |
| `faction_ref` | uuid | Which body they speak for |
| `agenda` | list[Goal] | What they want from you |
| `opinion` | float -1..1 | How they feel about the player |
| `leverage` | float | How much they can hurt you if crossed |

Note that `memory` is **not** a field on this table. It is a separate FK-anchored table — see 5.3.

### 5.2 Agent Tick

Each agent, each tick:

1. **Observe** — read the aggregate state relevant to their agenda. The Mining Guild head reads `stone_production`, `mine_worker_allocation`, `delve_incidents`.
2. **Evaluate** — compare observed state to agenda goals. Compute a satisfaction delta.
3. **Update opinion** — drift toward or away from the player based on that delta.
4. **Possibly act** — if opinion crosses a threshold, or a goal becomes urgent, emit a `PETITION` event: they come to the player with a demand, an offer, or a threat.

### 5.3 Memory (separate table)

Memory is what makes this feel real, and it must be **its own table**, not a list embedded in the agent row.

| Field | Type | Notes |
|---|---|---|
| `agent_id` | uuid | **PK part.** FK → named agents |
| `tick` | int | **PK part.** When it happened |
| `event_type` | enum | **PK part.** What the player did |
| `weight` | float | Signed impact on opinion |
| `decay_rate` | float | How fast it fades |

Composite PK: `(agent_id, tick, event_type)`.

Two reasons this cannot be an embedded list:

1. **Decay is a set operation.** Each tick, memory weights decay toward zero. As a table this is one bulk update across all rows. As embedded lists it is a nested loop over every agent's list, every tick.
2. **You need to query it.** "Which agents remember the mine refusal?" is a filter on `event_type`. With embedded lists you have to scan every agent and walk every list. With a table it is a single indexed lookup, which matters both for the agent tick and for writing dialogue that references shared grievances.

Entries decay slowly and agents reference them explicitly in dialogue ("You turned us away when we asked for the eastern shaft. We remember."). Cheap to implement, disproportionately powerful for player attachment.

**Pruning**: rows whose `weight` has decayed below a threshold should be deleted, not kept at near-zero. Otherwise the table grows without bound over a long game.

### 5.4 The Mercenary Case

The mercenary captain is a deliberate design object, not a generic agent. Their properties:

- Appears when `safety` is low and a raid is imminent — i.e., exactly when you need them.
- Their price is steep but *affordable*, and refusing them should plausibly lose you the settlement.
- They have their own agenda that is **not aligned with yours**. Accepting their help increments a hidden `debt` and `presence` value.
- High `presence` unlocks their own petitions, which escalate toward demands (territory, tribute, a seat on the council).
- The player who leans on mercenaries repeatedly ends up with a second power center inside their own walls.

This is the pillar-5 mechanic made concrete. The deal is *correct* in the moment and *corrosive* over time.

---

## 6. Event System

Events are the connective tissue between the aggregate sim and the named-agent layer.

### 6.1 Event Types

| Type | Trigger | Example |
|---|---|---|
| `RAID` | Low `safety` + elapsed time | Goblin warband approaches from the south |
| `DELVE_INCIDENT` | Deposit depth × mining intensity | Something was disturbed in the deep shaft |
| `PETITION` | Named agent opinion/agenda | The Smiths' Guild demands iron priority |
| `WINDFALL` | Random, low weight | A gem seam is exposed by a collapse |
| `CRISIS` | Compound state failure | Famine: food stock 0 for N ticks |
| `OPPORTUNITY` | High surplus + agent goodwill | An elven envoy proposes a trade pact |

### 6.2 Event Weighting

The event table is **state-conditioned**, not random. The roll each tick weights events by current simulation state:

```
weight(RAID) ∝ (1 - safety) × prosperity × time_since_last_raid
weight(DELVE_INCIDENT) ∝ max_active_depth × mining_intensity
weight(PETITION) ∝ max over agents of |opinion_drift|
```

This is what produces the pillar-4 consequence: a player who goes all-in on agriculture accumulates high `prosperity` and low `safety`, which mathematically *guarantees* a raid. The punishment is not scripted. It falls out of the numbers.

### 6.3 Event Resolution

Events present the player with 2–4 choices. Each choice:
- Applies immediate state deltas (resources spent, population lost)
- Writes `MemoryEntry` rows to affected agents
- May spawn follow-on events (accepting mercenary help → later mercenary petition)

---

## 7. Crafting System

Deliberately kept narrow at v1. The purpose of crafting is to give rare resources a sink and to create faction-wide buffs worth fighting over.

**Chain**: `Raw → Refined → Crafted`

- IRON + WOOD → (Smelter) → STEEL
- STEEL → (Workshop) → Tools (+efficiency to a zone type)
- STEEL + GEMS → (Workshop) → Arms (+garrison strength)
- GEMS + ARCANA → (Workshop) → **Artifact** (faction-wide modifier)

**Artifacts** are the top of the pyramid. There should be few of them, they should be expensive, and each should meaningfully change how the settlement plays — not a +5% stat bump, but something like "your miners no longer trigger delve incidents above depth 3" or "unrest decays 3× faster." Artifacts are also what other factions covet, which is a natural hook for the conquest layer later.

---

## 8. Phased Build Order

The sequencing rule: **get to a playable loop before you get to dragons.** Every phase should end with something you can actually sit down and play.

### Phase 0 — Skeleton
Godot project set up. Tile grid renders. Camera pan/zoom. A single hardcoded sprite moves. No simulation at all.
*Exit criteria: you can look at a map and move around it.*

### Phase 1 — The Ledger
Population table, resource ledger, tick loop steps 2–4 only. No zones yet — hardcode one farm and one lumber camp. UI shows the numbers. Population starves if you don't produce food.
*Exit criteria: you can watch numbers go up and down over time, and you can lose.*

### Phase 2 — Zones & Allocation
Zone painting. Worker assignment UI. Efficiency and saturation curves. Multiple zone types. This is the first phase where the player makes real decisions.
*Exit criteria: you can build a functioning settlement that sustains itself.*

### Phase 3 — Sprites
Presentation layer. Citizen sprites fabricated from employment numbers. Buildings render per zone. **Nothing about the simulation changes.** This phase is purely visual and should be provably removable without breaking the game.
*Exit criteria: the settlement looks alive, and unplugging the renderer changes no game outcome.*

### Phase 4 — Satisfaction & Unrest
Satisfaction computation, unrest accumulation, escalating consequences up to coup. Now the player can lose for social reasons, not just starvation.
*Exit criteria: neglecting your population is a distinct, survivable-but-real failure mode.*

### Phase 5 — Deposits & Depth
Finite deposits. Survey mechanic to discover them. Depth tiers. `DELVE_INCIDENT` events. The first real risk/reward decision.
*Exit criteria: you can choose to dig deeper for iron and get hurt for it.*

### Phase 6 — Events & Raids
Event system, state-conditioned weighting, raid mechanic, garrison and safety. The specialization-consequence pillar becomes live.
*Exit criteria: an agriculture-heavy build gets raided and has to react.*

### Phase 7 — Named Agents
Agent state, agendas, opinion, memory, petitions. Introduce 3–4 agents first, not the full cast. **Mercenary captain lands here** — this phase is where the game gets its soul.
*Exit criteria: someone knocks on your door, you turn them down, and they remember.*

### Phase 8 — Crafting & Artifacts
Refinement chains, workshops, tools, arms, artifacts. Rare resources finally matter.
*Exit criteria: there is something worth digging deep for.*

### Phase 9+ — Expansion
Additional races as faction variants. Diplomacy. External map. Conquest layer. Dragons.
*Nothing here starts until Phases 1–8 are actually fun.*

---

## 9. Technical Notes for Implementation

**Language/Engine**: Godot 4.x, GDScript. GDScript is Python-adjacent and will feel familiar coming from SQL/scripting. Do not reach for C# unless profiling proves you need it — you almost certainly will not, because the simulation is arithmetic, not entity iteration.

**Data-driven design**: All tuning values (base production rates, consumption per capita, satisfaction weights, event weights, depth risk curves) live in external JSON or Godot `Resource` files, **not** in code. This plays directly to existing XML/JSON experience and means balancing does not require touching GDScript.

Suggested layout:
```
/data
  /resources.json      — resource definitions, tiers, caps
  /zones.json          — zone types, base rates, saturation curves
  /events.json         — event definitions, weights, choices
  /agents.json         — agent archetypes, agendas
  /balance.json        — global tuning constants
```

**Save/load**: Because the simulation is pure aggregate state, serialization is nearly free — dump the tables to JSON. There is no scene graph to reconstruct, no per-entity state to preserve. This is a significant hidden benefit of the architecture.

Serialize the **entity tables and aggregate tables only**. Do *not* serialize derived state (satisfaction, production rates, efficiency) — recompute it on load from the persisted tables. If a loaded save produces different satisfaction than the pre-save session did, that is a bug in the derivation, and persisting the value would have hidden it rather than fixed it. The save file is a useful forcing function for keeping the derived/persisted boundary honest.

**Testing**: The aggregate model is *unit-testable*, which is unusual for games. You can assert that 100 workers in a farm with efficiency 0.8 produce exactly N food per tick. Write these tests. They will save enormous time during balancing.

**Determinism**: Seed the RNG and log the seed. A reproducible tick sequence makes bug reports and balance debugging tractable.

---

## 10. Open Questions

Deliberately unresolved. These should be answered by playing Phase 2–4 builds, not by argument.

1. **Time scale** — how long is a tick in game-fiction terms, and how many ticks in a "season"? Affects pacing of everything.
2. **Map scale** — one settlement, or a settlement plus surrounding territory? Phase 9 conquest implies the latter, but Phase 1–8 does not need it.
3. **Population ceiling** — what is the target max? This determines whether `VISUAL_CAP` ever actually binds.
4. **Death permanence for named agents** — can they be killed? If so, are they replaced, and does the replacement inherit the faction's memory of you?
5. **Player avatar** — the Overlord framing implies the player is a *person* in the town, not a disembodied hand. Is there a player character sprite, and does it matter mechanically?

---

## Appendix: Reference Frame

| Source | What is being borrowed |
|---|---|
| **Songs of Syx** | Aggregate simulation, zone painting, population scale, macro-economic focus |
| **Overlord (anime)** | Player-as-sovereign framing, faction vassalage, conquest ambition, morally compromised alliances |
| **Rimworld** | Emergent consequence, state-conditioned event generation, the feeling that the world reacts to your choices |
| **Dwarf Fortress** | Depth-as-risk, "dig too greedily" as a *player choice* rather than a cutscene |
