# Context: t16, Space Fortress geometry weapons

The epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.7.2–§2.7.7 B (with §2.5.5, §2.5.6, §2.6, §2.15, §2.16) is the approved design. This file lists what
exists, so the task plan only fills the gaps.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_fortress/fortress_brain.gd` | Movement (t6), batteries + `attack_gate()` (t7), `begin_spin()` / `end_spin()`, `on_emp_started()`, `silence()` (empty, t16's), `attacks_snapshot()` (spoke / core-ring fields 0 placeholders), `arena_snapshot()` (`[]`) | t16 adds the spoke volleys, ring pulse and core ring here, owner-ticked from `tick()` |
| `assault/scenes/enemies/space_fortress/space_fortress.gd` | Root: `_ready()` builds mounts, binds the brain, owner group `fortress_<id>`; `_on_health_changed` death (power_down, `brain.silence()`, scuttle); no `_physics_process` override | t16 builds `CoreRingPool` in `_ready()`, binds spokes / ring / pool to the brain, adds the FADE tick in `_physics_process` |
| `assault/scenes/enemies/space_fortress/space_fortress.tscn` | Hull, nine parts, `Thrusters`, `CriticalOverlay`, `PhaseDriver` | t16 adds `HullBeams/Spoke0..3` (+ beam instances) and `PulseRing` |
| `assault/scenes/enemies/space_fortress/space_fortress_config.gd/.tres` | Flat config groups Parts … Batteries | t16 appends a `Geometry weapons` group |
| `assault/scenes/projectiles/enemy_beams/enemy_beam.gd`, `beam.tscn` | Owner-ticked beam: `setup`, `start`, `tick`, `cancel` (TELEGRAPH→OFF, ACTIVE→FADE), `phase_changed`, `target_hit`; emitter points along node local +X; hits `EnergyHitScan` victims outside the owner set; `registers_hazard` | the spoke beam scene inherits `beam.tscn` |
| `assault/scenes/projectiles/enemy_beams/energy_ring.gd`, `energy_ring.tscn` | Owner-ticked ring: TELEGRAPH → EXPANDING → FADE → OFF; centre fixed at `start(gap_start_deg)`; `in_gap()`; `gap_center_deg()` | the pulse ring scene inherits `energy_ring.tscn` |
| `assault/scenes/enemies/carrier/carrier_pulse_ring.tscn`, `carrier_brain.gd` (`_kill_ring`, `_tick_pulse`) | The precedent: an inherited ring scene authoring its own values, owner-ticked by a brain, rng gap start | same shape |
| `global/resources/attack/radial_attack_pattern.gd` | `fire(ship, pool)`: full ring when `arc >= TAU`, `base_angle` absolute (caller precesses) | the core ring is a runtime `RadialAttackPattern.new()` |
| `global/components/bullet_pool.gd` (`BulletPool`) | `acquire`, deferred `_recycle`, `cancel_active()`, `_warned_exhausted`; container = grandparent | `CoreRingPool` built in code |
| `assault/scenes/projectiles/enemy_bullet/rounds/enemy_rounds.gd` | `EnemyRounds.pool_size_for(burst, life, period)` | pool 72 |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` | `ProjectileLifetime` `max_time` 18, `max_distance` 2400 | core-ring life = min(18, 2400 / 210) = 11.43 s |
| `assault/scenes/enemies/base_enemy.gd` | `_physics_process`: suspended → return; EMP window → mover only; `apply_emp` → `brain.on_emp_started()` | the FADE tick runs when the brain does not |
| `tests/integration/test_fortress_weapons.gd` | t7 rows A1–A6; helpers `_world`, `_spawn`, `_watch`, `_expire` (direct `_recycle`), `_run`, `_tick_full`, `_ladder_to` | t16 appends rows 7–12; row 6's `attacks` literals change |
| `tests/integration/test_space_fortress.gd` | §25 row `test_each_phase_shows_its_declared_changes`, `BUILT_KEYS`, `_assert_declared_changes(..., unbuilt)` | add ARENA, drop the shields_exposed ATTACKS exemption |
| `tests/integration/test_enemy_bullet_lifetime.gd` | `_every_shipped_enemy_bullet_speed()` | add the fortress config's `core_ring_speed` |
| `tests/integration/test_energy_ring.gd` | `_real_player()`, `_victim()` (fixture enemy + circle hurtbox), `_player_r_p()` | helper shapes to copy |
| `tests/integration/test_station_gunnery.gd::test_the_ring_step_leaves_no_permanent_safe_lane` | the station's lane-coverage row | re-expressed for the fortress (row 9) |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `EnemyBeam` / `EnergyRing` | the whole weapon: timing, hits, drawing, hazard registration, owner-set exemption |
| `FortressBrain.begin_spin(0)` / `end_spin()` / `spin_direction()` | alternating volley spins (t6) |
| `RadialAttackPattern` | ring geometry with an absolute `base_angle` |
| `BulletPool` + `EnemyRounds.pool_size_for` | the pool and its sizing rule |
| `CarrierBrain._kill_ring()` | how a brain ends a ring (cancel; here the FADE is finished by the root's tick instead) |
| `test_fortress_weapons.gd` `_expire` / `_tick_full` | returning rounds to the pool at once; hand-ticking the full fortress |
| `test_energy_ring.gd` `_real_player` / `_victim` | real player and fixture victim with a hurtbox |
| `test_space_fortress.gd` `_scale_clock` / `_restore_clock` | the 8× real-physics clock |

## Conventions that constrain this
- Owner-ticked weapons only (no `Timer`, no `create_timer`); `tick()` is each beam's / ring's only clock.
- Inherited beam / ring scenes author every gated value in their own scene; gates read an instantiated node.
- Flat config; never write to a loaded resource; the `RadialAttackPattern` is `new()`-built.
- Single writer: the brain only requests motion; spins go through `begin_spin()` / `end_spin()`.
- Nothing fires outside `EnemyWorld.view_rect()` in Assault; weapons only while `is_engaged()`.
- Signals declare their arity; per-tick prints only behind `OS.is_stdout_verbose()`.
- Real-physics rows at 8×; rows in both harnesses; GUT allotment +3.0 s.
