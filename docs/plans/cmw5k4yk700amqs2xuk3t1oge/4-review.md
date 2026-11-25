VERDICT: CHANGES_REQUESTED
# Review: Hijack Pulse (Phase 9 t9), round 1

Reviewed `3-plan.md` and `1-context.md` against epic §2.5, §2.10, §2.11, §2.15, §2.18 and "For every task", and against the code on `agent/auto-dev`
@ 46c9c09. The design is sound and follows §2.11: no-area dart, `BulletPool` with no persist, `ProjectileLifetime` 1.6 s / 1400 px, cap counted in
darts, hook at PULSE end, the LOS precedent from `LaserTenderBrain`. The row list covers every acceptance criterion. Three problems block approval: one
design finding the plan buries, one behaviour with no row (and the t8 edit hides it), and one fairness row whose geometry and fallback are not
fixed. The rest are small fixes.

## What I checked and found correct (no action)

- **Receding rocket (row 5).** Tick order is Hacker, rocket + lifetime, dart + lifetime, and the dart checks, moves and claims before its lifetime runs.
  The rocket is at 650 + 8.333 n px and the dart at 15 n px, so the gap is 650 − 6.667 n. `ProjectileLifetime._physics_process` trips on
  `distance >= max_distance` (`global/components/projectile_lifetime.gd:79`) at n = 94 (1410 px). The gap there is 23.33 px (30.0 px at n = 93),
  and the clock is 1.567 s, under the 1.6 s rule at line 76. The figures "tick 94", "23.3 px" and "≥ 20 px" are right, and the control (rocket
  flying toward the Hacker) fails the same assertion.
- **Hook clock (row 11).** `apply_ability_lock` sets `_timed_left = max(…, 1.0)` (`global/entities/player_base.gd:254-259`). `_tick_clock` zeroes
  the lock at `<= 1e-6` (`player_base.gd:283-286`). The lock is still on after 59 `_step_disruption(1/60)` calls (0.0167 left) and off after 60.
  `_step_ability_lock` does not take its early return while locked.
- **869 / 871 px (row 9).** With `first_pulse_delay` 0 the cooldown is 0 on tick 1, and `_want_pulse` runs after `_arc_motion` in `_tick_hold_arc`
  (`hacker_frigate_brain.gd:249-259`), so 869 px gives TELEGRAPH on tick 1. At 871 px the gate is checked on all 60 ticks with the cooldown already
  at 0, so that control is non-vacuous. The 649 / 651 px pair against `SeekingOrdnance.eligible`'s inclusive `<=` (`seeking_ordnance.gd:30`) is
  sound (see finding 5 on placement).
- **Cadence (row 10).** `_start()` and the countdown both run inside tick 1, so 2.0 − 120·(1/60) ≤ 1e-6 on tick 120. Measured in ticks, the
  intervals fall in [6.0, 8.0] with no tolerance. With `range_drift` 0 the 650 px control cannot fire, because t8's band keeps the Hacker
  ≥ 660 px away.
- **Deferred recycle / row 15.** `BulletPool._on_bullet_expired` defers `_recycle` (`bullet_pool.gd:96-116`), so a hand row that never yields keeps
  every dart in `_active`. The ≤ 4-dart rule is right, and the cap-4 control exactly fills the pool. In row 15's await, the MessageQueue flush comes
  before the delete flush in the same iteration. The two expired darts are therefore re-parented into the pool, which is not itself queued for
  deletion, and freed with the Hacker. The flying dart goes through `cancel_active()` in the pool's `_exit_tree`. All three are freed, as the row
  asserts. The Hacker and the darts have their own physics off, so the awaited frames do not tick them.
- **t8's TELEGRAPH-expiry row.** `test_hacker_frigate.gd:757-770` re-enters TELEGRAPH every tick. Under the new cancel, expiry goes TELEGRAPH →
  DISENGAGE in one transition, so `seen == [DISENGAGE]` still holds.
- **LOS precedent.** The brain tick runs inside the physics step, so `Engine.is_in_physics_frame()` is true on real physics and false in hand rows.
  `can_see_player()` excludes the actor's RID (`enemy_brain.gd:101-105`). Rows 14(a) and 14(c) together catch both a gate that never casts and one
  that lets enemy bodies block.
- **Conventions.** Randomness comes from `rng`. The cooldown uses the 1e-6 rule. The dart's `expired` has 0 arguments and is emitted only through
  the lifetime latch. The dart has no `CollisionObject2D`, so `acquire()` reparenting it inside the physics tick is safe. Tells use `StateLight`
  CHARGING / COMMIT (`state_light.gd:20,73-76`) and drawn parts, not a recoloured hull. All new config fields are flat. Nothing reinvents an existing
  component.

## Blocking findings

### B1. The plan finds that the hijack cannot hurt a still or strafing player who fires at the Hacker, then buries it
Plan: Risks lines 328-330, row 22 (lines 305-315), context line 52. Code: `homing_missile.gd:138-158` (speed eases 500 → 380 over 0.5 s, turn
1.6 rad/s, arming at 0.25 s and 60 px, fizzle at 2.5 s), `retarget()` at lines 182-204 (keeps the current heading).

I re-ran the rocket's rule per tick at 1/60. The plan's measurement holds, so the fairness geometry is justified. But the finding is larger than
the plan says:
- A rocket claimed while heading straight away from a still player, 100–550 px out, fizzles. So does one heading anywhere from 0° to 60° off
  "away", at every distance from 100 to 550 px.
- **The realistic case.** A still player fires the K salvo at the Hacker, which is the nearest enemy, so `RocketState._launch_homing` locks onto it.
  - Open Space (Hacker at 720 px): the claim comes about 0.6 s after launch, about 300 px out, heading away. The rocket fizzles; closest approach
    305 px.
  - Assault (520 px): the claim comes about 180 px out. The rocket fizzles; closest approach 188 px.
  - A player strafing at 360–420 px/s is never reached either (closest 232 / 400 px).
  - The only player blasted is one flying after their own rockets at 420 px/s (blast at 1.48 s).
- The plan's statement "the hijack's real threat is rockets passing toward or across the player" is wrong for "across". A rocket crossing 90° off
  away at 350 px fizzles (closest 130 px); at 450 px it fizzles at 31 px. Only at 550 px is there a blast, at 2.0 s.

So, with t4's tuning, the Hacker's only attack does not threaten a still or strafing player in normal play. That contradicts the epic's owner
summary ("turns slowly back toward you and explodes for a small blast"). The owner has to decide whether to retune `hijack_turn_rate` /
`hijack_seconds` / `hijack_speed` in a follow-up. A line in `DECISIONS.md` is not enough.

**Fix:**
- (a) **Add a documented-limit row**, hand-ticked, on both real player scenes. A still player fires a real `RocketState` homing salvo at the Hacker
  from its held range during PULSE. Assert that all three are claimed, no `ContactBlast` is created, and every rocket's closest approach is
  > `hijack_trigger_radius`.
  - Control: the same salvo with the player cruising after its rockets at 420 px/s is blasted.
  - This puts the epic's literal reading of the fairness row ("rockets fired at the Hacker": a still player loses 0 ≤ 54) into the suite. A retune
    then flips a visible row.
- (b) **Label row 22's geometry with the word "Deviation"**, with the measured numbers. The plan's own rule (lines 3-4) is that §2.11 wins wherever
  a difference is not labelled.
- (c) **Correct the doc wording** for `ENEMY.md`, `PROJECT.md` and the counters list in the Problem section, lines 13-16. Measured, the threat is to
  a player who flies after their own rockets (or to rockets crossing at 550 px and beyond), not to rockets passing toward or across the player.
  "Fire away from it" is not a distinct counter: firing *at* it is equally safe for a still player.
- (d) **Put this in the task report as an explicit owner question**, not only in `DECISIONS.md`.

### B2. Nothing tests that the Hacker keeps moving during TELEGRAPH and PULSE, and the t8 edit removes the only rows that would
Plan: §5 line 151 (`_spawn()` writes `first_pulse_delay = 1000`), Design line 110 / 121 (`_arc_motion` in both phases). Code:
`enemy_mover.gd:216-258` (with no request, `desired` is the cleared primary, so the body decelerates to rest), `test_hacker_frigate.gd:66-77,
202-240`.

§2.11 says "The Hacker keeps moving (HOLD_ARC steering) in TELEGRAPH and PULSE". Suppose a build forgets `_arc_motion` / `face_toward` in those
phases. The hull then decelerates and sits still for 2.5 s with its nose frozen, and every proposed row passes:
- The range band holds against a still player even while the hull is parked.
- The only t8 row that still runs with the pulse on is `_life()`, which checks the view clamp, not the arc.

**Fix:** add a row to `test_hijack_pulse.gd`, both harnesses, with cones 0 and `range_drift` 0:
- Over a whole TELEGRAPH + PULSE (2.5 s), the bearing round a still player advances at the HOLD_ARC rate measured over the 1 s before TELEGRAPH,
  within ±0.02 rad/s, and the nose stays on the player.
- Plus a cone leg in Open Space: snap the nose cone onto the hull on the TELEGRAPH entry tick (t8's snap procedure). The hull leaves through the
  near edge within t8's 2.2 s bound, before PULSE ends.
- A build without `_arc_motion` fails both legs.

Alternatively, run t8's 20 s Open Space holds-range row and the nose-cone rows with the shipped `first_pulse_delay`, and assert ≥ 1 PULSE as a
precondition, adding the bearing-rate assertion.

Optional but cheap: pin the committed behaviour. A player rushing inside 420 px during TELEGRAPH gets no BREAK_OFF until PULSE ends, then
BREAK_OFF on the next HOLD_ARC tick. The plan states this (lines 145-146), but no row pins it, so a later change would be invisible.

### B3. Fairness row 22(a): the geometry is not fixed, and the planned fallback is the wrong way round
Plan lines 306-313. I simulated the row's own geometry: three rockets 450 px out flying at a point 400 px behind the player, darts at 900 px/s, and
the player moving from the claim tick.
- **The Hacker's placement decides whether the row means anything.**
  - With the Hacker 300 px beside the path, level with the rockets' start or up to 200 px nearer the player, the claim comes at 0.37–0.40 s and the
    still player is blasted at about 0.9 s.
    - Open Space cruise + 90° turn: closest 99–115 px.
    - Assault cruise + 90° turn up: closest 68–75 px.
  - With the Hacker far back (500 px aside, level with the start), the claim comes at 0.77 s, with the rocket inside 60 px of the player. The still
    control is **not** blasted (vacuous), and an Open Space turn-down run **is**.
- **The fallback** ("the t4 Assault dodge shape … replaces the turn", line 310) is worse here. Strafe-and-reverse was blasted in 2 of 3 early-claim
  placements (24–26 px) and only cleared the third by 46 px.

**Fix:**
- Write the row's coordinates into the plan: Hacker position, rocket start and spread, when the player starts moving. Pre-run them the way t4's
  dodge row did (its doc records "closest approach 64 / 219 px and 90 px"), and record the closest approaches.
- Add a precondition that the claim happens ≥ 0.3 s before the still player's blast tick.
- Drop the strafe-and-reverse fallback. If the turn run is blasted, change the geometry and log the change, rather than switching to a dodge shape
  that fails more often.

## Minor findings

### m1. Two more unlabelled deviations
- **The LOS rows.** Epic §2.11 says `fixture_wreck`. `tests/helpers/fixture_wreck.gd:1-3` has "No body, no collision", and `LineOfSight` casts a
  bodies-only ray (`line_of_sight.gd:30-48`), so a fixture wreck can never block. Using `wreck_medium.tscn` (the `test_sniper.gd:1463` `_wreck()`
  precedent, physics off so it cannot drift) is necessary. Label it a deviation in rows 14(b) and 14(c); 14(c) currently says only "Wreck". Also
  hand it to t10: §2.12's "behind a `fixture_wreck` at PULSE end is not locked" row has the same problem and must use the real wreck on real
  physics.
- **EMP during PULSE** (lines 138-141, row 20). §2.11 fires the lock "at PULSE end … also when a budget expiry ends the window". An EMP-ended PULSE
  with no lock is a reasonable reading of §2.6 ("stop attacking"), but it changes §2.11, so call it a deviation. t10's Disruptor rows inherit it.

### m2. Row 5 and row 9 placement must be exact
`eligible()` is inclusive (`<=`) and Godot `Vector2` is float32, so a diagonal 650 px offset can compute as 650.00003 and the "just eligible"
rocket would get no dart.
- **Row 5:** specify an axis-aligned run. For example, the hull at (x0, y) and the rocket at (x0 + 650, y), receding along +x, held there (not
  ticked) until the Hacker's tick on PULSE's first tick.
- **Row 5, Assault:** the projectile world rect is x −164…1444 (`arena_camera.gd:86-89`). The rocket ends 1433 px from the hull and the dart
  1410 px, so x0 must be ≤ 10. Otherwise the rocket's own lifetime ends it first, and the dart ends on "rocket freed", not on the 1400 px rule. The
  row's tick-94 assertion would catch this, but write the coordinates in.
- **Row 9:** say the 649 px rocket is also held, not ticked.

### m3. Row 14(a) precondition
The raw `intersect_ray` from the hull centre should pass `exclude = [hacker.get_rid()]`, exactly as `can_see_player()` does
(`enemy_brain.gd:104`). It should also assert `hit.collider == fixture`, not just a non-empty hit, so the precondition proves the fixture body is
what the ray meets.

### m4. The gate-time estimate is low, and the 16× fallback is unsafe for 22(b)
- Line 321 estimates "about 9 s of game time per harness pair". The proposed real-physics runs come to about 7–8 s per harness, roughly 15–16 s per
  pair:
  - 13: about 1.5 s;
  - 14(a)+(b): 0.3 + 0.9 + up to 1.6 s;
  - 14(c): about 1.3 s;
  - 22(b): about 1.5–2 s.
- At 8× that is about 2 s of wall time before any hand row, on a 2.5 s allotment. t4's whole file took about 1.8 s.
- Moving 22(b) to 16× (line 322) is not safe. Its pinned HP equality depends on the player's 0.5 s i-frame `Timer`, which runs on idle frames, and
  the Phase 8 t2 note in `tests/README.md` shows 8× already strains that margin.

**Fix:**
- Run row 13 inside 14(c)'s world: after the wreck is freed and TELEGRAPH starts, fire the bullet, and use 14(a)'s run as the no-hit control.
- End each real-physics run on its condition, not on a fixed wait.
- Keep 22(b) at 8× and assert that the three blasts land within ≤ 3 ticks of each other, so the pinned value cannot depend on Timer granularity.

### m5. `ripple_count()` is undefined
Line 66 has a new ripple every 0.4 s, each living 0.4 s, so at most one ring shows (two at a boundary). Row 21's "the ripple count is right at
t = 0.0 / 0.41 / 1.21 s" never says what is right. Define it, for example "ripples emitted so far = floor(t / 0.4) + 1 → 1 / 2 / 4", or the visible
count, and put the expected numbers in the row.

### m6. Player resolver wording
Line 44 says the dart takes "the first node of group `player` that is not queued for deletion (the node `TargetInfo.player()` reads)". But
`TargetInfo.player()` takes `players[0]` with no such filter (`target_info.gd:28-31`). Either use the same rule in the dart and in
`lock_player_abilities()` as TargetInfo, or drop the parenthesis. `lock_player_abilities()` must also `has_method`-guard, because the harness stub
has no `apply_ability_lock`.

### m7. Stale comments the docs step should catch
- `hacker_frigate_brain.gd:19` says "A TELEGRAPH / PULSE finishes first". From t9, a TELEGRAPH is cancelled and only a PULSE finishes.
- `test_hacker_frigate.gd:756` says "(the deferral t9's real telegraph uses)". t9 cancels instead of deferring.

### m8. Row 4: pre-run the in-flight geometry
"Falls below 10° before its window ends" depends on the claim point. The hijacked turning radius is 380 / 1.6 ≈ 238 px, and a rocket claimed too
close beside the player can circle it without ever lining up. Record the pre-run heading errors and closest approaches, as t4 did.

---

VERDICT: APPROVED
# Review: Hijack Pulse (Phase 9 t9), round 2

I re-read revision 2 of `3-plan.md` against round 1 and against the code: `enemy_mover.gd:216-275`, `assault_corridor_constraint.gd:35-89`,
`test_hacker_frigate.gd:306-352` and `homing_missile.gd:127-204`. I also re-ran the changed geometries tick by tick with the rocket's and the dart's
rules (1/60, the hand-tick order Hacker → rockets → darts → player).

Every round-1 finding is answered. Approved. R1–R3 below are concrete test-design corrections the builder applies while writing the tests; none
changes the design. As written, the controls in R2 and R3 would not fail, and R1's would fail at random, so without them those three controls are
vacuous or flaky. R4–R7 are small.

## Round-1 findings: verified resolved

- **B1.** The threat paragraph replaces the wrong "toward or across" wording (lines 19-28).
  - Row 6 gains the measured-limit leg.
  - Row 22 is labelled D4.
  - The owner question goes into the task report.
  - The still-player leg is robust: a rocket claimed while heading 0°–60° off "away", 100–550 px out, never comes back closer than ≈ 97 px.
  - The leg's control is not robust; see R1.
- **B2.** Row 23 is added. Its main assertions are sound. Its parked control and its cone-leg sign are not; see R2 and R3.
  - Removing `_arc_motion` would also fail the nose assertion, as the plan claims. With no `face_toward` the mover faces its own velocity
    (`enemy_mover.gd:261-262`). While the hull brakes (≈ 0.19 s at 700 px/s²), that velocity is tangential, and the nose swings ≈ 15° off the
    player, more than the 5° bound.
- **B3.** Row 22's fixed geometry works. Setup: P at the origin, rockets at P + (−7 / 0 / 7, −450) flying +y, Hacker at P + (300, −450), in PULSE
  from tick 0.
  - All three are claimed at 0.43–0.45 s.
  - The still player is blasted by all three on the same tick, 0.90 s. The claim comes 0.45 s before the blast (the precondition asks ≥ 0.3 s),
    and the spread is 0 ticks (≤ 3).
  - Closest approaches for the moving runs: Open Space turning +y 228–232 px, turning −y 186–198 px; Assault turning −y 147–159 px. Every one is
    far above the 30 px trigger.
  - The Assault hull at (940, 110) is inside the corridor, and 541 px from the player, outside `min_range`.
- **m1.** D2 and D3 are labelled and listed in §7; D3 is handed to t10.
- **m2.** Axis-aligned placements. Row 5's hull (0, 300) and rocket (650, 300) along +x keep the rocket (≈ 1433) and the dart (1410) inside the
  Assault x ≤ 1444.
- **m3.** `exclude` and `collider == fixture` are in the precondition.
- **m4.**
  - Row 13 is merged into 14(c), with 14(a) as the no-hit control.
  - 22(b) stays at 8× with the ≤ 3-tick spread assertion; the spread is 0 in my run.
  - The estimate holds. The real-physics budget is if anything high: 22(b)'s still run ends at about 0.95 s, not 2.6 s.
  - ≈ 2.2 s against 2.5 s is plausible, with sharing listed as the fallback.
- **m5.** `ripple_count()` = `floor(t / 0.4 + 1e-6) + 1` gives 1 / 2 / 4 at the ticks nearest 0.0 / 0.41 / 1.21 s.
- **m6, m7, m8.** Done.
- **Parked Hacker.** With `max_speed` 0.001, the request is capped by `limit_length(max_speed)` (`enemy_mover.go`-equivalent line in
  `enemy_mover.gd:225-227`). `context_avoid` keeps the request's length, the factor only shrinks it, and a wreck adds no drift, so the body moves
  ≤ 0.001 px/s while `face_toward` still turns the nose. That holds with the caveats in R5.

## Recommendations (apply while building)

### R1. Row 6, Control A (the following player) passes or fails at random; replace it
Plan lines 283-284, and Problem line 24. Code: `homing_missile.gd:193` and `:150-152` (arming needs the rocket ≥ 60 px from the player on some
tick after the claim).

A player cruising after their salvo at 420 px/s is about 48 px behind the rocket at the claim (29 px in Assault), so the rocket is not yet armed. It
turns round and often passes through the player without ever being armed. I scanned Hacker distance 560–840 px (step 20), follow speed
300–700 px/s, and launch-direction offsets 0° / ±3°. No single setting blasts at all three offsets except two small patches at 360 and 420 px/s.
- Assault, 0°: the rocket fizzles after passing 2–7 px from the player.
- Open Space, 720 px: a fizzle at 0° (closest 30.4 px) and a blast at 20°.

Row 6's Hacker also moves (shipped drift and cones), so the result would hang on every later movement tweak.

**Fix:**
- Make Control A a geometry that is certain to blast. On the first rocket's `retargeted`, re-place the still player 300 px ahead along that
  rocket's heading. A rocket claimed heading at a still player from ≥ 225 px is blasted, and closest < 30 px follows from the rule (row 22's
  still-player shape).
- Record the follower case only as a measured note in `DECISIONS.md`.
- Soften Problem line 24 and the §6 doc wording. A player who follows their rockets *can* be blasted, depending on a few degrees and tens of px;
  rockets claimed while heading back at the player from ≥ 225–350 px reliably are.

### R2. Row 23's parked control does not fail the rate equality
Plan lines 396-399. With `max_speed` 0.001 the hull's bearing rate is ≈ 0 both in HOLD_ARC (1.0–2.0 s) and in the window (2.0–4.5 s), so "window
rate = HOLD_ARC rate ± 0.02" holds for the parked control too.

**Fix:** also assert the absolute rate: both rates within ±0.02 rad/s of `orbit_speed_cw` (0.18, the arc `force_orbit_direction(1)` selects). The
parked control then fails the absolute bound, and the mutation fails both.

### R3. Row 23's cone leg uses the near-way snap, so its control cannot fail
Plan line 402 says "the player's facing set to the hull's bearing −10°" with `force_orbit_direction(1)`. In t8's convention
(`test_hacker_frigate.gd:313-315`: `axis = b + s · 10° · (1 if far else −1)`, with `s` = +1 for direction +1), that puts the hull 10° on its own
direction of motion from the axis. That is the **near**-way case. The plan's cone-0 control then exits at 2.18 s (epic §2.10 table, 0.18 rad/s near
case, cone off), inside the 2.2 s bound, so it does not fail.

**Fix:** use t8's far-way snap (axis = bearing + `s` · 10°; better, call or copy `_snap_and_measure` with `far = true`). The cone-off exit is then
4.12 s.

### R4. Say how PULSE starts in rows 3, 5, 7 and 12
Rows 2 and 15 say `enter_phase(PULSE)`; rows 3, 5, 7 and 12 do not. In Open Space, row 5's hull (0, 300) sits 300 px from the player at (0, 0),
inside `min_range` 420. Through the natural cycle, `_tick_hold_arc` would enter BREAK_OFF (`hacker_frigate_brain.gd:253-256`), never TELEGRAPH.

**Fix:** enter PULSE with `enter_phase(PULSE)` in these frozen rows, or place the player ≥ 420 px from the hull.

### R5. Conditions for the parked Hacker
`max_speed` does not hold the hull still in three cases:
- `mover.boost()` ignores `max_speed`, and BREAK_OFF uses it in Open Space (`hacker_frigate_brain.gd:333-334`).
- `_enter_disengage()` writes `mover.max_speed = exit_speed` (line 375).
- `AssaultCorridorConstraint.filter` adds ≥ 60 px/s of entry speed or edge pressure outside x −100…1380, y −380…1100, whatever the request
  (`assault_corridor_constraint.gd:35-80`).

**Fix:** in rows 14 and 22(b), keep every parked hull ≥ 420 px from the player (or set `min_range` 0 in the parked config), inside the Assault
corridor, and keep `engage_seconds` longer than the run. Row 22 already satisfies this; write the row-14 coordinates so it visibly does too.

### R6. Row 23's committed leg: say which tick BREAK_OFF lands on
t8's stub ran `_tick_hold_arc(delta)` on the tick it re-entered HOLD_ARC (`hacker_frigate_brain.gd:351-352`). If `_end_pulse()` copies that,
BREAK_OFF lands on the PULSE-end tick itself, not "the first HOLD_ARC tick after" it (line 407). Decide one and write the row to match.

### R7. Nit: row 4's crossing rockets
Row 4's crossing rockets are claimed about 470 px from an Open Space player, heading 90° off. My run of that case ends either in a blast or in a
fizzle at about 31 px. The row asserts only the turn and the heading error, which is fine, but in the pre-run record whether each rocket blasts, so
a later change to the claim point is visible.
