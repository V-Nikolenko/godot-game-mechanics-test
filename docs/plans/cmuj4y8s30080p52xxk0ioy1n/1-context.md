# Context

The epic plan (`docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.10 step 2, §2.6, §5 C3) is approved and
already specifies this task; this file only records where the pieces are.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_sections()` authors every wave via `WaveBuilder` | 119 `b.drone()` lines carry `.move(...)`, two also `.free_after(5.0)` (cloud_descent 5.0 / 14.0 side drones) |
| `assault/scenes/systems/wave_builder.gd` | `SpawnConfig.squad(id)` exists (t5) | the loose-wave grouping |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | squad key `"<wave>:<id or spawn index>"`, weak board map | formations are already one squad each; loose entries without an id are squads of one |
| `tests/integration/test_level1_drone_spawns.gd` | t1 pin (121 rows, `movement: true` for drones) | rewritten to `movement: false` |
| `tests/helpers/level1_drone_concurrency.gd` | `spawn_times()` / `peak_concurrency()` | extended with squad-aware, per-spawn-lifetime intervals for C3 |
| `tests/integration/test_engagement_deadline.gd` | §2.6 formula test | unchanged; the exit case below is its integration twin |
| `tests/helpers/enemy_ai_harness.gd` | player stub + ArenaCamera | pattern for the new exit test |
| `swarm_drone_config.tres` | `engage_seconds` 5.5, `rear_engage_seconds` 5.5, `exit_speed` 320, `acceleration` 600 | lifetime numbers for C3 |
| `razor_drone_config.tres` | `engage_seconds` 9.0 etc. | Razor lifetime for C3 |
| `station_reinforcements.gd` | BOTTOM squad on rails | untouched (stays on rails) |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `DroneConcurrency.spawn_times` | slot-expanded spawn times, same arithmetic as WaveManager |
| `test_engagement_deadline.gd::_swarm_deadline/_razor_deadline` shapes | worst-exit formulas |
| `test_spawn_camera_pan.gd` | WaveManager + current camera + container setup |

## Conventions that constrain this
- Design units in wave data, never pre-multiplied.
- Tests: no `create_timer` in helpers; `check-test-leaks.sh` after anything that awaits (WaveManager's own
  `_spawn_with_delay` awaits a SceneTreeTimer, so the exit test must let every delayed spawn land before it ends).
- Bonus Drone schedule (`_section_schedules` / `_spawn_bonus_drone`) must not change.
