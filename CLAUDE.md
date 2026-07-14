# CLAUDE.md

Project constraints for this repository. Read `DESIGN.md` for the full systems specification. This file contains the rules that must hold across every session.

---

## What this project is

A 2D top-down management simulator. Godot 4.x, GDScript. Aggregate simulation with a small named-agent layer on top. See `DESIGN.md` §1 for design pillars.

The developer's background is SQL and data engineering, not game programming. Explain game-specific concepts (scene tree, signals, node lifecycle, delta time) when they first come up. Do not explain data modeling, set operations, or state transitions — that ground is already covered.

---

## The one rule that cannot be broken

**The simulation layer is the source of truth. The presentation layer is a read-only view of it.**

Concretely:

- Nothing in `/sim` may import from `/render`.
- Nothing in `/render` may mutate simulation state.
- The only channel between them is the read-only snapshot published in tick step 12.
- A sprite arriving somewhere does not deliver a resource. The ledger already updated on the tick. The sprite is a delayed, decorative illustration of a number that has already changed.

If a requested change appears to require violating this — if the natural implementation has a sprite writing to the ledger, or a UI element calling into the tick loop — **stop and raise it rather than working around it.** There is almost always a correct alternative, and the workaround will be expensive to unwind later.

The test for this invariant: deleting the entire `/render` directory should not change any game outcome. If it would, the boundary has leaked.

---

## Repository layout

```
/sim        simulation layer — source of truth, no rendering imports
/render     presentation layer — reads snapshot, writes nothing
/events     event system and state-conditioned weighting
/agents     named-agent layer, memory, petitions
/data       JSON tuning files — see below
/tests      unit tests over the simulation
DESIGN.md   full systems specification
CLAUDE.md   this file
```

---

## Data modeling rules

The keying model in `DESIGN.md` §3.0 is not a suggestion. It matters because Godot's node model will push toward giving everything an instance ID, and that is correct for entities and wrong for aggregates.

**Entity tables** — zones, deposits, agents. These have independent lifecycles. Surrogate UUID keys.

**Aggregate tables** — resource ledger, population. Exactly one row per dimension value, permanently. Natural keys (`resource`; `(race, cohort)`). Never insert a second row for an existing dimension value. The only write pattern is update-in-place. Do not add surrogate keys to these — a `ledger_id` would permit two STONE rows, which is a bug the schema should make impossible.

**Derived state** — satisfaction, production rates, efficiency. Recomputed every tick from the tables above. Never persisted. Never stored. If you find yourself caching a derived value across ticks, that is a performance optimization and needs justification, not a default.

**Memory** is its own table with composite PK `(agent_id, tick, event_type)`. Not a list on the agent row. Decay is a bulk update; queries filter on `event_type`. Prune rows whose weight decays below threshold.

---

## Tuning values live in `/data`, not in code

All balance constants — base production rates, consumption per capita, satisfaction weights, event weights, depth risk curves, saturation falloff — belong in JSON files under `/data`.

If a number appears in a `.gd` file and it is not a structural constant, it is in the wrong place. Balancing this game should never require editing GDScript.

```
/data/resources.json    resource definitions, tiers, caps
/data/zones.json        zone types, base rates, saturation curves
/data/events.json       event definitions, weights, choices
/data/agents.json       agent archetypes, agendas
/data/balance.json      global tuning constants
```

---

## The tick loop

Order is load-bearing. Do not reorder without discussing it. See `DESIGN.md` §4 for the full sequence.

The tick is decoupled from framerate. Simulation correctness must not depend on how fast the game renders.

Seed the RNG and log the seed. A reproducible tick sequence is what makes balance bugs tractable.

---

## Testing

The aggregate model is unit-testable, which is unusual for a game. Take advantage of it.

Any production, consumption, or satisfaction formula should have a test asserting exact output for known inputs. When balance drifts later, these tests are what tell you whether the formula changed or the data did.

Prefer tests over manual playtesting for anything expressible as arithmetic.

---

## Build order

Phases are defined in `DESIGN.md` §8. Each phase has an exit criterion. **Do not begin a phase until the previous phase's exit criterion is actually met and the result has been played.**

The temptation to skip ahead — to add sprites before the ledger works, or named agents before events exist — should be resisted. The phases are ordered by dependency, not by interest.

Current phase: **Phase 1 — The Ledger.**

Phase 1 scope: population table, resource ledger, tick loop steps 2–4 only. One hardcoded farm, one hardcoded lumber camp. No zones. No sprites. No agents. UI is a debug panel showing raw numbers.

Phase 1 exit criterion: you can watch numbers change over time, and you can lose to starvation.

Anything outside that scope is out of scope. If it seems necessary, raise it — it probably indicates a gap in the design rather than a reason to expand the phase.

---

## Working style

Explain the *why*, not just the *what*. When a design pattern is introduced, say what it buys and what it costs. When there is a real alternative, name it and say why it lost.

Push back on requests that will cause problems later. A design objection raised now is cheap; the same objection discovered in Phase 6 is not.

Do not write speculative infrastructure for phases that have not started.
