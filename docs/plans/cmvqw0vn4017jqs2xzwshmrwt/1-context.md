# Context — t4: segment hazards (`HazardInfo` + `context_avoid`)

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t4, epic plan §2.6 (with §2.1's twin-beam numbers and §2.4's laser-wall
registration, which the endpoint-beam task t5 builds on top of this). Epic research: `docs/plans/cmug23ona0015m52w4t1m73bc/2-research.md`
(not repeated here).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/hazards/hazard_info.gd` | `HazardInfo` (RefCounted): `position`, `radius`, `pull_force`, `movement_penalty`, `avoid_weight`, `velocity`, claims; `falloff()`, `accel_at()`, `penalty_at()`, `contains()` — circles only (`contains`/`penalty_at` are one-line `pos.distance_to(position) <= radius (+ margin)`). | Gains `segment_half`, `exempt_group`, `closest_point()`; `contains`/`penalty_at` get a segment branch, circle expression untouched. |
| `global/hazards/hazards.gd` | Static registry. `around(pos, reach)` filters through `info.contains(pos, reach)`; `penalty_at` / `accel_at` sum or max over every info. | No code change: `around()` becomes segment-aware through `contains`; `accel_at` of a no-pull segment info is `Vector2.ZERO` already (falloff 0 with `core_radius` 0). |
| `global/enemy_ai/steering.gd` | `Steering.context_avoid(pos, desired, infos, avoidance, margin, lookahead, prev_dir)`: 16-slot danger map, per-hazard cone at the led centre (`asin(min(1,(R+M)/d)) + slot`, tapered `avoid_weight · skirt · (1 − off/hw)`), merge by MAX, threshold `1 − avoidance`, clear-way rule, masked pick with `prev_dir` blend, parabolic refinement, speed floor 0.35. | Gains the segment branch inside the per-info loop; the circle body is not edited. |
| `global/enemy_ai/enemy_mover.gd` | `EnemyMover.step()`; `_avoid(desired)` queries `Hazards.around(pos, margin + |desired| · 0.6)`, drops a LOS blocker the actor has claimed, calls `context_avoid`, stores `_avoid_prev`. | Gains the `exempt_group` drop next to the own-claim drop. |
| `tests/unit/test_hazards.gd` | Intent rows for `HazardInfo` / `Hazards` / `HazardDrift` (circle `contains`, `penalty_at`, `around` boundaries). | Segment rows are added; circle rows stay as they are. |
| `tests/unit/test_context_avoidance.gd` | Intent rows for `context_avoid`: pass-through bit-identity, going round, margins, graded thresholds, led drift, MAX merge, hysteresis. Helper `_fly()` integrates the output with no accel limit. | Segment rows are added (with an accel-limited integrator); every existing row stays as is. |
| `tests/unit/test_enemy_mover.gd` | `EnemyMover` intent rows; has the avoidance rig (`_rig`, `_advance`, `_avoider`, `_obstacle`, `_wreck`) and the own-claim drop row. | The exempt-group drop row lives beside the own-claim drop row (it is `EnemyMover._avoid`'s behaviour and needs the registry + an actor). |
| `assault/scenes/projectiles/enemy_beams/enemy_beam.gd` | t2's `EnemyBeam`; exports `registers_hazard`, `avoid_weight`, `hazard_pad`; `hazard_info()` answers null until t5. | Not touched. t5 fills the info (§2.4) using the fields this task adds. |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `Geometry2D.get_closest_point_to_segment(p, a, b)` | Clamped projection for `closest_point()` and for the steering branch (the fighter brain already uses it). |
| `Steering.context_avoid` cone formula | The end cones and the closest-point cone reuse it as written (same half-width, same taper, same skirt). |
| `tests/unit/test_context_avoidance.gd::_info`, `_avoid` | Row helpers; a `_segment()` builder sits beside `_info()`. |
| `tests/unit/test_enemy_mover.gd::_rig`, `_advance`, `_avoider` | The exempt row's mover harness. |
| `tests/helpers/fixture_wreck.gd` | Shape of a duck-typed registry fixture (the exempt row uses an inner class of the same shape with a segment info). |

## Conventions that constrain this
- **Bit-identity with no segment hazard** (Ph6/Ph7 gates): `test_context_avoidance.gd` pass-through rows, `test_enemy_mover.gd`'s
  "no hazard / far well is bit-identical for every mover kind", every level-1 replay. The circle path must produce the same bytes.
- `HazardInfo` callers treat fields as read-only; one instance per hazard node, updated in place.
- Other `Hazards.around()` consumers (Sniper, Fighter cover, Ram wells, Mine Layer stacking, chain mines) filter by `kind` or
  `line_of_sight_blocker`; a laser wall (`kind = &"laser_wall"`, no LOS block) is skipped by all of them except Fighter
  `_inside_other_hazard()` and Sniper `_candidate` / `_inside_other_hazard` (`sniper_brain.gd:554–557, 633–637`), which go through `around()` →
  segment-aware `contains`, the intended reading (round-1 review m2).
- Twin beam numbers (§2.1): `hit_half_width` 10, `draw_half_width` 14, `hazard_pad` 24 (footprint radius 38), `avoid_weight` 0.5,
  `tip_grace_px` 0 (hit segment = drawn segment). `twin_beam.tscn` does not exist yet → named constants in the unit rows; t5 replaces
  them with `EnemyBeamScenes.export_of` reads.
- Roster avoidance profiles (`*_config.tres`, else the `*_config.gd` default; margin, accel, max speed): 1.0 — Swarm (12, 600, 220), Razor (16, 900), Sniper (90, 520, 320), Support (80, 700);
  0.8 — Fighter (60, 700, 300), Gatling (60, 600, 260), Mine Layer (24, 420, 240); 0.7 — Missile Corvette (80, 240); 0.6 — Bomber (70, 260, 240); 0.5 — Ram (60, 500).
- Gate time: allotment 1.5 s of new GUT time; baseline `scripts/gate-time.sh` GUT `Time` **201.007 s**, 2381 tests (2026-10-29).
