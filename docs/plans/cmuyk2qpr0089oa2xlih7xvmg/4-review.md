VERDICT: CHANGES_REQUESTED

# Review of the t10 plan (Bomber bombing runs)

I read `3-plan.md` and `1-context.md`, the epic plan's §2.3, §2.4, §2.9.4, §2.10 and the §4 t10 row, the epic review's
B1, N7 and N9, and this code: `bomber_brain.gd`, `bomber.gd`, `bomber_config.gd/.tres`, `bomber.tscn`,
`enemy_ordnance.gd`, `contact_blast.gd`, `hurtbox_component.gd`, `dubins_path.gd`, `steering.gd`, `enemy_mover.gd`,
`engagement_budget.gd`, `target_info.gd`, `assault_corridor_constraint.gd`, `arena_camera.gd`, `wave_manager.gd:189-197`,
`fighter_brain.gd:395,1080-1215`, `test_bomber.gd`, `test_enemy_dual_mode.gd:374-420` and `enemy_ai_harness.gd`.

Most of the plan holds up. The B1(c) arithmetic is right, the plan-radius deviation is justified, and the build reuses
the right code. Two problems would leave the implementer with acceptance rows that cannot pass as specified:
- the live-player set-up is a chase the bomber cannot win;
- the new `pursuit_launch_range` ends a pursuit run flying straight at the player.

## What I checked and found correct

- **B1(c) arithmetic** (plan "Prediction"; `enemy_ordnance.gd:164-230`, `bomber_config.gd:142-145,191-201`).
  - At 220 px/s: `t_wall` = 180/170 + 0.5 + 0.4 + 110/220 = 2.459 s, so P̂ is 541 px ahead and the middle mine rests
    at 511 px.
  - The mine is released at run coordinate 204, which is 1.20 s. Arming counts from launch (`_clock >= arm_delay`),
    so it arms at 1.70 s. The player is then 137 px short.
  - The player reaches the trigger edge (431 px) at 1.959 s. That is the same at every speed, because the
    `(trigger + arc)/|v̄|` term cancels.
  - Detonation after the 0.25 s warning: 25 px short at 220, 30 px past at 440, 42.5 px short at 150. All are inside
    the 48 px blast.
  - The overlap poll (`_player_in_range`) adds one or two frames of lag, about 7 px per frame at 440. That still
    leaves ≤ 45 px.
  - `t_wall` at RUN entry is ≤ 2.69 s, below `mine_horizon` 3.0. The arithmetic is correct.
- **Ejection decay** (`enemy_ordnance.gd:179-182`). The plan's displacement `v₀·T/2` is right in the limit. With
  60 Hz ticks, the clock is incremented before the move, so the sum covers k = 1..17 of 18. That gives `v₀·0.1417`
  instead of `v₀·0.15`, about 5.6 % short.
  - The worst case is |rest − pos| = √(24² + 30²) = 38 px, which lands about 2.2 px short.
  - That is inside the plan's 4 px tolerance, and inside the 40 px line tolerance (30 px bow + 2 px).
  - Adding `mine_eject_time` and applying it in `Bomber.drop()` (`bomber.gd:79-85`) is the right way to share one
    number.
- **Plan-radius deviation** (`enemy_mover.gd:190-197`). `step()` caps the change in velocity at `acceleration·dt`
  (`move_toward`). `max_turn_rate` caps only `rotation` (`:210-213`).
  - So the velocity turn rate at 240 px/s is 260/240 = 1.08 rad/s, and the radius is v²/a = 221 px. The epic's
    150 px circle cannot be flown.
  - `max_speed / min(max_turn_rate, a/max_speed) × 1.1` = 244 px mirrors `FighterBrain.PLAN_RADIUS_FACTOR`
    (`fighter_brain.gd:92`). It is justified.
- **Deviations from the epic that are justified:**
  - Assault "one run per life". This is the epic's own words, §2.4 item 8.
  - `mine_eject_time`.
  - Recording B1(e) instead of honouring it. The board row requires it.
  - The plan-radius change.
- **Conventions.** These are respected:
  - requests only;
  - a `delta` clock, with no `Timer`;
  - `phase_changed(new_phase: int)` keeps its arity;
  - flat number fields with script defaults, so the `.tres` stays HP/contact/score;
  - no level data touched.
- **Reuse.** The plan reuses `DubinsPath.candidates/sample`, the Fighter's pure-pursuit `_track`, `Steering.turn_toward`
  and `orbit`, `Bomber.drop()`, and the existing DISENGAGE. Nothing is reinvented.
- **The Revision 1 demonstration can fail.** A damped lead frozen at APPROACH start (≈ 0.6·1.2·220 ≈ 160 px) is far
  behind a 220 px/s player after a 2–4 s approach. Clause (2a) then fails.

## Findings

### F1. BLOCKING: the stated live-player and outcome set-up is a tail chase the bomber cannot win, and "the line stands still over the last 1 s" cannot pass at 220 px/s once B1(c) is applied

Checked against `3-plan.md` ("Prediction", test plan rows (2), "line stands still" and "B1(d) outcome"),
`bomber_config.gd:142-145`, `assault_corridor_constraint.gd:84-89` and `dubins_path.gd:33-48`.

**How the clamp moves the line.** While `t_approach_left + c` exceeds `mine_horizon`, `t_wall` is clamped to 3.0 s.
Here `c` = 180/170 + 0.5 + 0.4 + (trigger + arc)/|v̄|. So P̂ = P + 3·v̄, and the line start moves with the player at
|v̄|.

B1(c) adds 0.5 s to `c` at 220 px/s, so the line only stops moving when `t_approach_left` drops below:

| Player speed | `t_approach_left` threshold | Path length at 240 px/s |
|---|---|---|
| 220 px/s | 0.54 s | 130 px |
| 150 px/s | 0.31 s | 75 px |
| 440 px/s | 0.79 s | — |

The epic's 1.04 s threshold no longer holds.

- **The common set-up cannot reach RUN in time.** The plan's set-up has the player at (100, 700) moving +x and the
  bomber at (700, 150). The line is vertical, its start at (760 + 220t, 520), heading down.
  - The bomber starts from rest, 60 px behind that start in x and 370 px above it. It must arrive heading down, so its
    x-velocity ends at 0, while the start recedes at 220 against the bomber's 240.
  - The Dubins length from a bomber travelling at about +x to a heading-down goal is at least a quarter turn at
    r = 244 (≈ 380 px). So it never falls below 130 px, and the clamp never releases.
  - A straight-line bound puts the earliest feasible RUN entry beyond 6 s, before counting the final turn. That is
    past `approach_cap`.
  - By then P̂.x (≈ 641 + 220·T) is far past the grown rect's 1316 px edge.
- **Consequences:**
  - The N7 claim "P̂ stays inside the grown rect at freeze, so nothing is clamped" is false.
  - In Assault the wall is clamped behind a player who has already passed it, so (2) and the outcome row fail.
  - In Open Space RUN arrives late or never, because the `approach_cap` re-choice picks MINE again (see F5).
- **At 440 px/s it is worse.** The player is faster than the bomber, so only a head-on geometry can ever reach the
  start.
- **The "line stands still" row fails at 220 px/s as written.** "Centre moves < 20 px over the last 1 s of APPROACH"
  includes about 0.46 s of the clamped regime, during which the centre moves about 100 px.

**Required changes:**
1. Specify a set-up where the bomber approaches from ahead of the player's track, and give the numbers that show P̂ is
   unclamped at freeze in Assault. For example, the player at (100, 700) moving +x and the bomber at about (1150, 150):
   - The line start then comes toward the bomber at about 220 px/s.
   - A heading-down bomber meets it at about 1.6–2.2 s.
   - P̂.x at freeze is about 1100, below 1316.

   Do the same for the 440 px/s outcome row. The test should assert, or print and assert, that P̂ was not clamped at
   freeze, so a later geometry drift fails loudly instead of quietly testing a clamped wall.
2. Re-state the stand-still row so it measures over the unclamped window: from the first re-plan with
   `t_wall < mine_horizon` to RUN entry. Assert that the window lasts ≥ 0.4 s (at least two re-plans), so the row
   cannot pass vacuously.
   - Do not "fix" this by raising `mine_horizon`. The t19 hub `lose_radius` inequality in epic §2.10 reads
     `mine_horizon · mine_speed_max`, and 3.5 s would push it past 1700.

### F2. BLOCKING: the new `pursuit_launch_range` leaves the bomber 120 px from P̂, flying straight at it, when the run ends; ESCAPE then passes about 40 px from a stationary player

Checked against `3-plan.md` ("Bombing line", the PURSUIT and ESCAPE rows), `bomber_config.gd:127-130,157`,
`steering.gd:474-483` and `enemy_mover.gd:190-197`.

- **Where the run ends.** P̂ sits at run coordinate `s_t` = L/2 + 300 = 480. The pursuit bomb launches at the midpoint
  (s = 180), but RUN continues to the line's end at s = 360. The bomber is then 120 px short of P̂ and heading straight
  at it.
- **What ESCAPE does from there.**
  - ESCAPE turns at min(1.4, 260/220) = 1.18 rad/s while speeding up from 170 to 220 px/s, so the turn radius is about
    144–186 px.
  - The closest approach to a player 120 px dead ahead is about 36–43 px.
  - That is inside the 96 × 44 body, so the `ContactHitBox` (35 damage) rams the player.
  - The distance falls from 120 to about 40, which breaks the board's "ESCAPE … opens distance" row.
- **Why it matters.** This is the deviation's own stated purpose ("turns away before overflying the player") failing.
  A slow, far player — the PURSUIT case — has P̂ ≈ P, so this is the normal pursuit run, not an edge case.

**Required changes:**
- Make the run end clear of P̂. For example, launch at the line's end with `s_t = L + pursuit_launch_range`, so the
  slow, ARMED straight is kept and ESCAPE starts about 300 px out, with a closest approach of about 210 px. Or end a
  PURSUIT run at its launch point.
- Add a PURSUIT case to the ESCAPE row: a stationary player at 800 px, with the distance growing from RUN end
  throughout ESCAPE. As specified, the row is satisfied by a GRAVITY set-up and would not see this.

### F3. NON-BLOCKING (but fix in the plan text): the choice rule gives a close 600 px/s player a GRAVITY bomb, not a pursuit bomb

Checked against `3-plan.md` "Ordnance choice" and epic §2.4 item 2.

- The rule is: MINE if 150 ≤ |v̄| ≤ 440; else GRAVITY if d < 420; else PURSUIT. So a boosting player within 420 px gets
  a gravity bomb, which moves at 120 px/s with a 1.0 s fuse and is useless against them.
- The epic's prose ("a boosting player gets a pursuit bomb instead") and the board row ("a 600 px/s player gets a
  pursuit bomb") both say otherwise. The epic's bullet list is the inconsistent part.
- **Change:** route `|v̄| > mine_speed_max` to PURSUIT whatever the distance, and place the 600 px/s stub inside
  `gravity_range`. Otherwise the row passes on distance alone and cannot fail on the speed rule.

### F4. NON-BLOCKING: nothing gates B1(c) itself; add one cheap discriminating assertion

Checked against `3-plan.md` step 7(ii) and test rows (2) and outcome.

- With t9's 0.25 s warning and t6's arm-time poll, the Revision 2 numbers (no B1(c) term) already pass (2) and the
  outcome row. At 220 px/s the player is 27 px from the middle mine when it arms, the mine triggers at once, and the
  player is 28 px past it at detonation.
- An implementation that drops the `(trigger_radius + arc_depth)/|v̄|` term therefore stays green.
- **Change:** add the property B1(c) actually buys, in both harnesses: at the middle mine's arm time,
  `(mine − player)·v̂ > trigger_radius`. That means the player enters the radius after arming, so the warning blink
  starts as they arrive. Revision 2 fails this (27 < 80), and the plan's design passes it (137 > 80).

### F5. NON-BLOCKING: `approach_cap` re-choice is a no-op, so an Open Space bomber behind a cruising player loops on MINE

Checked against `3-plan.md` "Ordnance choice" and "APPROACH".

- The re-choice runs the same deterministic rule on the same inputs, so 80 % of the time it re-picks MINE. A bomber
  that cannot get ahead of a 220–420 px/s player (F1's geometry) re-approaches a receding wall forever.
- **Change:** on `approach_cap`, take the next kind in the cycle (MINE → GRAVITY → PURSUIT) instead of re-evaluating
  the rule. PURSUIT is the epic's own answer to a "far or evasive" player.

### F6. NON-BLOCKING: GRAVITY: say which P̂ the 30 px ray row measures, and in which direction the 100 px/s player moves

Checked against `3-plan.md` RUN "GRAVITY" and epic §4 t10.

- The line is frozen over the damped P̂ at RUN entry. The release is about 1 s later, and the 15° correction toward the
  live P̂ shifts the ray by only tan 15° · 80 px ≈ 21 px.
- A 100 px/s player moving across the line drifts about 100 px in that time. So "within 30 px of the live damped P̂"
  fails, while "within 30 px of the frozen P̂" passes at 0° as well. The 15° cap is untested either way.
- **Change:** state the reference P̂ and the player's direction, and show the 15° number meets the row.

### F7. NON-BLOCKING: count only `ContactBlast` hits in the outcome row, and size the stub's hurtbox

Checked against `contact_blast.gd:9-10,37`, `bomber.tscn` (`ContactHitBox` layer 256) and `hurtbox_component.gd`.

- The bomber's own contact hitbox is also on layer 256. A stub `HurtBox` with mask 256 that counts `received_damage`
  would score a ram as a "mine hit". This matters especially if F2 is not fixed.
- **Change:**
  - Count `area_entered` where `area is ContactBlast`.
  - Give the stub the real player hurtbox's shape and size, so the 48 px blast margin is measured against what the
    game uses.

### F8. NON-BLOCKING: smaller points

- **Assault attack-in-budget, moving stub.** At 220 px/s from x = 640, the stub leaves the 1380 px corridor edge
  within about 3.4 s. The real player is clamped. Say what the stub does at the edge (stop, or bounce), and note that
  P̂ pins to the R edge almost at once (P + 3·v̄ = 1300 at t = 0). `wave_manager.gd:194` places (0, −400) design at
  (640, −440).
- **N9.** The plan does not say whether the WaveManager + ArenaCamera attack-in-budget harness is file-local or a
  `tests/helpers/` file that t13 and t17 can share. State it.
- **RUN stall guard.** The guard is `L/run_speed + 1.0` = 3.12 s, which exceeds the epic's stated ≤ 2.12 s deferral
  (§2.4 item 8). No ENEMIES_CLEARED section holds a bomber, so no gate depends on it. Either cite the bound or note
  the difference in DECISIONS.
- **GRAVITY overfly (epic design, not introduced here).** The GRAVITY line passes directly over a stationary P̂ at
  s = 260 and runs on to 360, so the bomber overflies, and can ram, the player it bombs. Worth a DECISIONS line for t21
  feel tuning. Not a blocker for this task.

## Summary of required changes
1. F1:
   - a head-on live-player and outcome set-up (220 and 440), with numbers showing P̂ is unclamped at freeze in
     Assault, asserted in the test;
   - the stand-still row measured over the unclamped window, which must last ≥ 0.4 s.
2. F2: a PURSUIT run that ends clear of P̂, and a PURSUIT case in the ESCAPE row.

F3–F8 are improvements the implementer should take; F3 and F4 are one line each and make two rows able to fail.

## Review round 2

VERDICT: CHANGES_REQUESTED

I re-read `3-plan.md` Revision 2 and checked it against `enemy_mover.gd:180-217`, `steering.gd:474-483`,
`dubins_path.gd:33-48`, `enemy_ordnance.gd:164-230`, `bomber_config.gd:119-222`, `fighter_brain.gd:1117-1140`,
`player_fighter.tscn:334-343` and `player_ship.tscn:259-266`.

### Round-1 findings now resolved

| Finding | Resolution | Plan lines |
|---|---|---|
| F2 | Resolved (details below) | 56-60, 150-151 |
| F3 | Resolved. The choice rule at `:36-37` sends `|v̄| > mine_speed_max` to PURSUIT at any distance. The 600 px/s stub sits inside `gravity_range` (`:140`), so the row can fail on the speed rule | 36-37, 140 |
| F4 | Resolved. The assertion is at `:126-129`. Revision 2 numbers give 27 px against 80, so it fails; this design gives 137 px, so it passes | 126-129 |
| F5 | Resolved | 38, 75 |
| F6 | Resolved: the gravity bomb inherits the heading, which is the epic's wording | 89-91, 142-144 |
| F7 | Resolved; one NON-BLOCKING nit below (R2-4) | 157-159 |
| F8 | Resolved | 79, 165-168 |

Details of the F2 resolution:
- **Distances check out.** P̂ abeam the end at 300 px gives a launch from the midpoint of √(180² + 300²) = 350 px at
  atan(300/180) = 59°, as the plan says.
- **The pursuit test can fail.** At RUN's end the player sits at 90° to the heading, so the first ESCAPE tick already
  increases the distance: a second-order term s²/600 ≈ 0.013 px, plus the turn away. The distance then grows
  monotonically. A design that ends with P̂ ahead, like Revision 1, fails the per-tick row.
- **The direction is now frozen per APPROACH** (`:50-53`). That is correct: from the line's start, the bearing to P̂
  is the line itself.

### R2-1. BLOCKING: the APPROACH goal still moves at |v̄| for most of the approach, and nothing leads it, so the "head-on" set-up is a lag pursuit too (F1 not fully resolved)

Checked against `3-plan.md:22-24,66-72,130-137` and `fighter_brain.gd:1117-1130`.

**How the goal moves.** While `t_approach_left + c > mine_horizon`, P̂ = P + 3·v̄. So the line start moves at the
player's speed:
- 55 px per 0.25 s re-plan at 220 px/s;
- 110 px per re-plan at 440 px/s.

At 220 px/s, c = 2.46 s, so this holds for all but the last 0.54 s (130 px of path).

**The plan tracks only the current goal.** It re-plans a Dubins path to the start as it is now. The only iteration
(`:71-72`) refines `t_approach_left` inside a `t_wall` that is clamped anyway.

**Why the head-on set-up still fails.** Take the set-up at `:130-131`: the bomber at (1150, 150), nose down, and the
line start at (760 + 220t, 520), heading down.
- The shortest path to the current start first turns the bomber toward −x. A lateral 390 px over a vertical 370 px is
  more than an S-curve at r = 244 can cover, so the path loops.
- The start is meanwhile coming at the bomber at 220 px/s. The x-gap closes long before the 370 px y-gap does.
- The start passes under the bomber, the goal flips behind it, and the approach becomes the same tail chase F1
  described.
- The geometry that works is the opposite of what the planner asks for. The bomber should fly straight down, slightly
  away (+x), which needs a world velocity of about (+10, 218).

**What the plan leaves the implementer.** "Exact coordinates are tuned in the test" (`:133-134`) hands over a search
for a spawn point at which a goal-chasing planner happens to converge. That is fragile, and the gameplay case (any
mine run against a moving player in Open Space) behaves the same.

**The stand-still row's ≥ 0.4 s floor is phase-dependent** (`:135-137`). The unclamped window is at most 0.54 s at
220 px/s. "From the first re-plan with `t_wall < mine_horizon`" lands anywhere in it on the 0.25 s re-plan grid, so
the measured window is between 0.29 and 0.54 s, and the row passes or fails depending on the spawn's phase.

**Resolve: plan to where the start will be, as the Fighter already does.** `FighterBrain._plan` iterates
`goal + target.velocity · T` for exactly this reason ("for a moving player, to where S will be on arrival",
`fighter_brain.gd:1117-1130`). The plan copies `_track` but drops this part. The simplest form:
- The Dubins goal is the line start through the **uncapped** wall point `P + v̄·(t_approach_left + c)`, iterated 3×
  on the path length like the Fighter.
- For a constant-velocity player that point does not move during the whole APPROACH, because `t_approach_left` falls
  as fast as P advances. The Dubins problem is then a static goal.
- It equals the capped P̂ at freeze, because c ≤ 2.69 < `mine_horizon`. So the wall, (1), (2), the outcome row and
  t19's lose-radius inequality are unchanged.
- `predicted_drop_point()` may keep reporting the capped value. `mine_horizon` stays as shipped.

Then:
- the stand-still row can measure the whole approach, or at least the last 1.0 s (the epic's wording);
- the head-on set-up becomes a requirement on the planner rather than a tuning search;
- F5's `approach_cap` fallback is left for genuinely unreachable players, such as a boosting one.

If the coordinator prefers to keep the planner as it is, the plan must instead:
- give a worked convergence for its set-up;
- drop the window floor to one re-plan interval.

### R2-2. NON-BLOCKING (strongly recommended, one default + one assertion): a gravity bomb released 80 px short of a stationary player cannot hurt it

Checked against `bomber_config.gd:167,183-186`, `enemy_ordnance.gd:198-224` and `3-plan.md:54,89`.

**What happens on the release.**
- The bomb is released when P̂ is `gravity_release_lead` (80) ahead and flies at 120 px/s.
- It arms at 0.3 s, 36 px later, with the player already inside the 80 px trigger. The 1.0 s fuse starts then.
- It detonates after another 120 px, which is 76 px past a stationary player. The blast reaches 48 px plus the 13.5 px
  hurtbox, so 61.5 px: a miss.

**This is the gravity-bomb analogue of B1.** The "slow/close player" response is harmless to a player who sits still.

**Resolve.**
- Raise the default to `gravity_release_lead ≥ trigger_radius + gravity_bomb_speed · gravity_bomb_arm_delay` = 116,
  for example 120. The bomb then triggers at the radius edge and detonates `speed · fuse − trigger_radius` = 40 px
  past the player, which is a hit.
- Assert that inequality next to t9's mine inequality.
- The GRAVITY geometry still fits: s_t = 180 + 120 = 300 < 360, and the bomber ends 60 px past the player, heading
  away, so the ESCAPE row is unaffected.

### R2-3. NON-BLOCKING: two geometry cases the plan leaves undefined, and both occur in its own rows

Checked against `3-plan.md:50,56-63,164-165`.

- **Tie-break.** "Rotated by `approach_angle` toward the bomber's heading side" has no answer when the heading is
  parallel to the bearing. That is exactly the stationary attack-in-budget row: the bomber spawns nose-down at
  (640, −440) with the player straight below at (640, 360), and d = 800 gives PURSUIT. Name a tie-break, for example
  toward the corridor centre, else `rng`.
- **The Assault clamp for PURSUIT.** The clamp at `:61-63` assumes the line passes through the anchor. A PURSUIT line
  is offset 300 px from P̂. State that the offset line itself is clipped and slid, and that a slide may move P̂ off
  the exact abeam point; the per-tick ESCAPE row is Open Space or unclamped.

### R2-4. NON-BLOCKING: the stub hurtbox per harness

Checked against `3-plan.md:157`, `player_fighter.tscn:340-343` and `player_ship.tscn:265-266`.

- 13.5 px is the Assault fighter (r 5 × scale 2.7). The Open Space ship's hurtbox is r 5 with no scale.
- Use the mode's own size. The margins still hold: 30 px past at 440, plus up to 15 px of poll lag, is under
  48 + 5 = 53.

### R2-5. NON-BLOCKING: a sustained boost is never attacked

Checked against `3-plan.md:36,50-53`.

- A 600 px/s player gets PURSUIT, but the PURSUIT line translates with a damped P̂ that moves at about 600 px/s. A
  240 px/s bomber reaches its start only head-on. Otherwise `approach_cap` cycles it to MINE, which is just as
  unreachable.
- That is acceptable for this task: a boost is temporary, and the board row tests only the choice. It is worth a
  DECISIONS line next to B1(e).

### Summary
- One blocking item remains, **R2-1**: plan the Dubins goal to the uncapped wall point (the Fighter's
  arrival-prediction iteration). This makes the head-on set-up and the stand-still row robust.
- **R2-2** is a one-number fix that makes the gravity bomb able to hurt the player it is aimed at. It should ride
  along.

## Review round 3

VERDICT: APPROVED

I checked Revision 3 (`3-plan.md:22-38, 61-92, 148-190, 217-224`) against `fighter_brain.gd:1117-1130`,
`dubins_path.gd:118-150`, `enemy_mover.gd:190-197`, `enemy_ordnance.gd:138-147,198-230`, `bomber_config.gd:163-186`
and `assault_corridor_constraint.gd:84-89`.

### R2-1: resolved

The plan now caps only `c` and plans to the uncapped arrival time (`:23-31`, `:85-89`):
`t_wall = min(t_approach_left, approach_cap) + min(c, mine_horizon)`, with
`T = length(path to the line through P + v̄·(T + c)) / max_speed` iterated 3× on every re-plan. This is the Fighter's
`GOAL_PREDICT_ITERATIONS` pattern.

- **The goal stands still.** For a constant-velocity player, `T` falls as P advances, so the Dubins goal is static.
- **The wall at freeze is the epic's formula.** At RUN entry `T` = 0, so the frozen wall is
  `P + v̄·min(c, mine_horizon)`. With shipped numbers `c` ≤ 2.69 s < 3.0, so (1), (2), the outcome row and t19's
  lose-radius inequality are unchanged.
- **The 220 px/s head-on set-up now converges (`:148-153`).** The player starts at (100, 700) moving +x; the bomber
  starts at (1150, 150), at rest, nose down.
  - The start sits at (641 + 220·T, 520), and the fixed point is T ≈ 1.7 s.
  - The path is an S-curve of about 135 px lateral over 370 px vertical, about 410 px long, which fits r = 244.
  - P̂ at freeze is x ≈ 1015–1115, inside the grown rect's 1316. So `wall_clamped()` is false, and N7 holds in both
    harnesses.
  - Starting from rest makes `t_approach_left` (measured at `max_speed`) under-read for the first 0.92 s, so the goal
    drifts forward a little while the bomber accelerates. The stand-still row measures only the last 1.0 s of an
    approach of about 2.2 s, after the bomber reaches cruise.
- **The stand-still row (`:154-156`) can now pass and can fail.** A Revision-2 planner moves the centre about 100 px
  in that second.

### R2-2: resolved

Checked against `:63-65` and `:189`.

**Stationary player, with the overlap of the 80 px trigger and the player hurtbox counted:**
- The bomb is released about 120 px short and arms at 0.3 s, when it is 84 px out.
- That is already inside 80 + 13.5 (Assault) or 80 + 5 (Open Space), so the warning starts at arming.
- It detonates 120 px later, 36 px past the player. That is within 48 + r, so it hits, as the plan states.

**The 80 px default still misses:** the bomb detonates 76 px past, beyond 61.5 or 53.

**The asserted inequality is sufficient for a hit:**
- With `lead ≥ trigger_radius + speed·arm_delay` (116), the bomb is still outside the trigger radius when it arms, so
  it triggers at the radius edge or at arming.
- It then detonates at most `speed·fuse − trigger_radius` = 40 px past.
- That is within the blast in both modes.

**The geometry still works:**
- s_t = 180 + 120 = 300 < 360, so the bomber ends 60 px past P, heading away.
- The GRAVITY ESCAPE per-tick row and the "line through P" row are unaffected.
- The launch's `max_travel` (distance to the aim point + 120) is larger than the 156 px fuse distance, so it cannot
  detonate early.

### Nothing new blocks

Two notes for the implementer. Both are NON-BLOCKING.

**N-a: the 440 px/s outcome row needs its own spawn** (`:180-183`, "Head-on set-up as in (2)").
- At 440 px/s the wall start sits at (1072 + 440·T, 520). It passes x = 1150 at T ≈ 0.2 s and then outruns a
  240 px/s bomber, so the arrival iteration has no fixed point from (1150, 150). `T` hits `approach_cap`, and the run
  would cycle to the next kind.
- In Open Space (the only harness for this row) place the bomber where the start will be at T ≈ 1.7 s, about
  (1820, 150).
- Alternatively, start the player further left. Then assert that APPROACH reached RUN with MINE, so a mis-placed spawn
  fails loudly.

**N-b: the tie-break is degenerate in the stationary attack-in-budget row** (`:71-72`, `:184-186`).
- The bomber spawns at (640, −440), the player is at (640, 360) or (640, 560), and the corridor centre is
  (640, 360).
- So "toward the corridor's centre" is also parallel to the bearing.
- Fall back to the `rng` side whenever the centre is itself within the same |cross| < 0.05 of the bearing.

Neither affects the design. Each is a set-up detail that the plan's own assertions would surface on the first run.
