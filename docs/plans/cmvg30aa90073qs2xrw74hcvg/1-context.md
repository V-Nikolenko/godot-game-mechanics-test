# Context — t4: the context-steering avoidance stage

Epic `cmug23om70001m52wqfwclf3l` (Enemy rework, phase 6), plan task key **t4**. The epic plan
(`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md` §2.4, §2.2, §4.1, §4.4) is the approved design; the epic
research (`2-research.md` §2.2, F1/F2/F10, failure modes 1–2, 4–5) chose context steering as a **mover stage**.
This file is the code inventory for building that stage; it does not re-open the choice.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/enemy_ai/steering.gd` | `Steering`: pure, stateless movement primitives (`seek`, `arrive`, `orbit`, …) | Home of the new pure `Steering.context_avoid()` and its four constants |
| `global/enemy_ai/enemy_mover.gd` | `EnemyMover`: single writer of an AI enemy's velocity / rotation. `step()` already runs slow → `_avoid()` (a no-op hook left by t2) → accel limit → drift → constraint → write | `_avoid()` becomes the real stage; the mover keeps `prev_dir` state; header comment rewritten |
| `global/hazards/hazards.gd` | Static registry: `count()` (O(1)), `around(pos, reach)` (allocates; `info.contains(pos, reach)`) | Source of the infos the stage reads |
| `global/hazards/hazard_info.gd` | `HazardInfo`: `position`, `radius`, `avoid_weight`, `velocity`, `line_of_sight_blocker`, `is_claimed_by(node)` | Every field the stage reads; the claim test for the "own cover" drop |
| `global/hazards/hazard_field.gd` | `HazardField`: the well / anomaly / field script; `avoid_weight` default 1.0; never sets `line_of_sight_blocker` | Fixture well in tests (as t2's rows do); a fixture *wreck* needs a duck-typed node instead |
| `assault/scenes/enemies/base_enemy.gd` | `_physics_process`: `brain.tick(delta)` then `mover.step(delta)`; `_ready()` copies the three hazard fields from config onto the mover (t2) | The profile reaches the mover with no new wiring |
| `global/resources/ship_config.gd` + nine `*_config.tres` | `hazard_avoidance` / `hazard_margin` / `hazard_resistance` (t2, plan §2.2 table) | The per-profile knobs; values already shipped, unchanged here |
| `assault/scenes/enemies/swarm_drone/swarm_drone_brain.gd` | APPROACH = `Steering.corkscrew` toward the player + nudges; BURST = `mover.boost(_burst_dir, 480, 0.45)`; IDLE (Open Space) orbits `patrol_anchor` | Real-brain rows: skims (APPROACH), BURST captured (boost bypasses the stage) |
| `assault/scenes/enemies/fighter/fighter_brain.gd` | APPROACH = Dubins lead-in to the pass start S | Real-brain row: goes round a well in its path |
| `assault/scenes/enemies/{razor_drone,ram_corvette}/*_brain.gd` | All other `mover.boost()` callers: Razor dash, feint lunge, **IDLE_BOOST** (0.4 s along the heading); Ram CHARGE | Every boost bypasses the stage (plan rule; no "ignore hazards" API) |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis velocity filter; runs **after** the stage | "Corridor still bounds the result" row |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `tests/integration/test_enemy_dual_mode.gd` | `_tick()` (exact hand integration), `_hazard_world(mode)`, `_fixture_well(at, props)`, `_fixture_enemy(...)`, `_spawn_fighter(...)`, `_set_limits(...)`, the Hazards section (t2) to append to |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` builders (the Assault one resolves the real corridor) |
| `tests/helpers/fixture_enemy.tscn` + `fixture_brain.gd` | A `BaseEnemy` with **no config** (so its mover's `hazard_avoidance` stays 0 unless a test sets it) whose brain requests `desired_velocity` each tick |
| `tests/unit/test_enemy_mover.gd` | `_rig()`, `_advance()`, `_well()`, and t2's bit-identical recorder `_record(kind)` (four mover kinds, `var_to_bytes`) |
| `tests/unit/test_hazards.gd` | The duck-typed fixture hazard pattern (a plain node answering `hazard_info()`) — the shape of a fixture wreck |

## Conventions that constrain this

- `EnemyMover` is the single writer of motion (`test_enemy_mover_single_writer.gd`); the stage only changes the
  *desired* vector inside `step()`. Brains are not touched.
- **Pass-through rule**: no hazard in reach (or `Hazards.count() == 0`) → `desired` returned unchanged, so t2's
  bit-identical rows (no hazard, far well, −0.0 case) stay green. With `count() == 0` the stage is never entered.
- An unconfigured mover (`hazard_avoidance` 0, the fixture enemy, every bare `_rig()`) never avoids — t2's dual-mode
  rows run on fixture enemies and must not change.
- Determinism: no `Timer`, no rng in the stage; tests hand-tick with fixed `delta`.
- `Hazards` is static: every hazard in a test is `add_child_autofree`d.
- Gate time: allowance **+3.5 s**; GUT ≤ 240 s.
- Nothing in `global/` references `ArenaCamera`.
