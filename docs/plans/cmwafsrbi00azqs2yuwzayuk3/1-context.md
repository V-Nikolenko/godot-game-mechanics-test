# t11 context — Level 1's four gunships become Heavy Gunships off rails

Task `cmwafsrbi00azqs2yuwzayuk3`, epic `cmug23oo90029m52wae4clve0` (Phase 10), epic plan §2.12 (+ §2.4.3, §2.5, §2.15, §2.16) and the epic review's
round-2 findings N4 (wall timing in the lit replay) and N5 (rocket boundary derived from config). Read at `7225e63`.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Level 1's sections and waves; `laser_column_schedule()` (static, data); `_spawn_laser_columns(columns, warn = 3.0, active = 4.0)` (:218) builds `LaserRay`s under `get_parent()` at world (x, −380), `registers_hazard` true | deep_space 3.5 s `b.heavy_gunship().at(0, -500)` (:349, no rail since t4); cloud_descent 50.0 s `.at(0, -400).move(b.straight(42))` (:987), 62.0 s `.at(-100, -400).move(b.straight(36))` and `.at(100, -400).move(b.straight(36)).delay(0.8)` (:1017-1018). The rails come off here; the two defaults are hoisted to constants. |
| `assault/scenes/levels/edelia/1/level_1.tscn:46` | `LaserWallWave` = `laser_wall.tscn` at (0, −380) | The level-start wall: 12 rays at local x 28…644 (56 px beams → world x 0–672), `warn_duration` 3.0, default active 4.0, `auto_start`, `registers_hazard`. Not in the schedule. |
| `assault/scenes/hazards/laser_ray/laser_ray.gd` | `start()` → INIT (warn timer, `create_timer`) → INCREASE anim → IDLE (lethal; `active_duration` timer) → DISSOLVE anim → free | `is_lethal_now()` (IDLE), `danger_rect()` (world AABB of the hit strip), 9999 on any layer 128/256/512 hurtbox (module hurtboxes included). Timers and animations run on **idle** time: at 16× a transition lands on an idle frame (≈ 0.1–0.3 game s). Animations: increase 7 × 0.4 / 5 = 0.56 s, dissolve 7 × 0.6 / 5 = 0.84 s (`laser_ray.tscn` SpriteFrames). |
| `tests/helpers/level1_slice_replay.gd` | Slice replay through a real `WaveManager` in `HARNESS.assault()`, player stub, seeded brains; `run(host, waves, length, target_path, observe, tweak)`; statics `section()`, `placed()`, `slice_waves()` | Gains the opt-in `light_lasers` (default off). Callers today: `test_missile_corvette.gd`, `test_support_ship.gd`, `test_mine_layer.gd`, `test_level1_ph8_attacks.gd`, `test_level1_ph9_attacks.gd`, `test_heavy_gunship.gd` (statics only). |
| `tests/helpers/level1_column_replay_worker.gd` | Manual measurement (not GUT) | The technique to reuse: a plain `Node` under the harness root with `set_script(DIRECTOR_SCRIPT)` (no `_ready()`), its real `_spawn_laser_columns()` called on the timeline; `node_added` collects every `LaserRay`; coverage = `ray.is_lethal_now() and ray.danger_rect()…`. |
| `tests/helpers/ph10_exit_keys.gd` | `heavy_gunship_exit(host)` — memoised corridor exit probe (t4: **9.03 s**, 2166 runs, 0 capped) | The only legal way to build the probe call (a sweep in `test_heavy_gunship.gd` fails a hand-built one). Process-wide memo, so a second caller costs nothing. |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship_brain.gd` | `attack_window()` (:274, 1.05 s = heavy cannon 0.7 + 1 × 0.35), `budget` (`EngagementBudget`, counts from the first tick), `Phase.DISENGAGE`, `phase_changed`, `_missiles_open()` closed once `_expiry_seen` / DISENGAGE pending | Deadline terms. The pod closes **at budget expiry** (t5), not at DISENGAGE, so the rocket term is `engage + rocket max_time` (N5's second point is already met). |
| `assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn` | `Modules/{BatteryPort,BatteryStarboard,Cannon,Missiles,VentPort,VentStarboard}`, each `MountSlots/Slot0` (`TurretMountSlot.variant`) | Missiles = `ROCKET_BATTERY` (variant 2); its `pool_specs()` → DUMB (4.0 s) and PURSUIT (6.0 s) `persist: true`. |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd` | `phase_changed(phase)`, `round_fired(projectile)` | Battery FIRE detection and the round count for the fire-density record. |
| `tests/integration/test_engagement_deadline.gd` | `_deadline_rows(section, path, tail)` (:236), `_over`, `_cloud_descent`, `_add_to_last_wave`, `_with_fighter_wave_before_last`, the corvette rocket-term boundary (:852), `MARGIN` 0.5 | Gains the heavy rows. cloud_descent: ENEMIES_CLEARED, timeout 10.0, last trigger 76.0; waves 66.0 / 68.0 / 72.0 / 76.0 follow 62.0. |
| `tests/integration/test_level1_specialist_spawns.gd` | The pin / frozen-legacy-peak / count gate / one-extra boundary / spill-over shapes; `_rail_lifetime()` (cull-rect sampling, the EnemyPathMover rule); `_wall_wave_row()`; `_next_cleared_deadline()` | Shapes to copy for the heavy gate (heavies are not specialists, §1.1 S10). |
| `tests/integration/test_heavy_gunship.gd:1010` | `test_the_deep_space_heavy_fires_a_battery_inside_its_budget` — hand-ticked, no traffic, no lasers: first battery FIRE at 6.12 s | Stays; t11's replay is the in-traffic, lit version. |
| `tests/integration/test_level1_ph8_attacks.gd` | 16× slice replays; `_scale_clock()` / `_restore_clock()`; the deep_space 3.0 s slice already replays the 3.5 s heavy (wave-order quirk) | Must stay green; shape to copy. |

Section order (`_build_sections`): deep_space (DURATION 30 s) → asteroid_belt (DURATION) → station_assault (ENEMIES_CLEARED, one wave at 0.0) → planet_approach (DURATION
110 s) → cloud_descent (ENEMIES_CLEARED, timeout 10.0).

No other test replays the 50.0 / 62.0 s cloud_descent waves with their heavies: `test_level1_fighter_exit.gd` starts at 66.0 s, `test_level1_drone_exit.gd` replays only the
76.0 s wave, `test_level1_specialist_exit.gd` keeps only snipers and rams, `test_level1_fighter_fire_density.gd` filters to fighters / Gatlings (its schedule row
pins wave triggers, which do not change), the sniper / ram attack rows use spawn classes (single ships).

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `Level1Director.laser_column_schedule()` / `_spawn_laser_columns()` | The real columns, called through a `set_script` spawner (no copy of the laser set-up). |
| `level1_slice_replay.gd` `section()` / `placed()` / `slice_waves()` / `run()` | Slices, real `WaveManager`, seeding, the spawn-settle rule (no stranded timers). |
| `ph10_exit_keys.gd::heavy_gunship_exit()` | The measured exit (memo hit after the first caller). |
| `level1_drone_concurrency.gd` `spawn_intervals()` / `peak_interval_count()` / `peak_window_rate()` | Legacy-rail intervals and the 2 s-window peak. |
| `test_level1_specialist_spawns.gd::_rail_lifetime()` | The legacy cull-rect lifetime (copied: the specialist file's helpers are instance methods of another test). |
| `TurretMountScenes`, `RocketBatteryMount.pool_specs()` | The pod's rocket scenes for the rocket term, read, never typed. |

## Conventions that constrain this

- Design units 640×360, `ArenaCamera.WORLD_SCALE` 2.0: `.at(x, y)` spawns at world (640 + 2x, 360 + 2y) (camera centre + offset × 2).
- Tests first; real-physics replays on the 16× clock (tick-paced), restored in `after_each`; one scenario computed once and shared as plain data (Gate time rule 2).
- Exit probes only through `ph10_exit_keys.gd`; nothing types a number a config or scene holds; no hand-typed `uid://`.
- Gate time: t11's allotment 3.0 s (1.5× line 4.5 s); two `scripts/gate-time.sh` runs before and after; gate output well under 1 MiB; `scripts/check-test-leaks.sh` after
  anything that awaits (lasers create `SceneTreeTimer`s).
- `DECISIONS.md` and the gate-time table are append-only.
