# Review, round 1

VERDICT: CHANGES_REQUESTED

The design fits the task. It covers every §2.7.2 bullet and every §4 t8c case, reuses the board, the steering and the
t8b brain rather than rebuilding them, and keeps to the single-writer, flat-config, rng-only and signal-arity rules.
I checked D1 and D2 and both hold:

- **D1.** Solving the orbit chase `z' = 4(R·e^{iωt} − z)` gives a steady radius of `R·4/√(16+ω²)`. At ω = 0.55 that
  is 257.6 px (−0.9 %), with a 35 px lag at 141 px/s, inside the 60–220 px/s clamp. At 1.4 rad/s the request would
  be about 344 px/s, which the 220 cap saturates, so the epic value really does fail.
- **D2.** A ±0.35 rad offset leaves at least 50° between REARs at 90° spacing.
- **Budget gate.** `can_start_attack` needs 1.289 s of budget left (`swarm_drone_brain.gd:161-165`).

Four problems remain. Two are in the tests, and as specified those tests will fail or get weakened during an
unattended run. Two are in the mechanism.

## Blocking

**B1. The dual-mode cases ignore the Assault budget.** In the Assault harness `EngagementBudget` is active
(`engagement_budget.gd:31`). Every drone reaches DISENGAGE at 5.5 s (`swarm_drone_brain.gd:126`), and none can start
a WINDUP after 4.21 s.
- `test_formation_recovers_after_a_150_px_displacement`: 4 s of settling plus a 3 s recovery is 7 s, so every member
  has left before the check. This cannot pass in Assault.
- `test_the_lead_freed_mid_burst_…`: the first burst comes at about 1.4–2.9 s. The promoted flank then finishes its
  pass (about 1.65 s), goes REJOIN → CLOSE_IN, and needs time on the ring before `can_start_attack()`. "The new lead
  later bursts … a flank enters WINDUP after it" will usually fail the budget gate in Assault.
- `windup_seconds = 100` does not hold the lead in Assault. `can_start_attack()` is false (the budget has less than
  100 s left), so the lead circles CLOSE_IN's 200 px ring at 130 px/s forever (`:220-225`). That ring passes straight
  through both flank slots, which are also 200 px from the player, so separation pushes the flanks off their slots.
  The ≤ 30 px flank tolerance becomes timing-dependent.

Fix: every case that runs longer than about 4 s, or relies on `windup_seconds = 100`, sets `engage_seconds` and
`rear_engage_seconds` large on the private config (for example 1000). The only exceptions are the two
`rear_engage_seconds` cases. State this in the test plan.

**B2. `test_rear_holds_the_orbit_radius` samples through the role rotation.** With a squad of 5, the lead's
`release_lead` comes at burst + 2.9 s (two passes: 0.45 + 0.8 + 0.4 + 0.45 + 0.8). That is about 4.2–5.8 s, inside
the 3–6 s sampling window.
- `release_lead` pins the old lead to REAR (`squad_controller.gd:185-186`), wherever its overshoot left it, and it
  reaches FORM the same tick.
- The full recompute can also demote a flank to REAR mid-pass.
- `rear_index` and `rear_count` change, so every REAR's slot jumps by up to a whole spacing, and REARs cut chords
  across the ring.

All of these are "REAR-role members in FORM" that are legitimately out of tolerance, and the plan's only mitigation
(Risks, line 184) covers something else. Also, with 2 REARs, rear 1's first slot is diametrically opposite. That is a
520 px chord through the player at ≤ 220 px/s, so a 3 s settle is marginal.

Fix: freeze the attack cycle as the recovery case does (`windup_seconds = 100` plus B1's `engage_seconds`), settle
for 4 s, and keep the ± 10 % sample. The case `test_the_rear_ring_centre_stays_inside_the_corridor` has the same
problem and needs the same fix.

**B3. `rear_ring_angle` can be read as `NAN`.** Plan lines 40-42 say only `rear_index == 0` initialises it. Rear 0
is the first REAR in join order, not the first REAR to reach FORM. In an Assault formation spawned off-screen, or a
staggered wave, rear 0 can still be in APPROACH while rear 1 is in FORM. Rear 1 then computes
`NAN + idx·TAU/n + offset`, `Steering.orbit` returns a NaN velocity, and `move_and_slide()` puts the drone at NaN. No
planned case would notice: every squad case spawns all members inside 360 px, so everyone reaches FORM on the first
tick, in join order.

Fix: any REAR that reads `NAN` initialises the angle, to its own bearing minus `idx·TAU/n` minus `phase_offset`. Only
rear 0 advances it. Say that the ring stands still while rear 0 is not in FORM. Add a case: rear 0 held in APPROACH
far away while rear 1 is in FORM gives a finite velocity and the ring radius.

**B4. The attack window is not closed when the LEAD changes through a recompute other than the lead's own
leave/release.** The board clears `attack_window_open` only in `leave()` of the lead (`squad_controller.gd:63-64`) and
in `release_lead()` (`:121`). The trouble is that `_reassign()` is a full recompute by distance (`:162-186`). A
non-lead `leave()` (for example a flank that hits the player and detonates, which is the normal success case), a
`join()`, or a `_prune()` can all move LEAD to another member while the old lead is mid-cycle. The plan's REJOIN rule
(line 33) only acts when the member is "still LEAD", so the demoted lead does nothing, and the window stays open with
no lead in BURST. Two things follow:
- A flank that has not yet answered winds up with no lead burst.
- Every flank that did answer keeps `_answered_window == true`, because the window never closed (line 52). So the new
  lead's burst gets no pincer.

Fix: in `_reassign()`, clear `attack_window_open` whenever the LEAD member changes. This is one line and subsumes the
two existing clears. Add a unit case in `test_squad_controller.gd`, plus an integration case: free a flank while the
lead is in OVERSHOOT, positioned so the lead is demoted. The window then reads false, and the new lead's burst is
answered by a flank.

## Non-blocking

- **N1.** "The REAR member never enters WINDUP in 10 s" (line 165) is ambiguous. In Open Space the initial REAR
  becomes a flank at `release_lead`, about 4 s in, and then attacks legitimately. Assert "no WINDUP entry while
  `role_of(member) == REAR`" instead.
- **N2.** `_nudge()` reads mate velocities, but existing t8b cases join a bare `Node2D` mate
  (`test_swarm_drone.gd:622-627`). After REJOIN the demoted drone runs FORM in the same tick, so `mate.velocity`
  raises a script error. Read the velocity duck-typed, or only from `CharacterBody2D`.
- **N3.** The transition loop runs `for _i in 3` (`swarm_drone_brain.gd:131`), but the new chain OVERSHOOT → REJOIN →
  FORM → WINDUP needs 4 handler runs. As written, WINDUP's first tick makes no request. Raise the bound and update the
  comment.
- **N4.** `EngagementBudget.elapsed()` is not needed. `budget.seconds - budget.remaining()` gives the same value: it is
  `-INF` when inactive and capped at `seconds` after expiry, which is ≥ `rear_engage_seconds` by the config pin. It is
  optional, but it is one less API.
- **N5.** Initialise the ring angle from the drone's bearing to the clamped centre, not to the target. In the corridor
  case they differ by 160 px.
- **N6.** In the corridor boundary check, phrase it as "the maximum error over the samples is above 10 %". Distance
  from the player sweeps 100–420 px, so it passes through 260 on some ticks.
- **N7.** Checked, no change needed: in the nudge test, evade (220 px/s) outweighs coincident separation (6 × 30 =
  180 px/s), so "points away from the player" means dot > 0 and holds.

# Review, round 2

VERDICT: APPROVED

B1, B2, B3 (mechanism), B4 (board side) and N1–N6 are resolved in the revised text. The revision adds one small hole
next to B4, and the new B3 case has a construction error. Both are one-line spec corrections with no design
consequence, so they are **required amendments at implementation** (log them in DECISIONS), not a reason for a third
round. They are A1 and A2 below.

## Round-1 findings, checked

- **B1** is resolved. The budget rule (plan :168-171) covers every case over about 4 s and every `windup_seconds = 100`
  case. With `engage_seconds = 1000`, `can_start_attack()` (`swarm_drone_brain.gd:161-165`) is true for 100 + 0.45 +
  ~0.29 + 0.15 s, so the frozen lead really enters WINDUP and holds at `_hold_at` in both modes. It does not circle
  CLOSE_IN's ring through the flank slots.
- **B2** is resolved. The radius case (:178) and the corridor case (:189) are frozen. No window opens, so there is no
  `release_lead`. The only remaining recompute triggers are join, leave and prune, and a frozen 5-squad fires none of
  them. The roles, `rear_index` and `rear_count` are therefore stable over the 4 + 3 s run. The "exactly 2 REARs, both
  in FORM" sanity check is correct for 5 members (`squad_controller.gd:170`, `flank_count = 2`).
- **B3** is resolved in the mechanism. The formula at :40-44 is consistent. The initialiser's own slot evaluates to
  `bearing − k·TAU/n − off_k + k·TAU/n + off_k = bearing`, and every other REAR derives its slot from the same shared
  scalar, so the ring is one rigid ring. It advances only from rear 0's FORM ticks, and a NAN can no longer reach
  `Steering.orbit`. The case is miscounted, though (A2).
- **B4** is resolved on the board. Clearing on "lead before ≠ lead after" inside `_reassign()` works for every caller:
  - `leave()` and `_prune()` erase the lead's role before `_reassign()` runs (`:60`, `:151`), so a `_roles` scan finds
    no lead before and a new one after.
  - `release_lead` has the member as LEAD before and REAR after (`:185-186`).
  - The sole-member `release_lead` produces no lead at all, which also counts as a change.

  The existing unit cases `test_attack_window_clears_when_the_lead_that_opened_it_leaves` and
  `test_release_lead_clears_the_attack_window` (`test_squad_controller.gd:167-180`) both use the four-member rig, so
  they still pass. No other test reads `attack_window_open` (grep: only `test_squad_controller.gd`). The solo drone has
  no board. The sole-member t8b case (`test_swarm_drone.gd:592-614`) closes the window in REJOIN.

  One edge case: `_reassign()` returns early on an empty board (`:163-164`). If the last member was the lead, the
  window stays `true` on a board with no members, and the next `join()` clears it (no lead before, a lead after). That
  is harmless, but the "lead before" read must happen *before* that early return, or be a stored field. The class
  comment at `:30-33` also needs to be rewritten, because it describes the two clears this change removes.
- **B4 integration case (:190)** can be built. After the flank is freed, the survivors are the old lead (in OVERSHOOT),
  the other flank and the REAR. Teleporting the REAR next to the player before the `free()` makes the distance
  recompute (`_closer_to_hint`, `:190-195`) demote the lead. The demoted lead then takes the OVERSHOOT-exit rule to
  REJOIN, skips `release_lead`, and ends up as a flank in FORM. It answers the new lead's burst, since every
  `_answered_window` was reset by the closed window. Open Space has no budget, so nothing expires.
- **t8b cases still hold.** `test_a_lead_with_a_mate_hands_the_lead_on_at_rejoin` (`test_swarm_drone.gd:617-630`)
  now routes the demoted drone to FORM as a flank in the same tick. The bare `Node2D` mate is covered by N2's
  `CharacterBody2D`-only velocity read (:159), and the chain fits the loop bound of 4 (N3).
- **N1–N6** are all applied as described. N4 is right: `budget.seconds − budget.remaining()` (:100-102).

## Required amendments (apply at implementation, log in DECISIONS)

**A1. A lead demoted during WINDUP still opens the window at BURST.**
- *The defect.* Plan :31 opens the window on BURST entry when `_pass_role == LEAD`, and `_pass_role` is taken on
  WINDUP entry (:30). The only mid-pass role check is at OVERSHOOT exit (:32). So if any recompute moves LEAD away while
  the lead is in WINDUP, its BURST entry sets `attack_window_open = true` anyway. That means a non-lead opens the
  window just after the board closed it for the lead change.
- *What follows.* The flanks answer that stale window and latch `_answered_window = true`. The window then stays open
  through the *new* lead's burst, because nothing closes it until the next lead change, so the new lead gets no
  pincer. That is B4's symptom again, reached through the WINDUP → BURST gap instead of OVERSHOOT → REJOIN. It also
  breaks the board's documented invariant that only the current LEAD writes it true (`squad_controller.gd:30-31`).
- *It is not rare.* The lead winds up on CLOSE_IN's 200 px ring (`swarm_drone_brain.gd:219`, `CLOSE_IN_RADIUS`), and
  the flanks sit on slots at `flank_distance` = 200 px. The distance ranking between them is close to a tie, so any
  leave during the lead's WINDUP can hand LEAD to a flank. That leave might be a REAR shot down, or a first-window
  flank detonating while the lead holds its second-pass WINDUP (BURST 0.45 + OVERSHOOT 0.8 puts WINDUP 2 at +1.25 to
  +1.65 s after the first burst).
- *Fix.* On BURST entry, open the window only when `_pass_role == LEAD and _role() == LEAD`.
- *Test.* Add a case, or a boundary step inside the :190 case: demote the lead while it is in WINDUP (free a member so
  the recompute moves LEAD), let it burst, and assert `attack_window_open` stays false until the new lead's own BURST.

**A2. The B3 case (:179) needs a squad of 5, not 4.** A squad of 4 has one REAR (`squad_controller.gd:170`: LEAD + 2
FLANKs + 1 REAR), so there is no "rear 1". Build it with 5 members:
- Place the positions **before** `join()`, because roles are computed only at join/leave (`:45-50`) and never from a
  later teleport.
- The far drone (2000 px) must join before the other REAR, so that `rear_index` (join order among REARs, `:79-88`)
  makes it rear 0.
- The near REAR must still rank 4th or 5th by distance, for example 300 px from the player while the other three are
  closer.
- Add a sanity assert that `rear_index(far) == 0`, `rear_index(near) == 1`, and the far drone is in APPROACH
  throughout. At 220 px/s it covers under 900 px in 4 s, so it stays beyond the 360 px exit.

## Non-blocking

- **N8.** `rear_ring_angle` is never reset to `NAN`. A REAR that joins the ring later (after a recompute or a
  promotion) takes its slot on the existing ring, which may be across from where it is now. That drone then crosses
  the ring along a chord, as B2 described for a change in the REAR set. The tests never do this, since all their
  cycles are frozen. It is acceptable in play, but mention it in ENEMY.md.
- **N9.** Because the lead and the flanks are near-equidistant (see A1), the B4 rule will close the window fairly
  often in real fights, whenever a drone is shot down. That is the correct consequence of the epic's
  distance-recompute design (§2.4), not a defect of this plan. Note it in DECISIONS as expected behaviour, so a
  playtest observation of "pincer sometimes skipped after a kill" is not re-filed as a bug.
