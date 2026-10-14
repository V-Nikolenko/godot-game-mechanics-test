# Context — t21: level 1 deep_space / planet_approach specialists off rails

Epic plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.9.2, §2.9.4, §4 row
`test_level1_specialist_spawns.gd`. Epic review findings that touch this task: **N4** (lever 4's ram floor is
`worst spawn-to-LINE_UP + line_up_cap`, not `spawn-to-WIND_UP + 0.25`; t17 restated it as
`worst spawn-to-LINE_UP + line_up_cap + ATTACK_GATE_MARGIN (0.05)`).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_section_1()` (deep_space, 30 s DURATION) and `_build_section_2()` (planet_approach, 110 s DURATION) build every wave with `WaveBuilder` | The 11 + 24 sniper/ram/bomber lines still carry `.move()`, `.free_after()` and `.shoot_at_player()`; these are what this task strips |
| `tests/integration/test_level1_specialist_spawns.gd` | t1 pin: 50 rows (section, trigger, offset, delay); frozen `_LEGACY_PEAK_SPECIALISTS` (deep_space 5, planet_approach 3, cloud_descent 4); `_RAIL_SECTIONS` live-equals-constant check | Gains the no-rail check, the count gate and its boundaries; deep_space / planet_approach leave `_RAIL_SECTIONS` |
| `assault/scenes/enemies/sniper/sniper_brain.gd` | DISENGAGE = curve (`ω = min(max_turn_rate, acceleration / exit_speed)`) to the nearest edge of `EnemyWorld.projectile_world_rect()`, free once strictly outside. Budget expiry in AIM / LOCK defers to the shot (`aim_seconds + lock_seconds`) | Deferral term and the exit the probe measures |
| `assault/scenes/enemies/bomber/bomber_brain.gd` | Same curved DISENGAGE. Expiry in RUN defers to the run's end, `≤ line_length / run_speed + RUN_STALL_SLACK` (`line_length ≤ run_length`). Assault: one run, then ESCAPE → DISENGAGE | Deferral and exit |
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | Expiry in WIND_UP / CHARGE / STAGGER defers (≤ `wind_up_seconds + charge_max_time`). After a charge, DISENGAGE flies **straight** along `charge_dir` at `exit_speed`; otherwise the same curved nearest-edge exit | Deferral, straight bound and the measured curved bound |
| `*_config.tres` (sniper, bomber, ram) | Sniper and bomber `.tres` set only HP/contact/score/radii (all other fields are `.gd` defaults); the ram `.tres` sets every field | Levers write here only if the gate fails |
| `tests/helpers/level1_drone_concurrency.gd` | Pure interval arithmetic (`peak_interval_count`, `spawn_intervals`) | Reused for the peak count |
| `tests/helpers/enemy_ai_harness.gd` | `HARNESS.assault()` world (ArenaCamera, corridor, player stub) | The exit probe runs in it |
| `tests/integration/test_engagement_deadline.gd` | Ph3's `_disengage_seconds()` probe: 202 starts × 2 speeds, manual `_physics_process(DT)` stepping, position integrated from velocity | The shape this task's measured exits copy |
| `tests/integration/test_sniper.gd`, `test_bomber.gd`, `test_ram_corvette.gd` | The §2.9.4 attack-in-budget rows (read `engage_seconds` etc. from the preloaded shipped `.tres`) | Must stay green after any lever |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `DroneConcurrency.peak_interval_count()` | Peak alive over `{start, end}` intervals |
| `test_engagement_deadline.gd::_disengage_seconds()` | Probe loop (no real-time physics, so cheap) |
| `test_level1_fighter_spawns.gd::test_migrated_sections_have_no_rail_left` / `test_a_fighter_line_given_move_again_fails_the_pin` | The no-rail check and its `.move()` boundary |
| `HARNESS.assault()` | Assault world with a live `projectile_world_rect()` |

## Conventions that constrain this

- Triggers, offsets and delays are frozen by the t1 pin; the levers never move a trigger.
- Every lifetime term is read from config fields or measured on the real scene; never a typed number; never a
  straight-line exit for the sniper or bomber (epic review finding 13 / the Ph3 open item).
- `WaveManager` triggers waves strictly in list order (the Ph3 "wave-order quirk"), so a wave's effective trigger is
  the running maximum over the list.
- The gate is close to the harness's ~300 s limit (t10 report): new tests must not step real-time physics.
- No hand-typed UIDs; a new helper `.gd` gets its `.uid` from `--import`.
