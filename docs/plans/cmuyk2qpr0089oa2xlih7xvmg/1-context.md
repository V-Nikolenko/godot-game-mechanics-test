# Context — t10 Bomber bombing runs (task cmuyk2qpr0089oa2xlih7xvmg)

Epic plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.4 items 1–8, §2.9.4, §4 row
`test_bomber.gd (t10)`, plus review round 2 finding B1 (c)–(e) and N7/N9 (prompt "Plan review").

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/bomber/bomber_brain.gd` | t9 shell: `Phase {APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE}`, `enter_phase` seam, APPROACH = plain intercept, budget → DISENGAGE (curved exit) | t10 replaces APPROACH and fills RUN / ESCAPE / REPOSITION, the deferral |
| `assault/scenes/enemies/bomber/bomber.gd` | `Bomber.drop(kind, dir, speed, target_point)` — pool acquire + config → `launch()`; rail clock | The brain's only way to release ordnance |
| `assault/scenes/enemies/bomber/bomber_config.gd/.tres` | Flat config with every §2.4 field (t9) | Read by the brain; `.tres` holds only HP/contact/score (defaults are the script's) |
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd` | t6 ordnance: mine ejected with linear-decay speed over `eject_time` 0.3 s, then still; armed `arm_delay` after launch; trigger = poll of overlaps; warning then `ContactBlast` | Sets the mine-rest arithmetic (displacement = v₀·T/2) and the outcome test's physics |
| `global/components/contact_blast.gd` | Layer-256 blast area, detected by a player `HurtBox` | What the outcome test counts |
| `global/enemy_ai/dubins_path.gd` | `DubinsPath.candidates(p0,h0,p1,h1,r)`, `sample(step)` | The APPROACH lead-in |
| `global/enemy_ai/steering.gd` | `turn_toward`, `orbit` | Path tracking, ESCAPE arc, REPOSITION |
| `global/enemy_ai/enemy_mover.gd` | Single writer; `max_speed`, `acceleration` 260 cap the velocity change | The feasible turn radius at 240 px/s is v²/a = 221 px, not 150 |
| `global/enemy_ai/engagement_budget.gd` | `update()`, `remaining()`, `active` only in Assault | Deferral and "one run per life" |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = x −100..1380, y −380..1100 | Clamp rect (grown by −64) |
| `tests/integration/test_bomber.gd` | t9 cases, hand-ticked (`_tick`) | t10 extends it |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a stub player | The dual harness |
| `tests/integration/test_level1_fighter_exit.gd` | Real `WaveManager` + `ArenaCamera` replay harness | Shape of the attack-in-budget row |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `FighterBrain._plan/_track` | Dubins plan + pure-pursuit tracking over `sample(8)` with `turn_toward` — copied in reduced form (no clearance / squad logic) |
| `BomberBrain._enter_disengage/_tick_disengage` | The Assault exit, unchanged |
| `Bomber.drop()` | Ordnance release |
| `TargetInfo.player()` | Player position and velocity |
| `test_enemy_ordnance.gd::_player` | Shape of a player stub with a layer-128 area |

## Conventions that constrain this
- Brain requests only (`mover.request_velocity`, `max_speed` field writes); single-writer gate has an empty allowlist.
- Clock = accumulated `delta`; randomness only from `brain.rng`; no `Timer` / `create_timer`.
- Signals declared with the arity they emit (`phase_changed(new_phase: int)` already).
- Config flat (shallow `duplicate()` complete); new fields are plain numbers.
- `test_level1_*` pins: level-1 bombers stay on `.move()` rails until t21 — t10 must not touch level data.
- Tests: hand-ticked where physics overlaps are not needed; real physics frames (await `physics_frame`) only for
  the blast-outcome and WaveManager rows. No abandoned timers (`scripts/check-test-leaks.sh`).
