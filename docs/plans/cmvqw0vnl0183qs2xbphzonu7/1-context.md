# Context — t9 turret groups and the power source

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t9. Builds epic plan §2.10.1–§2.10.4 and §2.19 (approved; handed out in the task prompt).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/defense_turret/defense_turret.gd` | Turret root: `variant`, `set_turret_group(group)` (before `add_child`, reads `owner_group` duck-typed), `set_powered(false)` (latched), `_build_mounts()` | The group's members; the stagger gate binds here |
| `.../defense_turret/mounts/turret_mount.gd` | Mount cycle; `var telegraph_gate: Callable` asked last on TRACK -> TELEGRAPH, a refusal retries next tick; `fire_range`; `power_down()` | Stagger seam (t6 built it for this task); coverage reads the reach |
| `.../mounts/pulse_ring_mount.gd` | `trigger_range` 300; `ring()`; ring exempts the owner group | Coverage reach of a ring mount; friendly-fire row |
| `.../mounts/beam_turret_mount.gd` | `beam()`; TELEGRAPH / ACTIVE beams; power-down cancels / fades | Shutdown row (R8.24) |
| `.../mounts/turret_mount_scenes.gd` | `scene_for(variant)`, `export_of(...)` | Add `reach_of(variant)` |
| `assault/scenes/enemies/defense_turret/defense_turret_brain.gd` | `Phase.UNPOWERED`, `power_down()` light OFF; Assault perception = inside `view_rect()` | Shutdown rows read it |
| `global/components/assault_drift.gd` | `AssaultDrift` (60 px/s in Assault, frees below the projectile world rect) | PowerSource child |
| `assault/scenes/enemies/base_enemy.gd` | `died` emitted synchronously inside `_on_health_changed` before `queue_free()` | "Same call" shutdown hangs off `died` |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | `_spawn_ship`: `global_position = cam.global_position + cam.offset + offset*2`, props before `add_child`, emits `enemy_spawned` | A wave spawns the preset scene like any entity |
| `assault/scenes/systems/wave_builder.gd` | `SpawnConfig`, scene path consts | `TURRET_GROUP_ASSAULT_PAIR`, `turret_group(path)` |
| `assault/scenes/systems/arena_camera.gd` | `enemy_view_rect()` centre = `global_position + offset`; `projectile_world_rect()` centre = pinned (640, 360) | World-anchor arithmetic, through `EnemyWorld` only |
| `global/enemy_ai/enemy_world.gd` | `arena()`, `view_rect()`, `projectile_world_rect()` | Only path the group may use |
| `assault/scenes/systems/score_tracker/score_tracker.gd` | Orphans via `EventBus.enemy_spawned_orphan`; a wave spawn with no `died` signal is never scored; `counts_as_escape` false skips the penalty | Group not scored; members scored |
| `global/components/bullet_pool.gd` | `_container = get_parent().get_parent()`, `acquire()`, `_active` | Members' pools resolve to the container |
| `assault/scenes/hazards/minefield/minefield.gd` | Coordinator that frees itself after its last member | Precedent for the self-free |
| Roster gates: `tests/integration/test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`, `test_wreck.gd` (`_SHIP_SCENES`), `test_base_enemy.gd` (`_MIN_ROSTER_SIZE` 14, `_AUTHORED_CONTACT_MODES`), `test_enemy_dual_mode.gd` | Hand rosters + sweeps | `power_source.tscn` joins each |
| `tests/integration/test_engagement_deadline.gd` | `_section_has_scene()` guard rows | "no ENEMIES_CLEARED section spawns a turret group" |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()`; the Assault one adds an `ArenaCamera` at (640, 360) whose `offset` a row can set |
| `tests/integration/test_defense_turret.gd` | Hand-tick idiom (`t._physics_process(DT)` with physics + drift off), `_victim()` fixture enemy with a 14 px hurtbox, beam hit logs |
| `tests/integration/test_bomber.gd` (~l. 800) | Real `WaveManager` in the Assault harness with a container |
| `DefenseTurret.set_turret_group`, `TurretMount.telegraph_gate` | Built in t6 for exactly this task |
| `EnemyRing.in_gap(bearing)`, `radius()` | Non-vacuous friendly-fire check |
| `defense_turret.tscn` | Template for `power_source.tscn` (shared circle, HurtBox 512/65, ContactProfile NONE, AssaultDrift, no ContactHitBox) |

## Conventions that constrain this
- Design-unit coordinates ×2 at spawn; the world anchor removes only the camera's horizontal pan, via `EnemyWorld`, never `ArenaCamera`.
- Config-driven: flat `PowerSourceConfig extends ShipConfig`, `.tres` wins, private copy (`BaseEnemy._init`/`_enter_tree`), one `*config*.tres` per dir.
- Signals declared with arity; per-frame prints behind `OS.is_stdout_verbose()`; never hand-type a `uid://`.
- Deferred attach for anything a wave may spawn inside a physics flush.
- Tests first; both harnesses; hand-ticked rows, `_Ticker` not lambdas on `physics_frame`; leak check after awaits; GUT allotment 1.2 s (before: 203.73 s).
