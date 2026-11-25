# Context — t11: retire the space station, migrate its tests to the Space Fortress

Epic plan §2.11 (docs/plans/cmug256so0031m52wbxomst72/3-plan.md) is the approved design; this file records what the code looks like at
`c84cc5d` so the plan below can name exact rows.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_station/` (space_station.gd/.tscn, config .gd/.tres, station_gunnery, station_laser_phase, station_reinforcements, station_turret .gd/.tscn, ENEMY.md, .uid sidecars) | The legacy mini-boss | Deleted whole. Nothing outside tests / wave_builder references it (level 1 spawns the fortress since t10). |
| `assault/assets/sprites/enemies/station_core.png`, `station_turret.png`, `station_turret_destroyed.png` (+ `.import`) | Station art | Referenced only by station files, `tests/helpers/fixture_modular_host.tscn` (turret / destroyed), `test_enemy_module.gd` (`WRECK_TEXTURE`), `test_entity_sprite_transparency.gd` (`STATION_CORE` / `STATION_TURRET`). All three deletable once those are re-pointed. |
| `assault/scenes/systems/wave_builder.gd:144,322` | `space_station()` / `SPACE_STATION` | Delete. No caller outside the station tests. |
| `global/boss/boss_death_sequence.gd` | Shared death spectacle (t4) | Still holds `var _station` and station comments; the death-sequence test reads `seq._station`. Rename to `_host`, re-word comments. |
| `assault/scenes/enemies/space_fortress/space_fortress.tscn` | Fortress: r 176 circle hull (body = hurtbox = contact shape), root layer 0 / mask 0, root HurtBox mask 1121; 9 parts under `Modules` (batteries r 22 at (±99, ±99) and (150, 0), hangar 36×56 at (−150, 0), generators r 26 at (0, ±120), core r 44); part HurtBox mask 1120; `DeathSequence.blast_spread_radius` 150 | Every re-pointed row targets it. |
| `space_fortress_config.tres` | `death_sequence_duration` 2.4, `death_blast_count` 10, `core_health` 1500, `battery_health` 260 | The death-sequence config pins. |
| `global/boss/shield_sector.gd` | A generator's death detaches its sector's bubbles in the same call | Lets the damage-path rows bare the south batteries with one `destroy()`. |
| `space_fortress.gd::homing_point(from)` | Nearest live vulnerable part | The homing-missile row steers through it. |

## Station test inventory (acceptance grep hits, by file)
Delete: `test_space_station.gd`, `test_station_laser_phase.gd`, `test_station_gunnery.gd`, `test_station_reinforcements.gd` (+ `.uid`).
Rename + re-point: `test_station_death_sequence.gd` → `test_boss_death_sequence.gd`; `test_station_incoming_damage_paths.gd` → `test_fortress_incoming_damage_paths.gd` (`git mv`, `.uid` follows).
Edit rows: `test_enemy_contact_damage.gd` (ROSTER entry), `test_contact_hitbox_geometry.gd` (ROSTER), `test_enemy_hurtbox_geometry.gd` (ROSTER, 88×240 boundary, core-spans-hull row), `test_entity_sprite_transparency.gd` (core corners + control), `test_config_instance_isolation.gd` (station-children row, `STATION_SCENE`), `test_spawn_camera_pan.gd` (2 rows), `test_explosion_effect_placement.gd` (turret row), `test_level1_drone_spawns.gd` (BOTTOM row), `test_base_enemy.gd` (turret-mask extra case, exclusion list, `_MIN_ROSTER_SIZE` 26 → 25, refuse-repair), `test_enemy_bullet_lifetime.gd` (speed sources + pins), `test_engagement_deadline.gd` (source scan), `test_enemy_module.gd` (`WRECK_TEXTURE`).
Comment-only: `base_enemy.gd`, `bullet.gd`, `enemy_module.gd`, `laser_ray.gd`, `arena_camera.gd`, `bullet_pool.gd`, `explosion_effect.gd`, `radial_attack_pattern.gd`, `level_1_director.gd`, `wave_builder.gd`, `boss_death_sequence.gd`, `space_fortress.gd` ("The station's death order"), tests `test_suite_integrity.gd`, `test_signal_emit_arity.gd`, `test_armor_query.gd`, `test_enemy_path_mover.gd`, `test_player_bullet_lifetime.gd`, `test_laser_ray_hit_mask.gd`, `test_station_assault_section.gd`, `tests/unit/test_explosion_effect.gd`, `test_score_tracker_escape_penalty.gd`, `tests/helpers/armored_fixture.gd`, `fixture_enemy_unrepairable.gd`, `test_gatling_interceptor.gd:217`, `test_fighter.gd:275`, `scripts/lib/strip_sprite_bg.gd`.

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/helpers/enemy_ai_harness.gd` | Open Space / Assault worlds for the re-pointed fortress rows |
| `test_space_fortress.gd` `_spawn` / `_scale_clock` / `BeamDriver` / `_reach` | Patterns copied into the re-pointed files (physics off, 8× clock, real beam driver, part reach) |
| `test_level1_fortress_section.gd`, `test_engagement_deadline.gd` fortress rows | Already cover the fortress in level 1 — nothing to add for section rows |

## Conventions that constrain this
Never touch `open_space/scenes/mission_*/space_stations/` (Fortuna). Never hand-type a `uid://`; `git mv` keeps `.uid` sidecars. Signals / single-writer / config-isolation gates must stay green. Real-physics rows at 8×. GUT time must not rise (record before / after).
