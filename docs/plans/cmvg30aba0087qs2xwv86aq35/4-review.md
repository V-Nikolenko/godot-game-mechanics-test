VERDICT: CHANGES_REQUESTED

# Review: t14, the Fighter waits behind a wreck (`3-plan.md`)

I checked the plan against the code. Its structure is sound:

- COVER is a separate phase, appended to the enum.
- The claim is released in one place, `enter_phase()`.
- The no-hazard path costs one compare.
- `_derive_pass()`, the RUN_IN latch and the squad hold are untouched.

Most of its claims about the codebase hold (see "Checks that hold" below). Four problems need fixing before
unattended implementation:

1. The hold motion repeats a pitfall the project has already documented.
2. The Assault pass reserve is argued only for the easiest geometry.
3. One liveness exit has no test.
4. The plan's case for Assault assumes COVER happens in level 1, and the spawn geometry nearly rules that out.

All four are cheap to fix. None needs a redesign.

## Major

### M1. A bare `mover.arrive(C)` every tick chatters at C, so the fighter leaves cover with a random heading

- **Checked:**
  - Plan "In COVER" step 2 (`mover.arrive(C, config.max_speed)` every tick).
  - `global/enemy_ai/steering.gd:26-35`: the slowing radius is `v²/2a`, which is zero at rest, so the request is full
    speed until the fighter is inside a sub-pixel radius.
  - `sniper_brain.gd:354-367`: "Arrival latches with hysteresis … re-seeking a point the sniper is already on would
    chatter at full speed round it".
  - `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md:1641`: the same warning, written for later tasks to reuse.
  - `fighter_brain.gd:1454-1457`: `_heading()` is the velocity direction above 1 px/s.
  - `:1157`: `_best_path` plans the Dubins lead-in from `_heading().angle()`.
  - `:1195`: `_track` turns from `_heading()` at 1.8 rad/s.
  - `:678`: the breach pass picks its lane side from `_heading()`.
- **Problem:**
  - At C the fighter flips between about 0 and 12 px/s every tick or two (accel 700 → 11.7 px/s per tick), along its
    approach axis. At the exit tick `_heading()` is therefore that jitter direction, not the nose that `face_toward(P)`
    turned onto the player. About half the time it points away from the player.
  - Any post-cover lead-in then starts with a Dubins plan from a backwards heading. That covers a lead-in by a squad
    LEAD, and by a solo whose C is beyond the breach radius (about 355 px in Assault for the plan's own layout; see M2).
    The plan can loop at radius 183 px and cost up to about 1.75 s of turning, which eats the Assault reserve.
  - Row 3 cannot see this. Its `T_lead` control is spawned "from the exit pose (same position, velocity, rotation)", so
    it copies the jitter.
- **Fix:**
  - Reuse the Sniper's arrival latch. Within an arrive radius (for example 10 px) request `Vector2.ZERO` plus
    `face_toward(P)`; re-seek C only beyond twice that radius (20 px, below `COVER_HOLD_PX`).
  - The fighter then holds at rest with its nose on the player, and `_heading()` at the exit reads that nose.
  - In row 3 (Open Space, static wreck and player), assert the exit pose: `actor.velocity.length() <=
    HEADING_MIN_SPEED` and the nose within `nose_cone_deg` of the player.
  - Add the latch to the plan's "Existing code to reuse" table.

### M2. The 3.0 s `cover_pass_reserve` is argued and tested only for a solo fighter that breaches

- **Checked:**
  - Plan §N2 ("S is 480 px out … plus the lead-in or a breach") and its "Alternatives rejected" (the reserve
    "already guarantees the pass's time whatever the trip took").
  - `fighter_brain.gd:649-655`: a squad member never breaches; it flies to S.
  - `:1087-1094`: the station-arrive is used only within 2 plan radii (366 px).
  - `:903-909`, `:955-957`, `:1006-1014`: `_go()` refuses when `run_budget_slack() <= 0`, so a member "holds and leaves
    with the budget".
  - `:602-608`: `_clamp_run`. In the plan's own Assault layout S is clamped to about (985, 200), so the breach radius is
    `min(480, |S−P̂|) − 25` ≈ 355 px, not 455.
- **Problem:**
  - **Squad LEAD in Assault.** After cover it must fly to its FRONTAL S, which in the harness is clamped to y ≈ 15, and
    then hold. Example: the cover ends at the reserve (3.0 s left) and C is about 380 px from S. A lead-in of about 1.5-2 s
    leaves roughly 1.0-1.5 s at S. The run needs `along/300 + 0.25` ≈ 1.4 s, so `_go()` refuses and the LEAD never
    attacks. That breaks the plan's own promise, "never at the price of its attack (Assault)".
  - **Solo in Assault.** In Assault, C usually needs a lead-in: the fighter spawns more than 800 px from the player (M4),
    and C must lie between `cover_break_range` (300) and about 355 px of the player to breach. Row 12 tests only the
    breach geometry (C at 325 px).
  - This is also epic review N2's "cross-checked with `run_budget_slack()`", which the plan did not do.
- **Fix:** add two Assault rows:
  - (a) A squad of two, wreck on the LEAD's way in, the reserve exit forced (as in row 12). Assert the LEAD's RUN_IN
    starts with `run_budget_slack() > 0` and a burst opens before DISENGAGE.
  - (b) A solo whose C lies beyond the breach radius, so it needs a lead-in. Same assertions.
  - If either fails, make the exit trip-aware rather than just raising the constant. For example, leave COVER when
    `remaining() <= cover_pass_reserve + |C − pass_start| / max_speed`, deriving the pass with no side effect, or for a
    LEAD when `run_budget_slack()` measured from S would drop below the hold margin. Alternatively, keep squad LEADs out
    of Assault cover and record that in DECISIONS.
  - Drop the "guarantees … whatever the trip took" wording unless the rows prove it.

### M3. The `cover_max` exit has no row, and it is the only liveness bound in Open Space

- **Checked:**
  - Plan "In COVER" exit list.
  - Test plan rows 3-13.
  - `engagement_budget.gd:50-53`: `remaining()` is INF in Open Space, so the reserve exit never fires there.
- **Problem:**
  - In Open Space, when the hold cannot complete, `cover_max` is the only exit while the player stays more than 300 px
    away and the wreck lives. That happens with a strafing player, a small (r 13) wreck the 30 px tolerance cannot hide,
    or a C blocked by a body.
  - Row 3's `t_exit ≤ cover_max` is satisfied by the hold, so a broken `cover_max` (for example `_phase_time` reset each
    COVER tick) would leave a fighter in COVER indefinitely with every row green.
- **Fix:** add an Open Space row:
  - Raise `cover_hold` past `cover_max` on the private config, or keep the hold from completing.
  - Assert COVER is still the phase at `cover_max − DT`, APPROACH is emitted at `cover_max` (± 1 tick), and the claim is
    released.

### M4. In level-1 Assault, the first APPROACH tick is off-screen, so COVER will rarely trigger, but the plan argues the opposite

- **Checked:**
  - `wave_manager.gd:194`: spawn = camera + offset × 2.
  - `arena_camera.gd:39-43` and `assault_corridor_constraint.gd:83-88`: the corridor is x −100…1380, y −380…1100.
  - `level_1_director.gd:968-988`: fighters `.at(±500, 40)` → x = −360 / 1640, and `.at(0, −400)` → y = −440.
  - `fighter_brain.gd:166`: Assault fighters start in APPROACH, so their first APPROACH tick is the spawn tick.
  - `wreck.gd:190-193`: Assault wrecks always drift down at 60 px/s.
- **Problem:**
  - With `cover_search_radius` 500 measured from the spawn point, an Assault fighter can only take a wreck in the outer
    ~60 px (top entry) or ~140 px (side entry) of the screen near where it enters, or in the off-screen buffer.
  - Wrecks are born where ships die and drift away from the top. COVER in level 1 is therefore close to an Open Space
    feature in practice.
  - The plan's case for keeping it dual-mode rests on the opposite premise ("level 1 is where wrecks appear in numbers").
    So does its main risk ("fighters spawned after a fighter died now find wrecks"). In the wreck-guard replay the
    66 s fighters' wrecks are ~900+ px from the 72 s spawns by then.
- **Fix:**
  - Count COVER entries in `test_cloud_descent_clears_in_time_with_wrecks_left_behind` (connect `phase_changed`; print
    the count with the existing `gut.p`) and report it.
  - Record the real Assault reach in DECISIONS and in the owner-facing summary.
  - If the owner wants level-1 fighters to use cover, that is a deviation from the task's "first tick" and needs its own
    justification. For example: in Assault, run the check on the first APPROACH tick inside the corridor, with
    `cover_min_budget` re-derived for it. Raise it as an option; do not build it silently.

## Minor

- **m1. The wreck guard: the plan's lever targets the wrong thing, and one green run is not evidence.**
  - Checked: `tests/README.md:468` (this replay's clear time varies 8.15-9.15 s over 4 runs), `test_level1_fighter_exit.gd`
    file header (fighters leave ≈ 4.5-4.8 s after `waves_complete`, so they are not the last out), and epic §2.9 (the
    guard's pre-approved levers: Assault wreck `avoid_weight` 0.3, then halve `wreck_chance`).
  - The fighters' own life is bounded by the budget arithmetic, which COVER cannot extend. Any regression would come
    through wreck placement affecting the drones or the Ram, and a larger `cover_pass_reserve` does not address that.
  - Fix: run the guard at least 3 times before and after, and report the maximum. If it fails, look at who leaves last:
    use the reserve only if a fighter is last; otherwise use the §2.9 levers in order. Never raise the timeout.
- **m2. "Once per RUN_IN": the clearing side is untested, and plan line 30 overstates it.**
  - `_cover_used` is cleared only in `_enter_run_in()`. `_enter_calm()` (`fighter_brain.gd:450-467`) leaves it set.
  - So a hub fighter that took cover, never ran in, went RETURNING and was woken again takes no cover. That contradicts
    "Open Space: each time the hub idle wakes the fighter".
  - Fix: decide whether `_enter_calm()` clears it (a new engagement), fix the sentence, and add an Open Space row:
    cover → RUN_IN → RETURNING → re-notice → COVER again, plus the converse.
- **m3. A LEAD in COVER can be demoted by a later join.**
  - `squad_controller.gd:60-65` calls `_reassign()` on every `join()`, and `:202-226` re-sorts roles by distance to the
    player. Level-1 squad members join up to 0.8 s apart (`level_1_director.gd:982-986`).
  - Fix: add the exit "`_role()` is no longer LEAD → APPROACH" (one compare; it keeps S15 true at every tick), or accept
    the case explicitly in DECISIONS.
- **m4. No target in COVER is unspecified.**
  - `TargetInfo.player()` returns an empty info (`target_info.gd:25-31`), so C would be computed from `Vector2.ZERO`.
    `can_see_player()` is false with no player, so the hold would "complete".
  - Fix: on `not target.has_target`, leave for APPROACH, which already requests zero.
- **m5. The Assault case of row 11 cannot happen with shipped values.**
  - The reserve exit (3.0 s) always comes before budget expiry.
  - Fix: say the row sets `cover_pass_reserve = 0` (and a large `cover_hold` / `cover_max`) on the private config, and why.
- **m6. Every Assault wreck drifts, and every planned row holds the wreck still.**
  - `test_sniper.gd:1463-1468`'s `_wreck()` turns off physics processing. So no row tracks a C moving at 60 px/s, and the
    "C has left the shrunk corridor" exit is never exercised.
  - Fix: let the wreck drift in the Assault case of row 13. Assert the hold completes or COVER ends on the corridor rule,
    with the claim released.

## Nits

- **n1.** `_inside_other_hazard()` duplicates `sniper_brain.gd:633-637`. That is fine at five lines, but a shared static
  helper would keep the two cover users from drifting apart.
- **n2.** Explosive wrecks pass every rule.
  - C is `r + 40` from the centre, inside the 110 px blast, so a player who shoots the wreck hurts the hiding fighter.
  - This matches the Sniper and is good bait, but say so in `ENEMY.md`, or exclude explosive wrecks deliberately.
- **n3.** Row 3's `T_lead` control must run with the subject's wreck unregistered (the registry is static).
  - Otherwise the control takes cover too, or its pass differs. Say so in the row.

## Checks that hold

- **APPROACH entry points.** APPROACH is entered at construction (`:166`), from NOTICING (`:438`) and through the test
  seam. REPOSITION never hands to APPROACH (`:814-834`, `:839-844`, `:955-962`), so the epic's "a REPOSITION that hands
  to APPROACH" is correctly dropped.
- **The first-tick hook.** Placing it after the `has_target` guard and before `_derive_pass()` catches all of these
  entries. `_leave_cover` → `enter_phase(APPROACH)` re-arms the check, which `_cover_used` then refuses, so there is no
  loop.
- **No-hazard path.** It draws no rng. The mover's pass-through with a far registered hazard is exact
  (`enemy_mover.gd:221-251`), so row 9 is a real identity test.
- **Claim release (N3).** Release in `enter_phase()` covers APPROACH, DISENGAGE and RETURNING; AnchorIdle can only reach
  RETURNING from COMBAT (`anchor_idle.gd:53-70`). `on_suspended()` covers rails, and `HazardInfo.try_claim()` handles a
  freed claimer by instance id. N3 is settled.
- **N2 arithmetic.** `budget.update()` runs before the dispatch (`:279`). 5.0 < 6.0 − 1/60 holds, and the row-8 boundary
  (±0.5·DT around `cover_min_budget`) is correct. Budget expiry in COVER cannot be deferred by a burst
  (`_try_open_burst`, `:1312`), so the deadline / attack-in-budget gates (no hazards) are unaffected.
- **N8.** `predicted_position()` and `_slow_for_mates()` behave as the plan says for a mate in COVER (`:1247-1263`,
  `:1594-1607`). COVER calls the mover directly, so `_give_way` never runs for it. N8 is recorded as accepted, which the
  epic review allowed.
- **Hand-ticked rows.** These are valid with a real held-still wreck, because the fighter approaches C from its own side
  and never touches the body. Rays see the body after the two physics frames.
- **Gate time.** About 15 hand-ticked dual cases at 0.02-0.1 s each, plus two 8× live cases at about 0.4 s, fit the +3 s
  allowance, including the rows requested above.
- **Conventions.** The single-writer gate, the flat-config gate and the appended enum all hold.

## Round 2

VERDICT: APPROVED

I re-checked Revision 1 against the code: `fighter_brain.gd`, `steering.gd:26-35`, `sniper_brain.gd:352-367`,
`wreck.gd:181-193` / `:452-459`, `base_enemy.gd:275` and `fighter.gd:59-62`. Every round-1 finding is resolved or
reasonably declined. The four items left are all small enough to apply **during implementation without another
review**. The exact change for each is given below.

### Round-1 findings

- **M1 resolved.** The latch is the Sniper's `_travel()` shape: settle within 10 px, re-seek beyond 20 px (below
  `COVER_HOLD_PX`).
  - While settled it requests `cover.velocity`. `HazardInfo.velocity` is the wreck's real step velocity, yield included
    (`wreck.gd:181-186`, `_refresh_info`), so this is zero for a still wreck and for every test fixture.
  - The fighter then brakes to exactly zero: `move_toward` lands on the target once the gap is below 700 × DT. So
    `_heading()` reads the nose.
  - The nose converges inside the hold even at `max_turn_rate` 1.8 rad/s (`fighter.gd:62`).
  - Row 3's exit-pose assertion can now fail on the round-1 bug.
- **M2 resolved.**
  - The trip-aware exit `remaining() <= cover_pass_reserve + |X − S| / max_speed` pays for the flight to S from wherever
    the fighter is. It is conservative for a solo that breaches.
  - Rows 14 (squad LEAD) and 15 (a solo that needs a lead-in, with the breach-radius precondition) assert
    `run_budget_slack() > 0` at RUN_IN and a burst before DISENGAGE. Both are constructible inside the Assault corridor.
  - The fallback levers are ordered and bounded, and `engage_seconds` is never touched.
  - With a 5.0 s entry gate I found no spawn geometry in which the exit is already due on the entry tick: side entry
    ≈ 5.2 s, top entry ≈ 5.0 s, against 5.98 s remaining.
- **`_derive_pass()` called from COVER has no side effect I can find.** Walking `fighter_brain.gd:515-583`:
  - `_latched` is false before RUN_IN, so it always derives.
  - `_lead` is re-derived before any reader uses it: `_enter_run_in` re-derives, and `_begin_breach_pass` recomputes it.
  - `_rear_side` / `_rear_due` are reset exactly as APPROACH resets them every tick. A COVER fighter is LEAD or solo, so
    its kind is never REAR.
  - `_frontal_sigma` is latched at the spawn / wake position, the same tick and position as today.
  - Mates read only `pass_dir` in `_crossing_stagger()`, and only for RUN_IN / EXTEND mates (`:976`).
    `is_braking_onto_station()` reads `pass_start` only in APPROACH / REPOSITION (`:389`). `predicted_position()`
    never reads it for COVER (`:1259`).
  - `run_budget_slack()` is read for REARs only (`:1045`) and by the new rows.
  - It writes nothing to `SquadController`.
- **M3 resolved** by row 16 (the `cover_max − DT` / `cover_max` boundary, with the claim released).
- **M4 resolved.**
  - The level-1 reach is stated plainly in §Problem.
  - The wreck guard prints a COVER count.
  - Checking at corridor entry is offered to the owner, not built.
- **m1-m6, n2 and n3 resolved.**
  - m1: 3× before / after, and the levers chosen by who leaves last.
  - m2: `_enter_calm()` clears `_cover_used`. A no-hazard write, and row 17.
  - m3: the demotion exit, plus a row-6 case.
  - m4: the no-player exit; APPROACH then keeps `_cover_check_pending` until the player is back, and `_cover_used`
    refuses a second cover, so there is no loop.
  - m5: reserve 0 in row 11.
  - m6: the Assault wreck drifts in row 13. A settled fighter riding at 60 px/s lags C by only the ~15 px/s rotation
    term, which the 20 px re-seek absorbs.
  - n2 and n3 are covered.
- **n1 declined** with a sound reason: it would touch the Sniper. Accepted.

### Remaining items, to apply during implementation (no further review needed)

- **R1 (minor): step order in `_tick_cover`.**
  - §"In COVER" lists the trip-aware reserve exit in step 1 but derives S in step 2 ("Otherwise …").
  - On the entry tick `pass_start` is still its default `Vector2.ZERO` (`fighter_brain.gd:179`), because the cover
    check runs before `_derive_pass()` in `_tick_approach`.
  - Implemented literally, `|X − (0,0)|` ≈ 1,250 px adds about 4.2 s to the threshold. Every Assault COVER would then
    end on its entry tick. Rows 3, 12, 14 and 15 would catch it, but the order should be fixed rather than discovered.
  - Order: (1) the no-player exit; (2) `_derive_pass(target)`; (3) the remaining exits, reserve included; (4) C and
    the latch; (5) the hold clock.
  - The plan's `_frontal_sigma` claim (taken at the spawn position) also needs step 2 to run on the entry tick, which
    this order gives.
- **R2 (minor): the M1 exit pose holds only for a still wreck.**
  - Open Space wrecks from deaths drift at 25 % of the dead ship's velocity (`base_enemy.gd:275`), up to about
    75 px/s. A settled fighter riding one leaves cover with `_heading()` = the drift, not the nose.
  - It is bounded (no budget in Open Space) and only cosmetic: a lead-in may start with a turn.
  - Add it to §Risks beside the Assault-drift note, and to `ENEMY.md`. No new row is required.
- **R3 (nit): row 3's exit pose.**
  - Assert it on the state the brain saw on the exit tick: the pre-tick `x0` / velocity of `_simulate`'s record.
  - After that tick's `_tick_approach` and mover step the fighter is already accelerating.
- **R4 (nit): rows 17(b) and the guard's COVER count.**
  - Row 17(b): a forced `enter_phase(RUN_IN)` leaves `_latched` true, because only `_complete_pass()` and
    `_enter_calm()` clear it. So assert only the COVER entry, or reach APPROACH again through a real pass and the idle
    cycle.
  - The guard's COVER count should count entries that held at least one tick, so a same-tick enter / exit never
    inflates the M4 measurement.
