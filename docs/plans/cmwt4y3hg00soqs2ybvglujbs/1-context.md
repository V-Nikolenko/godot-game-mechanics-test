# Context — t5 Space Fortress shell (task cmwt4y3hg00soqs2ybvglujbs)

The design is the epic's approved plan: `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.5 (+ §2.1, §2.2, §2.14–§2.16). This file only records
what the code gives the task, read @ `f359dfa`.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/carrier/carrier.gd` / `.tscn` | Armoured-hull modular heavy (Ph10) | The template: `deflects_hit`/`is_armored` true, `_on_received_damage` → `armor_deflected` + flash, core `destroyed` → `health.set_health(0)`, `world_anchored_x`, `homing_point`, `rocket_clear_radius`, owner group, part nodes `Sprite`/`HurtBox`/`Light` under `Modules`, `ModularHull` sibling |
| `assault/scenes/enemies/space_station/space_station.gd` | Legacy mini-boss | The death latch (`_dying`), `Timer` child for `death_duration`, `_make_corpse_harmless()`, `_finish_death()`, `death_started` signal; stays untouched (t11 retires it) |
| `assault/scenes/enemies/base_enemy.gd` | Root of every enemy | `_init`/`_enter_tree` privatise config; `_ready` copies score/flags; `answers_emp()`/`apply_emp()`; `suspend_ai()`; `_physics_process` brain→mover |
| `global/components/enemy_module.gd`, `modular_hull.gd` | Parts and coordinator | Parts write their `Health` from the `max_health` export in their own `_ready()` (before the root's); `set_vulnerable` is a no-op on a wreck; `destroy()` sets light OFF / wreck texture or tint |
| `global/boss/boss_phase.gd`, `boss_phase_driver.gd` | Phase ladder (t1) | `bind(hull, health)` enters phase 0 synchronously; `phase_entered(index, id)`; `validate(hull)` |
| `global/boss/shield_sector.gd` | Sector bubbles (t15) | `ShieldSector.new(generator, protected, {capacity, regen_delay, regen_seconds, reboot_seconds, radius_pad})`; sets generator light SHIELDED |
| `global/boss/boss_reinforcements.gd`, `escort_container.gd` | Bays and escorts (t2) | `BossReinforcements.new(host, hull, driver, rng, owner_group, live_cap, boost_speed, boost_seconds)`; `tick(delta, active)`; `scuttle_all()`; `EscortContainer.of/ensure` |
| `global/boss/boss_death_sequence.gd` | Death spectacle (t4) | Host contract: `death_started` signal + `death_duration` var + optional `config.death_blast_count` (read in its `_ready`) |
| `global/ship_modules/emp_blast_module.gd`, `global/components/emp_pulse.gd` | EMP sources | Both ask `answers_emp()`; EMP Blast otherwise process-disables the node (the dying-wreck gap §2.5.6 closes) |
| `assault/scenes/systems/wave_builder.gd` | Spawn builders | add `space_fortress()` / `SPACE_FORTRESS` |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/integration/test_carrier.gd` | `_shoot()` real-bullet record (range-ended vs consumed), `BeamDriver`, `_nova()`, clock scaling, `_world(mode)` |
| `tests/helpers/enemy_ai_harness.gd` | Both harnesses |
| `tests/integration/test_config_instance_isolation.gd` `ConfigProbe` | Identity check from inside a child's `_ready()` |
| `tests/integration/test_boss_phase_rules.gd` | Sweep; t5 flips the expectation to "contains `space_fortress.tscn`" |
| station PNGs `assault/assets/sprites/enemies/station_core.png` (256²), `station_turret.png` (64²) | Placeholder art until t9 |

## Conventions that constrain this
Root layer 0 / mask 0; contact layer 256 mask 128; hurtbox 512 / 1121; part hurtbox mask written by `EnemyModule`. Flat config. Single writer (root/brain never write
velocity/rotation). Signals declare what they emit. No `Timer` in brains; the root's death `Timer` child is the station precedent. Never "station" in new names.
