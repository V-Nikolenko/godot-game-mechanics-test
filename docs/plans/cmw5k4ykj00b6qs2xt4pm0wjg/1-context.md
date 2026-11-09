# Context: t14, level 1 placement of a local jammer and a Hacker Frigate (epic cmug23onr001pm52w9swwophy, plan §2.17)

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_section_2()` = planet_approach (DURATION 110 s), `laser_column_schedule()` | The two new spawn lines go into existing planet_approach waves |
| `tests/integration/test_level1_specialist_spawns.gd` | Frozen 2.5x specialist gate (`_ai_intervals`, `_peak`), per-phase pins `EXPECTED_PH5/PH7/PH8`, `_ph8_intervals`, `_member_life`, `_column_conflicts`, spill-over rows | `EXPECTED_PH9`, `_ph9_intervals`, the lives / overlap row, column clearance extended to the jammer, a 96 s Hacker boundary |
| `tests/integration/test_engagement_deadline.gd` | ENEMIES_CLEARED guards; t7 / t8 already added "no jammer in ENEMIES_CLEARED", "no sector jammer in any section", "no Hacker in ENEMIES_CLEARED" | New guards: Disruptor, EMP zone (scene path), source scan of `assault/scenes/levels` for EMP zone / placed EMP mine / EMP-laying Minefield / sector jammer, wave-entry Minefield `w_emp` |
| `tests/helpers/level1_slice_replay.gd` | Replays a slice of a section through a real `WaveManager` with a player stub | Hacker PULSE-in-budget and jammer-locks-a-parked-player replays (16x) |
| `tests/helpers/ph9_exit_keys.gd` | `hacker_exit(host)` — the memoised Hacker corridor exit (worst 5.67 s) | Hacker life term; never hand-build the probe call |
| `tests/integration/test_level1_ph8_attacks.gd` | Ph8 attack-in-budget replays | Shape to copy for the new `test_level1_ph9_attacks.gd` |
| `assault/scenes/enemies/jamming_structure/` | Local jammer: r 28 body, field r 240, `AssaultDrift` 60 px/s, world-anchored x, frees below `projectile_world_rect().end.y` (1164) | Drift life and x clearance |
| `assault/scenes/enemies/hacker_frigate/` | Hacker: `engage_seconds` 9.0, `pulse_seconds` 1.6 (a PULSE at expiry finishes), `first_pulse_delay` 2.0 | Life = 9.0 + 1.6 + slack + exit |
| `assault/scenes/hazards/emp_zone/emp_zone.tscn`, `assault/scenes/hazards/minefield/minefield.tscn` (`w_emp` export), `assault/scenes/projectiles/enemy_ordnance/mines/emp_mine.tscn`, `assault/scenes/enemies/hacker_disruptor/hacker_disruptor.tscn` | The pieces the guards detect | Paths for the guards |
| `assault/scenes/levels/` | `level_2.tscn`, `level_2_waves.gd`, `race/race_level_1.tscn`, `edelia/1/*` | The source scan's file set |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `test_level1_specialist_spawns.gd::_member_life()` formula | Worst drift life of a static from its design y (highest view centre, shake included) — reused for the jammer |
| `_column_conflicts()` | Column clearance (no end filter, wall row for the first section) — extended with Ph9 statics |
| `_ph8_intervals()` pattern | Per-ship intervals appended in `_ai_intervals()` |
| `test_engagement_deadline.gd::_section_has_scene`, `_add_to_last_wave`, `_cloud_descent` | Guard and boundary shape |
| `test_level1_ph8_attacks.gd` clock helpers, `Slice.placed()`, `Slice.slice_waves()`, `Slice.run()` | Replay rows |
| `test_player_ability_lock.gd` | `_step_disruption(1/60)` hand-steps a real ship's lock; `abilities_locked()` |

## Conventions that constrain this
- Design units 640x360, x2 at runtime; world x of a world-anchored static = 640 + 2 * design x.
- Spawn moment = the wave's EFFECTIVE trigger (running max in list order) + delay.
- Frozen constants never raised; never retune the enemies for the level; never deep_space.
- Probe calls only through `ph9_exit_keys.gd`. Replays at 16x, clock restored in `after_each`. `scripts/check-test-leaks.sh` after anything that awaits.
- Gate time allotment 2.5 s.
