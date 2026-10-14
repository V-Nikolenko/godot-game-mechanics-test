# Context — t22: cloud_descent's snipers and rams off rails

Task `cmuyk2qqp009loa2xb1k3py8o`. Epic plan `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.9.3,
§2.9.2 (count gate), §2.9.4, §4 rows for `test_engagement_deadline.gd` / `test_level1_fighter_exit.gd` /
`test_level1_specialist_exit.gd`; epic review N2 (replay start contradiction).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` `_build_section_3()` (l.804-) | cloud_descent, ENEMIES_CLEARED, timeout 10 s, last wave 76.0 s | 9 sniper lines (11, 32x4, 53x2, 62+1.2 x2) and 6 ram lines (28, 28+0.4, 38+0.6, 50+1.5 x2, 72+1.2) still carry `.move()` / `.free_after()` / `.shoot_at_player()` |
| `tests/integration/test_engagement_deadline.gd` | Ph2 drone/razor and Ph3 fighter/Gatling deadline rows; `_deadline_rows(section, path, tail)` per-entry with effective triggers; `_add_to_last_wave`; `_cloud_descent()` | t22 adds sniper/ram rows, ram/bomber boundaries, the forced-LINE_UP-expiry run |
| `tests/integration/test_level1_specialist_spawns.gd` | t1 pin (50 rows), `_LEGACY_PEAK_SPECIALISTS` (cloud_descent 4), `_RAIL_SECTIONS = [cloud_descent]`, t21 `MIGRATED_SECTIONS`, `_ai_lives()`, count gate, `test_extra_rams_at_the_peak_break_the_frozen_constant` (cloud_descent) | cloud_descent moves to MIGRATED; live-equals-constant check retired (Ph3 t17 shape: `_RAIL_SECTIONS = []`) |
| `tests/helpers/specialist_exit_probe.gd` | t21: slowest DISENGAGE on the real scene over the Ph3 404-start grid (view ±560 x ±320, 8 headings) | reused for the deadline rows' measured exits |
| `tests/integration/test_level1_fighter_exit.gd` | real WaveManager replay of cloud_descent from 66.0 s, includes the 73.2 s ram (on rails today) | must still empty in time with that ram on AI |
| `tests/integration/test_level1_fighter_fire_density.gd`, `test_bomber.gd`, `test_enemy_ordnance.gd` | clock speed-up precedent (`Engine.time_scale` x `physics_ticks_per_second` x `max_physics_steps_per_frame`, restored in `after_each`) | the new full-section replay (86 s game time) must not cost 86 s of wall clock |
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | expiry table: APPROACH/LINE_UP/WIDE_TURN disengage that tick (curved); WIND_UP/CHARGE/STAGGER defer; after CHARGE straight along `charge_dir`; after STAGGER curved. Curved turn rate `min(max_turn_rate, acceleration / exit_speed)` | the ram row's terms |
| `assault/scenes/enemies/ram_corvette/ram_corvette_config.tres` | `engage_seconds` 4.5, `exit_speed` 500 | the two pre-approved levers |
| `tests/integration/test_ram_corvette.gd::test_every_level1_ram_spawn_class_winds_up_inside_its_budget` | t17 attack-in-budget row | each lever is legal only while it is green |

## Measurements taken while gathering context (throwaway probe, deleted)
- t21 probe (view grid), ram curved exit: 6.35 s at `exit_speed` 500; 3.72 s at 560 (discontinuous: below ~520 the
  U-turn radius `v²/a` leaves a slow start circling inside the rect). Straight bound `diagonal / exit_speed`: 4.55 / 4.06.
- Fine grid inside the same view region (40 px, 24 headings, 700/280/10 px/s) at 560: 3.717 s — the coarse grid is exact there.
- Starts OUTSIDE the visible view (corridor soft/hard band, ±700): 6.42 s at 500, 5.72 s at 560 (fine 70 px grid).
- Sniper probe: 5.40 s.
- t17 attack row today: worst WIND_UP at 3.07 s of 4.5 (top-wide, stub away), so the latest LINE_UP is ≤ 3.07 s.
- `test_level1_fighter_exit.gd` today: container empty 9.18 s after `waves_complete` (drones), 28 s of wall clock (1x).

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `test_engagement_deadline.gd::_deadline_rows`, `_over`, `_add_to_last_wave`, `_cloud_descent`, `_last_wave`, `_section_has_scene`, `MARGIN` | the per-entry row machinery, unchanged |
| `specialist_exit_probe.gd::worst_disengage` | measured curved exits |
| `test_level1_fighter_exit.gd` | replay harness shape (container, seeding on `child_entered_tree`, exit recording, `waves_complete` on WM clock) |
| `test_level1_fighter_fire_density.gd::_scale_clock/_restore_clock` | sped-up clock with 1/60 game-second physics step |
| `test_ram_corvette.gd` seam `budget.seconds = budget.seconds - budget.remaining()` | forcing expiry on the next tick |

## Conventions that constrain this
- Design-unit offsets (640x360) scaled by `ArenaCamera.WORLD_SCALE`; never pre-multiplied.
- Every deadline term from config fields or a measurement; none typed (Ph3 rule).
- Levers only in the stated order and only if the gate fails; the t17 attack row must stay green.
- `tests/README.md`: coroutine-leak trap (run `scripts/check-test-leaks.sh`), SceneTreeTimer must fire before a test returns.
