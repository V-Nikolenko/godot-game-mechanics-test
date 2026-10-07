# Context — t8b-fighter-run

The epic's own `1-context.md` / `2-research.md` / `3-plan.md` (Revision 2, approved round 2 with implementer notes
N1–N12) in `docs/plans/cmufs7ekv000lnm2x7nbswijy/` are the design this task comes from. This file records only what
this task needs on top of them, read from the code on `agent/auto-dev` at f8efc74 (t8a done).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/fighter/fighter_brain.gd` | t8a shell: `Phase {APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE}`, `enter_phase()` seam, plain-intercept APPROACH that brakes at `standoff_radius`, DISENGAGE, `on_suspended()` rail fallback | The file this task fills in. RUN_IN..REPOSITION are `pass` today; no AI fire |
| `assault/scenes/enemies/fighter/fighter.gd` | Builds both `AimedAttackPattern`s per instance from config and hands `rng` to them; copies config onto the brain after the brain's `_ready()` | Patterns already exist: aimed (Pulse 300/8, accuracy 0.7, spread 0.035) on `AimedAttack`, forward (Scatter 420/6, spread 0.13, `aim_at_player = false`) on `ForwardAttack` |
| `assault/scenes/enemies/fighter/fighter_config.gd/.tres` | Every §2.4 field already exists (geometry, weapons, `min_burst_period` 1.2, tactics, rail) | No new *plan* field is missing; this task adds none except where §3 of the task plan says so |
| `assault/scenes/enemies/fighter/fighter.tscn` | Body/HurtBox/ContactHitBox share `CircleShape2D` r 13 × scale 2.2 = **28.6 px hull** | Clearance and "no hurtbox overlap" (player hurtbox 5 × 2.7 = 13.5 px, `test_razor_drone.gd`) |
| `tests/integration/test_fighter.gd` | t8a cases; `_harness()`, `_spawn()`, `_tick()` (re-integrates position from velocity) | Extended here. `test_approach_closes_on_the_player_and_holds_at_the_standoff` and `test_aim_mode_on_an_ai_fighter_changes_nothing` ("no AI firing yet") describe t8a-only behaviour and must be rewritten |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds; bare `CharacterBody2D` player (rotation 0 → `TargetInfo.facing` = UP) | Dual-mode specs |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = x −100..1380, y −380..1100 (1480²); pushes only outside it (soft band 120, hard 450) | Assault clamps, lane flip, bearing flip, containment assertions |
| `global/enemy_ai/steering.gd` | `turn_toward`, `clamped_lead_time`, `intercept` | The only way a brain bends a path (Ph2 D7) |
| `global/enemy_ai/enemy_mover.gd` | Single writer of velocity/rotation; `face_toward`; rotation capped by `max_turn_rate` (= `turn_rate`); `sprite_forward_angle_of()` | The brain requests only; the nose is `RIGHT.rotated(rotation + sprite_forward_angle_of(actor))` |
| `global/enemy_ai/burst_clock.gd` | `start/advance/is_running/stop`, first shot due on the first advance | Burst sequencing |
| `global/components/attack_controller.gd` | `fire_now()` fires the pattern once, ignoring `enabled` | One call per shot the clock reports due |
| `global/components/aimed_attack_pattern.gd` | `aim_point` (INF = ask `TargetInfo`), `spread_angle`, `rng`; non-aimed fires along the nose | The aimed burst locks `aim_point` for its duration |
| `global/components/state_light.gd` | `State {OFF, ARMED, CHARGING, COMMIT}`, `set_state()` | Telegraph |
| `global/enemy_ai/engagement_budget.gd` | `update()`, `remaining()`, `active` only in Assault | Deferred DISENGAGE |
| `global/components/bullet_pool.gd` | `_active` list, `acquire()` | Tests count shots as `_active` growth per tick |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `Steering.turn_toward` / `clamped_lead_time` | Heading bending at `turn_rate`; the 0.3–0.8 s lead |
| `TargetInfo.player()` / `intercept()` | P̂ and the aimed burst's lock point (blend by `aimed_accuracy`, as `aim_direction` does) |
| `EngagementBudget`, DISENGAGE (t8a) | Unchanged; DISENGAGE entry is only *deferred* while a burst runs |
| `BurstClock` (t3), `EnemyRounds` pools (t2/t8a) | Exact burst sizes; pools already sized (Pulse 20, Scatter 8) |
| `StateLight` | CHARGING / ARMED / OFF |
| Swarm/Razor brain shape | `phase_changed(new_phase: int)`, `enter_phase()` as the one transition path, `_phase_time`, `_heading()` |

## Conventions that constrain this
- Single-writer gate (`test_enemy_mover_single_writer.gd`): the brain never writes `actor.velocity/rotation`; it
  requests. `global/enemy_ai/*.gd` is swept too, so a new helper there must not write motion either.
- Signal arity gate: `weapon_mode_changed(mode: int)` is declared with its argument.
- Brain clock = accumulated `delta`; randomness only from `rng`; perception only through `TargetInfo`.
- Tests: harness built inside the body from a label (`use_parameters` leak trap); `_tick()` re-integrates position;
  the shipped `.tres` is never written (per-case changes go to the fighter's private `config`).
- Plan review notes that bind this task: **N1** (moving-player closest approach measured against the tick's P̂),
  **N4** (`min_burst_period` enforced by the brain), **N8** (degenerate solo/same-kind turns; measure TURN radius on a
  pass that really turns), **N9** (FRONTAL fallback lane ⟂ the new `u`).
