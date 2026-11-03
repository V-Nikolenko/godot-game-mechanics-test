# Context — t14 Twin drones and the Laser Tender: hub idle and Assault lives

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t14 (epic plan §2.14, with §2.12 / §2.13 / §2.20). Code read on `agent/auto-dev` @ `7597711` (t13 landed).
t12's context (`docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/1-context.md`) and t13's (`docs/plans/cmvqw0vnz018nqs2xv56q6a0a/1-context.md`) cover the shared AI stack, the rig and the
tender; this file lists only what t14 adds or leans on.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone_brain.gd` | Drone brain; `Phase { FORM, TELEGRAPH, ADVANCE, BREAK, WAIT, SOLO, DISENGAGE, LAUNCHED, IDLE, NOTICING, RETURNING }`; IDLE / NOTICING / RETURNING request zero velocity; `start_engaged` (no effect yet); `patrol_anchor` (defaults to the drone's own spawn point); SOLO `arrive`s at a live controller else at `patrol_anchor`; `_mirror(rig_phase)` maps the rig phase to the brain phase | The idle family gets its motion; the leader's `AnchorIdle` drives the rig; a launched drone is recalled to its tender |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_pair.gd` | Rig: `Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT, LAUNCHED }` (append-only), leader-only clock, `_enter()`, `is_committed()`, `controller` | Needs an idle rig phase (beam off, no frame, the orbit clock) and stand-down / engage seams |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_pair_spawn.gd` | Spawns A / B at ∓ L/2 along its local X and binds them | Must hand both brains one shared `patrol_anchor` (its own position); today each brain defaults to its own spawn point, 420 px apart |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.gd/.tres` | Flat config; no "Idle" group yet | Gains perceive 650 / lose 1500 / notice 0.35 / idle_radius 140 (+ idle_speed) |
| `assault/scenes/enemies/laser_tender/laser_tender_brain.gd` | Tender brain; `Phase { APPROACH, HOLD, LAUNCH, WAIT, REARM, DISENGAGE, IDLE, NOTICING, RETURNING }`; idle family holds still; `_dock_returning()` docks SOLO launched drones within `dock_radius`; REARM entered only from WAIT; `_setup()` instantiates and frees a probe `drone_scene` to read `drone_config` | Idle / notice / return motion; a returning tender recalls its launched pair; a tender re-engaged with empty cradles must rearm (otherwise HOLD can never launch again) |
| `assault/scenes/enemies/laser_tender/laser_tender.gd` | `launch_pair`, `dock`, `rearm_cradles`, `launched_drones`, `docked_count` | Gains a duck-typed `recalls_drones()` the drone brain reads (no drone ↔ tender class cycle) |
| `assault/scenes/enemies/laser_tender/laser_tender_config.gd/.tres` | "Idle" group already declared: perceive 700 / lose 1600 / notice 0.35 / idle_radius 160 / idle_speed 0.5 | Played as-is |
| `global/enemy_ai/anchor_idle.gd` | `AnchorIdle` (IDLE / NOTICING / COMBAT / RETURNING), `update(delta, actor_pos, target)`, `home_radius`, `force_notice()` | The handover both brains use |
| `assault/scenes/enemies/mine_layer/mine_layer_brain.gd` | Ph7 hub idle: `anchor_idle` built in `_setup()` when `not budget.active and not start_engaged`; `_tick_anchor_idle()` (busy phases never interrupted); IDLE = `mover.orbit(anchor, idle_radius, angle, max_speed)`, NOTICING = stop + face + `StateLight.blink_once()`, RETURNING = `arrive(anchor)` | The template (written fresh for each brain) |
| `tests/helpers/specialist_exit_probe.gd` | `worst_disengage(host, scene, phase, speeds, cap, start_set, prepare)`; process-wide `static var _memo` keyed by path, phase, speeds, cap, start set, `prepare`; `corridor_starts(corridor, world)` (19 × 19 × 3 = 1083 starts) | The two measured exits; the memo is what makes t19's identical calls free |
| `tests/integration/test_level1_specialist_spawns.gd` `before_all()` | How Ph5 / Ph7 build the corridor start set (`ArenaCamera` added and freed for `projectile_world_rect()`, `AssaultCorridorConstraint.new().inner_rect()`), speeds `[exit_speed or max_speed, 10.0]`, `_PROBE_CAP` 20.0, `_layer_probe_prepare` (pools emptied, player stub leaves group `player`) | The argument shape `ph8_exit_keys.gd` copies; t19 will call the helper from this file |
| `tests/integration/test_twin_laser_drones.gd`, `test_laser_tender.gd` | t12 / t13 rows; helpers `_pair()` / `_tender()` / `_step()`; Open Space rows rely on the brains fighting at once | Every Open Space behaviour row now needs `start_engaged = true` (the hub idle would otherwise hold them); t14's rows join these files |
| `tests/integration/test_enemy_dual_mode.gd` (`test_twin_laser_drones_form_and_telegraph_in_both_modes`, `test_laser_tender_launches_a_pair_in_both_modes`) | Open Space cases expect combat at once | `start_engaged = true`, as the earlier brains' cases do |
| `tests/integration/test_base_enemy.gd` tow table | Enters every refusing phase, sets every other phase by field | IDLE / NOTICING / RETURNING are already in both enums, so they are already covered as accepting phases |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `AnchorIdle` | Notice / lose hysteresis, `notice_time`, `home_radius` |
| `EnemyMover.orbit()` / `Steering.orbit()` | The ring motion (target point on the ring; speed `clamp(4·d, 60, max)`) |
| `StateLight.blink_once()` | The NOTICING tell |
| `SpecialistExitProbe.worst_disengage()` + `corridor_starts()` | The measured exits, memoised process-wide |
| Mine Layer `_tick_anchor_idle()` shape | Busy phases never interrupted; COMBAT handed over only from NOTICING |
| t13 docking (`LaserTender.dock()`, `_dock_returning()`) | Recalled drones dock through the same call |

## Conventions that constrain this

- Brains tick through `BaseEnemy._physics_process`; only `EnemyMover` writes velocity / rotation; the rig and the tender script write no motion (swept by
  `test_twin_laser_drones.gd::test_the_rig_and_the_spawner_write_no_motion`).
- Enums append-only (`TwinLaserPair.Phase` gains a value at the end; the brains' idle phases already exist).
- The rig never names the drone / brain classes; the drone brain must not name `LaserTenderBrain` (the tender brain already names the drone brain) — duck-type.
- Randomness only from a brain's `rng`.
- Hand-ticked drones clear their body `collision_mask` (t12).
- Rig-signal test handlers never capture the rig (RefCounted cycle → leak at exit).
- Gate allotment 8.5 s (rows 1.0, drone probe 3.5, tender probe 4.0); baseline measured at the start of this task.
- Neither brain reads the player in DISENGAGE today: the drone's `tick()` skips `pair.tick` / `_decide` in DISENGAGE and `_tick_disengage()` reads only the
  projectile world rect; the tender's `tick()` returns right after `_tick_disengage()`. `BaseEnemy._physics_process` and `EnemyMover.step()` read no player.
  So the probe's stub trick (rule 3) is harmless and must stay so after t14's idle code.
- The probe hands each ship a start velocity along its start heading. The drone's DISENGAGE exits along that heading when it has no frame, but along the rig's
  `-n` when it has one, and then its own velocity (≤ `max_speed` 300 off a boost) can point against the exit: a start-velocity case the probe cannot pose.
  The tender always exits toward the nearest world edge, and the corridor grid's headings point away from it, so its probe does pose the reversal.
