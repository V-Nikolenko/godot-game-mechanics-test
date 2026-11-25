# Context — t5: Heavy Gunship phases, vent, emergency, rear missiles, cannon shield

Task plan directory for Phase 10 t5 (epic plan `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.5, §2.9, §2.16; epic review
`docs/plans/cmug23oo90029m52wae4clve0/4-review.md` findings N1 (cannon-shield flank row), 3 (rockets in Assault), 11 (VENT keeps a burst), 15
(own rockets)). Built on t2 (`EnemyModule` / `ModularHull`), t3 (mounts, builder, traverse, `HEAVY_CANNON`) and t4 (the shell, movement, budget).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/heavy_gunship/heavy_gunship_brain.gd` | `HeavyGunshipBrain`: APPROACH / BROADSIDE / BREAK_AWAY, hub idle, DISENGAGE fast path; VENT / EMERGENCY are stubs that fall back to BROADSIDE; `_tick_weapons()` passes `can_fire` false to the Missiles mount | t5 fills VENT / EMERGENCY, hull phases, heat, the missiles' window and gate, part lights, the shield facing |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship.gd` | `HeavyGunship`: config apply, `build_mounts`, `homing_point`, launcher answers | attaches and configures the cannon shield, frees it with the cannon |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn` | hull 112 × 144, six edge-flush parts, `StateLight` | gains `Modules/Cannon/Shield` (`EnemyShield`) and a `Light` (`StateLight`) per part; no shape / position / `HomingPoint` changes |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship_config.gd` / `.tres` | flat config; header says the Phases / Defense groups arrive with t5 | the new fields |
| `global/components/enemy_module.gd` | part: `set_vulnerable`, `deflected`, `damaged`, `destroy()` turns its `Light` OFF | vents are opened / closed through it; untouched |
| `global/components/modular_hull.gd` | `hull_share` forwarding to the host `Health`, `module_destroyed` | an open vent doubles a hit through it; untouched |
| `global/components/enemy_shield.gd` | arc decided by the bearing from the **host part's centre** to `hit_box.global_position`; `face()` snaps; `is_armored()` on the host switches it off | the cannon shield; untouched |
| `global/components/state_light.gd` | `enum State { OFF, ARMED, CHARGING, COMMIT }` | needs an appended orange `VENTING` (§2.9 "orange venting") |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd` | cycle; `is_committed()` false in the base (the lance's COMMIT light); `telegraph_gate` public | VENT can_fire rule; the missiles' own gate |
| `.../mounts/burst_cannon_mount.gd` | losing `can_fire` stops a burst (`_fire_tick`); `FIRE -> COOLDOWN` only through `_end_fire` | "a burst ends" = a gun mount entering COOLDOWN |
| `.../mounts/rocket_battery_mount.gd` / `.tscn` | charge 0.5, salvo 2 × 0.35, cooldown 5.5; DUMB / PURSUIT pools of **2 each**, `persist: true` | the rear missiles; tiny pools matter for hand-ticked rows |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` | HitBox mask 128 / 512, armed only `rocket_clear_radius() + body_radius + arm_clearance` from the launcher's current position; `_tick(delta)` is hand-tickable | own-rocket self-hit check; possible launcher exemption |
| `global/components/bullet_pool.gd` | `expired` -> `call_deferred("_recycle")` | a synchronous hand-ticked loop never recycles: it must yield a frame after a rocket expires |
| `assault/scenes/projectiles/bullets/bullet.gd` | stops on the first damaging hit; `unlimited_pierce` (the Sniper Shot) passes every regular enemy | the only player round that reaches the cannon from the flank |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd`, `global/ship_modules/plasma_nova_module.gd` | direct emitters; the beam burns targets whose centre is within 12 px of its line | the closed-vent rows |
| `tests/integration/test_heavy_gunship.gd` | t4's 26 rows; `_spawn` / `_tick` / `_fire` / `_until_spent` / 16× clock helpers | t5's rows join it |
| `tests/unit/test_state_light.gd` | StateLight unit rows | one row for `VENTING` |
| `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`, `tests/README.md` (gate table) | append-only | t5 notes, gate row |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `HeavyGunshipBrain._arc_motion()` / `_face_broadside()` / `desired_nose()` | VENT and EMERGENCY movement and facing (only the held range and the speed cap change) |
| `HeavyGunshipBrain.attack_gate_open()` / `ATTACK_GATE_MARGIN` | the pattern for the missiles' window / budget gate |
| `Steering.break_contact(..., -orbit_dir, ...)` | the emergency boost direction (BREAK_AWAY's) |
| `EnemyModule.set_vulnerable()` / `deflected` / `destroy()` (light OFF) | vents open / closed, pings, dark wrecks |
| `ModularHull.module(id)` / `mounts_of(id)` / `module_destroyed` | part lookups; freeing the shield with the cannon |
| `EnemyShield` (`attach`, `face`, `facing`, `points`, `absorbed`) | the cannon shield, exports written from config |
| `StateLight` | hull and part lights |
| `test_enemy_module.gd`'s `BeamDriver` / nova idiom, `LASER_MODE` | beam / nova rows (the beam called hand-ticked through `BeamBehavior.tick()`) |
| `test_heavy_gunship.gd` helpers (`_world`, `_spawn`, `_tick`, `_fire`, `_until_spent`, `_scale_clock`) | every new row |
| `tests/README.md` → Gate time rule 2 | hand-ticked scenarios computed once and shared by several tests |

## Conventions that constrain this
- Brain ticks on physics through `BaseEnemy._physics_process`; only the mover writes motion; the brain may write mover limits (`max_speed`), committed moves are
  `mover.boost()`; randomness only from `brain.rng`. Signals declared with arity. Per-frame prints behind `OS.is_stdout_verbose()`.
- `set_vulnerable()` changed inside a physics callback must be deferred (the Ram `_expose` rule): the brain only changes it from `tick()`.
- Hull art nose-down: nose = local +y, port = local +x. Flush-edge geometry is frozen (t9 may not move it either).
- Flat config, `@export_group`; weapon tuning in mount scenes. One `*config*.tres` per enemy directory.
- DISENGAGE stays a fast path at the top of `tick()` and the probe (`ph10_exit_keys.gd`, Modules stripped) must stay bit-identical.
- Tests: GUT, both harnesses, hand-ticked at 1/60, projectile rows on real physics at the scaled clock (this file uses 16×, rule 1); scenarios shared
  through memo (rule 2); `scripts/check-test-leaks.sh` after anything that awaits. Gate allotment 2.5 s (escalate past 3.75 s for the task's files or a
  237 s two-run mean). Never hand-type a `uid://`.
