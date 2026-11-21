# Context — t2: `EnemyModule` and `ModularHull` (Phase 10 of the enemy rework)

Epic plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.1, §2.2 (this task's sections; approved, revision 2).
No `2-research.md` exists for the epic; the plan carries its own research. This task needs no web research: it is a
framework built from code already in the repository.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/components/hurtbox_component.gd` | `HurtBox`: `area_entered` -> type filter (`accepted_damage_types`) -> absorber slot (`absorbs_hit`, emits `hit_absorbed`) -> `received_damage.emit(hb.damage)` | The module takes damage only through `received_damage`, after both filters, so a local `EnemyShield` covers it |
| `global/components/hitbox_component.gd` | `HitBox`: `damage`, `damage_type` (LASER / ROCKET / CONTACT) | Type filter input; the module caches its decision per HitBox instance id |
| `global/components/health_component.gd` | `Health`: `decrease`, `amount_changed(current_health: int)`; `_ready()` clamps current to max | `max_health` 0 must skip `Health` (a 0-max `Health` reads dead) |
| `global/components/armor_query.gd` | `ArmorQuery.deflects(area, hit_box)`: `deflects_hit` on the hurtbox's parent, else `is_armored()` | A player bullet / rocket asks the module (`HurtBox`'s parent) whether to fly on |
| `global/components/armor_plate.gd` | `ArmorPlate`: resolve-once per HitBox id, erased on `area_exited`; breaks and frees | The cache shape `EnemyModule` copies; the module differs: damage via `received_damage`, stays as wreckage, killing shot consumed |
| `global/components/defense_profile.gd` | `DefenseProfile.apply_to(hurt_box)` writes mask + `accepted_damage_types` | `EnemyModule._ready()` applies its own child profile (BaseEnemy applies only the root's, `base_enemy.gd:89-90`) |
| `global/components/enemy_shield.gd` | `EnemyShield.attach(hurt_box)`; host = hurtbox's parent; never absorbs while host `is_armored()` | A shield on a module hurtbox protects that part only; the module answers no `is_armored`, so it works under an armoured root |
| `global/components/hit_effect.gd`, `explosion_effect.gd` | Hit burst; death burst into an explicit container | Damage burst, white deflect ping, destruction burst into the host's parent |
| `global/components/state_light.gd` | `StateLight` (`set_state(OFF)`) | Optional `Light` child goes OFF on destruction |
| `assault/scenes/enemies/space_station/station_turret.gd` | A part that survives its death as wreckage: texture swap, hurtbox off deferred (monitoring, monitorable, shape), explosion re-homed to the station's parent, `destroyed` once | The precedent for "wreckage stays" |
| `assault/scenes/enemies/base_enemy.gd` | Host base: root `HurtBox`, `Health`, `HitFlashAnimationPlayer`, `_on_received_damage` virtual | The fixture host extends it and refuses root damage |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd` | `TurretMount.power_down()` (UNPOWERED for good) | `EnemyModule.attach_mount` / `mounts()`; destroy powers mounts down (rows are t3's) |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd` | Player mining beam: targets groups `enemies` + `asteroids` within 12 px of its line, direct `received_damage.emit`, writes heat tint on the target node's `modulate` | Gains group `enemy_parts`; wreck tint must live on the `Sprite` child |
| `global/ship_modules/plasma_nova_module.gd` | Nova: direct `received_damage.emit(50)` on every `enemies` node's `HurtBox`, map-wide | Gains group `enemy_parts` |
| `assault/scenes/projectiles/enemy_beams/energy_hit_scan.gd` | Enemy energy weapons' victim scan: groups player / allies / enemies / asteroids | **Unchanged**; a row pins that `EnemyBeam` / `EnergyRing` never reach parts |
| `assault/scenes/hazards/laser_ray/laser_ray.gd` | Level laser: `HitZone` mask 128 / 256 / 512, `received_damage.emit(9999)` on `area_entered` and every 0.1 s while IDLE | A lit ray kills an open part through `received_damage`; a locked one ignores it |
| `assault/scenes/projectiles/bullets/bullet.gd` | Consumed (`expired`) on the first non-deflected hit; `queue_free` deferred | Every hurtbox overlapped in that step still gets the hit (killing-shot ordering) |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd`, `warhead/warhead_missile.gd` | Player rockets (`HitBox.damage_type` ROCKET); same deflect query | The type-filter row (a rocket against the LASER-only part) |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `armor_plate.gd::_resolve` / `_on_hurt_box_area_exited` | The per-HitBox decision cache, stale-id sweep, erase on exit |
| `station_turret.gd::_destroy` | Deferred hurtbox close (monitoring, monitorable, shape `disabled`), explosion into the host's parent |
| `tests/helpers/fixture_enemy.tscn` | The minimum `BaseEnemy` scene shape (HurtBox, Health, HitFlashAnimationPlayer); the new fixture host copies it |
| `tests/integration/test_enemy_shield_hits.gd` | Real projectile launch helper (`_fire`), 8x clock, `_is_consumed`, signal counter |
| `tests/integration/test_ram_corvette.gd::BeamDriver` | Driving a real `BeamBehavior.tick()` from `_physics_process` (also used by `test_defense_turret.gd`, `test_station_incoming_damage_paths.gd`) |
| `tests/integration/test_level1_laser_columns.gd::_ray` | A `LaserRay` with `auto_start` false, `warn_duration` / `active_duration` 0, phases driven by hand (no `SceneTreeTimer`) |
| `tests/integration/test_energy_ring.gd`, `test_enemy_beams.gd` | Hand-ticked `EnergyRing` / `EnemyBeam` builders (`EnemyBeamScenes.ring_scene()`, `scene_for(kind)`, `setup`, `start`, `tick`) |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds for the both-harness rows |

## Conventions that constrain this

- Signals declared with their exact arity (`test_signal_emit_arity.gd` sweeps self-emits). Per-frame prints behind `OS.is_stdout_verbose()`.
- Parts live under a `Modules` `Node2D`, never as direct children of the enemy root (`test_enemy_hurtbox_geometry.gd`'s one-direct-child-HurtBox rule, the `Plates` / `Turrets` precedent).
- Every `.tscn` / `.gd` outside `addons/` must load, instantiate and compile with no engine error or warning (`test_project_load_integrity.gd`), so the fixture scene is covered by it.
- Every collision bit used in a scene must be named (`test_collision_layer_names.gd`): 512, 32, 64, 1024 are named.
- New scenes stay UID-less (never hand-type a `uid://`).
- Real-physics rows on the 8x clock (`_scale_clock` / `_restore_clock`), hand-ticked rows at 1/60, both harnesses for behaviour specs, `scripts/check-test-leaks.sh` after anything that awaits.
- Gate-time budget: this task's own files ≤ 2.0 s (escalate past 3.0 s), two-run mean before / after with `scripts/gate-time.sh`, row in `tests/README.md`.
- `enemy_mine.gd`'s self-reference leak: `ArmorPlate` / `StationTurret` name their own class in signal signatures leak-free, so `EnemyModule` may too; the leak check confirms it.
