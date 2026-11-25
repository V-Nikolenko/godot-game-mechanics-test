# Context — t7: Carrier weapons, the anti-approach pulse and PANIC

Epic `cmug23oo90029m52wae4clve0` (Phase 10), plan §2.7 (with §2.6, §2.8 emergency-deployment hook, §2.9 lights, §2.16 numbers).
Builds on t6 (`docs/plans/cmwafsrb700afqs2yd3qqvvrb/`), t3 (`TurretMountBuilder`, traverse limits, `HEAVY_CANNON`) and Ph8 (`EnergyRing`).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/carrier/carrier.gd` | Armoured hull root; owner group `carrier_<id>`; `bind_hull()` to the brain; `launch_velocity()` / `rocket_clear_radius()` already answered | t7 builds the mounts here (module slots, then `HullMounts/*`), sets up the ring, cancels it on `died` |
| `assault/scenes/enemies/carrier/carrier_brain.gd` | Phases CRUISE/SCREEN/PANIC/CROSS/IDLE/NOTICING/RETURNING; movement only; `SWAY_ARC_HALF_DEG` 75 says "t7 reads it from the battery slot" | t7 adds mount ticking, the ring clock, PANIC effects, lights, EMP / suspend handling |
| `assault/scenes/enemies/carrier/carrier_config.gd/.tres` | Flat config | gains a `Weapons` group (pulse, missile, panic factors) |
| `assault/scenes/enemies/carrier/carrier.tscn` | Has empty `Modules/GunPort/MountSlots`, `Modules/GunStarboard/MountSlots`, empty `HullMounts`; StateLight at root; no Core light | t7 authors slots, `HullMounts/Bow` / `Dorsal`, the `PulseRing` child and a Core `Light` |
| `global/components/modular_hull.gd` | `build_mounts(host, rng, owner_group, gate, first_index) -> int`, `mounts_of(id)`, `modules()` | used as is (no change) |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd` | `tick(delta, target, can_fire)`, `scan()`, `power_down()`, `round_fired`, `phase()`, `cooldown_seconds`, traverse logic (`_target_in_arc` → never fires outside its arc) | the one-side-safe rule rests on the 150° traverse; bow arc on the 70° traverse |
| `.../mounts/turret_mount_builder.gd` | static `build(host, slot, index, rng, owner_group, gate)` | hull slots built with the index `build_mounts()` returns |
| `.../mounts/heavy_cannon_mount.tscn` | BurstCannonMount + Heavy Shell, traverse 70 | the bow cannon |
| `.../mounts/rocket_battery_mount.gd/.tscn` | DUMB/PURSUIT salvo, `pursuit_chance` 1/3, `cooldown_seconds` 5.5, `fires_past_cover()` true, persistent pools | the missile bank (needs PURSUIT only, cooldown 7.0) |
| `assault/scenes/projectiles/enemy_beams/energy_ring.gd/.tscn` | Owner-ticked ring: `setup/start/tick/cancel`, `phase()`, `target_hit`; hits via `EnergyHitScan` (groups player/allies/enemies/asteroids, host + owner group exempt) | `carrier_pulse_ring.tscn` inherits it |
| `assault/scenes/projectiles/enemy_beams/energy_hit_scan.gd` | Victim groups; never `enemy_parts` | the ring therefore never reaches a module (unchanged) |
| `assault/scenes/enemies/base_enemy.gd` | brain not ticked during EMP; `on_emp_started()` once; `suspend_ai()` → `on_suspended()`; `died` | the ring must not freeze mid-shot during an EMP or a rail |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship_brain.gd` | `_tick_weapons`: `can_fire = in_view and (sees or fires_past_cover())`, LOS only in physics frame; EMP → `scan(0.0)` every mount, light OFF; light CHARGING/ARMED from mount phases | the precedent t7 copies |
| `tests/integration/test_carrier.gd` | t6 rows; helpers `_world`, `_spawn`, `_tick`, `_part`, `_brain`, `_count` | t7 appends a `§weapons` section |
| `tests/integration/test_energy_ring.gd` | `_victim()` (fixture_enemy + 14 px circle + group enemies), `_player_r_p()`, fairness predicates | reused patterns for the ring rows |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `ModularHull.build_mounts()` + `TurretMountBuilder.build()` | every mount and pool; running pool index |
| `TurretMount.traverse_deg` / `TurretMountSlot.traverse_deg_override` | the arc limits (one side safe, bow 70°) — no new arc code |
| `EnergyRing` | the whole pulse; `carrier_pulse_ring.tscn` is an inherited scene with exports only |
| `HeavyGunshipBrain._tick_weapons` / `on_emp_started` / `_update_light` | can_fire rule, view gate, EMP cancel, light vocabulary |
| `tests/helpers/fixture_enemy.tscn` | the outside-enemy / launched-child ring victims |
| `StateLight` | hull light and the core's light |

## Conventions that constrain this
- Brain requests only; mounts write only their own rotation; mover single writer (gate `test_enemy_mover_single_writer.gd`).
- Owner-ticked weapons: the ring's `tick()` is its only clock (no Timer / `_process`).
- Flat config (`test_config_instance_isolation.gd`); weapon tuning in mount / ring scene exports; host-specific numbers (missile cooldown, min range, pulse trigger) in the config, as plan §2.7 lists them.
- Signals declared with their arity; per-frame prints behind `OS.is_stdout_verbose()`.
- No hand-typed `uid://`; the new `.tscn` is UID-less.
- Tests: hand-ticked at 1/60 in both harnesses; gate-time allotment 1.8 s for t7's own rows.
- carrier files t6 → t7 → t8: t8 (hangars) fills the emergency-deployment hook t7 leaves.
