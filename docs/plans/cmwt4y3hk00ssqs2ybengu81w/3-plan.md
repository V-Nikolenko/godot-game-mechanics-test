# t6 — Space Fortress movement (task plan)

The approved design is the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.6 (with §2.5.5's §25 row and §2.16's numbers). This file does
not redesign it: it fixes the points §2.6 leaves to the implementer, the build order and the concrete test rows.

## Problem
The fortress shell (t5) never moves or turns: a player can park on one side. This task makes it a 360° fight: the hull keeps its strongest sector turned
toward the player at a turn rate a circling player out-runs (so circling reaches the weak side), spins during volleys and continuously in `critical`, drifts
round a combat zone in Open Space from `core_exposed` on (always away from where the player will be), and in Assault descends to a hold, then bobs
vertically with x fixed. Nothing fires yet (t7 / t16); `is_engaged()` becomes real so they can gate on it.

## Design (only what §2.6 leaves open)

**Config** (`space_fortress_config.gd/.tres`, new group `Movement`, all flat): `turn_rate` 0.22, `assault_turn_rate` 0.30, `beam_spin_rate` 0.5, `critical_spin_rate`
0.6, `idle_spin_rate` 0.08 (rad/s); `perceive_radius` 1400, `lose_radius` 2600, `notice_time` 0.8, `home_radius` 8; `zone_radius` 600, `station_ring_factor` 0.6,
`reposition_min_step` 250, `reposition_lookahead` 1.0, `reposition_period` 8.0, `critical_reposition_period` 5.0, `reposition_speed` 60, `critical_reposition_speed`
90, `hold_tolerance` 24, `hold_speed` 40; `assault_enter_speed` 90, `assault_hold_y` 180, `assault_bob_amplitude` 100, `assault_bob_speed` 35,
`critical_bob_speed` 55, `assault_x_correct_speed` 20. (The return to the anchor uses `reposition_speed`.)

**Scene:** `EnemyMover` authors `turn_lerp = 0.0` explicitly (equal to the script default, but authored so a gate reading the `SceneState` sees the intent) and
keeps `acceleration` / `braking` 0 (instant velocity: holds, arrivals and the bob end exactly; a 1500 HP hull at ≤ 90 px/s does not need a ramp).

**Brain (`fortress_brain.gd`)**, Carrier-shaped:
- Fields: `patrol_anchor` (INF → spawn position in `_start()`), `start_engaged`, `assault` (read in `_start()`, and lazily in `on_boss_phase()` which runs from
  the root's `_ready()` before the first tick), `anchor_idle` (OS and not `start_engaged` only; the Carrier rule: a `start_engaged` fortress has no leash), the
  station point, the reposition clock, the bob direction, the presented side, the spin direction.
- `_start()` (first tick): OS → `HOLD` (start_engaged) or `IDLE` with `AnchorIdle(anchor, 1400, 2600, 0.8, home_radius)`; Assault → `ENTER`, or `HOLD`/`REPOSITION`
  at once if already at or below `assault_hold_y`.
- **Per-boss-phase settings** (written only in `on_boss_phase()`; these are the movement snapshot): `translation_mode` (`&"hold"` in `batteries` /
  `shields_exposed`; `&"reposition"` OS or `&"bob"` Assault from `core_exposed`), `spin_mode` (`&"face"`, `&"volley"` from `shields_exposed`, `&"continuous"` in
  `critical`), `reposition_period` (OS 8.0 / 5.0; 0 while holding and 0 for the bob), `travel_speed` (OS 60 / 90, Assault bob 35 / 55; 0 while holding).
  `movement_snapshot()` returns `[translation_mode, spin_mode, reposition_period, travel_speed]`. Entering `core_exposed` / `critical` zeroes the reposition clock
  (a new station point on the next engaged tick).
- `is_engaged()` = `phase` HOLD or REPOSITION. Engaged OS / Assault phase = HOLD while `translation_mode == &"hold"`, else REPOSITION (switched on the tick).
- **Facing** every tick (a face point is always requested, else travel would yaw the hull to its heading):
  - engaged and `spin_mode == &"continuous"` → spin at `critical_spin_rate` (direction: the next alternation when `critical` was entered);
  - engaged and a volley spin running (`begin_spin(direction := 0)`: 0 takes the next alternation, ±1 is explicit and becomes the last; `end_spin()`) → spin at
    `beam_spin_rate`; `spinning()` / `spin_direction()` read it;
  - OS `IDLE` (or no player) → idle spin at `idle_spin_rate` (OS) / hold the current facing (Assault, no player);
  - otherwise the facing rule at `turn_rate` (OS) / `assault_turn_rate` (Assault).
  A spin = `face_toward(pos + Vector2.from_angle(heading + dir · 1.0) · FACE_REACH)` with `mover.max_turn_rate` = the rate (heading = `rotation +
  sprite_forward_angle`). **`FACE_REACH` = 10 000 px**, not §2.6's illustrative 100: only the direction matters, and in a hand tick the mover measures the face
  point from the position `move_and_slide()` reached with the idle delta, so a short lever skews the target by up to ~0.05 rad on a slow machine (review R1-4).
- **`present_side() -> StringName`** (`&"north"` / `&"south"`): strength = live batteries of the sector × (1.0 while its generator lives, 0.5 once destroyed);
  the larger wins, a tie keeps the current side (initially the larger at start: south, 3 vs 2). `sector_strength(side) -> float` is public for the row. Facing
  point: `pos + Vector2.from_angle(bearing_to_player - local_bearing + sprite_forward_angle) · FACE_REACH`, local bearing north −π/2 (270°), south +π/2.
- **OS**: `AnchorIdle.update()` each tick (when built): IDLE → hold the anchor (`hold_position(anchor, home_radius / 2, hold_speed)`), idle spin; NOTICING →
  hold, facing rule; COMBAT → HOLD / REPOSITION; RETURNING → `arrive(anchor, reposition_speed)` with the facing rule, not engaged; on reaching IDLE the station
  point resets to the anchor (boss phase untouched). HOLD: `hold_position(station_point, hold_tolerance, hold_speed)`. REPOSITION: the clock counts down only
  while engaged; at ≤ 1e-6 it adds the period and picks; travel = `arrive(point, travel_speed)` until within 2 px, then `hold_position(point, hold_tolerance,
  hold_speed)`.
- **The pick (`pick_station_point(current, player_ahead) -> Vector2`, a public instance method: it reads the anchor and the config):** candidate k = `anchor +
  Vector2.from_angle(k · TAU / 8) · station_ring_factor · zone_radius`, k = 0..7; keep those ≥ `reposition_min_step` from `current`; the one with the largest
  distance to `player_ahead` wins, a later candidate only when farther by more than `PICK_EPS` 0.001 px, so the lowest index wins ties; none → `current`. `player_ahead` = `TargetInfo.predicted_position(reposition_lookahead)`;
  no player → no pick. Candidates lie on a 360 px circle inside the 600 px zone, so the leash holds by construction (the row asserts it anyway).
- **Assault**: `ENTER` requests `(x_fix, assault_enter_speed)` until world y ≥ `assault_hold_y`. HOLD: `vy = clamp((hold_y − y) · 4, ±assault_enter_speed)`.
  REPOSITION (bob): `vy = dir · travel_speed`, clamped so one step never passes `hold_y ± amplitude` (it lands on the end, then reverses; first direction +1, down
  toward the player). `x_fix = clamp((anchor_x − x) · 4, ±assault_x_correct_speed)`. All one `request_velocity()`.
- **Thrusters:** `Thrusters.visible` stays the root's phase-driven flag (t5; the snapshot reads it). "Visible while travelling" is the brain's
  `is_travelling()` (REPOSITION moving, RETURNING, ENTER) written as `Thrusters.modulate.a` 1.0 vs `THRUSTER_IDLE_ALPHA` 0.35, so the §25 visuals key never moves
  with travel (logged in DECISIONS for t9's art).
- **EMP:** nothing new — the base rule halts the mover and skips the brain; with no request the mover writes zero velocity and no rotation. `on_emp_started()` keeps
  t5's body.

**Root:** no change beyond what the brain needs (`on_boss_phase` already called). `test_space_fortress.gd`'s config row gains the new fields.

## Build sequence
1. Config fields + `.tres` values; scene `turn_lerp = 0.0`.
2. Movement rows in `test_space_fortress.gd` (watch them fail).
3. Brain: settings, `_start`, facing / spins, OS zone + leash, Assault enter / hold / bob, thrusters.
4. §25 row: movement key + exact per-phase arrays; config row; shell row's "not engaged until t6" message.
5. Gate time (two-run mean), `ENEMY.md` / `assault.md` lines, DECISIONS `### Phase 11, built in t6`.

## Test plan (`tests/integration/test_space_fortress.gd`, movement block; hand-ticked with the Carrier's `_tick`, both harnesses unless noted)

Spawn rule for these rows: Open Space at (640, 360) as t5; **Assault at (640, 180)** (on the hold line) unless the row is about the entry; the spawn x is read
after `_ready()` (world anchoring may shift it). Expected values (candidates, rates, speeds) are computed **by the test from the shipped config**, never by calling
the brain's own helpers.

1. **OS idle** (OS only: Assault has no idle): a non-engaged fortress holds the anchor ± 8 px for 20 s and turns exactly `idle_spin_rate · dt` per tick; a player
   at 1450 px stays unnoticed for 2 s (IDLE); at 1390 px it is NOTICING and not engaged on the next tick, and HOLD + `is_engaged()` within `notice_time` + 2 ticks
   (a range: 48 or 49 ticks, float accumulation).
2. **Facing:**
   - two south batteries dead (north 2 > south 1): presented side north; while turning, every per-tick change **equals** the mode's rate × dt (OS 0.22, Assault
     0.30; 1e-5 tolerance) until it settles, and the north side ends within 0.01 rad of the player bearing; then both north batteries die (north 0 < south 1) →
     south presented and the large turn again runs at exactly the mode's rate per tick, ending with the south side on the player;
   - `present_side()` cases on fresh fortresses: start (south 3 vs north 2) → south; **halving flips the side**: south generator dead (south 1.5 vs north 2) →
     north; **ties keep the current side from either side**: (a) from south, one south battery dead (2 vs 2) → south stays; (b) from north (two south batteries
     dead, north presented), north generator dead (north 1.0 vs south 1.0) → north stays;
   - **circling wins:** reads each player scene's `cruise_speed()` (instantiated, not added to the tree: OS `player_ship.tscn`, Assault `player_fighter.tscn`),
     asserts `rate × 500 < 0.5 × speed`, then circles a player at 500 px at `speed / 500` rad/s for 4 s: the angle between the presented side and the player
     grows at every 0.5 s sample and passes 1.5 rad. Boundary: the same player circling at `0.5 × rate` keeps it within 0.1 rad.
3. **Phases:**
   - `batteries` and `shields_exposed`, 10 s each with a player moving round: OS ≤ `hold_tolerance` from the station point (the anchor); Assault within 1 px of
     (anchor x, 180);
   - `core_exposed` OS, a chasing stub (moves toward the fortress at 300 px/s, stops at 300 px; velocity set so the prediction is live) for 60 s: the test builds
     the 8 candidates itself from the shipped config (`anchor + from_angle(k·TAU/8) · 0.6 · 600`), filters ≥ 250 px from the old point, takes the farthest from
     the player's position + velocity × 1 s captured before the tick (lowest index within 0.001 px); every station-point change equals it, is ≥ 250 px from the
     old point and inside the zone; the number of picks is exactly 8 (t = 0, 8, …, 56 s); every hull position stays inside the zone;
   - boundary: old point = the farthest candidate from a stationary player → the new pick is **nearer** the player than the old one and equals the test's rule;
   - `critical`: consecutive picks 300 ± 1 ticks apart, and the travelling speed is 90 (`|velocity|` while en route).
4. **Leash (OS):** a non-engaged fortress engaged in `core_exposed`, moved off the anchor by a reposition; the player goes to 2700 px → RETURNING (not engaged),
   arrives home → IDLE within `home_radius`, station point back at the anchor; `phase_driver().current_id()` unchanged throughout.
5. **Assault (Assault only):** spawned above the view (y −260) it enters at 90 px/s (|vy| = 90 while entering) to y 180 and holds there; then 15 s in each boss
   phase (60 s total): x within 1 px of the spawn x on every tick; **x correction:** the hull pushed 30 px off its x returns at ≤ 20 px/s and settles within
   1 px; from `core_exposed` y stays within [80, 280] and reaches both ends (bob); with the player below, killing two south batteries turns the presented side
   north and the rotation follows at the Assault rate. Facing assertions run under `await _fresh_idle_delta()` (the Ph10 helper, copied) with no physics-frame
   await after it.
6. **Spin:** the instanced scene's `EnemyMover.turn_lerp` resolves to 0 (value, not the `.tscn` line: an editor save drops a default); `begin_spin()` turns at
   exactly `beam_spin_rate` per tick, the next `begin_spin()` turns the other way; `end_spin()` returns to the facing rule; in `critical` the hull turns at
   `critical_spin_rate` (0.6 ≠ 0.5) every tick for 3 s whatever the player does. Boundary: with `turn_lerp` 0.3 written on a second instance's mover, the same
   volley spin turns at ≈ 0.3 rad/s, not 0.5 (the lerp runs before the cap), so the value is load-bearing.
7. **EMP:** engaged, moving (OS REPOSITION en route, Assault bob) and spinning, `apply_emp(5)`: for the 2 s window position and rotation are unchanged on every
   tick; after it both move again.
8. **§25 movement key:** `_assert_declared_changes` gains `MOVEMENT: &"movement"`; in both modes the movement array per phase equals the literal (OS `[hold, face,
   0, 0]` → `[hold, volley, 0, 0]` → `[reposition, volley, 8, 60]` → `[reposition, continuous, 5, 90]`; Assault `[hold, face, 0, 0]` → `[hold, volley, 0, 0]` →
   `[bob, volley, 0, 35]` → `[bob, continuous, 0, 55]`); the "one battery / one generator changes nothing" boundaries still hold.
9. **Thrusters:** `Thrusters.modulate.a` is 1.0 while the hull travels (OS REPOSITION en route, Assault ENTER and bob) and `THRUSTER_IDLE_ALPHA` while it holds
   (OS HOLD, Assault HOLD), and `Thrusters.visible` (the snapshot's) is unchanged by either.

Single-writer gate (`test_enemy_mover_single_writer.gd`) must stay green (requests and mover limit fields only).

## Risks
- Hand-ticked `move_and_slide()` moves by the idle delta: the `_tick` helper writes the position from velocity × dt (Carrier precedent).
- GUT time: ~20 000 hand ticks in total; measured after step 3, Assault row trimmed to 15 s per phase if needed.
- `on_boss_phase(batteries)` runs before the brain's first tick: the mode is resolved lazily there.

## Out of scope
Weapons, `attack_gate()` (t7), spoke volleys / ring (t16 calls `begin_spin` / `end_spin`), bays (t8), art (t9), level / hub placement (t10 / t13).
