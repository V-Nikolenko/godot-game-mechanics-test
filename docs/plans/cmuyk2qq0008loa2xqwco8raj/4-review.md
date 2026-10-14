# Review round 1

VERDICT: CHANGES_REQUESTED

Reviewed `3-plan.md` and `1-context.md` against the epic plan (`docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md`
§2.2.1, §2.5, §2.7, §2.9.4, §2.11, §4 t13 row; review N3, N9) and against the code at HEAD `047abd0`. (While this
review was running, uncommitted edits to `sniper_brain.gd`, `sniper_config.gd`, `sniper.gd`, `test_sniper.gd` and a
new `rail_trail.gd` appeared in the working tree. The review covers the plan, checked against the committed code.)

Most of the plan is sound and checks out against the code. The `break_min` deviation is needed and argued correctly.
From rest, a RELOCATE `arrive` toward a chord point gives a radially negative velocity on its first tick. The vector
`move_toward` in `enemy_mover.gd:197` keeps every tick's velocity a convex combination of radial-positive vectors
while BREAK_CONTACT lasts. Inertia (about 274 px/s radial, changing by at most 8.7 px/s per tick) covers the tick
where `phase_time` crosses 1.0 s.

The `side` formula is correct. With Godot's `orthogonal() = (y, −x)`, `s = sign(orth · away⊥)` gives a lateral
term with a positive dot on the away-from-line direction. That matches `steering.gd:200`.

RailTrail's two-path ownership (one-shot `expired` for the recycle, a weakref for `cancel_active()`) matches
`bullet_pool.gd:96-133`. The test idiom `expired.emit()` then `pool._recycle()` is safe: the deferred second
`_recycle` hits the `_active.has()` guard at `:106`.

N3 and N9 are applied. `SNIPER_ENEMY := SNIPER` (`wave_builder.gd:253`), so filtering on the scene path picks up the
(±120, −500) rows at `level_1_director.gd:277,282`. Stripping delays avoids `wave_manager.gd:173`'s
`create_timer`. Stripping `movement` drops `free_after` with the path mover (`wave_manager.gd:220-232`).

Attack-in-budget, checked from the code. The camera is at (640, 360) and `WORLD_SCALE` is 2. The worst class is the
far top spawn at (880, −640) with the stub at (640, 560): about 930 px to the ±60° seed, so AIM comes at about 4.6 s,
against 9.0 s. In the boundary case the corridor's not-entered floor of 60 px/s (`assault_corridor_constraint.gd:65`)
still leaves about 20 s, so that row really does fail.

The issues below need fixing before implementation.

## Findings

### 1. BLOCKING: the score sends RELOCATE straight past the player on almost every cycle
**Checked:** plan lines 89–90, 107; epic §2.5 Score.

With `w_sep` 1.0 and `w_travel` 0.4, and travel normalised by `2 · range`, the score always rises with Δ:
- The separation term rises at 1/180 per degree.
- The travel penalty rises at most about 0.0027 per degree. The chord from about 1.24·R to a ring point at R grows
  by at most about 0.78·R per radian.

So BREAK_CONTACT → `choose_firing_point()` always picks the candidate most opposite the last bearing. Worked through
for Open Space (R = 900, sniper about 1120 px out after the break):

| Candidate | Score |
|---|---|
| Δ = 180° | 0.55 |
| Δ = 135° | 0.34 |
| Δ = 90° | 0.18 |
| Δ = 60° | 0.11 |

Assault (R = 680, player at (640, 560)) gives the same ordering. The legal arcs |θ| ≤ 71° and 109°–131° still leave
opposite-side candidates, which score about 0.54 against 0.27 for Δ = 120°.

RELOCATE is a straight `mover.arrive()`. The segment from bearing b0 to b0 + 150–180° passes within
`a·b·sinΔ / travel` of the player: about 0–0.28·R, roughly 0–250 px. So on most cycles the sniper flies through or
past the player at 260 px/s, with a live contact hitbox. This:
- defeats BREAK_CONTACT;
- contradicts R4.15 ("no return loop") and the plan's own Problem statement ("slides to a fresh firing angle *around*
  the player");
- is not caught by any listed test. The post-shot row stops at 1.0 s, and the bearing row passes trivially.

The plan's line 90 only checks the path against the rect.

**Fix:** pin a path rule and test it. The simplest option that stays inside the epic's filter-then-score shape is a
**path-clearance filter**. It rejects a candidate whose straight segment from the current position passes within
`relocate_clearance` (a new flat field, e.g. 0.6 · range) of P. Alternatives:
- route RELOCATE via a ring waypoint;
- re-weight, logged as a deviation in DECISIONS.

Add a dual test: against a stationary player, over 3 cycles, the distance on every RELOCATE tick stays ≥ the
clearance. Check that this test fails on the plain straight-chord build. Also re-check the corner boundary, since a
clearance filter shrinks the legal arc.

### 2. BLOCKING: corridor-safe BREAK_CONTACT has no test of its own
**Checked:** plan lines 81–87; `assault_corridor_constraint.gd:58-76`; `enemy_mover.gd:190-197`.

This is the most intricate new logic in the task:
- per-axis zeroing against a stopping-distance threshold;
- negation when the remainder points toward the player;
- the corner zero.

The only Assault coverage is the dual post-shot row. That row exercises the logic only if the seeded firing point
happens to break toward an edge within 1.0 s.

Also, the mover's `move_toward` is a **vector** step (`enemy_mover.gd:197`), not a per-axis one. The axis share is
`|Δaxis| / |Δ|`, so the "half the rate" figure is an assumption, not a bound. The realistic worst case is the negate
branch with `away` nearly along the zeroed axis:
- v ≈ (274, −164) → desired (0, +320);
- share ≈ 0.49;
- stopping distance 146 px against the 160 px threshold.

So it holds today only through `EDGE_KEEP`.

**Fix:** add an Assault boundary case with three setups:
- a sniper at FIRE on the edge of the grown rect, breaking outward;
- one where the remainder must be negated;
- one in the corner.

Assert in each:
- position stays inside `inner_rect()` on every tick (so the corridor's `d > 0` branch never runs);
- distance non-decreasing;
- `v · (P − x) ≤ 0`.

It should fail with the corridor-safe step removed. Also correct the "move_toward decelerates each axis by a share"
wording to describe the vector step.

### 3. BLOCKING: nothing tests the BREAK_CONTACT side rule
**Checked:** plan lines 68–70; task description ("side away from the player's line"); epic §2.11 checklist row.

A sign error in `s` would make the sniper cut across the player's nose. None of the listed rows would notice:
- the post-shot row uses a stationary player, where either side increases the distance;
- `test_steering.gd` covers only the primitive, with `side` passed in.

**Fix:** add a dual case. The player moves at constant velocity (e.g. (200, 0)) and the sniper fires from each side
of the player's line. Assert that throughout BREAK_CONTACT the sniper's signed distance from the line through P along
`v̄` grows in magnitude and never changes sign.

### 4. BLOCKING: the forward-cone row can pass with the filter deleted
**Checked:** plan lines 95–98, 178.

The seven seeds sit at ±60°, ±90°, ±135° and 180°, each ±15°, so no seed bearing is ever within ±30°. Only the 3
random candidates can fall in the cone: about a 42 % chance that one does, and that one must also be the winner. So
"no chosen point within ±30° of `v̄`" is green on a build with no cone filter unless the setup happens to make an
in-cone candidate win.

**Fix:**
- put the sniper ahead of the moving player;
- assert from `last_candidates` that at least one candidate has |bearing| < 30° and every such candidate has
  `cone_ok == false`. Pick a seed for which one exists, or loop selections until one does;
- keep the 100 px/s half (`cone_ok` true for all).

### 5. NON-BLOCKING: the t12 Assault ENTER test is not on the update list
**Checked:** `test_sniper.gd:329-343` at HEAD.

`test_enter_in_assault_stays_inside_the_corridor_shrunk_by_the_fire_margin` asserts the sniper holds inside
`legal.grow(13)` after 480 ticks. With the cycle running, the sniper fires at about 3.7 s and is in BREAK_CONTACT or
RELOCATE at 8 s. BREAK_CONTACT legitimately leaves the grown rect (it stops only near the visible edge). Add this
test to the "t12 updates" row.

Separately, `test_sniper_disengage_frees_it_in_assault_only` (open_space, 1500 ticks) and
`test_open_space_has_no_budget_so_the_sniper_stays` will now fire. Rounds never move in hand-ticked runs, so the
two-round pool runs dry. The result is `push_warning` noise, which is not a failure (GUT `failure_error_types`
excludes warnings), but it is worth recycling there or noting it.

### 6. NON-BLOCKING: the 4-shot bearing row needs a longer budget in Assault
**Checked:** plan line 176; `sniper_config.gd` `engage_seconds` 9.0.

The first shot comes at about 4–5 s and each later cycle takes about 5–6 s (1.0 break + about 3 s relocate + 0.4
settle + 1.8). Four shots in the Assault parameter will hit DISENGAGE first. The test must raise
`sniper.config.engage_seconds` before the first tick, when `_start()` builds the budget. Say so.

### 7. NON-BLOCKING: the ENTER → SETTLE change from the epic's cycle diagram is not stated
**Checked:** plan line 26; epic §2.5 diagram (`ENTER → BREAK_CONTACT → RELOCATE → SETTLE`).

The plan's reading is the sensible one: ENTER *is* the seek to the first point, so a break before any shot makes no
sense. List it with the other deviations so t14 and t19 do not re-derive it.

### 8. NON-BLOCKING: the "hold BREAK_CONTACT" retry contradicts its own end condition
**Checked:** plan lines 71–73.

"Nothing legal → stay and restart the clock (one more `break_cap`, then retry)" does not match the end condition
`phase_time ≥ break_min and (d ≥ 0.9·range or …)`. A sniper already past 0.9·range retries after `break_min`
(1.0 s), not `break_cap`.

Also, while held in Open Space, the sniper keeps flying away at 320 px/s with no bound. An enclosed player sends it
640 px further per hold. Pick one rule. For example, keep breaking only while `d < range + range_jitter`, otherwise
request zero. Make the enclosed-player row assert it.

### 9. NON-BLOCKING: smaller precision points
- **Plan line 90.** "In Assault both ends lie inside the convex grown rect" is false. The BREAK_CONTACT end can be
  outside `grow(−fire_margin)`, though it is inside the visible rect. The conclusion still holds for the visible rect,
  which is the one that matters for corridor pressure. Fix the wording.
- **Plan lines 56–59.** Say what the LOCK→FIRE LOS ray targets: P (as SETTLE does) or `lock_point`. The two differ for
  a moving player.
- **Lock-point row.** The ≤ 2 px tolerance is about one tick of a 120 px/s player plus the intercept's motion. Freeze
  `lock_point` from the aim computed on the same tick LOCK is entered, and have the test read the intercept on that
  tick. Otherwise it fails by one tick of lag.
- **Missing cases.** There is no case for the SETTLE-end LOS refusal (a rock placed during RELOCATE → SETTLE →
  BREAK_CONTACT, never AIM, never CHARGING). There is also none for a budget that expires in LOCK and is resolved by a
  refusal (→ DISENGAGE at the refusal). Both can regress silently. Cheap additions.
- **Attack-in-budget row.** "200 px past it away from the spawn" is per *offset*, not per class: the side class
  holds both ±500 spawns. State the per-offset stub.
- **Asteroid fixtures.** The fixture must sit on a `LineOfSight.BLOCK_MASK` layer (`ENVIRONMENT` or `HAZARD_CONTACT`).
  The default `StaticBody2D` layer 1 is fine; say so so nobody moves it.

# Review round 2

VERDICT: APPROVED

Reviewed `3-plan.md` Revision 2 against round 1, the epic plan (§2.5, §2.9.4, §4 t13 row, line 800), and the
uncommitted implementation (`git diff` plus the new `rail_trail.gd`). I ran these myself:
- `test_sniper.gd`: 40/40, 6825 asserts. Printed bearing changes: Open Space 134.6 / 166.5 / 129.1°, Assault
  115.3 / 115.6 / 92.3°. Closest approach after the first shot: 476 px (clearance 405) and 370 px (clearance 306).
  Every level-1 offset reaches AIM with 4.6–7.8 s of budget left.
- Green: `test_enemy_mover_single_writer`, `test_signal_emit_arity`, `test_config_instance_isolation`,
  `test_enemy_dual_mode`, `test_enemy_bullet_lifetime`, `test_resource_uid_integrity`, `test_suite_integrity`.
- Not run here: the contact/hurtbox geometry gates, sprite transparency and project load. The change touches no
  scene, so they are low risk, but the full gate must still run before the commit.

## Round-1 blocking findings

1. **Resolved.** RELOCATE no longer flies past the player.
   - The path-clearance filter is `_path_clears`, `sniper_brain.gd:374-376`, applied in `_legal`/survivors at `:345,349`.
     It applies to ENTER and to travel-cap re-picks as well as BREAK_CONTACT, which is right.
   - `test_no_relocation_path_passes_through_the_player` can fail: from bearing 0 at 1000 px the top-scoring
     candidate without the filter is the ≈180° one, whose chord runs through P.
   - The dual 4-shot row now measures real positions on every tick after the first shot. That also covers the
     path's curvature from BREAK_CONTACT momentum, which the straight-chord filter does not model.
2. **Resolved.** Corridor-safe BREAK_CONTACT now has its own test.
   - Code: `_corridor_safe` `:540-557`. Test: `test_assault_break_contact_stays_inside_the_corridor`, with the three
     setups.
   - I traced the "turned" setup: the x-axis is blocked at 130 px of room against a 213 px threshold, the remainder
     (0, −0.097) is negated to (0, +1), and it slides down. Without the step, the sniper leaves `inner_rect()` within
     about 0.4 s, so the in-rect assertion fails.
   - I re-derived the worst case. `move_toward` steps along a straight line in velocity space, so the axis share is
     constant during a step. That case is `a·√(a² + (320 + b)²)/(2·520)` with `a² + b² = 320²`. It peaks at
     ≈ 152 px (a ≈ 305), against the 197 px braking term plus `EDGE_KEEP`, so the threshold holds.
   - The threshold uses `mover.acceleration` (520), not `braking` (700). That is correct: a 320 px/s request is never
     shorter than the current velocity, so `step()` uses `acceleration`.
3. **Resolved.** The side rule is now tested.
   - Code: `_enter_break_contact` `:495-505`, matching `Steering.break_contact`'s `away.orthogonal() · side`
     (`steering.gd:200`). Test: `test_break_contact_never_crosses_the_players_line` (dual).
   - The sign and never-shrinks assertions alone would still pass with the side flipped, because the radial term
     dominates. The > 570 px growth assertion is what catches a flipped side; the test comment says so.
4. **Resolved.** The forward-cone row can now fail with the filter deleted, in both ways it could be removed.
   - Forcing `cone_ok` true breaks the per-candidate flag assertions.
   - Dropping `cone_ok` from the survivor test breaks "no point in the cone": the sniper starts at bearing 0, so the
     nearest candidate is in the cone.

## Deviations

All are sound.
- **`break_min`:** necessary, as accepted in round 1.
- **Tier-A slack:** needed because the measured fire bearing differs from the chosen point's bearing. Tier B remains
  exactly the epic's hard rule.
- **ENTER → SETTLE:** sound.
- **LOCK checking both lines:** strictly safer than the epic.
- **Hold/retry rule:** one rule, bounded, and asserted by the enclosed-player row. Without the hold that row fails by
  more than 1000 px.
- **Clearance 0.45:** defensible, but the rationale is partly wrong (N1).
- **Per-trip travel cap:** acceptable for t13, with a caveat (N2).

## New code

No correctness bugs found. Convention checks:
- **Single writer:** the brain only calls `request_velocity`, `arrive`, `face_toward`, and (pre-existing) sets
  `max_speed` / calls `release_constraint()`. It reads `actor.velocity` but never writes it.
  The barrel writes only `scale.y` / `position.y`, never a rotation.
- **No timers:** none in the brain or in `RailTrail`.
- **Signal arity:** `EnemyBullet.expired` is bare, so `.bind(round_)` matches `_on_round_expired(round_)`.
- **One projectile owner:** the round stays pool-owned; the trail is not a projectile and frees itself.
  The one-shot `expired` connection plus the weakref covers both the recycle and `cancel_active()`, and both paths
  are tested.
- **Budget deferral:** expiry checked before `match` in `tick()`, with `_after_shot()` consuming `disengage_pending`
  on a shot, a refusal or an empty pool. This is correct on every path, including expiry on the AIM→LOCK tick and on
  the firing tick.

## Findings

### N1. NON-BLOCKING: the 0.45 rationale overstates what 0.6 would do
**Where:** `3-plan.md:138-142`.

0.6 would not push *every* Assault choice into the fallback.
- With P at (640, 560), the 135° ± 15° seeds leave a legal band at about 120–130° below the player. It sits inside
  the grown rect (y ≤ 1004, x ∈ [51, 1229]).
- A same-side move from ±60° to it is a 60–70° change whose chord passes about 580 px from P, so it survives 0.6.

What 0.6 really forbids is crossing over the top of the player. The sniper would then see-saw on one side, and the
fallback would be needed only when the jittered band misses. 0.45 is still a reasonable judgement value. Correct the
wording before it goes into DECISIONS.

### N2. NON-BLOCKING: the per-trip travel cap is now effectively only a stall guard
**Where:** `sniper_brain.gd:233-237`, `:257-261`.

With `max(relocate_cap, travel/relocate_speed + 1 s)`, a moving sniper normally arrives before the cap.
- **Boost-away:** for long trips, the epic's reaction (§ table line 800, "re-picks its point in the new player frame")
  now comes up to about 3 s later than the flat 4 s cap would allow.
- **No range check:** nothing checks range at SETTLE/AIM, so a sniper can aim from a point the player has left far
  behind, or flown onto.

This is not in the t13 acceptance criteria and is logged as a deviation. A cheap follow-up (t19 or tuning) would also
re-pick when `|target_point − P|` leaves `range ± 2·jitter`, or when `_path_clears` no longer holds for the remaining
path.

### N3. NON-BLOCKING: in Assault, corridor negation can override the side rule
**Where:** `sniper_brain.gd:553-554`.

When the remainder is negated, its lateral share flips. So near a wall the slide can cross the player's forward line.
The corridor rightly wins, and range is still non-decreasing. Say so in the plan's BREAK_CONTACT text or in
DECISIONS, so t21/t22 do not file it as a bug.

### N4. NON-BLOCKING: the trail lives in `EnemyContainer`, which `_wait_enemies_cleared` counts
**Where:** `rail_trail.gd:36-52`; `level_director.gd:170`.

`LevelDirector._wait_enemies_cleared` counts every child of the container. So a trail can hold an ENEMIES_CLEARED
section open for up to `trail_fade` (0.4 s) after its round is freed, for example when the sniper dies right after
firing. That is bounded and irrelevant while level-1 snipers stay on rails (rails get no trail). The t21/t22
deadline rows must add `trail_fade` to the sniper's worst-case exit.

### N5. NON-BLOCKING: the exit-time leak lines are not caused by this change, but run the full leak check
The single-file run prints `ObjectDB instances leaked` and `66 resources still in use` at exit. The committed
`test_bomber.gd`, run alone, prints the identical lines (also 66), and a unit file (`test_health_component.gd`)
prints none. So this is the integration harness's single-file artefact, not this change.

Plan step 7's `scripts/check-test-leaks.sh` over the full suite is still the real check. Run it before committing:
the attack-in-budget row awaits frames and frees harnesses mid-test.

### N6. NON-BLOCKING: small fixes and the docs step
- **`sniper_brain.gd:94-96`:** the `last_candidates` doc omits `path_ok`.
- **Assault checks use two different keys:** `_assault()` uses `budget.active` (`:287`), while the rect filter and
  corridor-safe use `mover.constraint != null` (`:322`, `:518`). They coincide today, because the corridor is the
  only `MovementConstraint`. One predicate would be clearer.
- **Plan step 8 is not done yet:** `ENEMY.md`, `assault.md` (RailTrail) and DECISIONS are untouched in the working
  tree. All six deviations, plus N1's corrected rationale and N3, must land in DECISIONS with the commit.
