# Context — t13 Laser Tender and Attack B (V-launch into a moving wall)

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t13. Builds epic plan §2.13 on top of t12's twin-drone rig (§2.12), with §2.3 and §2.19 (approved).
Code read on `agent/auto-dev` @ `7926c8e` (t12 landed). t12's own context (`docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/1-context.md`) covers the shared AI stack
(`BaseEnemy`, `EnemyBrain`, `EnemyMover`, `EngagementBudget`, `TargetInfo`, the corridor constraint, `EnemyBeam` TWIN, the harness, the roster gates); this file
lists only what t13 adds or leans on differently. Baseline `scripts/gate-time.sh`: GUT `Time` **206.547 s**, 2546 tests.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/twin_laser_drone/twin_laser_pair.gd` | `TwinLaserPair` rig: `bind(a, b, controller)`, leader-only clock, `Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT }`, Open Space frame follows the player, `assault_frame()` planner, strain / collapse, `release()`, `tick_beam()` | Attack B is a new rig entry: a LAUNCHED phase and a **fixed** (launched) frame that FORM must not re-derive from the player |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone_brain.gd` | Drone brain: mirrors the rig phase; LAUNCHED declared, holds still; SOLO `arrive`s at a live `pair.controller`; FORM adds the player's velocity as feed-forward | LAUNCHED gets its motion; FORM on a fixed frame must drop the feed-forward |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone.gd` / `.tscn` | Drone shell, body r 13 on layer 1 / mask 1 | Launched drones start inside the tender's r 40 body: a collision exception is needed |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.gd` | Pair spawner: instantiate, place, seed, `add_child`, `bind`, `enemy_spawned_orphan` | The shape `launch_pair()` copies |
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | HOLD_ARC broad orbit at a held range, nearest-edge DISENGAGE, `_on_budget_expired` deferral while TELEGRAPH / SALVO | The idea the tender's HOLD and launch deferral follow (written fresh) |
| `assault/scenes/enemies/mine_layer/*` | Newest mover specialist: `_apply_config`, `enter_phase` seam, `start_engaged`, `patrol_anchor`, wreck 0.35 medium | Shell / config template |
| `assault/scenes/enemies/defense_turret/defense_turret_brain.gd:99` | LOS only `if Engine.is_in_physics_frame()` else assume visible | The LAUNCH line-of-sight gate uses the same rule |
| `global/enemy_ai/enemy_mover.gd` | `boost(dir, speed, duration)`, `arrive`, `orbit`, `face_toward`, `release_constraint` | Launch boosts (renewed per tick), HOLD arc |
| `global/enemy_ai/target_info.gd` | `position`, `velocity`, `facing` (= `UP.rotated(rotation)`) | Attack B prediction; the standing-player facing rule |
| `global/enemy_ai/enemy_world.gd` | `view_rect`, `projectile_world_rect`, `arena` | Assault hold band, launch only inside the view, exit |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = (−100, −380, 1480, 1480) in the harness; the view is 1280 × 720 inside it | Assault walls are clamped into the inset inner rect |
| `assault/scenes/systems/score_tracker/score_tracker.gd` | Escape = `tree_exited` without `died` on a counted spawn | A docked drone is freed without dying; docking happens only in Open Space |
| `tests/integration/test_twin_laser_drones.gd` | Hand-tick helpers (`_step`, `_arm_stub`, `_victim`, `_hand_ticked`, `_scale_clock`), the no-motion source sweep over rig + spawner | Reused; the sweep gains `laser_tender.gd` (t12 DECISIONS: "any new non-brain file that holds a drone joins that sweep") |
| `tests/integration/test_base_enemy.gd`, `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`, `test_wreck.gd`, `test_enemy_dual_mode.gd`, `test_engagement_deadline.gd` | §2.19 roster gates and guards; t12 added the drone to each | The tender joins each (`_MIN_ROSTER_SIZE` 20) |
| `assault/scenes/systems/wave_builder.gd` | Spawn constructors | `LASER_TENDER`, `laser_tender()` |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `TwinLaserPair.bind(a, b, controller)` | Owner group incl. the tender (never hit by its pair's beam), beam on A, death hooks, `is_broken()` / `is_intact()` |
| Rig FORM → TELEGRAPH → ADVANCE → BREAK, strain, Assault one-attack rule in the drone brain | The whole wall after the V; Attack B only adds an entry and a fixed frame |
| `TwinLaserPair.assault_frame()` inset rule (`inner_rect().grow(-slot_tolerance)`) | The same inset for the Assault Attack B points |
| `EngagementBudget` | Tender life (10 s) and the drones' own budgets (from their launch) |
| `StateLight` | The cradle telegraph (CHARGING) |
| t12 test helpers | Hand ticks, stub hurtbox, fixture victim, 8× clock |

## Conventions that constrain this

- Brains tick through `BaseEnemy._physics_process`; only `EnemyMover` writes velocity / rotation (gated); `laser_tender.gd` places launched drones (`position` before `add_child`) and writes no motion.
- Randomness only from `brain.rng` (drone seeds drawn from the tender brain's rng).
- `accepts_tow()` false in LAUNCH (tow table row).
- Flat `LaserTenderConfig extends ShipConfig`, one `*config*.tres` in the dir, `.tres` wins; joins `enemies` in `_ready()`.
- Body, hurtbox and contact box share one `CircleShape2D` r 40 (COLLISION: contact box layer 256 / mask 0, damage = `collision_damage` 15).
- Hull art nose-down; placeholder art is code-drawn (t16 replaces it), the docked-drone visuals are textureless nodes so the transparency gate has nothing to read.
- Physics queries only on the physics step (LOS assumed true off it).
- Hand-ticked drones clear their body `collision_mask` (t12's finding).
- Test handlers on rig signals never capture the rig (RefCounted cycle → leak at exit).
- Gate allotment 2.0 s.
