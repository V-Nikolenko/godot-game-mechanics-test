# Context — t19 Level 1 placement: a turret group and a twin-drone pair in Deep Space, a Laser Tender in Planet Approach

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t19, building epic plan §2.18 (with §2.7, §2.10, §2.12–§2.14 and §2.16 for the pieces it
places and the columns it must clear). Code read on `agent/auto-dev` @ `8d2af49` (t18 landed; every kind this task places exists, and both exits are
measured and memoised).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_section_1()` (deep_space, DURATION 30 s; the 3.0 s wave sits after the 3.5 s gunship wave, so its effective trigger is 3.5 s — the Ph3 wave-order quirk), `_build_section_2()` (planet_approach, DURATION 110 s; the 2.0 s wave is first), `laser_column_schedule()` (static, data), `_spawn_laser_columns(columns, warn = 3.0, active = 4.0)` | The three new lines go into existing waves; the column schedule and the column timing defaults are read by the clearance row |
| `assault/scenes/systems/wave_builder.gd` | `turret_group(preset_path)`, `TURRET_GROUP_ASSAULT_PAIR`, `twin_laser_pair()` (`TWIN_LASER_PAIR` = the spawner scene), `laser_tender()` (`LASER_TENDER`) | Already built by t9 / t12 / t13 |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | spawn position = `cam.global_position + cam.offset + offset · WORLD_SCALE` | Spawn y depends on the camera's vertical pan (± `V_LIMIT` 380) — the worst-case drift life uses the highest view |
| `assault/scenes/systems/arena_camera.gd` | `projectile_world_rect()` (y −444 .. 1164), `SCREEN_H`, `V_LIMIT` | The drift life's end (`end.y`) and the highest view centre (`SCREEN_H / 2 − V_LIMIT` = −20) |
| `assault/scenes/structures/turret_group/turret_group.gd` + `presets/assault_pair.tscn` | World-anchored x in `_ready()` (Assault); deferred `spawn_members()`; slots BurstTurret (−50, 60) v0, RingTurret (50, −60) v3, PowerSource (0, 0) | Members at world x 462 / 512 / 562 for design x −64; slot y offsets enter the drift life |
| `assault/scenes/enemies/defense_turret/` , `power_source/` | Body circle r 28 / 34; `config.assault_drift_speed` 60; `AssaultDrift` frees below `projectile_world_rect().end.y`; burst pool `persist: false` | Body radius and drift speed for the clearance row and the lives; no ordnance tail |
| `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd`, `pulse_ring_mount.gd` | `Phase.FIRE`, `phase_changed`, `round_fired`; the ring fires only with the player within `trigger_range` 300 | The turret attack-in-budget row watches each mount reach FIRE while its host is inside `EnemyWorld.view_rect()` |
| `assault/scenes/hazards/laser_ray/laser_ray.gd` | `_BEAM_WIDTH` 56 (const), kill mask 128 / 256 / 512 | Half-strip 28 read from the class constant |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone_brain.gd`, `twin_laser_pair.gd` | `budget` (`EngagementBudget`, from the drone's spawn / launch), phases, `pair.advances_started`, `is_committed()` | Drone life = engage + telegraph + max advance + slack + exit; the pair row counts ADVANCE starts |
| `assault/scenes/enemies/laser_tender/laser_tender_brain.gd` | `budget`, `Phase.LAUNCH`, signal `launched(rig)`; a LAUNCH shown when the budget expires finishes (`_leave_after_launch`) | Tender life = engage + `launch_telegraph` + slack + exit; its drones launch no later than that minus the exit |
| `tests/helpers/ph8_exit_keys.gd` | `drone_exit()`, `tender_exit()`, `drone_exit_bound()` (5.37 + 0.463 = 5.83 s), `tender_exit()` 3.82 s | The only way to read the exits (memo hits; `test_laser_tender.gd`'s source sweep fails a hand-built probe call) |
| `tests/integration/test_level1_specialist_spawns.gd` | Pins (`EXPECTED`, `EXPECTED_PH5`, `EXPECTED_PH7`), `_ai_lives()` / `_ai_intervals()` / `_peak()`, the frozen 2.5× gate, the spill-over rows (`_next_cleared_deadline`, `_spills`), boundaries that assert planet_approach peaks at exactly 7 | Gains `EXPECTED_PH8`, Ph8 intervals in `_ai_intervals()`, the column-clearance row and Ph8 spill-over |
| `tests/integration/test_engagement_deadline.gd` | Ph8 "no ENEMIES_CLEARED section spawns a turret group / laser fence / twin pair / tender" rows already exist (vacuous until now), each with a "seen" boundary; `_deadline_rows()`, `_add_to_last_wave()` | Gains the life boundaries (a tender / a pair / a group in cloud_descent's last wave computes past 10 s) and a non-vacuity row |
| `tests/helpers/level1_slice_replay.gd` | `placed()`, `slice_waves()`, `run(host, waves, length, target_path, observe, tweak)`; seeds every `BaseEnemy` brain on `child_entered_tree` | The attack-in-budget replays. `target_path` matches `scene_file_path` of `BaseEnemy` children, so the group's / spawner's members are targeted by their own scene path |
| `tests/integration/test_mine_layer.gd` (l. 1650–1745) | The Ph7 level-1 slice rows at 16× (`_scale_clock`) | Shape to copy |
| `scripts/measure-level1-columns.sh` + `tests/helpers/level1_column_replay*.gd` | Manual column-kill measurement | Re-run with the Ph8 spawns in; counts to DECISIONS |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `_ai_intervals()` / `_peak()` / `_spills()` / `_next_cleared_deadline()` in the specialist gate | The density and spill-over machinery: Ph8 intervals are appended there, so every existing peak boundary also counts them |
| `PH8_EXITS.drone_exit_bound()` / `tender_exit()` | The measured exits, at zero GUT cost when `test_laser_tender.gd` ran first (alphabetical order: `test_laser_tender.gd` < `test_level1_specialist_spawns.gd`) |
| `EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, &"telegraph_seconds", …)` | The twin beam's telegraph (0.8), read from the scene |
| `Level1Director.laser_column_schedule()` + the script's method list (`_spawn_laser_columns` default args) | Column x, time, warn and active, never typed |
| `Slice.placed()` / `Slice.slice_waves()` / `Slice.run()` | The replays |

## Conventions that constrain this

- No new wave, no rail; Ph8 lines go into existing waves (so no effective trigger moves). None in an `ENEMIES_CLEARED` section.
- Numbers in rows are read from scenes / configs / code, never typed (the expected peaks are printed, the limits are the frozen 2.5×).
- The exits come only through `ph8_exit_keys.gd`.
- 16× clock only for the clock-bound slice rows; restore it in `after_each`. Run `scripts/check-test-leaks.sh` (awaits).
- Gate allotment 3.5 s of new GUT time; baseline from `scripts/gate-time.sh` at `8d2af49`.
- Pre-approved levers of §2.18 in order, never a bound moved.
