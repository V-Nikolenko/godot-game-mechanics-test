# t19 — Level 1 placement: a turret group and a twin-drone pair in Deep Space, a Laser Tender in Planet Approach

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t19, building epic plan §2.18 (approved). Context: `1-context.md` beside this file.
Baseline: `scripts/gate-time.sh` at `8d2af49`, measured at the start of this task.

## Problem

Level 1 has none of Phase 8's enemies. A player flying Deep Space should meet a two-turret emplacement drifting down the corridor with its power
source between the turrets, and, at the end of the section, a Twin-Laser Drone pair closing a laser through them; in Planet Approach's quiet opening
a Laser Tender should launch its pair into a moving wall. None of it may crowd a section past the frozen density gate, sit on one of level 1's lethal
laser columns (a power source standing in a column dies and darkens its group seconds after it appears), or hold the next `ENEMIES_CLEARED` section open.

## Design

### A. The three lines (`level_1_director.gd`), each inside an existing wave, no rail

| Section | Wave (list order; effective trigger) | Line |
|---|---|---|
| deep_space | `b.wave(3.0, …)` (drone trio, `w6`; effective 3.5 s) | `b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR).at(-64, -220)` |
| deep_space | `b.wave(29.0, …)` (sniper pair + fighter) | `b.twin_laser_pair().at(-250, -220)` |
| planet_approach | `b.wave(2.0, …)` (drone screen `w0`) | `b.laser_tender().at(-300, -200)` |

The director's header comment gains a Phase 8 paragraph (the Mine Layer paragraph's shape). No other line or wave changes.

### B. Lives (all in `test_level1_specialist_spawns.gd`, every term read from a scene, a config, code or the memoised probes)

- **Turret-group member** (per slot of the placed preset, instanced off-tree): `_TICK_SLACK` (the deferred spawn) + `(world.end.y − y_spawn) / config.assault_drift_speed`,
  `y_spawn = (world rect centre y − ArenaCamera.V_LIMIT − CameraShake's max offset 8) + design_y · WORLD_SCALE + slot.y` (the view at its highest,
  shake included — review N4). Ring turret (1164 + 528) / 60 = 28.20 s, power source 27.20 s, burst turret 26.20 s. No ordnance tail: every mount's `pool_specs()` has `persist == false`
  (checked in the spill-over row) and the ring is a mount child.
- **Drone (a `twin_laser_pair()` line, ×2)**: `engage_seconds + twin telegraph_seconds (EnemyBeamScenes) + max_advance + _TICK_SLACK + PH8_EXITS.drone_exit_bound()`,
  `max_advance = (max(standoff, tender assault_wall_lead) + overshoot) / advance_speed` (1.92 s). ≈ 8 + 0.8 + 1.92 + 0.03 + 5.83 = 16.58 s.
- **Tender**: `engage_seconds + launch_telegraph + _TICK_SLACK + PH8_EXITS.tender_exit()["seconds"]` ≈ 10 + 0.6 + 0.03 + 3.82 = 14.45 s.
- **The tender's two drones**: interval from the tender's spawn (the earliest a launch can be) to `spawn + engage + launch_telegraph + _TICK_SLACK` (the
  latest launch: a LAUNCH shown when the budget expires finishes, `_leave_after_launch`) `+ drone life` ≈ 2.0 + 10.63 + 16.58 = 29.21 s.

`_ai_intervals()` appends these (kinds `TURRET_MEMBER`, `TWIN_DRONE`, `LASER_TENDER`, `TENDER_DRONE`), so the 2.5× count gate and every existing
peak boundary count them. `_ai_lives()` is untouched (it is keyed per scene; the Ph8 lines expand to several ships) — a separate `_ph8_lives()` holds
the four figures and prints them.

### C. Rows in `test_level1_specialist_spawns.gd`

1. `EXPECTED_PH8` pin (section, kind `TURRET_GROUP_ASSAULT_PAIR` / `TWIN_LASER_PAIR` / `LASER_TENDER`, wave trigger, offset, delay) + internal
   consistency (3 rows; each shares a wave with other traffic, so no new wave) + no rail (`_rail_rows()` with the Ph8 kinds) + a changed-delay boundary.
2. `test_ph8_alive_curves_are_printed`: per migrated section, the alive count at every interval start/end (the curve), printed, Ph8 ships marked;
   asserts the peaks with Ph8 are within 2.5× (redundant with the gate, but it is the row the acceptance criteria call "curves printed") and that
   the Ph8 intervals exist (3 + 2 in deep_space, 1 + 2 in planet_approach).
3. `test_ph8_static_members_clear_every_lit_column` (§2.18): for every turret-group line in level 1, every slot member at world x
   `projectile_world_rect().get_center().x + design_x · WORLD_SCALE + slot.x` (world-anchored), every row of `Level1Director.laser_column_schedule()`
   for that section that **starts before the member's life ends** (`time < life end`; no end filter — review round 1, R1: the beam turns lethal
   only after its 0.56 s `laser_increase` animation, so `time + warn + active` ends too early, and any column lit before the member is gone may
   still be lit while it lives), `|x − column| ≥ LaserRay._BEAM_WIDTH / 2 + body radius`. Also asserts level 1 places no laser fence (the row covers
   group members only). **Boundary:** the same check on a fresh build with the line moved to revision 1's `(0, −220)` fails (power source at 640).
4. Spill-over: the existing `test_no_specialist_outlives_…` predicate covers the Ph8 intervals automatically (they are in `_ai_intervals()`); it
   gains the `persist == false` sanity for the placed preset's mounts and prints the Ph8 latest ends.
5. The existing planet_approach boundaries that assert "peaks at 7" stay green (the peak is still 7; the first moment it is reached moves to 28.4 s);
   their comments are updated.

### D. `test_engagement_deadline.gd`

The four "no ENEMIES_CLEARED section spawns a …" rows and their "seen" boundaries exist. Added:
- **Non-vacuity**: level 1 now places a turret group, a twin pair and a tender, each in a DURATION section only (the detection the guard rests on
  sees the real lines).
- **Boundaries (life, lower bounds, no exit term):** in cloud_descent's last wave at delay 0 a tender computes `engage + launch_telegraph + MARGIN`
  (11.1 s), a twin pair `engage + telegraph + max_advance + MARGIN` (11.22 s), and an `assault_pair` group its shortest member's drift life from the
  lowest view (> 10 s) — each past the 10 s timeout through `_deadline_rows()`.

### E. Attack-in-budget replays — new `tests/integration/test_level1_ph8_attacks.gd`

Slices through `level1_slice_replay.gd` at the 16× clock (`_scale_clock` / `_restore_clock`, the Ph7 shape), each stopping as soon as its claim is decided:
- **Turrets**: the deep_space group's slice; targets = `defense_turret.tscn` members. Each of the two turrets has a mount in `TurretMount.Phase.FIRE`
  while its centre is inside `EnemyWorld.view_rect()`. Stops when both have.
- **Twin pair (29.0 s)**: targets = the two drones. Each enters ADVANCE exactly once; the rig's TELEGRAPH starts with budget left; `advances_started == 1`;
  both end in DISENGAGE. Stops when both drones are in DISENGAGE (or gone). **Boundary:** the same slice with the drones' private `engage_seconds`
  1.0 never reaches ADVANCE.
- **Tender (2.0 s)**: target = the tender. LAUNCH starts with budget left, exactly one launch (`launched`); its pair's rig reaches ADVANCE with the
  drone budget left at TELEGRAPH. Stops at the first ADVANCE. **Boundary (review R2):** the same slice with the tender's private `engage_seconds`
  0.5 never reaches LAUNCH and launches nothing (stops at its DISENGAGE).
- Two turrets / two drones reach the rows only through the helper's `tweak` callback (`observe` gets the first target); each row asserts
  `targets == 2`.
- The `persist == false` sanity of §C.4 reads the mounts the way `TurretGroup.mount_reaches()` does and has a failing case: a `ROCKET_BATTERY`
  mount's pools persist. (The optional turret-row boundary is left out for gate time.)
- Member departure is analytic (B), not replayed.

### F. Measurement and records

- Run `scripts/measure-level1-columns.sh` with the Ph8 lines in; record the counts (Ph8 kinds included) in DECISIONS "Phase 8, built in t19".
- Alive curves (before / after) and the gate-time before / after in DECISIONS, `tests/README.md` → Gate time, the task report.
- Docs: the director header; `laser_tender/ENEMY.md`, `twin_laser_drone/ENEMY.md`, `turret_group/STRUCTURE.md` gain their level-1 placement; one
  CLAUDE.md sentence. (`updating-project-docs`: no entity added or renamed; t20 closes the roster docs.)

## Build sequence

1. Baseline `scripts/gate-time.sh` (running).
2. Specialist gate: `_ph8_lives()`, Ph8 intervals, curve printer; run before editing the director → the "before" curves (Ph8 empty). Add the pin and
   the column row (fail: no Ph8 lines yet).
3. Edit the director; run the specialist gate → the "after" curves, peaks, column row green, boundary red-on-revision-1.
4. Engagement-deadline rows.
5. Attack replays file; run; leaks script.
6. Levers only if a row is red (§2.18 order).
7. Column measurement; DECISIONS; README; docs; `verify.sh`; `gate-time.sh` after.

## Test plan

Rows named in C, D, E. Boundaries: revision-1 placement fails the column row; a changed Ph8 delay fails the pin; a Ph8 line given `.move()` fails
the no-rail row; tender / pair / group in cloud_descent's last wave each computes past its timeout; a pair with a 1 s budget never advances.

## Risks

- **planet_approach at exactly 7 with the tender's drones** (28.4–29.2 s): if the drone exit bound grew, 8 > 7.5 → lever 1 (tender then drone
  `engage_seconds` 10 → 6 / 8 → 6), only while the attack rows stay green.
- **Replay cost**: three slices at 16× of ~5–15 game s each; target ≤ 3.5 s total new GUT time (the specialist rows add only arithmetic; the exits are
  memo hits after `test_laser_tender.gd`).
- **The ring turret fires only with the player within 300 px**: in the slice the stub sits at the view's lower centre (x 640); the ring turret
  (x 562) reaches it after ~8 s of drift. If it does not within the slice, the row reports it; no placement change without a lever.
- Replays are seeded and deterministic per tick but traffic may differ by frame timing at 16×; the rows assert outcomes with margin, not exact times.

- **Existing slice rows now see the pair** (review N2): the Support Ship's 26.0 s and the Mine Layer's 16.0 s deep_space slices include the 29.0 s
  wave; both stop before the pair can attack and must stay green (checked in the full run).
- **Column measurement contamination** (review N3): the replay world now has shooters (twin beam, pulse ring, burst rounds), so a friendly-fire death
  inside a lit column could be counted as a column kill; noted in DECISIONS with the counts. The worker also counts the brainless power source.

## Out of scope

New waves, any change to Ph8 entity behaviour, Ph15's corridor AI, the docs closing pass (t20).
