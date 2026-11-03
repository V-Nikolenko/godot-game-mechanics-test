VERDICT: CHANGES_REQUESTED
## Round 1

Reviewed `3-plan.md` and `1-context.md` against the epic plan (`cmug23ona0015m52w4t1m73bc/3-plan.md`: "For every task", §2.3, §2.12, §2.13, §2.19),
DECISIONS.md Phase 8 (including "built in t12"), IDEAS §6.10, and the code at `7926c8e`: `twin_laser_pair.gd`, `twin_laser_drone_brain.gd`,
`twin_laser_pair_spawn.gd`, `twin_laser_drone.tscn`, `enemy_mover.gd`, `steering.gd`, `enemy_brain.gd`, `target_info.gd`, `engagement_budget.gd`,
`base_enemy.gd`, `missile_corvette_brain.gd`, `assault_corridor_constraint.gd`, `arena_camera.gd`, `score_tracker.gd`, `test_twin_laser_drones.gd`,
`test_base_enemy.gd` (tow table), `test_enemy_mover_single_writer.gd` and `enemy_ai_harness.gd`.

Most of the plan is sound. It enters the rig through an appended LAUNCHED phase and a fixed frame, and leaves t12's TELEGRAPH, ADVANCE, strain, BREAK and
one-attack code alone. The renewed one-step boost matches t12's ADVANCE rule, and the launch speed is clamped so the drone stops on its point. A boost
ignores `max_speed`, so 520 px/s over the drone's 300 is legal (`enemy_mover.gd:115-118`, `:224-226`). The rejected `n = (centre − P).normalized()` is
correctly replaced by the signed orthogonal. The `standoff` cap holds the §2.12 1.92 s bound. Seeding before `add_child` works because `EnemyBrain._ready()`
reads `rng_seed` (`enemy_brain.gd:55-59`). Docking runs only in Open Space, which has no `ScoreTracker`. No RefCounted cycles are added: the tender holds the
rig, and the rig holds only a Node reference back.

Four problems block approval. Two are §2.13 rows that the plan's own geometry cannot pass as written. One is an Assault design detail that fails against
the real steering code. One is a regression risk that no row can see.

### Blocking

**B1. The "V" fails for a moving player. Row 5 only tests the standing geometry, where the V happens to hold.**
Plan lines 136-138 (point order), 187-190 (row 5) and 191-194 (row 6). §2.13 requires "the angle between their launch directions is > 20° and < 160°: a V".
- **Open Space, a player moving across the tender's bearing.** I used row 6's own "moving" geometry: the tender at `P + (0, −650)` and a 200 px/s stub
  along +x. The plan puts `u ⟂ v`, so the points are `Q± ≈ P + (250, ±210)`, with the cradles at about `P + (∓30, −640)`. The non-crossing matching
  (the shorter one, which the plan picks) gives leg directions of about 68° and 57°. That is a V of about 11°, and about 9° if the tender has not
  drifted. The wall lies end-on to the tender, so both drones fly almost parallel, one to each end.
- **Assault, a strafing player.** Take the tender near `P.x` at the hold point (y 140) and the points at `(P.x + 180, P.y ± 210)` with P.y = 600. The
  shorter matching gives about 72° and 58°, a V of about 14°. With the tender lagging about 60 px it is about 19°.

Row 5 is parameterised on mode only, and its default is the standing case. Standing gives about 38° in Open Space and about 86° for the Assault still
case. So the row passes, while the cases the tender meets most (a moving player) launch near-parallel legs. That drops a §2.13 requirement without saying
so.

**Fix:** run row 5 over the moving cases too: Open Space `moving` and Assault `strafe`. Then do one of these:
- **Change the design so the V holds.** The wall must stay `⟂` the heading (§2.13), so the freedom left is in the launch. For example, the tender's
  HOLD could choose its arc side so its bearing to the player is not along the heading.
- **Narrow the row and log it.** In DECISIONS ("Phase 8, built in t13") and the task report, state the geometric limit: an end-on wall cannot give a
  20° V with straight non-crossing legs. Keep the 20° assertion for broadside geometries. For end-on ones, assert non-crossing plus a separation between
  the drones that grows over the first 0.3 s.

Either way, the plan must say which, and the row must cover the moving geometry.

**B2. Row 13's strafe expectations contradict the plan's own geometry, and row 7's frame expectation is ambiguous.**
Plan lines 217-221 (row 13), 197-200 (row 7) and 77-81 (signing the normal toward the player). Row 13 `strafe` puts the stub at 200 px/s along +x and
expects `normal = +x (the wall is ahead, advancing back at the player)`.
- **The arithmetic.** At launch (t ≈ 0.6 s) the wall is placed at `x = P.x + 180`. The far leg is about 690 px, so about 1.33 s at 520 px/s. By the time
  `_fix_launched_frame()` runs, a stub that keeps strafing has moved about 266 px, which puts it about 90 px past the wall.
- **What the plan's own rule then does.** It signs `n` toward the line from the player, which gives `n = −x`. The wall then chases the player from
  behind. The row as written fails, or passes only if the stub stops at launch, and the plan does not say which.
- **The same consequence in Open Space.** It follows from §2.13's prediction horizon: `t = |P − tender| / launch_speed` covers the flight only, not FORM
  or the 0.8 s telegraph. A constant-velocity player is always past the wall before it lights.
- **Row 7 `assault:200` / `open_space:200`.** The row asserts the frame is "equal to the launched frame". The normal can be re-signed at the latch, so
  only `centre` and `axis` are guaranteed equal.

**Fix:** state the stub's motion exactly in row 13. Either it strafes until the launch and then stops, in which case assert `n = +x`, or it keeps
strafing, in which case assert the re-signed `n = −x` and that the wall still advances toward the stub. Add a case for the other behaviour so the
re-sign rule is pinned both ways. In row 7, restrict "equal to the launched frame" to `centre` and `axis`, and assert `n` against the sign rule computed
from the latched player. Record in DECISIONS that the Attack B wall lands behind a player who holds a constant velocity, and that it then chases. This is
the §2.13 formula working as written, but it should be visible to t16/t18/t19 tuning, not left implicit.

**B3. In Assault, a strafing player can keep the tender in APPROACH until its budget runs out, and no row would notice.**
Plan line 111: Assault APPROACH → HOLD fires "within `HOLD_REACH` (24 px) of" the hold point. Lines 121-124: the hold point's x is `clamp(P.x, …)`, so it
moves with the player.
- **Why it cannot catch up.** `mover.arrive()` is `Steering.arrive` (`steering.gd:26-35`). It slows inside a radius of `v² / (2 · accel)`, which is 50 px
  at the tender's 200 px/s and 400 px/s².
- **The result.** A hold point moving at 200 px/s is trailed at about 50 px, which is more than 24. One moving at the Assault cruise of 360 px/s is never
  caught at all. So a player who keeps strafing during the tender's approach keeps it in APPROACH, and the budget expires with no launch.
- **Why no row catches it.** Every Assault row (4, 5, 7, 8, 9, 12, 13, 14, `mid_telegraph`) starts the tender *at* its hold point. The plan says so at
  line 171.

**Fix:** make the Assault APPROACH → HOLD condition the band, not the point: `|pos.y − hold.y| ≤ HOLD_REACH`, inside `view_rect()`. The x tracking
continues in HOLD. Add a row: the tender spawned above the view (as `WaveBuilder` places it), with the stub strafing at 360 px/s, reversing at the
corridor edges or at a constant velocity. Assert that it reaches HOLD and launches within `engage_seconds`. Add a boundary for the old 24 px rule
failing the same run, if that is cheap.

**B4. The tender/drone collision exception, and the synchronous `add_child` on a real physics step, are never exercised.**
Plan lines 47-48 (the mutual exception) and 167-169 (every tender and launched drone has its body `collision_mask` cleared). All rows are hand-ticked with
masks cleared, which is t12's technique (`test_twin_laser_drones.gd:149-152`). With both masks at 0, deleting the `add_collision_exception_with` calls
fails nothing.
- **What the exception protects.** The drones start inside the tender's r 40 body: the cradles are 31.6 px from its centre, and the drone radius is 13.
  Without the exception, `move_and_slide()` on real physics pushes them out, and the straight V legs deflect.
- **What else goes untested.** No row launches on a real physics step, which is the plan's reason for deviating from "deferred".

**Fix:** add one real-physics row at the 8× clock, with masks intact. Both modes are best; one is acceptable if gate time requires it. The tender
launches and each drone's displacement after 0.3 s is within 5° of its launch direction. Each drone reaches its point within `slot_tolerance` by
`launch_seconds_of + a tick`. Each drone is in the tender's `get_collision_exceptions()` and the tender in each drone's. This costs about 0.2–0.3 s, and
it also covers B3's spawn-from-above run if combined with it.

### Non-blocking

**N1. The gate-time estimate undercounts the runs.** Plan lines 244-246 assume "≈ 14 hand-ticked runs". The parameterisations the plan lists come to
about 28–30 runs: rows 4, 5, 8, 9, 12, 13 and 15 at ×2 each, row 7 ×4, row 6 ×2 plus the pure case, rows 10, 11, 14 and 16, three structure rows, and
the dual-mode case ×2. Row 10 alone is about 18 s of game time, and B4 adds a real-physics row. t12 measured about 0.05 s per hand-ticked run with two
bodies (`tests/README.md:620`); with three bodies this lands at about 2.0–2.3 s, at or over the 2.0 s allotment. Commit to the sharing up front rather
than "if over budget": rows 7–9 and 12 on one recording per mode, rows 4 and 5 on one launch per mode.

**N2. The advance cap is a deviation, and the plan does not call it one.** Plan lines 82-86. `min((centre − P)·n, standoff) + overshoot` is *shorter*
than §2.13's "|P − centre| + overshoot" whenever the latched player is more than `standoff` from the line. In Open Space no bound needs the cap. The cap
is a sensible design choice, but log it as a deviation in DECISIONS rather than describing it as "it is never more".

**N3. A lone drone from an older rig can be stranded inside the tender.** Plan lines 125-126 (the dock check looks only at "each drone of the last
rig"). The SOLO drone `arrive`s at the live controller (`twin_laser_drone_brain.gd:162-166`), and the collision exception lets it overlap the tender.
Suppose it is slowed by a well or a wreck past `rearm_seconds`. The tender rearms and launches a new rig, the old drone stops being "of the last rig", and
it never docks: it sits inside the tender for good. **Fix:** dock any live SOLO drone whose `brain.pair.controller == tender`, for example by keeping a
small list of launched drones, not only the last rig's.

**N4. The brain calls a private method on the tender.** Plan line 116: the brain calls `tender._set_docked(2)`. Expose a public `rearm_cradles()` or
`set_docked(n)` instead of having one class call another's underscore method.

**N5. The plan does not say where the brain reads the drone's tuning from.** Plan lines 129-130 read `L`, `slot_tolerance` and `standoff` "from the drone
scene's config .tres". Read them through the tender's `drone_scene` export: an instance cached once, or the `PackedScene` state's `config` property.
Hard-coding `twin_laser_drone_config.tres` would diverge as soon as a Ph10/Ph11 caller swaps `drone_scene`.

**N6. The tender brain should join the no-motion sweep.** It holds drones under a receiver other than `actor`. `test_enemy_mover_single_writer.gd` only
checks `actor.`/`body.`/`self.` in brains (`:48-54`). Add `laser_tender_brain.gd` to t12's any-receiver sweep alongside `laser_tender.gd` (plan line
240). It costs nothing and closes the same hole t12's DECISIONS describes.

**N7. Some rows are weaker than they look.**
- Row 6's "pure `attack_b_points()` boundary" (line 194) gives only the uncapped case: 650 / 520 = 1.25 s, which is under `lead_time_max` 1.5. Add a
  capped case, for example 1000 px giving 1.5 s.
- Row 10 (lines 209-210) bounds the second launch only from below. Add an upper bound (`+ TICK_SLACK`) so a slow rearm fails.
- Row 7's "ADVANCE lasts `advance_distance / advance_speed`" is self-referential. Have the test compute `advance_distance` from the latched player and the
  frame using the plan's formula.

**N8. The Assault hold point can put the tender on top of the player.** Plan lines 122-124: the hold point is `(P.x, view.y + 140)`. A player flying in
the top band ends up under, or touching, the tender. Consider keeping `hold.y ≤ P.y − (R + clearance)`, or note it as accepted (COLLISION contact,
15 damage).

**N9. Document the seam's calling rule.** Plan lines 50-52 justify adding the drones synchronously because the brain tick is the only caller. Since
`launch_pair` is the Ph10/Ph11 seam, say in its doc comment that it must be called on the physics step and never from a physics callback (use
`call_deferred` there). A future Carrier calling it from `area_entered` would otherwise error.

**N10. Owner groups pile up on the tender.** Each launch adds the tender to a new `twin_pair_<id>` group (`twin_laser_pair.gd:101-103`), and nothing
removes it. This is harmless but unbounded in a long hub session. Optionally `remove_from_group(old_rig.owner_group)` once that rig is broken and its
beam freed.

## Round 2

I re-read the revised `3-plan.md` against the round-1 findings and against the same code (`twin_laser_pair.gd`, `twin_laser_drone_brain.gd`,
`steering.gd:26-35`, `enemy_mover.gd`, `assault_corridor_constraint.gd`, `arena_camera.gd`, `enemy_ai_harness.gd`).

The four round-1 design findings are resolved:
- **B1:** the narrowing is a sound, honest choice. It is logged at lines 162-167 and runs on the moving geometries in row 5. The "toward" case is
  broadside: by my arithmetic it opens about 50°.
- **B2:** row 13 now pins `strafe_then_stop` (n = +x) and `strafe_on` (n = −x), and row 7 asserts `n` from the sign rule. The chase-from-behind
  consequence is logged at lines 102-105.
- **B3:** the band trigger is at line 130.
- **B4:** row 17 runs on real physics with masks intact.

The non-blocking items N1-N10 are all taken up. Two new row specifications, however, fail on a correct build as written. Both are one-line fixes, but a
tests-first implementer would otherwise read the failures as code bugs.

### Blocking

**R2-B1. Row 5's "ends `L` apart at the end of LAUNCHED" fails whenever a leg is capped, and `open_space:crossing` is capped.** Plan lines 222-224.
The rig leaves LAUNCHED at `max(launch seconds)` (line 90). A capped leg ends `launch_speed · launch_max_seconds` = 728 px from its cradle, short of its
point.
- **The arithmetic for `open_space:crossing`.** The geometry is row 6's: tender at `P + (0, −650)`, stub at 200 px/s along +x, launch at 0.6 s. The far
  leg runs from about `P_launch + (−90, −640)` to `P_launch + (250, 210)`, which is about 916 px. So at the end of LAUNCHED that drone is about 190 px
  short, and the separation error is far above `length_tolerance` 16.
- **Fix:** assert the `L ± length_tolerance` separation at the latch (the first TELEGRAPH tick, where t12's slot / separation latch guarantees it). Or
  assert it at the end of LAUNCHED only for cases where neither `launch_seconds_of` equals `launch_max_seconds`, and state which cases those are.

**R2-B2. Row 13b's boundary ("never within `HOLD_REACH` of the moving hold point before its launch") is likely false with a stub that reverses.**
Plan lines 263-266.
- **The arithmetic.** At 360 px/s the stub reaches the inset rect's right edge (about 1356) at roughly 2.0 s. The hold point's x stops at
  `r.end.x − 2R` (1300) and then comes back at 360 px/s. The tender has just reached the band, at roughly x 950–1000 and moving +x at up to 200 px/s.
  It crosses the returning hold point at around 2.5 s, which is before the launch at band entry plus 0.6 s, about 2.6 s. During that crossing it is
  within 24 px in both x and y for several ticks.
- **The consequence.** The point rule would have fired, so the boundary assertion fails, or flips with small timing changes.
- **Fix:** restrict the boundary to the window before the stub's first reversal, and start the stub at the inset rect's left edge moving +x. That gives
  about 4 s of uninterrupted 360 px/s strafing, ample for the tender to reach the band. Assert in that window that the tender reached the band (and
  HOLD) while never being within `HOLD_REACH` of the point. Keep the reversing run for the main assertion ("reaches HOLD and launches within
  `engage_seconds`").

### Non-blocking

**R2-N1. The gate estimate is still optimistic.** Line 297 says "≈ 16 shared hand-ticked scenarios". By the rows as written, the count is about 25:
- row 5: 5 cases, with row 4 sharing them;
- row 6: 2;
- row 7: 4, and rows 8 and 12 can share its standing-stub cases;
- row 9: 2, since its runner stub differs from row 7's;
- row 10: 1;
- row 11: 2;
- row 13: 3;
- row 13b: 1;
- row 14: 1;
- row 15: 2;
- the dual-mode case: 2.

The real-physics rows run at 8×, so game seconds cost one eighth in wall time. Row 17's Assault case spawns above the view and waits out the approach,
about 4 s of game time and so about 0.5 s of wall time. The two rows together come to about 0.7 s, not 0.4.
- **Expected total:** about 2.1–2.7 s against the 2.0 s allotment.
- **Cheap trims:** row 17's Assault case can start in the band, since 13b already covers the approach. Rows 13b and 17 can share the Assault approach
  if they are kept hand-ticked plus real.
- **Why this is not blocking:** the absolute phase headroom is large (206.5 s against 238 s) and the plan already names its remedy.

**R2-N2. The `dock()` doc text at line 66 is stale.** It still says "only for a SOLO drone of this tender's last rig", which contradicts the N3 change
(line 146: any drone it launched). Update it.

**R2-N3. The N8 cap can block a launch near the top of the corridor.** The hold y is now capped at `P.y − 120`. A player hugging the top of the inner
rect drives the hold point above the view, so neither the band trigger nor `_can_launch()` (both need the tender inside `view_rect()`) fires until the
player comes down. The budget may expire without a launch. This is acceptable, since it is what §2.13 allows for a budget that runs out before LAUNCH,
but say so in ENEMY.md or DECISIONS.

**R2-N4. N10 only covers the previous rig.** The owner-group cleanup is checked only for the previous rig, at the next launch. A rig that still had a
live drone then keeps the tender in its group for good. This is harmless; a one-line note is enough.

## Round 3 (owner-authorised, scope: R2-B1 and R2-B2 only)

VERDICT: CHANGES_REQUESTED

I checked only rows 5 and 13b of `3-plan.md` (lines 226-233 and 273-277), the progress note at lines 17-20, and the code they depend on. R2-B1 is
correctly fixed. R2-B2 is fixed in kind, but the new window assertion holds only for an unstated range of tender spawn x, and its margin is much
thinner than the "≈ 4 s" in the row suggests. A one-line pin closes it.

### R2-B1: fixed

- **The assertion holds by construction.** `twin_laser_pair.gd:254-258` enters TELEGRAPH only when both drones are within `slot_tolerance` of
  `slot_of()` *and* `separation_error() <= config.length_tolerance`. That check runs on the leader's tick, immediately before `_enter(TELEGRAPH)`.
  - On a launched frame, `slot_of(A)` = `centre − axis·L/2` = `point_a` and `slot_of(B)` = `point_b`, because every Attack B point pair is exactly
    `L` apart (plan lines 165-170).
  - So the rig cannot reach a TELEGRAPH tick unless the drones were `L ± length_tolerance` apart on the tick that latched.
- **Reading it after the step is also safe.** If the row reads separation after the full hand-tick step, both drones have moved one more tick. They
  are `arrive`-ing at their own slots (`twin_laser_drone_brain.gd:151`), so the error does not grow.
  - t12 already reads it this way (`test_twin_laser_drones.gd:217-218`, with `max_err` including the first TELEGRAPH tick), and that check is green.
- **`open_space:crossing` latches in time.** The capped drone is about 190 px short of its slot when LAUNCHED ends at 1.4 s. It then arrives at
  `max_speed` 300 / `acceleration` 900 well inside `form_timeout` 3.0 (`twin_laser_drone_config.tres:16-25`).
- **The new capped-leg clause (line 231-232) passes, but only just.**
  - The rig leaves LAUNCHED on the tick where `phase_time` reaches 1.4. On that tick the drone mirrors FORM and does not boost, so it gets 83 boosted
    ticks (719.3 px).
  - It then decelerates from 520 by 15 px/s per tick (`enemy_mover.gd:240-246`, no `braking`). At "`launch_seconds_of` + 1 tick" it has flown
    about 735.9 px.
  - That is 7.9 px from 728, against a tolerance of one tick's travel (8.67 px): a margin of about 0.8 px.
  - **Non-blocking:** measure the capped leg on the LAUNCHED → FORM tick (727.7 px), or allow two ticks' travel.

### R2-B2: the window is sound only for a tender spawned near or right of the view centre

I simulated the tender's APPROACH motion headless, using the real `Steering.arrive` plus `move_toward` at the tender's `max_speed` 200 and
`acceleration` 400, at DT 1/60.
- **Hold point:** `(clamp(P.x, −20, 1300), min(140, P.y − 120))`, from `inner_rect()` = (−100, −380, 1480, 1480).
- **Stub:** starts at the inset rect's left edge (x −76) and strafes +x at 360 px/s.
- **Tender:** spawned at y −200.

Results:
- **Stub timing:** it reverses at 3.97 s. The hold point stops at x 1300 from 3.82 s.
- **The tender is slow to reach the band.** It arrives at |y − 140| ≤ 24 inside the view at 3.02 s for spawn x 1000, 3.38 s for x 640, 3.55 s
  for x 560 and 4.02 s for x 400.
  - It is slow because, while it chases a point that outruns it, its velocity points mostly along x. It drops at only about 90-130 px/s.
  - Spawned above the stub (x −76, a natural reading of "from above, against the player"), it reaches the band at 5.33 s, after the reversal.
- **Consequence:** for any spawn x below about 410, the row's "the tender reaches the band (and HOLD) in that window" fails on a correct build. That
  is the failure class R2-B2 was meant to remove.
  - At the likely reading (x 640, WaveBuilder's `.at(0, …)` column with the hand-ticked camera offset 0; `wave_manager.gd:194`), the margin is
    0.59 s, not "≈ 4 s".
  - That margin is set by the tender's speed and acceleration, so later tuning can erase it.
- **The rest of the fix is sound.**
  - **Before the reversal:** the tender's closest approach to the moving hold point is 111-170 px at every spawn x I tried, far outside
    `HOLD_REACH` 24. The "never within `HOLD_REACH`" half is robust.
  - **After the reversal:** the closest approach falls to 3-18 px. This confirms round 2's concern and shows the window exclusion is needed.
  - **The boundary can still fail on a broken build:** under the rejected point rule the tender never HOLDs before the reversal, so the in-window
    "reaches HOLD" assertion fails.
  - **The main assertion holds:** with the reversing stub, HOLD and launch happen within `engage_seconds` (launch ≤ 5.93 s at every spawn x).

**Fix (one line in row 13b, plan line 273-274):**
- Pin the spawn, for example at `(640, −200)` (view centre, 200 px above the view), or ahead of the stub's run at `(1000, −200)`, which gives about
  0.95 s of margin.
- State the expected numbers so an implementer can tell a geometry slip from a code bug: band and HOLD at about 3.4 s (or 3.0 s), first reversal
  at about 3.97 s, and closest approach to the point before the reversal of about 137 px (or 111 px).
- Replace "≈ 4 s of straight strafing" with the real window (the 3.97 s reversal).

Nothing else in rows 5 and 13b, or in the progress note, contradicts the rest of the plan.

## Round 3b (confirmation of the round-3 fix)

VERDICT: APPROVED

I checked only the round-3 edits in `3-plan.md`.

- **Line 21: the new "Revised after review round 3" note.** It matches what was changed.
- **Row 5, lines 233-235.** The capped-leg clause is now measured on the LAUNCHED → FORM tick, at about 727.7 px. That is 0.3 px from 728,
  against one tick's travel of 8.67 px. This removes the 0.8 px margin from round 3. The latch-tick `L ± length_tolerance` assertion is unchanged
  and still holds by construction.
- **Row 13b, lines 274-279.** It matches my simulation for a spawn at x 1000.
  - Spawn: `(1000, −200)`, which is 200 px above the view (view top y 0) and ahead of the stub's run.
  - Stub: starts at x −76 and strafes at 360 px/s.
  - Band and HOLD: about 3.0 s (simulated 3.02 s, at tender x ≈ 804, inside the view).
  - First reversal: about 3.97 s, so about 0.95 s of margin.
  - Closest approach to the hold point before the reversal: about 111 px, far outside `HOLD_REACH` 24.
  - "≈ 4 s" is gone. The printed diagnostics are a good addition.
  - The boundary still fails under the point rule, and the main assertion (launch within `engage_seconds`) still holds.
  - The hold y is 140 for any stub y ≥ 260, so the row's unstated stub y (the Assault default of 600) does not change these numbers.

No contradiction with the rest of the plan.
