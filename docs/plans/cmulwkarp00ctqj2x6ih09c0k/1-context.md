# Context — t17, cloud_descent off rails

Epic plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.9.3 (Revision 2, approved; review note N5 binds the
boundary rows). Direct precedent: t16, `docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md` (Revision 2, owner option A),
and its as-built note in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` ("Phase 3, t16 … built with the owner's
option A"), which says: "t17 should reuse all of these, including the measured gate for cloud_descent (legacy 15.0)".

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` `_build_section_3()` | cloud_descent's 24 waves | Its 27 fighter lines (9 waves) are the edit |
| `tests/integration/test_level1_fighter_spawns.gd` | The t1 pin, frozen `_LEGACY_PEAK_FIGHTERS` (cloud_descent **8**) / `_LEGACY_PEAK_SHOTS_PER_S` (**15.0**), `_RAIL_SECTIONS = [cloud_descent]`, `MIGRATED_SECTIONS`, count gates | 27 rows → AI rows; retire the live==constant check; add cloud_descent to the gates |
| `tests/integration/test_level1_fighter_fire_density.gd` | Measured shots/s gate (owner option A) per section | Gains a cloud_descent case |
| `tests/integration/test_engagement_deadline.gd` | Ph2 drone/Razor deadline over ENEMIES_CLEARED sections | Gains per-entry fighter rows + boundary rows |
| `tests/integration/test_level1_drone_exit.gd` | Ph2 real-run exit test (last wave, stub player, 1×) | The shape for the new `test_level1_fighter_exit.gd` |
| `tests/helpers/level1_drone_concurrency.gd` | `squad_key`, `shooter_squad_intervals`, `ai_shooter_kinds`, `worst_exit_after_speed`, `peak_window_rate` … | Reused, nothing new expected |
| `assault/scenes/enemies/fighter/fighter_brain.gd` | `budget` started in `_start()` (`:401`), expiry deferred to the end of a running burst (`:1395`, "≤ 0.8 s"), `run_budget_slack()` stops a run that cannot finish | The deadline formula's `deferral` term is exactly this |
| `assault/scenes/systems/level_director/level_director.gd:167` | ENEMIES_CLEARED clock = `enemies_cleared_timeout` from `waves_complete` | 10 s for cloud_descent, 180 s for station_assault |

## Data (read from the code, 2026-10-06)
- ENEMIES_CLEARED sections: `station_assault` (180 s, one wave: the space station; no fighter/Gatling entries) and
  `cloud_descent` (default 10 s).
- cloud_descent fighter waves (raw_waves index → trigger): 2→5.0 (3 loose), 5→14.0 (3 loose), 8→26.0 (2 loose),
  12→38.0 (2 loose fighters + a ram), 13→42.0 (6 loose), 15→50.0 (3 loose + gunship + 2 rams), 18→59.0 (wedge 3),
  20→66.0 (2 loose), 22→72.0 (4 loose + V3 at delay 0.5 + ram). 27 lines. Last wave: 23→76.0 (5 drones, max delay 0.8).
- Existing drone squad tags in that section: `w1 w7 w14 w17 w19 w21 w23` — confirm the `w<raw_waves index>` convention.
- `FighterConfig`: engage 6.0, burst_telegraph 0.3, aimed 5 × 0.1, forward 7 × 0.05, max_speed 300, exit_speed 520,
  acceleration 700, braking 700 → deferral 0.8, worst exit 2.841 (exit_distance 804) → 10.14 s after entry incl. 0.5 margin.
- `GatlingInterceptorConfig`: engage 7.0, spin_up 0.25, sync_wait_max 0.75, 12 × 0.09, max_speed 260, exit 520, accel 600,
  braking 900 → deferral 2.08, worst exit 2.918 → 12.50 s incl. margin.
- `test_level_1_sequence.gd` runs all five real sections compressed (no camera, no player) and requires the container
  empty at the end; it already passes with AI drones (Ph2) and AI fighters in deep_space / planet_approach (t16).

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `DroneConcurrency.ai_shooter_kinds()` | Fighter lifetime / deferral / exit from config — the deadline rows use the same terms |
| `DroneConcurrency.worst_exit_after_speed()` | Razor-shaped exit (already used by `_razor_deadline`) |
| `DroneConcurrency.shooter_squad_intervals()` / `peak_intervals()` | The count gates |
| `test_level1_fighter_fire_density.gd::_assert_measured_gate()` | The measured shots/s gate + DISENGAGE / no-EnemyPathMover exit checks, per section name |
| `test_level1_drone_exit.gd` | Harness (`enemy_ai_harness.gd` assault), container, WaveManager, `_recording` flag, `_MIN_RUN_SECONDS` leak guard, rail boundary |

## Conventions that constrain this
- Design units in the level (640×360, ×2 at runtime); only `.move()`, `.free_after()`, `shoot_*()` are stripped.
- Loose fighter lines sharing a wave get `squad(&"w<n>f")` (n = raw_waves index); lone loose lines stay untagged.
- Signal arity on every handler; `_recording` guard; every spawn timer must fire before a test returns
  (`scripts/check-test-leaks.sh`).
- Frozen legacy constants are never edited, only divided by.
