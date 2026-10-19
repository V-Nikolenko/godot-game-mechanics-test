# Context — t17: Level 1 placement of the Missile Corvette and the Support Ship

Epic `cmufs7elw001pnm2xr3b6fteb` (Enemy rework phase 5), epic plan §2.18 (+ §2.9–2.13, §4.1, §4.3). This task's own
design is the epic plan's §2.18; this file only records what the code offers it.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_sections()`: deep_space (DURATION 30 s), asteroid_belt, station_assault, planet_approach (DURATION 110 s), cloud_descent (ENEMIES_CLEARED, 10 s net) | The new lines go into `_build_section_1()` / `_build_section_2()` |
| `tests/integration/test_level1_specialist_spawns.gd` | 50-row `EXPECTED` pin of sniper / ram / bomber, `_LEGACY_PEAK_SPECIALISTS` frozen (5 / 3 / 4), count gate `peak <= 2.5 x legacy` over `_ai_intervals()` with lives `engage + deferral + measured exit` (view grid) | Gains `EXPECTED_PH5`, the two new kinds in `_ai_lives()` (corridor-measured exits), the extra-corvette boundary, the spill-over row |
| `tests/integration/test_engagement_deadline.gd` | Per-entry ENEMIES_CLEARED deadline rows (`_deadline_rows`, `_add_to_last_wave`, `_section_has_scene`) | Gains "no ENEMIES_CLEARED section has a corvette / a support" + the rocket-term boundary |
| `tests/helpers/specialist_exit_probe.gd` | `worst_disengage(host, scene, phase, speeds, cap, start_set)`; `corridor_starts(corridor, world)` (1083 starts) | Measures both new exits, hand-ticked |
| `tests/integration/test_missile_corvette.gd` / `test_support_ship.gd` | t7–t15 specs; corvette brain exposes `phase`, `salvos_fired`, `budget`; support brain `is_supporting()`, `shield`, `ward`, `budget` | Attack-in-budget rows land here |
| `tests/integration/test_ram_corvette.gd` §t17 13 / `test_sniper.gd` / `test_bomber.gd` | Ph4 attack-in-budget rows: real `WaveManager`, real `ArenaCamera`, seeded brains from `child_entered_tree` | Template for the rows |
| `tests/integration/test_level1_specialist_exit.gd` / `test_level1_fighter_fire_density.gd` | 8x replays: `_scale_clock`, three idle frames before `load_section`, seeds by spawn index, restore in `after_each` | Template for the 8x slice replay |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Triggers waves strictly in list order; spawns at `cam.global_position + cam.offset + offset x 2`; no camera -> no spawn | Why `test_level_1_sequence.gd` (no camera) is unaffected |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `MissileCorvetteBrain` | `Phase.TELEGRAPH/SALVO/DISENGAGE`, `salvos_fired`, `budget.remaining()`, `attack_window()` (= 0.7 + 2 x 0.22 = 1.14 s), attack gate `remaining >= 1.19` |
| `SupportShipBrain` | `is_supporting()`, `shield` (`EnemyShield` named `ProjectedShield` on the ward), `ward`, `Phase.DISENGAGE`; no budget deferral |
| `EnemyRocketScenes.max_time_of(kind)` | Rocket lifetimes from the scenes (Dumb 4.0, Pursuit 6.0, Cluster 4.0, Warhead 7.0) — the deadline boundary's rocket term |
| `WaveBuilder.missile_corvette()` / `support_ship()`, consts `MISSILE_CORVETTE` / `SUPPORT_SHIP` | Spawn lines |
| `HurtBox.has_absorber()` | Proves the projected shield is attached |

## Conventions that constrain this
- Design-unit offsets (640 x 360), scaled x2 at runtime; never pre-multiply.
- `WaveManager` triggers in list order (the Ph3 "wave-order quirk"); a spawn's moment is its wave's effective
  trigger (running max) + delay. Adding entries into an existing wave changes no other wave's index or trigger.
- No existing row and no existing enemy config may change (task); a new row's trigger may move.
- Every gate must be able to fail (boundary rows). Real physics only at 8x, restored in `after_each`; seeds from
  spawn index; `scripts/check-test-leaks.sh` after anything that awaits; GUT delta <= 15.0 s.
