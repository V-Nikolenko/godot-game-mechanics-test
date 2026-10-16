# Context: t8, the Missile Corvette's fight

Epic plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.10 (this task), §2.9 (t7 shell), §2.4 (tow hooks), §4.1,
§4.3 (approved). This file records only what in the code the build leans on.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | t7 minimal brain: APPROACH (`arrive` at `held_range()` on the player→corvette line, nose via `face_toward`), Assault budget → DISENGAGE (Bomber exit), `accepts_tow()` already false in TELEGRAPH/SALVO, full append-only `Phase` enum | The file this task fills in |
| `assault/scenes/enemies/missile_corvette/missile_corvette.gd` | `fire(kind, aim_point) -> EnemyRocket` (alternates TubeL/TubeR, null + `rockets_refused` when a pool is dry), `set_tube_glow(amount)`, `sprite_forward_angle = PI/2` | The brain's only way to launch and to light the tubes |
| `assault/scenes/enemies/missile_corvette/missile_corvette_config.gd/.tres` | Every §2.9 field (range, arc, salvo, engagement) | All numbers the brain reads |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket_scenes.gd` | `scene_for`, `pool_size_for`, `max_time_of(kind)` (reads a scene export through `PackedScene.get_state()`) | Generalise to read `cruise_speed` for the intercept, without instantiating |
| `global/enemy_ai/enemy_mover.gd` | `orbit`, `break_contact`, `arrive`, `face_toward` wrappers; `max_turn_rate` caps the nose | All motion requests |
| `global/enemy_ai/steering.gd` | `orbit` (anchor walks the circle at a caller-advanced angle; correction `clamp(d*4, 60, max)`), `break_contact` (lateral share doubled for a closing threat) | HOLD_ARC motion |
| `global/enemy_ai/target_info.gd` | `player(tree)`, `predicted_position(t)`, `intercept(from, speed) -> {ok, point, time}` | Kind choice and aim points |
| `global/enemy_ai/burst_clock.gd` | `start(count, gap)`, `advance(delta) -> due` (first shot on the first advance) | SALVO cadence |
| `global/enemy_ai/engagement_budget.gd` | `update`, `remaining()` (INF outside Assault), public `seconds` | Deferral and attack gate |
| `global/components/state_light.gd` | `State { OFF, ARMED, CHARGING, COMMIT }`, `get_state()` | Telegraph light |
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | `ATTACK_GATE_MARGIN := 0.05`, `_attack_allowed()`, expiry deferred in committed phases | Gate / deferral idiom |
| `assault/scenes/enemies/bomber/bomber_brain.gd` | `choose_kind(...)` precedent | Kind choice shape |
| `tests/integration/test_missile_corvette.gd` | t7 rows; `_spawn` (hand-ticked, `start_engaged`), `_tick` (brain + integrate velocity) | t8 rows join this file |
| `tests/integration/test_base_enemy.gd` `_REFUSING_PHASES` | Real-scene tow refusal per brain | Corvette row (TELEGRAPH, SALVO) |
| `tests/helpers/enemy_ai_harness.gd` | Dual-mode world; Assault adds `ArenaCamera` (corridor x −100..1380, y −380..1100) | Every dual row |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `Steering.orbit` / `break_contact` via the mover | Broad arc and the min-range escape, no new steering maths |
| `TargetInfo.intercept` | Lead time for DUMB spacing and the PURSUIT/CLUSTER/WARHEAD aim point |
| `BurstClock` | Exact salvo size and gap |
| `EngagementBudget.remaining()` + the Ram's gate margin | Attack gate |
| `MissileCorvette.fire` / `set_tube_glow` | Launch and tube light, already built and tested in t7 |

## Conventions that constrain this

- Brain requests only (`test_enemy_mover_single_writer.gd`, empty allowlist): no `actor.velocity` / `rotation` writes.
- Clocks are accumulated `delta`; randomness from `brain.rng` only; the player only through `TargetInfo`.
- Shooters never use `StateLight.COMMIT` (Ph2/Ph3).
- A telegraphed attack is never cut off by the budget and never moved by an ally (`accepts_tow`).
- Tests: dual-mode `use_parameters(["open_space", "assault"])`, harness built in the body, hand-ticked; GUT allotment 5.0 s.
