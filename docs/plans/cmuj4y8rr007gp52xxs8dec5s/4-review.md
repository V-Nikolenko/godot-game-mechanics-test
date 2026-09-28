# Task plan review, round 1

VERDICT: CHANGES_REQUESTED

The plan follows the epic closely and gets most of the mechanics right against the real code. These all check out:
the Swarm `enter_phase()` / lazy `_start()` / bounded `for _i in 4` chain precedent
(`swarm_drone_brain.gd:192-233, 252-260`); `AttackController` with a null pattern at `_ready()`
(`attack_controller.gd:21-26`, which guards with `is_instance_valid`) and `fire_now()` ignoring `enabled` (`:44-46`);
the `BulletPool` grandparent container (`bullet_pool.gd:44-48`, which also has a scene-authored precedent at
`space_station.tscn:131-142`); RAMMING arming with `_armed` set synchronously (`contact_profile.gd:79-83, 116-125`), so
a hand-emitted `area_entered` while armed does reach `contact_made`; and the scene-authored nodes against the
gates. `StateLight` builds its texture in code, the config stays flat, the brain writes no `.velocity`/`.rotation`,
and the Razor root body (mask 1) does not collide with the player body (layer 4).

I replayed the numbers headless (`/tmp/rv/sim*.gd`), using an exact copy of `EnemyMover.step()`'s `move_toward`
accel/braking rule and the real `Steering.orbit`/`turn_toward`/`hold_position`:
- The overshoot works as specified. It turns about 145° in 1.2 s, keeps its speed at 200 px/s or more, and never
  turns by more than `3.0·δ` in a tick (max 0.0500002 rad). It always exits on the 1.2 s timeout, not the 20° rule, at
  about 308 px from the player.
- The B5 pin holds: 2.4 rad.
- The feint's end bearing does exceed 120°.

The problems are elsewhere: some design premises are wrong, and two acceptance criteria are not guaranteed by the
mechanism as written.

## Blocking

**B1. `test_engagement_deadline.gd` does not do what the plan says it does.**
- *The plan's claim* (Build sequence step 4): the test "evaluates a Razor spawn with the Razor config, so a Razor added
  to an ENEMIES_CLEARED section fails the test, as the epic §2.6 says it will".
- *What the file does:* it evaluates every spawn in `DRONE_OR_RAZOR_SCENES`, Razor included, with `SWARM_CONFIG`
  (`test_engagement_deadline.gd:15, 25, 28-32, 100-101`). A Razor added to cloud_descent today evaluates to 9.58 s
  against the 10 s limit and **passes**.
- *Why it matters:* the plan also defers budget expiry through a boost. That makes the Razor's real worst case
  `9.0 + 0.9 (max_dash_seconds) + 2.51 + 0.18 + 0.5 + 0.8` ≈ 13.9 s. The guard that DECISIONS "Conventions" and epic
  §2.6 promise ("the same test fails if a Razor is added to an ENEMIES_CLEARED section") therefore does not exist.
- *Required:*
  - Add `test_engagement_deadline.gd` to the change list.
  - Pick the config per scene (Razor → `razor_drone_config.tres`, with its own `acceleration`).
  - Add a `max_dash_seconds` term for the Razor, because its expiry is deferred through a dash and the Swarm's
    `can_start_attack()` gate does not apply to it.
  - Add a boundary case: a synthetic Razor entry in an ENEMIES_CLEARED section must fail the formula. Without it, the
    guard can silently regress again.

**B2. The side-lane check does not guarantee the lane at DASH entry, which is where the test asserts it.**
- *Where the check runs:* ORBIT, at the roll (plan "Side lane").
- *What happens next:* the drone then holds at `_hold_at`, its stopping point.
- *Why that breaks the lane:*
  - At the roll the drone is moving at `orbit_correct_speed` (160 px/s). It saturates because the anchor moves at
    1.8 × 130 = 234 px/s.
  - Braking at 700 px/s² from that speed carries it about 18 px further.
  - The orbit it actually flies is about 82–110 px from the player (see B3), so those 18 px are about 10–12° of
    bearing.
- *Effect on the test:* a roll that fires inside the last ~11° of a lane dashes outside it. That is about a quarter of
  the lane's 45° width. `test_the_assault_dash_bearing_is_in_the_side_lane` asserts [30°, 75°] at DASH entry over
  several seeds, so it will fail on some seeds, or pass only on hand-picked ones.
- *Required:* evaluate the lane against the bearing of the point the dash will actually start from (`_hold_at`,
  computed at decision time), or narrow the check band by the drift and state the margin. Then keep the DASH-entry
  assertion.

**B3. The feint geometry assumes a 130 px orbit, but the drone actually orbits much closer, and at 25° the fake lunge
passes through the player.**
- *What the drone actually does:* `Steering.orbit` caps its correction at `orbit_correct_speed` 160 px/s, and the
  anchor runs at 234 px/s, so the drone lags inside the ring.
  - Measured with accel 900 / braking 700 over seeds 1, 2, 3, 4, 5, 42 and 100: settled distance 82–110 px, not 130.
  - The feint starts 88–110 px out.
  - The existing pin already hints at this: `test_razor_drone.gd:258-262` asserts `min < orbit_radius`.
- *What that does to the 25° lunge:*
  - Closest approach is **37–46 px** centre to centre, not the ≈55 px the epic claims and the plan repeats.
  - The Razor's `ContactHitBox` radius is 3.08 × 10 = 30.8 px (`razor_drone.tscn`, CircleShape2D default radius
    × scale). The player fighter's hurtbox is 5 × 2.7 = 13.5 px (`player_fighter.tscn:283-343`). Together that is
    44.3 px.
  - So on most seeds the fake visibly flies through the player and nothing happens. That breaks the epic's own
    rationale ("passes beside the player … clear of a 20 px hull plus the player's hull") and the task item "lunge
    past".
- *Why this is not a simple retune:* the end bearing trades off against clearance.

  | Offset | End bearing | Clearance |
  |---|---|---|
  | 25° | 138–143° | fails |
  | 35° | 124–130° | 51–63 px (passes) |
  | 40° | 117–124° | 57–70 px, but the bearing fails > 120° |

- *Required:*
  - Correct the geometry section to the measured orbit.
  - Choose values that meet **both** conditions with a stated margin. Options:
    - aim the lunge at a point a fixed clearance beside the player, rather than at a fixed angle;
    - lengthen `feint_lunge_seconds` together with a larger offset;
    - raise `orbit_correct_speed` so the drone really flies at 130.
  - Record the change in DECISIONS as a deviation from the board's "25°".
  - Add an assertion to the fake case: minimum centre distance during FEINT_LUNGE/FEINT_BRAKE ≥ the contact hitbox
    radius + a player-hurtbox constant.
  - Restate the orbit case's band from these measurements. ±40 px around 130 fails on seeds 4 and 42 (88 and 82 px).

**B4. The post-feint real dash skips the Assault side lane, and nothing tests it.**
- *The conflict:* the plan rejects a lane check after the feint. Epic §2.8.2 says a dash "only commits when the
  drone's bearing from the player is within a side lane", and the acceptance criterion is general.
- *Why it happens:* the feint sweeps about 124–143° round the player. From a lane bearing that can land in the
  vertical gap. For example, starting 60° from horizontal and sweeping about 140° ends 10° off vertical, so the real
  dash is almost straight up or down the screen.
- *Required:* satisfy both epic rules without an orbit leg. In Assault, choose the lunge side (the sign of the offset,
  which also sets the `orbit_dir` flip) so that the predicted far-side bearing (start bearing ∓ the measured sweep)
  falls in a lane. Alternatively, veto the fake at roll time when neither side lands in one.
- *Test:* add an Assault case with a forced `fake` over several seeds, asserting the dash-entry bearing is in
  [30°, 75°].

## Non-blocking

- **N1. The reversal "boundary" bound is not a real bound.**
  - The drone's angular velocity changes by more than `acceleration·δ / r` per tick: I measured up to 0.006 rad/s over
    it, because `ω = cross(rel, v) / r²` also moves with the radial speed.
  - Assert on the quantity the mover actually bounds instead: `|Δv| ≤ max(acceleration, braking)·δ + 1e-3` per tick,
    plus the sign change of ω.
  - Also state ε explicitly.
- **N2. The reversal-frequency rule differs from the epic and is untested.**
  - Epic: "at most once per window". Plan: once per attack cycle. The plan's rule is better (it prevents endless
    reversing), but record it as a deviation.
  - Add a case: after a forced `reverse`, the next unforced roll cannot pick REVERSE.
- **N3. The lunge sign convention should be spelled out.**
  - In Godot, `(to_player).rotated(+25°)` with the anchor at `RIGHT.rotated(angle)` passes the player on the side
    *opposite* the orbit tangent. The drone therefore sweeps round in −`orbit_dir`, and flipping `orbit_dir` continues
    that sweep. That is self-consistent.
  - Epic's "toward orbit_dir" reads the other way. Write the sign into the plan, and assert in the fake case that the
    post-feint ORBIT direction matches the sweep.
- **N4. Mechanisms without a test.** Each can regress silently:
  - deferring DISENGAGE through a boost: expire the budget mid-DASH, and assert the DASH completes and DISENGAGE
    starts on the first tick after the boost;
  - the `FEINT_BRAKE_MAX_SECONDS` and `RETURN_MAX_SECONDS` caps;
  - the player freed mid-cycle, in WINDUP, OVERSHOOT or RETURN: the plan only covers a missing target in ENTER.
- **N5. `test_a_miss_fires_exactly_one_pulse`** should also check:
  - the bullet's direction points at the player;
  - its `HitBox.damage` equals `pulse_damage`.

  Take the pool count right after OVERSHOOT entry, as well as at the end.
- **N6. `test_contact_outside_the_dash_is_ignored`** only re-tests `ContactProfile`. Also assert `dash_hit == false`
  and health unchanged, so it pins the Razor's own wiring.
- **N7. `on_suspended()`.**
  - `BaseEnemy.suspend_ai()` arms the RAMMING profile (`base_enemy.gd:121-122`). The Swarm sets its light to ARMED
    there (`swarm_drone_brain.gd:236-237`).
  - State the Razor's choice, even though no Razor rides a rail today (`test_station_reinforcements.gd:320-325`).
- **N8. Stale comments.**
  - `swarm_drone_brain.gd:536` references `RazorDroneBrain._check_dash_end()`, which this task removes. Repoint it
    at the Swarm's own rule.
  - The `razor_drone.gd` / `razor_drone_brain.gd` headers describe the Phase 1 kamikaze.
- **N9. The pulse is lost when the budget expires mid-DASH**, because DISENGAGE replaces OVERSHOOT. That is fine, but
  say so in the plan so nobody reads it as a bug.

# Task plan review, round 2

VERDICT: APPROVED

Approved **with binding amendments A1–A5 below** (same form as t8c's "approved round 2 with amendments"). Each is a
precise edit. Apply them to `3-plan.md` before implementing, and record them in `5-progress.md`. Every round-1
finding is otherwise answered correctly.

## What I re-verified

I re-ran the headless replays (`/tmp/rv/sim4.gd`–`sim9.gd`): an exact copy of `EnemyMover.step()`, the real
`Steering.orbit`/`hold_position`/`turn_toward`, and the boost counted down per tick, as `_boost_left -= delta` does.

- **Orbit at `orbit_correct_speed` 260.** It settles at 117–119 px on all seven seeds. The anchor is catchable, and
  the new config pin is right.
- **Lunge aimed 70 px beside the player.** Measured from the lunge's start point, the closest approach is 61.7 px
  and the sweep is 128.3°, on both sides and every seed. Both match the plan exactly. The lunge runs 28 ticks
  (168 px) rather than 27, because of float accumulation; the numbers already include that.
- **Lane prediction.** The predicted far-side stop lands within 3–7 px of the actual stop, which is ≤ 2.3° of lane
  angle. That is inside the 3° margin, provided the hold uses a finite speed (A3). The `_hold_at` prediction for a
  real dash lands within 2–4 px, also inside the margin.
- **Lane-side selection for fakes.** Trying the default side and then the other is sound. The two candidates sit
  about ±128° about the player, and a stale choice waits in ORBIT, as a real one does.
- **Sign convention.** With `to_player.rotated(s·PI/2)`, the lunge passes on the side *opposite* the orbit tangent,
  and the sweep runs in the `−s` sense. The plan's rule "sweeps round in `−s`, then `orbit_dir = −s`" is correct.
  Its prose "passes on the side of the direction the drone was orbiting" is backwards; fix that wording.
- **Deadline test.** `test_engagement_deadline.gd` now picks its config per scene and adds a boundary case. That
  fixes B1's structure. The B1 formula itself is not a bound; see A4.

## Amendments

**A1. Where the > 120° sweep is measured from (blocking as written).**

*Problem:* the test "bearing at WINDUP entry vs bearing at FEINT_WINDUP entry > 120°" **fails on the default side**.
- On FEINT_WINDUP entry the drone is doing about 234 px/s. It holds at its stopping point, which is about 39 px
  further along the orbit.
- That drift is about 17° in the `+orbit_dir` sense. The default lunge (`s = orbit_dir`) then sweeps in `−s`, against
  the drift.
- Measured from FEINT_WINDUP entry, the sweep is therefore **111.3°** for `s = orbit_dir` and 145.3° for
  `s = −orbit_dir`, on every seed. The Assault lane rule can pick either side, so both harnesses are exposed.

*Edit:*
- In the FEINT_BRAKE "Measured geometry" bullet and in `test_the_fake_passes_beside_and_ends_on_the_far_side`, measure
  the sweep from **the bearing at FEINT_LUNGE entry** (the point the feint holds at and lunges from): > 120°, measured
  128.3°.
- Add one sentence to DECISIONS stating this reading of "ends > 120° round from where it started". The epic's N5
  number (≈ 130°) was computed from the lunge start, so this is the epic's own geometry.

**A2. Re-anchor the orbit on ENTER → ORBIT (blocking for the orbit band, and for real play).**

*Problem:* `_orbit_angle` is drawn at random in `_ready()` and is never re-anchored on the first ORBIT entry. The
anchor can therefore start on the far side of the player.
- Measured from a (130, 0) spawn: the first second's distance spans **16–130 px**. Seed 1 flies straight through the
  player. The second second still spans 82–135 px.
- So `test_orbit_holds_the_radius` (± 15 px from 1 s to 2 s) fails on seeds 1 and 42.
- A window can roll a feint or a real dash at 1.0 s, straight out of that chase, which voids the feint geometry and
  the lane prediction.

*Edit:*
- In ENTER, on the transition to ORBIT, set `_orbit_angle = (actor.global_position − orbit_centre).angle()`, as
  RETURN and FEINT_BRAKE already do. Keep the `_ready()` draw so the rng sequence is unchanged.
- Measured with the re-anchor: 119–130 px within the first second, and 103–127 px even when arriving at 200 px/s
  inward. The drone is settled by 1 s.
- Restate the orbit case: *"from 0.5 s after ORBIT entry until the phase first leaves ORBIT, the distance stays in
  `orbit_radius` − 15 … + 15"*. The current "1 s settle + 1 s" runs past the 1–2 s window, so the roll would end the
  orbit mid-measurement.

**A3. The hold speed.**

*Problem:* the plan never says what max speed FEINT_WINDUP/WINDUP pass to `mover.hold_position(_hold_at, 4, ·)`. The
Razor's mover has `max_speed` 0 (uncapped). With an unbounded argument, `Steering.arrive` stops about 18 px short of
`_hold_at`, and the lane prediction error grows to 7–8°, well beyond the 3° margin.

*Edit:* specify `mover.hold_position(_hold_at, HOLD_TOLERANCE 4.0, orbit_correct_speed)`. This is the measured case
above: gap 2 px, prediction error ≤ 2.3°.

**A4. The Razor deadline formula is not an upper bound.**

*Problem:* after a deferred dash the drone can be moving at 480 px/s *away* from its chosen exit edge.
- It brakes (700) down to 320, then accelerates (900) through to +320.
- That takes 0.94 s and loses 91 px, so the exit takes about 3.74 s.
- The plan's terms (`dash_speed/braking + exit_distance/exit_speed + exit_speed/(2·acceleration)`) give 3.38 s: an
  under-estimate.

*Edit:* use this conservative form for the Razor:

`last_delay + engage_seconds + max_dash_seconds + (dash_speed + exit_speed) / min(acceleration, braking) +
(exit_distance + dash_speed² / (2·braking)) / exit_speed + margin`

That is 0.8 + 9.0 + 0.9 + 1.14 + 3.03 + 0.5 ≈ **15.4 s**. Update the boundary case's quoted number to match; it must
still exceed 10 s.

**A5. `test_the_feint_brake_cap` setup.**

*Problem:* setting `braking = 1` on the private config before spawn also sets `_hold_at = pos + v̂·|v|²/2`, which is
tens of thousands of px away. The drone never holds, and the case tests nothing.

*Edit:* connect to `phase_changed`, and write `mover.braking = 1.0` on the mover itself (a test-side field write) only
when FEINT_BRAKE is entered. Then assert WINDUP entry at `FEINT_BRAKE_MAX_SECONDS` ± 1 tick.

## Non-blocking
- Fix the FEINT_LUNGE prose: the lunge passes on the side opposite the orbit tangent. The formula, the `−s` sweep and
  the `orbit_dir = −s` rule are already right.
- The lane prediction's boost length is `ceil`-ish, not exact: 28 ticks rather than 27, from float accumulation. The
  3° margin absorbs it; add a comment so nobody tightens the margin.
