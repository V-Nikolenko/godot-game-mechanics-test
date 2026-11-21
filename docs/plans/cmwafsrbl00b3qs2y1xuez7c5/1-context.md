# t12 context — a Carrier crosses Planet Approach

Task `cmwafsrbl00b3qs2y1xuez7c5`, epic `cmug23oo90029m52wae4clve0` (Phase 10), epic plan §2.13 (+ §2.6.3, §2.8, §2.12, §2.15). Read at `7aba280`.
t11's context (`docs/plans/cmwafsrbi00azqs2yuwzayuk3/1-context.md`) covers the laser and replay files in more depth; this file lists only what t12 adds or reads.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_section_2()` = planet_approach (DURATION 110 s); its 65.0 s wave holds two snipers (delay 0) and a ram (0.7). `laser_column_schedule()` planet_approach rows 10 / 25 / 38 / 55 (x 300 / 700 / 1100) / 78 (x 150 / 550 / 950) / 98 (x 450 / 850). `COLUMN_WARN_SECONDS` 3.0, `COLUMN_ACTIVE_SECONDS` 4.0 (t11). | Option A appends `b.carrier().at(55, -260)` to the 65.0 s wave: no new wave, so no effective trigger moves. |
| `assault/scenes/enemies/carrier/carrier.gd` | World-anchored x in `_ready()` (`.at(x, y)` → world x 640 + 2x); frees itself once `global_position.y - body_size().y / 2 > projectile_world_rect().end.y` (on the root, so an EMP cannot skip it). Body rectangle 176 × 280 (half height 140). | The worst Assault life: spawn y is camera-relative (`WaveManager`: `cam.global_position + cam.offset + offset * WORLD_SCALE`), so the highest view (offset −`V_LIMIT` 380, shake `CameraShake._MAX_OFFSET` 8) gives y −548 from design y −260, and 1304 + 548 px at 90 px/s ≈ 20.6 s. |
| `assault/scenes/enemies/carrier/carrier_brain.gd` | CROSS: constant `assault_cross_speed` 90 down, acceleration / braking 0 (t6 D5), sway leashed ±`assault_sway_leash` 30 around the anchored x; `_tick_hangars()` latches the view entry of the hull centre. | x swept = spawn x ± (30 + `module_x_extent` 100). |
| `assault/scenes/enemies/carrier/carrier_hangars.gd` | Assault: the schedule clock runs from view entry; the port bay OPENS at `first_launch_delay` 3.0, the starboard at + `starboard_launch_delay` 4.0; children come out `door_open_seconds` 0.8 later; `assault_launch_count` 2 each, swarm drones (`assault_hangar_scene`), ONE squad for both bays; signal `launched(module_id, children)`. | Launch windows for the attack-in-budget row only (no PANIC there): earliest = spawn + 3.0 (+ 4.0) + 0.8 (view entered at once), latest = the carrier's worst life. The drone gate's intervals start at the carrier's spawn (PANIC's `emergency_deploy()` launches any unlaunched bay at once; review round 1, finding 1). |
| `assault/scenes/systems/arena_camera.gd` | Follows the group-`player` node with a deadzone (40, 30), offset clamped ±(`H_LIMIT` 100, `V_LIMIT` 380); `projectile_world_rect()` is pure constants (x −164..1444, y −444..1164). | The replay stub's y decides the view, so the carrier's life in the replay. |
| `tests/helpers/level1_slice_replay.gd` | t11's lit replays (`light_lasers`, `lit_section`, `lit_from`, `deaths`, `clearance`, `lit`), `PLAYER_OFFSET` (0, 250) from the camera centre. | At the usual stub place the camera offset is +220 (250 − the 30 px deadzone), the carrier spawns at y 60 and is freed at ≈ 78.8 s, before the 78.0 s set turns lethal (81.56 s): a lit check there would be vacuous. t12 adds an opt-in `player_offset` (default `PLAYER_OFFSET`, every caller unchanged). |
| `tests/integration/test_level1_heavy_spawns.gd` | t11's heavy gate; `_scale_clock(LIT_MAX_STEPS)`, `_check_ray_edges()`, `_assert_idle_capped()`, `_next_cleared_deadline()`, the fire-density print. | Gains `EXPECTED_PH10_CARRIER`, `_carrier_column_conflicts()`, the spill-over, the lit carrier replay (lasers + attack + fire record). |
| `tests/integration/test_level1_drone_spawns.gd` + `tests/helpers/level1_drone_concurrency.gd` | C3 gate: planet_approach legacy 6, today capable 7 (≤ 12), all 9 (≤ 15); `squad_intervals()` (first 3 of a squad capable), `peak_intervals()`. `_c3_lifetimes()`: swarm 5.5 + worst exit. | The carrier's ≤ 4 drones are appended as one squad of intervals. Even fully overlapping the peak they give 10 / 13, inside 12 / 15. |
| `tests/integration/test_engagement_deadline.gd:974` | `test_no_enemies_cleared_section_spawns_a_carrier` + boundary (t6) | The guard row exists; t12 adds that level 1 really places one carrier (so the guard is not vacuous). |
| `tests/integration/test_level1_ph9_attacks.gd:214` | The jammer slice replays planet_approach 61.0 → 88.2 s (stops on the lock, ≈ 65.9 s) | The only existing replay whose window holds the 65.0 s wave: it will now spawn the carrier too (at slice 4.0 s). Must stay green. Other planet_approach slices (corvette 40 / 85, support 28, mine layer 47, hacker 42, tender 2) do not reach the 65.0 s wave. |
| `tests/integration/test_level1_specialist_spawns.gd` | Specialist pin and 2.5× gate (counts by scene path); `_static_life()` (highest view, shake), `_column_conflicts()` (statics, no start filter) | The carrier is not a specialist (unchanged); `_static_life()`'s rule is what the carrier's worst life follows. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `level1_slice_replay.gd` `section()` / `placed()` / `slice_waves()` / `run()` / `lit_seconds()` / `column_lethal_offset()` / `ray_timing()` | Slices, the lit lasers through the director's own `_spawn_laser_columns()`, death and clearance records. |
| `test_level1_heavy_spawns.gd` `_check_ray_edges()`, `_assert_idle_capped()`, `_next_cleared_deadline()`, `_section()`, `_build_sections()` | Ray-edge timing, step-cap check, spill-over predicate. |
| `level1_drone_concurrency.gd` `squad_intervals()` / `peak_intervals()` / `capable_peak_time()` | Interval peaks. |
| `Carrier.hangars()` (`launched`), `battery_mounts()`, `bow_mount()`, `missile_mount()`, `TurretMount.round_fired` | Attack-in-budget hooks and the fire record. |
| `RocketBatteryMount.pool_specs()` (via the scene's `HullMounts/Dorsal` slot) | The missile bank's rocket life for the spill-over term. |

## Conventions that constrain this

- Design units: `.at(x, y)` → world x 640 + 2x (world-anchored); spawn y camera-relative.
- Every number read from code / scene / config (`CarrierConfig`, `LaserRay._BEAM_WIDTH`, `ArenaCamera.V_LIMIT`, `CameraShake._MAX_OFFSET`, the director's constants); nothing typed.
- Lit runs cap `max_physics_steps_per_frame` at 16 (README rule 1), 16× clock, one scenario shared as data; `check-test-leaks.sh` after anything that awaits.
- Never change a frozen constant (`_LEGACY_PEAK_*`, `_EXPECTED_LEGACY_PEAKS`); no Carrier in an ENEMIES_CLEARED section.
- Gate time: t12 allotment 2.5 s (1.5× line 3.75 s); two `scripts/gate-time.sh` runs before and after.
- `DECISIONS.md` and the gate table are append-only.
