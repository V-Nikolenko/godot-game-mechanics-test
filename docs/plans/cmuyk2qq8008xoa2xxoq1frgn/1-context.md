# Context — t16 Ram Corvette armour (task `cmuyk2qq8008xoa2xxoq1frgn`)

Epic `cmufs7ele0015nm2xvag3vrwc` (Enemy rework phase 4). Approved epic plan:
`docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.6.1, §2.6.3, §2.7 (ram row), §4 t16 row.
This file records only what the code says today (HEAD `1e7c9e0`); it does not repeat the epic plan.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/ram_corvette/ram_corvette.gd` | Legacy `RamCorvette`: own `_physics_process` (straight down, frees below camera), group `ram_ships`, first hit → `_enter_damaged_state()` (swap to `ram_ship_damaged.png`, `defense_profile.apply_alternate()` 33→97, HP reset 100), `is_laser_blocking()` = not damaged | Rewritten. |
| `assault/scenes/enemies/ram_corvette/ram_corvette.tscn` | `AnimatedSprite2D` (ram_ship.png 32×32, flipped 180° by `BaseEnemy._rotate_sprite`), body `CircleShape2D` r 36 shared by `HurtBox` (mask 33 via scene `DefenseProfile`) and `ContactHitBox` (20 → 50 from config), `HitFlashAnimationPlayer` tracks `AnimatedSprite2D:material` | Rebuilt. Root body is layer 1 (default) — that is what makes it a beam blocker. |
| `ram_corvette_config.gd/.tres` | `movement_speed` 100, HP 999, contact 50, score 35 | New flat fields. |
| `global/components/armor_plate.gd` | `ArmorPlate` (t4): authored-or-built `HurtBox` (512 / 96, empty accepted types), `Health`, `Sprite`; idempotent per-HitBox `_resolve`; `broken(plate)`, `deflected(hit_box)`, `is_alive`, `set_glow`, `deflects_hit`; break = close hurtbox deferred, hide sprite, explosion into the entity's parent, `queue_free` | Three instances under `Plates`. |
| `global/components/armor_query.gd` | `ArmorQuery.deflects(area, hb)`: `deflects_hit` first, then `is_armored()` | The hull answers `deflects_hit` → `is_armored()`. |
| `global/components/contact_profile.gd` | `Mode.ARMOR` (t5), armed at `setup()`, `shove_speed` export, never detonates | Authored in the scene. |
| `assault/scenes/projectiles/bullets/bullet.gd` | `unlimited_pierce` branch stops on `asteroids` **or `ram_ships`** for 0 | Drop the `ram_ships` half (X4). |
| `assault/scenes/projectiles/missiles/{homing,warhead}/*.gd` | Rockets; homing steers at `homing_point(from)` when present; both ask `ArmorQuery` | Unchanged; exercised for real. |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` | `RocketState._launch_warhead()` (3 rockets, offsets (±16, 26), (0, 36), fly `UP.rotated(actor.rotation)`), `_launch_homing()` (3 rockets 7 px apart, lock round-robin on group `enemies` sorted by distance) | The real volleys. `_ready()` connects `movement_controller.action_single_press`; `@onready $CooldownTimer`. |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd` | Ray on bodies, mask `1 | 1024`; a collider with `is_laser_blocking() == true` truncates the beam and is skipped; targets are groups `enemies` + `asteroids`, damage by direct `received_damage.emit` | Ram blocks while armoured; once exposed and in `enemies` it is burnt. |
| `global/ship_modules/engine_boost_module.gd` | Direct `received_damage.emit(45)` on group `enemies` within 32 px; `_IMMUNE_CLASSES` contains `RamCorvette` | Remove `RamCorvette` (hull rule deflects instead). |
| `global/ship_modules/emp_blast_module.gd` | Stuns group `enemies`; `_IMMUNE_CLASSES` contains `RamCorvette` | Unchanged — EMP keeps skipping it. |
| `assault/scenes/enemies/space_station/space_station.gd` | The precedent: `is_armored()`, `armor_deflected(damage: int)`, `_on_received_damage` deflect + flash | Pattern copied. |
| `assault/scenes/enemies/bomber/bomber_brain.gd` | t9 shell brain: phase enum + `enter_phase` seam, APPROACH plain intercept, `EngagementBudget`, DISENGAGE nearest-edge exit | Template for the minimal `RamCorvetteBrain`. |
| `assault/scenes/enemies/enemy_path_mover.gd` | Rail: switches the actor's physics off, calls `suspend_ai()`, frees off-screen | All 23 level-1 rams are on rails (`.move(b.straight(...))`); unchanged play there. |
| `tests/integration/test_ram_corvette.gd` | Legacy intent tests (mask 33, first hit arms, HP 999, both modules immune) | Replaced by the t16 rows. |
| `tests/integration/test_base_enemy.gd` | Ram mask constants + 3 ram cases, ram in generic-flow exclusion, ram in flip list, `_AUTHORED_CONTACT_MODES` | Edited deliberately (task text). Note its rule: never statically reference `RamCorvette` there (leak at exit). |
| `tests/unit/test_defense_profile.gd` | `test_scene_authored_profile_is_not_duplicated_by_base_enemy` loads `ram_corvette.tscn` (the only scene-authored `DefenseProfile`) | Moves to a fixture scene (X2). |
| `tests/integration/test_station_reinforcements.gd` case 16 + `station_reinforcements.gd` comment | Comment says the ram narrows its mask to 33 | Comment-only update. |
| `tests/integration/test_player_bullet_lifetime.gd` | Consumption rules; `test_an_unlimited_pierce_bullet_is_stopped_by_an_asteroid_for_zero_damage` header mentions ram-ship | Gains plate rows. |
| `tests/integration/test_enemy_dual_mode.gd` | Dual harness spawn/tick helpers per enemy | Gains a Corvette APPROACH/DISENGAGE pair. |
| Gates: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` (exactly one direct-child HurtBox, covers body), `test_config_instance_isolation.gd` (flat config), `test_enemy_mover_single_writer.gd`, `test_signal_emit_arity.gd`, `test_entity_sprite_transparency.gd`, UID / project-load integrity, collision layer names | Must stay green. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `tests/integration/test_armor_query.gd` | `_count(sig)` signal counter (GUT watchers crash on a freed plate), real-projectile spawn helpers |
| `tests/integration/test_station_incoming_damage_paths.gd` | `BeamDriver` (real `BeamBehavior.tick` from `_physics_process`), `mining_laser.tres` mode |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a fake player |
| `BomberBrain` | Budget + DISENGAGE code to mirror |
| `SpaceStation._on_received_damage` | Deflect + `armor_deflected` + flash |

## Conventions that constrain this

- Brain requests only; `EnemyMover` is the single writer (empty allowlist gate).
- Config flat (shallow `duplicate()` complete); `.tres` wins, applied in `_apply_config` after the brain's `_ready()`.
- Signals declared with their emitted arity.
- No hand-typed `uid://`; new ext_resources stay UID-less.
- Hurtbox covers body within 1 px; contact box shares body shape SubResource and scale; plates never direct root children.
- Art placeholder only (t18 draws the art); no texture > 90 % opaque.
