# t14 — Twin drones and the Laser Tender: hub idle and Assault lives

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t14, building epic plan §2.14 (with §2.12, §2.13, §2.20). Context: `1-context.md` beside this file.
Baseline (`scripts/gate-time.sh` at `7597711`): GUT `Time` **207.286 s**, 2576 tests, 93280 asserts.

## Problem

In the hub, a Twin-Laser Drone pair or a Laser Tender placed on patrol attacks the player the moment the scene starts, from anywhere on the map, and never
stops: their IDLE / NOTICING / RETURNING phases exist but hold the ship still and nothing enters them. The player should instead find a pair slowly circling
its patrol point with the beam off, and a tender circling its own point with both drones docked; each notices the player with a visible blink when it comes
within reach, fights, and goes home (a launched pair flying back to dock) once the player is far away.

In Assault both already attack once and leave, but how long the leaving takes has never been measured, so the level-1 placement task (t19) has no exit time
to plan density and deadlines with. This task measures both exits once per test run, through one helper the level-1 task will call with the same
arguments.

## Design

### A. Twin-Laser Drone pair — hub idle (`twin_laser_drone_brain.gd`, `twin_laser_pair.gd`, `twin_laser_pair_spawn.gd`, config)

**Config** (`TwinLaserDroneConfig`, new group "Idle", flat): `perceive_radius` 650, `lose_radius` 1500, `notice_time` 0.35, `idle_radius` 140 (§2.14), and
`idle_speed` 0.5 rad/s (*starting value*, not in §2.14: the tender's figure; 70 px/s on the ring). `.tres` gets the same values.

**Rig** (`TwinLaserPair`): `Phase` gains **`IDLE`, appended** (`{ FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT, LAUNCHED, IDLE }`). In rig IDLE there is no
attack: no frame is computed, the beam is never started, and the leader's tick only advances `idle_angle += config.idle_speed * delta`.
- `idle_anchor: Vector2`, `idle_angle: float`, `idle_state: int` (an `AnchorIdle.State`, written by the leader's brain, read by both brains).
- `is_busy() -> bool`: TELEGRAPH, ADVANCE, BREAK, COLLAPSED or LAUNCHED — an attack that has been shown, its BREAK, or a launch, is never cut short.
- `stand_down(anchor: Vector2) -> void`: from any non-busy phase but IDLE: `beam.cancel()` (a no-op when OFF), `frame_fixed = false`, `idle_anchor = anchor`,
  `idle_angle = (B − A).angle()` (each drone keeps its side), `_enter(IDLE)`.
- `engage() -> void`: from IDLE, `_enter(FORM)` (the first FORM frame takes the drones' bearing outright, t12's `_fresh_frame`).
- `idle_slot_angle(d) -> float`: `idle_angle` for B, `idle_angle + PI` for A (opposite each other on the ring).
- The leader's tick in IDLE never strains, breaks or forms; `is_intact()` / the death hooks are unchanged, so a drone killed while idling breaks the pair at once.

**Brain** (`TwinLaserDroneBrain`):
- `anchor_idle: AnchorIdle`, built in `_setup()` when `not budget.active and not start_engaged` and the drone has no controller (`pair == null or pair.controller == null`):
  `AnchorIdle.new(patrol_anchor, perceive_radius, lose_radius, notice_time, idle_radius + slot_tolerance)` — `home_radius` is the ring plus `slot_tolerance` because the
  leader returns to a ring point, not the anchor. Both brains build one (the survivor of a broken pair keeps it), but **only the leader of an intact,
  uncontrolled pair updates it**, once per tick, before `pair.tick()` — the rig's single clock. The distances it reads are the leader's own position to the player.
- `_tick_anchor_idle(delta, target)` (leader only), on `anchor_idle.update(...)`:
  - IDLE or RETURNING: `pair.idle_state = state`; if the rig is neither IDLE nor busy → `pair.stand_down(patrol_anchor)`.
  - NOTICING: if the rig is IDLE → `pair.idle_state = NOTICING` (a pair still fighting when the player comes back keeps fighting).
  - COMBAT: if the rig is IDLE → `pair.engage()`.
  The first leader tick of a cold Open Space pair therefore stands the rig down from its initial FORM.
- `_mirror(IDLE)`: a controlled (launched) pair → `RETURNING`; otherwise `IDLE` / `NOTICING` / `RETURNING` from `pair.idle_state`.
- Phase entry: NOTICING → `StateLight.blink_once()` (both drones blink; the lens is otherwise OFF in every idle phase, as `_update_light()` already makes it).
- Motion (requests only): IDLE and RETURNING (uncontrolled) → `mover.orbit(pair.idle_anchor, idle_radius, pair.idle_slot_angle(actor), max_speed)` — RETURNING flies to
  the drone's moving ring point, IDLE stays on it; NOTICING → zero velocity, `face_toward(player)`; RETURNING with a controller → `arrive(controller, max_speed)`.
- **Launched pair recall:** the leader of an intact, controlled pair reads `_recalled()` each tick, before `pair.tick()`: the controller is **live** (valid and not
  queued for deletion: the SOLO code's test, factored into one `_controller_live()`), `has_method(&"recalls_drones")` and it returns true. True and the rig neither IDLE
  nor busy → `stand_down(controller position)` (brains mirror RETURNING → fly to the tender); false while the rig is IDLE → `engage()`. So **a recalled pair whose tender
  dies (or a controller without the method) re-engages on the leader's next tick** and fights Attack A cycles, as t13's orphaned pairs do (review B1). RETURNING with a
  controller `arrive`s at it only while `_controller_live()`; otherwise it holds (the leader engages the same tick anyway). The drone brain never names `LaserTender` /
  `LaserTenderBrain` (duck-typed, the `is_armored()` precedent).
- **A lone drone (SOLO) in Open Space with no live controller** orbits its own anchor alone: `mover.orbit(patrol_anchor, idle_radius, solo_angle, max_speed)`, with
  `solo_angle` taken from `(position − anchor).angle()` on SOLO entry and advanced at `idle_speed` (from far away the ring point lies on the line to the anchor,
  so t12's "SOLO turns it toward its anchor" row still holds). It cannot attack, so it does not notice either. This applies whether or not `start_engaged` is set
  (`start_engaged` only skips the noticing idle; a survivor with nowhere to dock always circles its anchor; review N10).
- `start_engaged` (default false) skips all of the above (no `AnchorIdle`): every behaviour row that expects combat at once sets it (step 1).

**Spawner** (`TwinLaserPairSpawn.spawn_pair()`): sets both brains' `patrol_anchor` to its own global position (the pair's midpoint) before adding them, so the
pair shares one anchor. A hub layout (t18) places the spawner at the patrol point.

### B. Laser Tender — hub idle (`laser_tender_brain.gd`, `laser_tender.gd`)

- `anchor_idle` built in `_setup()` when `not budget.active and not start_engaged`: `AnchorIdle.new(patrol_anchor, 700, 1600, 0.35, idle_radius 160)` (config group "Idle",
  already declared by t13; `home_radius = idle_radius`, the Mine Layer's, because the tender returns to the anchor point itself). First tick: IDLE instead of APPROACH.
- `_tick_anchor_idle(delta, target)` before `_decide()`, the Mine Layer's shape: busy = LAUNCH or DISENGAGE; IDLE / NOTICING / RETURNING entered when not busy and not
  already there; COMBAT from NOTICING → APPROACH.
- Motion: IDLE → `mover.orbit(patrol_anchor, idle_radius, _idle_angle, max_speed)`, `_idle_angle` taken from `(position − anchor).angle()` (0 at the anchor) on IDLE
  entry and advanced at `idle_speed`; NOTICING → zero velocity, `face_toward(player)`, `StateLight.blink_once()` on entry; RETURNING → `arrive(patrol_anchor, max_speed)`.
  IDLE and RETURNING run **before** `_move()`'s no-target early return (they need no player; review N7).
- `LaserTender.recalls_drones() -> bool` = the brain is in IDLE, NOTICING or RETURNING. `_dock_returning()` (Open Space only, already) also docks a launched drone whose
  brain is **RETURNING** (recalled) within `dock_radius`, not only SOLO: the first to dock breaks the rig, the survivor goes SOLO toward its live controller and docks too.
- **Cradles across a hub cycle** (found in context: REARM is entered only from WAIT, so a tender whose pair died or docked away while it was idling would reach HOLD with
  empty cradles and never launch again):
  - **one rearm clock across the hub transition** (review N6, worded exactly per review round 2 B2): REARM keeps t13's rule (`_phase_time ≥ rearm_seconds` →
    `rearm_cradles()` → HOLD). `_rearm_elapsed` obeys, in every Open Space tick and phase:
    - it is set to 0 whenever `docked_count() == 2` or `_pair_lives()` (checked every tick, in every phase);
    - it **advances** by `delta` only in IDLE / NOTICING / RETURNING; at `rearm_seconds` → `rearm_cradles()` (so the idling tender carries its docked pair, §2.14);
    - it is **never** reset by a phase change;
    - it is **consumed** (set to 0) when `rearm_cradles()` fires, and when it seeds REARM's `_phase_time` (the seed is written after `enter_phase()`, which zeroes `_phase_time`);
    - entering an idle phase **from REARM** seeds it from REARM's `_phase_time`.
    So progress is never thrown away and the cradles fill `rearm_seconds` after the pair died (± a tick at the REARM → idle seam), whichever order the transitions come in;
  - in Open Space, APPROACH or HOLD with `docked_count() < 2`: a live pair → WAIT (whose existing rule REARMs when it dies); otherwise → REARM, seeded with
    `_rearm_elapsed`. This rule runs at the top of `_decide()`, before its REARM check, so a seeded REARM can still cascade into HOLD → LAUNCH on the same tick. A lone drone
    still on its way home does not hold it back: it docks during REARM (`dock()` clamps at 2) and REARM still completes (round 1's "stay" case dropped; logged in DECISIONS,
    review N12). None of t13's flows reaches APPROACH / HOLD with empty cradles, so t13's rows are unchanged.
- `start_engaged` (default false) skips the idle; t13's rows set it (step 1).

### C. Assault lives — the two measured exits

- **New helper `tests/helpers/ph8_exit_keys.gd`** (no `class_name`; callers `preload` it), the only place the two probes' arguments are built:
  - `static func drone_exit(host: Node) -> Dictionary` / `tender_exit(host: Node) -> Dictionary` → `SpecialistExitProbe.worst_disengage(host, load(scene),
    <Brain>.Phase.DISENGAGE, [config.exit_speed, 10.0], CAP, corridor_starts(host), prepare_probe)`, the speeds read from the shipped `.tres` (read only).
  - `const CAP := 20.0` (Ph5 / Ph7's `_PROBE_CAP`); `static func corridor_starts(host)`: an `ArenaCamera` added under `host` for `projectile_world_rect()` and freed,
    `AssaultCorridorConstraint.new().inner_rect()`, exactly `test_level1_specialist_spawns.gd::before_all()`'s construction; deterministic, so equal across calls.
  - `static func prepare_probe(ship: Node) -> void` — a **static function** (its `Callable` is `(ph8_exit_keys.gd, "prepare_probe")`, equal and equal-hashing on every
    reference; checked in a scratch project and by the reviewer: two references compare equal and hit the same `Dictionary` key; two identical lambdas do not). It runs
    before the ship is added to the tree, so it reaches the tree through `Engine.get_main_loop() as SceneTree` (review N3). It applies Ph7's gate-time rule 3: every node
    in group `player` leaves the group — the probe world's stub is the only player in the tree during `before_all()`; a row that calls it with its own harness player
    present loses that player's targeting for good, which the doc comment says. For the tender (`ship is LaserTender`) it also sets `drone_scene = null` so
    `LaserTenderBrain._setup()` skips instantiating and freeing a probe drone on each of the 2166 runs (`drone_config` is read only by `attack_b_points()`, never in
    DISENGAGE). **The saving is that line** (reviewer's measurement: tender probe 3.11 → 2.46 s); the stub strip saves nothing for either brain (3.20 vs 3.17 s), because
    neither reads the player in DISENGAGE — it is applied because the task asks for it, and row C3 pins that it is harmless (review N4).
  - **Speeds** (review N1): the **drone `[10.0]`** — its frameless DISENGAGE exits along its own velocity heading, so an `exit_speed` start flies the same straight path as the
    10 px/s start with the same heading and is ahead of it at every instant (measured by the reviewer: the same 5.37 s worst from the same start, 1083 runs, 1.65 s instead of
    3.20 s); the **tender `[exit_speed, 10.0]`** (2166 runs) — its heading points away from its exit edge, so the fast start is its worst (380 px/s against the exit exceeds
    anything it carries; `max_speed` 200; the reviewer's worst start is the 380 px/s one). §2.14 writes `[exit_speed]` and budgets ≈ 2166 runs per probe; the drone's single
    10 px/s speed is a logged deviation (DECISIONS), faithful because the slow start dominates and the reversal term below is measured against it.
  - **Drone start-velocity term** (context, last bullet): with a frame the drone exits along the rig's `-n`, and a FORM / BREAK drone can then carry up to `max_speed`
    (300; boosts are only along `-n` in ADVANCE or, frameless, along the exit in LAUNCHED) against it, which the probe cannot pose. That costs at most the kinematic
    reversal delay against a 10 px/s start: `(u + 10) / a + (u² − 10²) / (2 · a · V)` with `u = max_speed` 300, `a = acceleration` 900, `V = exit_speed` 420 =
    **0.46 s**. `ph8_exit_keys.gd` exposes it as `static func drone_reversal_seconds() -> float` (from the shipped config), and the drone's Assault exit bound everyone
    uses is `drone_exit()["seconds"] + drone_reversal_seconds()` (`drone_exit_bound(host)`). Logged in DECISIONS for t19, with the reviewer's note that it is slack:
    framed Assault exits are axis-aligned (`n` ∈ {UP, ±RIGHT}), so the worst framed exit (≈ 4.8 s with the term) stays under the probe's 5.37 s frameless diagonal; it is
    kept as a conservative bound, and row C4 ties it to the real mover. The probe's start set is untouched.
- **Memo proof:** `SpecialistExitProbe` gains `static var measured: int` (incremented once per `_measure_worst_disengage`), read by the memo row only.
- **Where they run:** once, in `before_all()` of `test_laser_tender.gd` (it pays for both); t19's `test_level1_specialist_spawns.gd` will call the same helper and get memo hits.
- **Stub check before relying on it** (step 5): neither brain reads the player in DISENGAGE (context); after t14 the new idle code is also skipped in Assault
  (`budget.active` → no `AnchorIdle`; the recall needs a controller that recalls, which an Assault tender never does). A row proves the trick changes nothing: one corridor
  start measured with and without `prepare_probe` gives bit-identical seconds.

### Alternatives rejected

- **The idle state on the rig (an `AnchorIdle` inside `TwinLaserPair`)**: §2.14 builds it in the leader's brain, and a lone survivor needs its brain's anchor anyway.
- **A real BREAK before every stand-down** (§2.14's "BREAK, return, IDLE" read literally): BREAK only matters after an attack, and an attack's own BREAK already
  runs (BREAK is busy, so the stand-down waits for it); outside an attack the beam is off and the drones simply fly home.
- **Bounding the drone exit with a straight line** (no probe): forbidden by §2.14. **Shrinking the start set or dropping the 10 px/s speed** to fit the budget: forbidden.
- **A drone → tender class reference for the recall**: a class cycle (the tender brain names the drone brain); duck-typed `recalls_drones()` instead (the `is_armored()` precedent).

## Build sequence

1. **Earlier rows engage explicitly.** `_pair()` (`test_twin_laser_drones.gd`), `_tender()` (`test_laser_tender.gd`) and the two `test_enemy_dual_mode.gd` cases set
   `start_engaged = true` on every brain they create, as the earlier brains' cases do. (Green before and after: the flag is inert until step 2/3.)
2. **Drone idle:** config "Idle" group + `.tres`; rig `IDLE`, `stand_down`, `engage`, `is_busy`, `idle_slot_angle`; brain `anchor_idle`, `_tick_anchor_idle`, mirror,
   motion, NOTICING blink, recall (with `_controller_live()`), lone SOLO orbit; spawner shares the anchor. The rig enum pin
   (`test_twin_laser_drones.gd::test_the_phase_enums_are_declared_in_full_and_in_order`) gains `"IDLE"` (review N8). Rows A1–A7 first (failing), then the code.
3. **Tender idle:** brain `anchor_idle`, idle family motion, idle rearm, APPROACH / HOLD unarmed rule, `_dock_returning` RETURNING; `LaserTender.recalls_drones()`.
   Rows B1–B8 first.
4. **`ph8_exit_keys.gd`** + `SpecialistExitProbe.measured`; `before_all()` in `test_laser_tender.gd`; rows C1–C4. Time each probe on its own (GUT `-gselect` of the file,
   and `Time.get_ticks_usec()` around each call, printed).
5. **Stub check** (grep both brains' DISENGAGE paths once more after steps 2–3) and row C3's identity.
6. `bash /agent/verify.sh`, `scripts/check-test-leaks.sh`, `scripts/gate-time.sh` (after); docs: both `ENEMY.md`, `docs/enemy-roster.md` if it lists behaviour,
   `assault.md` / `PROJECT.md` / `CLAUDE.md` lines for the idle and the helper, `DECISIONS.md` "built in t14", `tests/README.md` gate row.

## Test plan

All hand-ticked unless marked; the hub idle is Open Space only (Assault has no idle, asserted). `test_twin_laser_drones.gd`:
- **A1 `test_the_idle_config_and_the_cycle_radius_inequality`**: 650 / 1500 / 0.35 / 140 / 0.5 from the `.tres`; `perceive < lose`; the cycle's farthest distance
  `standoff + overshoot + L/2 + break_speed · break_seconds` (= 982) ≤ `lose_radius`, computed from config. **Boundary:** a duplicate config with `lose_radius` = cycle − 1 fails the same check.
- **A2 `test_an_open_space_pair_starts_idle_and_an_assault_or_engaged_pair_does_not`**: Open Space cold → after one tick of each drone rig IDLE, both brains IDLE, leader
  `anchor_idle` set, beam OFF; Assault → no `anchor_idle`, rig FORM; Open Space with `start_engaged` → no `anchor_idle`, rig FORM. Both drones' `patrol_anchor` = the spawner's position.
- **A3 `test_the_idle_rig_orbits_its_anchor_within_idle_radius_for_30_s_with_the_beam_off`**: player 2000 px away; 3 s to settle (the spawn is ± 210 px, outside the ring),
  then 30 s: every tick both drones within `idle_radius + 8` of the anchor, the two opposite (angle between them 180° ± 10°), the beam OFF and no `laser_wall` hazard
  registered, never NOTICING; the rig swept `idle_speed · 30 s` ± 10 %.
- **A4 `test_the_pair_notices_at_perceive_radius`** (cases `"inside"` / `"outside"`): from a settled idle, the player held each tick at the leader + (650 ∓ 1) px.
  Inside: NOTICING on that tick (rig `idle_state`, then both brains), both lenses blink (`CHARGING` right after `blink_once()`), the drones stop, and after `notice_time`
  (± 2 ticks) the rig is in FORM. Outside: 60 ticks, never NOTICING, rig IDLE.
- **A5 `test_beyond_lose_radius_the_pair_goes_home_and_idles`** (cases `"beyond"` / `"inside"`): an engaged pair (noticed, in FORM); the player teleported to the leader +
  (1500 ± 1) px. Beyond: next tick rig IDLE, both brains RETURNING, the beam OFF; within 6 s both drones back within `idle_radius + 8` and the brains IDLE. Inside (1499):
  30 ticks still fighting (rig not IDLE).
- **A6 `test_a_pair_whose_player_leaves_mid_advance_finishes_the_attack_first`**: lose radius crossed in ADVANCE → the rig runs ADVANCE → BREAK to their ends, then IDLE (busy boundary).
- **A7 `test_a_lone_drone_in_open_space_circles_its_anchor`**: B killed while idling → A SOLO; after 4 s of settling, 5 s within `idle_radius + 8` of the anchor, beam freed/cancelled.

`test_laser_tender.gd`:
- **B1 `test_the_idle_config_and_the_cycle_radius_inequality`**: 700 / 1600 / 0.35 / 160 / 0.5; `perceive < lose`; `preferred_range + launch_speed · launch_max_seconds` (= 1378)
  ≤ `lose_radius`. **Boundary:** `lose_radius` = 1377 fails.
- **B2 `test_an_open_space_tender_starts_idle_with_its_docked_pair`**: Open Space cold → IDLE, `anchor_idle` set, `docked_count()` 2, both `DockedDrone` shown, light OFF; Assault
  and `start_engaged` → no `anchor_idle`, APPROACH.
- **B3 `test_the_idle_tender_orbits_within_idle_radius_for_30_s_without_launching`**: player 2500 px away; from the anchor, 30 s within `idle_radius + 8`, no launch, docked 2, never NOTICING.
- **B4 `test_the_tender_notices_at_perceive_radius`** (`"inside"` / `"outside"`: 700 ∓ 1): inside → NOTICING (blink, stop, face) → APPROACH after `notice_time` ± 2 ticks;
  outside: 60 ticks IDLE.
- **B5 `test_beyond_lose_radius_the_tender_goes_home`** (`"beyond"` 1601 / `"inside"` 1599): beyond → RETURNING, then IDLE within `idle_radius` of the anchor; inside → for 30 ticks never RETURNING / IDLE (review N11: not "still APPROACH / HOLD", which a
  longer run could leave by launching).
- **B6 `test_a_launched_pair_flies_back_and_docks_when_the_tender_goes_home`**: engaged tender (via notice), launch, drones in FORM; player teleported beyond 1600 from the
  tender → the tender RETURNING, `recalls_drones()` true, both drone brains RETURNING within a tick of the rig leaving any busy phase; within 8 s both drones docked
  (`docked_count()` 2), neither emitted `died`, the beam never lethal after the recall.
- **B7 `test_a_tender_that_lost_its_pair_rearms_while_idle_and_on_re_engaging`** (cases `"idle"` / `"hold"`): the pair killed while the tender is in WAIT (it enters
  REARM), then the player teleported beyond `lose_radius` (the tender goes home mid-REARM); `"idle"`: cradles full again `rearm_seconds` (± 2 ticks) after the pair died,
  never earlier; `"hold"`: the player returns (inside `perceive_radius`) before that → NOTICING → APPROACH / HOLD with empty cradles enters REARM carrying the clock,
  full at the same time (± 2 ticks), and launches again (the unarmed rule; HOLD with empty cradles is never a dead end).
- **B8 `test_a_recalled_pair_whose_tender_dies_re_engages`** (review B1): a pair recalled (rig IDLE, brains RETURNING); the tender killed → on the leader's next tick the rig
  leaves IDLE (FORM) and both brains fight again; no error from a freed controller (the run continues 60 ticks).
- **C1 `test_the_measured_assault_exits_are_printed_and_under_10_s`**: from `before_all()`'s two results: printed (seconds, start, runs, capped, and each probe's own
  wall cost); `runs` 1083 (drone) / 2166 (tender), `capped` 0, drone `seconds + drone_reversal_seconds()` < 10, tender `seconds` < 10.
- **C2 `test_the_exit_keys_are_built_once_and_measured_once`**: calling `drone_exit()` / `tender_exit()` again leaves `SpecialistExitProbe.measured` unchanged and returns
  equal dictionaries; `prepare_probe` references compare equal. **Boundary** (on the Bomber's scene and `BomberBrain.Phase.DISENGAGE`, so the sweep below never flags this
  file; review N9): a one-start probe called twice with a fresh lambda as `prepare` measures twice, and twice with one static `Callable` measures once. **Source sweep**
  (per call, review round 2 B3): every `tests/**/*.gd` other than `ph8_exit_keys.gd` is stripped of comments (`test_enemy_mover_single_writer.gd`'s static `_code_only()`),
  then for each `worst_disengage(` call its argument text up to the matching closing parenthesis must not name `twin_laser_drone.tscn`, `laser_tender.tscn`,
  `TwinLaserDroneBrain` or `LaserTenderBrain`. A synthetic positive (a string holding such a call, run through the same checker) proves the sweep fires; this file's own Bomber
  boundary and `test_level1_specialist_spawns.gd`'s calls read clean.
- **C3 `test_the_stub_trick_leaves_the_exit_unchanged`**: one fixed corridor start per ship measured through `disengage_seconds()` in a fresh probe-shaped world, **first
  without** `prepare_probe`, then with it (the strip is permanent for that world) → identical seconds.
- **C4 `test_a_framed_drone_exit_against_its_velocity_costs_at_most_the_reversal_term`** (review N2): in an Assault harness, a hand-ticked bound pair whose rig frame is set
  to `n = UP` (exit DOWN) with drone A at a fixed start near the top of the corridor moving at `max_speed` UP; B is killed and A hand-ticked with the probe's loop until it
  queues itself; compared with a lone drone's `disengage_seconds()` from the same start heading DOWN at 10 px/s: the difference is > 0 (the reversal is real) and
  ≤ `drone_reversal_seconds()` + 1 tick (the term bounds it).
- `accepts_tow()`: the `test_base_enemy.gd` tow table already covers IDLE / NOTICING / RETURNING as accepting phases for both brains (no new entry).

## Gate time

Allotment 8.5 s (rows 1.0, drone probe 3.5, tender probe 4.0). Rows: A3 / B3 are the only long ones (≈ 1800 ticks × 2 / × 1 bodies); the rest are short hand-ticked runs.
If a probe overruns: first confirm `prepare_probe` ran (the stub out of group `player`; `drone_scene` null), then share work across the scenario (e.g. one harness world
already is); never shrink the start set. Over 238 s total → `Result: ESCALATE`.

## Risks

- **AnchorIdle on the leader only**: the follower can be nearer the player than the leader, so the pair notices up to `L` later than a single ship would. Accepted (one clock;
  §2.14 says "built in the leader's brain").
- **A pair that loses its leader while idling**: the pair breaks (as any death does), the survivor orbits alone; it never re-pairs. Same as combat today.
- **Drone exit reversal term**: an analytic addition to a measured figure; it is an upper bound of a straight-line kinematic delay, not a replacement for the measured
  path. If the reviewer prefers, the alternative is a test-only start-velocity hook on the probe (a `prepare` that leaves a frame), which would need the rig in the probe world.
- **t13 rows**: `_tender()` / `_pair()` now pass `start_engaged`; any t13 / t12 row that spawned without those helpers is found by running both files before step 2.

## Out of scope

- Placing pairs / tenders in the hub (t18) or level 1 (t19, which reuses `ph8_exit_keys.gd`); art (t16); docs beyond this task's lines (t20).

## Revision 1 (answering review round 1)
B1 fixed (recall needs a live controller with `recalls_drones()`; else the leader engages; row B8). N1 drone speeds `[10.0]`; N2 row C4; N3 `Engine.get_main_loop()` + `ship is LaserTender`; N4 saving attributed to `drone_scene = null`; N5 `has_method`; N6 one rearm clock carried across REARM and the idle phases, B7 rewritten; N7 idle motion before the no-target return; N8 enum pin; N9 boundary on the Bomber; N10 lone SOLO orbits regardless of `start_engaged`.

## Revision 2 (answering review round 2)
B2: the rearm clock rule worded exactly (reset only on full cradles or a live pair, advance only in idle phases, never reset by a phase change, consumed on use, REARM seeded after `enter_phase()`). B3: the C2 sweep checks each `worst_disengage(` call's own arguments after stripping comments, with a synthetic positive. N11: B5 inside asserts "never RETURNING / IDLE". N12: the dropped "stay" case is logged in DECISIONS.
