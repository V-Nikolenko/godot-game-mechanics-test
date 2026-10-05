VERDICT: CHANGES_REQUESTED

# Review of `3-plan.md` (Revision 1), round 1

I checked the plan against the code, not against the plan's own account of it. For measurements I re-ran the
prototype's own sweeps (`test_zz_sweep.gd`) on the working tree, plus three measurement files of my own. Those ran in
a throw-away copy of the project under `/tmp`, so nothing in the repo was touched.

The copy was taken from the 1327-line `fighter_brain.gd` prototype. While this review was running, `fighter_brain.gd`
grew to 1366 lines (mtime 08:31: a `_fly_ring` clearance change), `tests/unit/test_enemy_mover.gd` was edited, and
`tests/unit/test_fighter_avoidance.gd` appeared. **Implementation has started before a verdict.** The give-way code
the findings below are about did not change shape (`_give_way`, `avoidance`, `_share`, `give_way_rank`, the
`get_nodes_in_group` scan).

The role → pass-kind table, the window open/close, answer-once, the N3 "settled at S" gate, dry REARs and the
same-call reassignment are built correctly, and they match epic §2.5 and the Swarm precedent. The problems are all in
separation (D4) and in what the test plan can see. Among other things, the plan's own separation mechanism breaks the
pincer it exists to protect, and the planned metric cannot see that.

## Blocking

**B1 — D4 cannot be approved at task level. Either stay inside `flank_stagger`, or take D4 to the owner.**

- The acceptance line bounds the fix explicitly: "the only pre-approved fix is flank_stagger". D4 goes well beyond
  that:
  - a ~150-line reciprocal-avoidance layer;
  - D5, a change to the heading source that **every** phase steers from;
  - D6, new API on the shared `EnemyMover`.
- By CLAUDE.md, work that turns out to need more than its sizing ends the run `Result: ESCALATE`. A task reviewer
  should not grant it.
- The measurements do show that `flank_stagger` alone cannot pass. I re-ran the shipped sweep with `_give_way()`
  short-circuited:
  - **45/54 runs fail, worst 0.9 px** (the plan says 47/54, 0.5 px, so it is substantially confirmed);
  - the failures fall at **0.78–1.05 s, in APPROACH/REPOSITION pairs**, before any run exists for a stagger to delay.
- **Those collisions come from this plan's own D1/D2, not from the run crossing that the epic's estimate was about.**
  The LEAD reaches its station first and parks there. In `test_zz_one`-style traces the LEAD holds at S from 0.83 s,
  and the flanks' lead-ins pass through that station.
- That opens an in-scope alternative the plan never examined. `_best_path()` (`fighter_brain.gd:913-945`) already
  rejects Dubins candidates whose 16 px samples come too close to the player. Two ways to use it:
  - treat held or holding mates' stations (and, if needed, their predicted positions) as extra obstacles in that same
    sampling;
  - or choose the LEAD's station so that the flank lead-ins cannot cross it.
- The Swarm's existing `Steering.separation` nudge (`swarm_drone_brain.gd:652-673`, `steering.gd:122`) is the other
  precedent the plan cites and never measured.
- **Required:** Revision 2 either:
  - (i) meets the separation criterion with `flank_stagger` plus in-scope routing (no new avoidance layer, no D5/D6);
    or
  - (ii) records the measured comparison and ends the run ESCALATE, so the owner decides D4/D5/D6 as a scope change.

**B2 — D4 as built breaks the pincer and silences attackers, and the plan's metric cannot see it.**

- I counted every squad `RUN_IN` entry that did **not** come from a hold at S. That is an APPROACH/REPOSITION
  deadline or breach pass: a FRONTAL-shaped pass from wherever the fighter happens to be, which answers no window.
  Counts over the 54-run shipped sweep:

  | Build | Open Space | Assault |
  |---|---|---|
  | with give-way (this plan) | **7 / 81 runs**, in 6 of 18 layouts | **3 / 54 runs**, in 3 of 9 V3 layouts, and 1–2 attackers fire **0 shots** |
  | give-way disabled | 0 / 86 | 0 / 54, no silent attacker |

- Trace, Assault V3, player (640,560), `at(0,-230)`. This is the **first layout of the shipped sweep that the plan
  reports as passing**:
  - FLANK_LEFT stalls at (410,−9) from 1.2 to 2.8 s, **113 px from the LEAD holding at (480,80)**. That is exactly
    the 4-hull give-way disk (114.4 px). The nudge is ≈ (−190,−235) against a path that runs through the disk: a
    classic reciprocal-avoidance local minimum against a mate that cannot move out of the way.
  - It re-plans away from its S (295,400), never reaches it, and at its 4.99 s deadline it starts a breach pass
    712 px from the player.
  - The LEAD waited `lead_wait_max` for it (1.15 → 4.35 s) and started its run with 1.65 s of budget left.
- **Required:** the committed file must assert over every separation placement, in both harnesses:
  - every squad member's `RUN_IN` is entered from a hold at its S;
  - **each** LEAD/FLANK fires ≥ 1 round in Assault at the shipped budget. That is per attacker, not "the attackers
    fire ≥ 1" collectively.
- Without these, the window test's placements get chosen to dodge breach entries, and the regression ships.

**B3 — The plan's residual-failure claim is false. The known failures are in V3 and W5, the formations this task
ships.**

- §Risks says the residual failures are in "wider layouts (V4/V6, the player in a far corner)".
- My re-run of `test_zz_sweep.gd::test_wide` on the working tree gives **5 fails, not 6**. The three separation
  failures are:
  - **V3, Open Space, P(900,640), `at(170,−240)`: 24.0 px** (TURN/TURN at 10.1 s, inside the plan's own cycle
    window);
  - **W5, Open Space, P(400,480): 36.7 px**;
  - V6: 47.6 px.
- The other two are player clearance: V4 Open Space at 51.1 px in TURN, and Assault V6 at 30.7 px in DISENGAGE (the
  latter is the pre-existing out-of-scope exit).
- The worst failure is a V3, and P(400,480) is near the screen centre, not a corner.
- `test_members_never_come_within_two_hull_radii` "3 placements each" passes only because it reuses the shipped
  sweep's placements, which miss these layouts.
- **Required:**
  - correct §Risks;
  - put the known-failing V3/W5 layouts in the committed separation case, or fix them;
  - no hand-picked placements for an acceptance criterion.

**B4 — `test_rears_fire_nothing` is vacuous as specified. It cannot fail.**

- Measured at the shipped config:
  - **REARs fly 0 passes in all 9 Assault W5 layouts**: the 6.0 s budget expires first;
  - in Open Space their first dry pass comes at **12.3–19.95 s**. That is on the LEAD's second window at the
    earliest, by the "every second window" rule (`fighter_brain.gd:761-767`), so it falls at or after the plan's
    "over a cycle" end.
- A REAR that never runs trivially fires 0. The test would stay green even with the `pass_role == REAR` guard
  (`fighter_brain.gd:1138`) deleted.
- **Required:**
  - run until each REAR has completed ≥ 1 dry pass, and assert that as a precondition;
  - in Assault, give the members' **private** config copies a long `engage_seconds` (the shipped `.tres` is never
    written);
  - assert no CHARGING on those passes.

**B5 — The hand-tick harness collides with stale "ghost" bodies. In-game, fighters do collide with each other, and
the plan says neither.**

- The `Fighter` root is a `CharacterBody2D` on layer 1 with mask 1: `fighter.tscn:74` has no `collision_*` lines,
  and nothing sets them at runtime.
- `_tick()` calls `move_and_slide()` in a space that is never stepped inside a GUT test, so every fighter collides
  with its mates' **spawn positions**.
- Evidence, same Assault V3 layout as B2: FLANK_LEFT sits at v = (0,0) at (669,−152) from 4.8 s to 6.0 s while it
  requests 300 px/s, 59 px from the LEAD's spawn point (640,−100). With `collision_mask = 0` on the test fighters it
  flies on, and one of the two silent attackers disappears.
- **Required:**
  - the committed file removes member–member body collisions in the harness, e.g. `add_collision_exception_with()`
    per pair (test-only), with a comment explaining why;
  - the prototype numbers are re-measured that way.
- The plan's Problem statement ("pass through each other") is also wrong for the real game. The bodies collide
  physically, so without avoidance a flank bumps into, and slides along, a holding LEAD.
- Say so. The routing or avoidance work is about not bumping, and the separation assertion measures the brain, not
  the engine.

**B6 — The acceptance criterion says "pass in both harnesses". The plan marks three of the named cases
single-harness.**

- These cases have no "(dual)" mark, but each is named in the acceptance line:
  - `test_killing_the_lead_reassigns_in_the_same_call`;
  - `test_a_w5_flank_killed_promotes_the_closest_rear_in_the_same_call`;
  - `test_a_role_change_mid_run_keeps_the_latched_pass_until_reposition`.
- Make them dual.
- `test_the_pincer_and_the_frontal_pass` is Open Space only, but epic §4 marks the whole file Dual. Add an Assault
  variant: lateral runs, lanes 100 px apart, with the corridor bearing flip allowed. Or state the reason it is skipped.

**B7 — Assault timing is unexamined.**

- With D2, the LEAD's first `RUN_IN` in Assault lands **2.0–4.35 s** after spawn, against a 6.0 s budget (1.7–3.5 s
  without give-way).
- A solo t8b fighter from the same V3 spawn starts its run at 3.4 s.
- The pre-approved density lever 1 (`engage_seconds` 6.0 → 4.5, t16/t17, DECISIONS "Conventions") would leave many
  Assault squads with no attack at all.
- **Required:**
  - state the measured time-to-first-burst in Assault;
  - bound the holds by the remaining budget. The Swarm `can_start_attack` precedent works: in Assault, a member does
    not wait or hold when its remaining budget is less than a run plus a burst;
  - record the number for t16 in DECISIONS, as t8b's I8 note did.

## Non-blocking (the implementer must apply these)

- **N1:** Build step 1 says to remove "a scan of every enemy in the tree". But §3.3 item 1 ("including a mate that
  has left it to DISENGAGE") needs exactly that scan (`fighter_brain.gd:1062`, `get_nodes_in_group(&"enemies")`).
  The board cannot list ex-members. Make the plan consistent. This applies only if D4 survives B1.
- **N2:** `give_way_rank()` returns 0–3 for the non-run phases, but `_share()` (`fighter_brain.gd:1094-1101`) only
  tells RUN_RANK apart from everything else. The ordering is dead, so use a bool.
- **N3, X9 transient:** "a FLANK demoted mid-pass … keeps firing" lets 4 fighters fire at once after a closer join.
  Gate `_try_open_burst` on the latched **and** the current role being non-REAR. That guarantees ≤ 3 and costs one
  line.
- **N4:** `_reassign()` (`squad_controller.gd:202-224`) is a full distance recompute. After a FLANK death, the
  closest ex-REAR can become **LEAD**, or push the surviving FLANK down to REAR. Assert the recompute instead: the 3
  closest to the hint are LEAD + 2 FLANK, the closest ex-REAR is among them, and `rear_count()` fell by one. Do not
  assert "it holds a FLANK role".
- **N5:** The REAR spacing deviates from the epic without being listed:
  - the epic says a ring at `rear_standoff_radius`, "spaced by `rear_index/rear_count`", with lane
    `pass_offset + 2 × flank_lane_gap`;
  - the build uses one lane per `rear_index` on the REAR's own latched side (`fighter_brain.gd:394-404`), and
    `rear_count` is unused.
  It is reasonable, but list it as a deviation, together with how IDEAS §17's "the formation contracts" is realised
  (the index drops, so the lane moves in by 100 px).
- **N6:** The latch is released at EXTEND's end, and TURN re-derives the next pass (`fighter_brain.gd:634`). Epic
  rule 1 says "until the next REPOSITION". State that this is t8b's as-built latch. Also state that TURN's
  break-away arc (120 px first-arc clearance, t8b) is the one exemption from rule 2.
- **N7:** The `join()` in `Fighter._ready()` differs from the epic's "on its first tick". It follows the Swarm
  precedent and gives roles before tick 1, which is fine, but list it.
- **N8:** Correct the wide-sweep numbers (5 fails, not 6), per B3.
- **N9:** If any give-way or clearance numbers survive, note that the Swarm keeps `separation_radius` /
  `flock_nudge_cap` / `evade_radius` in config. Justify keeping them as constants, or move them.

## Checked and fine

- `test_fighter.gd`: 52/52 on the working tree, so D5's "t8b cases unaffected" claim holds.
- `test_enemy_mover_single_writer` 9/9, `test_config_instance_isolation` 7/7, `test_enemy_mover` 43/43 and
  `test_signal_emit_arity` 8/8 all pass on the working tree.
- The shipped sweep with give-way gives 2/54 fails, both at `engage_seconds` 60, which matches the plan. Runtime is
  23 s for 174 runs, so the planned 12-run file fits the ~20 s budget.
- `SquadController`:
  - same-call reassign on leave or prune, and the window closes on any LEAD change (`squad_controller.gd:60-83`,
    `:202-232`);
  - `rear_index` / `rear_count` behave as the plan assumes.
- WaveManager with stagger 0 never awaits `create_timer` (`wave_manager.gd:170-174`). It writes `squad` before
  `add_child` (`:206-209`).
- Hull radius is 13 × 2.2 = 28.6 px (`fighter.tscn:35,83`).
- The window opens only when the latched role is LEAD (`fighter_brain.gd:558-561`). It closes on EXTEND only if the
  fighter still leads (`:832-835`).
- Answer-once resets on reading the window closed (`:249-250`). A FLANK answers only when settled at S
  (`:745`, `:762`), per N3.
- D6 is additive and read-only (`enemy_mover.gd:79-82`). The config fields are flat.
- The t8b lock-step `aim_mode` case exists as described (`test_fighter.gd:352-367`), so strangers must not interact.

# Round 2 (Revision 2)

VERDICT: CHANGES_REQUESTED

I checked Revision 2 against the uncommitted working-tree code (`git diff` vs `f753884`). I also ran everything in a
throw-away copy (`/tmp/rev`) and touched nothing in the repo except this file. In that copy:
- `test_fighter_squad.gd` passes 15/15 in 39 s. Its sweep prints the plan's numbers: worst separation 66.3 px (Open
  Space) and 67.3 px (Assault), and 7 Assault attackers held silent by the budget.
- These files are green on the working tree: `test_fighter.gd` 52/52, `test_enemy_mover_single_writer` 9/9,
  `test_config_instance_isolation` 7/7, `test_signal_emit_arity` 8/8, `test_enemy_dual_mode` 9/9,
  `test_level1_fighter_spawns` 5/5, `test_wave_squads` 8/8 and `test_enemy_contact_damage` 4/4.
- I did not run `scripts/check-test-leaks.sh`. The file uses stagger 0, so it creates no `SceneTreeTimer`.

## Question 1: scope

**The give-way is within the task's discretion.** It is materially different from what round-1 B1 ruled out:
- B1's objections were three things:
  - D5, a new heading source for **every** phase;
  - D6, new API on the shared `EnemyMover`;
  - a reciprocal layer that also bent the attack legs.
- Revision 2 has none of them:
  - `_give_way()` (`fighter_brain.gd:1317-1323`) runs only for a holder, through `_slide_aside()`, and for a member
    on a lead-in, through `_slow_for_mates()`;
  - RUN_IN, EXTEND, TURN and DISENGAGE are untouched;
  - it changes no heading source;
  - it only re-issues `mover.request_velocity()`, which replaces the earlier request (`enemy_mover.gd:75-76`);
  - the single-writer gate is green.
- Round 1 itself listed the Swarm's `Steering.separation` nudge as an in-scope precedent to measure. A brain-local
  rule for "wait at your station without being run through" fills a phase the epic leaves to the implementation.
- §8's "option i's spirit" is overstated: this is reactive avoidance, not routing. That wording is cosmetic and does
  not block.

**The "over a full cycle" reading is a relaxation, and it hides a real failure (B1 below).**
- The *start* point is defensible. The epic uses "cycle" for the attack: "after `passes` passes … a 1.5 s regroup,
  then a new cycle" (epic `3-plan.md:269-270`), and research gives "one full pass cycle ≈ 3 s × 2 passes"
  (`2-research.md:146`). The only fix it pre-approves, a FLANK_RIGHT start delay, addresses run crossings, not the
  fan-out from spawn.
- The plan should still say plainly that this is the option `5-escalation.md` put to the owner as decision 1(b),
  "relax the criterion". It now calls it "the epic's wording" without explaining the change of position.
- The *end* point is not defensible. The test stops at the LEAD's **second RUN_IN** (`test_fighter_squad.gd:486`).
  That is one pass, not the epic's `passes` = 2.
- It also stops at the exact frame the second window opens. The second window is the first window on which REARs
  fly: a REAR answers every second window (`fighter_brain.gd:777`).
- Read "cycle" either way and the result is the same:
  - as `passes` passes, the measured interval is half a cycle;
  - as one window, the way the implementation reads the REAR row's "every other cycle", the test measures only the
    one cycle in which no REAR ever moves.
- So no REAR dry pass is ever inside a separation check:
  - in Open Space, the measurement ends as REARs launch;
  - in Assault, at the shipped budget, REARs never fly (round-1 B4).

## Blocking

**B1 — Over a full two-pass cycle the W5 fails separation in 35 of 42 Open Space layouts, worst 3.5 px.**
- Reproduction, a copy of `test_fighter_squad.gd` with two edits:
  - `_cycle` stops at `lead_runs >= 3`, i.e. the first RUN_IN of the next cycle, instead of `>= 2` (line 486);
  - the cap goes from 20 s to 45 s (line 450).
- All 84 Open Space runs reach the third LEAD RUN_IN, within 28.9 s, so nothing stalls. Results:

  | Formation | Failing layouts | Worst / range |
  |---|---|---|
  | V3 | 0 of 42 | 77.4 px |
  | **W5** | **35 of 42** | **3.5–44.5 px** |

- Every W5 failure falls at 15.6–20.4 s, in the **second window**. With role logging added, the closest pair is:
  - almost always a REAR on its dry pass in TURN, against the LEAD's, FLANK_LEFT's or FLANK_RIGHT's TURN
    (`TURN/TURN roles REAR/FLANK_RIGHT passroles 4/3`, `REAR/LEAD`, `REAR/FLANK_LEFT`);
  - in a few layouts, FLANK_LEFT against FLANK_RIGHT in REPOSITION/TURN.
- TURN never gives way, by design (§3.3). `_crossing_stagger()` only spaces run **starts**:
  - the parallel same-direction branch (`fighter_brain.gd:815-822`) trails by one gap;
  - its own comment (816-817) warns that "their turns at the far end would converge".
- Restoring Revision 1's two-gap trail does not help: still 35 of 42, worst 2.2 px. It also pushes Assault silent
  attackers from 7 to 16.
- **Supporting data (not a separate blocker).** In Assault with a long PRIVATE budget, the squad flies its second
  pass. Then V3 fails in 11 of 42 layouts and W5 in 27 of 42, including REPOSITION/REPOSITION at 0.9 px (see N5).
  So the in-cycle 0/168 holds only because the shipped 6 s budget allows one window.
- **This is the task's own new behaviour failing**, not pre-existing fan-out: REAR dry passes are X9 and are built
  here. In game the bodies collide (layer 1 / mask 1), so these REARs would ram their attackers.
- No small fix exists that I could approve without measuring it. The candidates all need design and a new sweep:
  - a REAR dry pass that never shares a window with the attackers' runs, for example answering on the window
    *close*, or starting after the last attacker leaves TURN;
  - a separation rule for TURN;
  - REAR lanes or standoff further out.
- **Required:**
  - the separation case must cover a full cycle: Open Space to the LEAD's third RUN_IN, i.e. both windows, so the
    REARs fly. Equivalently: every window up to and including the first one a REAR answers;
  - the criterion must hold there;
  - otherwise the run escalates again. This time the owner gets this measurement, and the reading "first window
    only" is an explicit owner decision (escalation 1(b)), not a re-interpretation.

## Non-blocking

The implementer can apply these directly in a future run. None of them rescues B1.
- **N1:** Stale comment, `fighter_brain.gd:816-817`. It says "trails the mate's by at least twice the crossing gap",
  but line 819 trails by one. Make it say one gap.
- **N2:** The N3 current-role REAR gate (`fighter_brain.gd:1109`) has no test. Mutating it to `pass_role == REAR`
  only leaves all 15 cases green. Add a case: a closer member joins mid-pass, so a FLANK is demoted to REAR, and it
  fires nothing after the demotion.
- **N3:** `_cycle` never asserts that it reached its end point. With the 20 s cap, a stall after window 1 would
  silently shorten the measured interval. Add, in Open Space, `assert_gte(lead_runs, <end>, where)` before
  `_drop(w)` (`test_fighter_squad.gd:497`).
- **N4:** The separation check skips any pair with a role-NONE member (`test_fighter_squad.gd:480`), i.e. anyone on
  its DISENGAGE exit. Yet `_slow_for_mates()` deliberately yields to exiting ex-members (`fighter_brain.gd:1326`,
  `:1397`). State that exclusion in plan §5, or measure it.
- **N5: hole in the give-way.** A mate braking onto its station is in `Steering.arrive`: slow, but not holding yet.
  - It is not slid from: `_slide_aside` treats it as a moving track with ~zero length (`:1366`, `q != prev`).
  - It is not yielded to: `_slow_for_mates` skips mates under 0.3 × `max_speed` (`:1392`).
  - A second member flying to its own station therefore just closes in. That is the likely cause of the 0.9 px
    REPOSITION/REPOSITION in the long-budget Assault data.
  - Treat a mate that is slow but not holding as a static obstacle for the slower member's speed choice, or count
    "braking onto S" as holding for `_slide_aside`.
- **N6: possible Open Space stall.** In `_tick_hold`, both `lead_wait_max` and `flank_wait_max` sit behind
  `if not is_settled(): return` (`fighter_brain.gd:762`).
  - A member held more than 32 px off S therefore never runs in Open Space, with no budget to break the hold.
    Two causes: two holders inside the clearance pushing apart forever (`:1349-1354`), or a mate repeatedly crossing
    its station.
  - Only `HOLD_DRIFT_PX` (160) rescues it.
  - It is not seen on the grid. The nominal stations are ≥ 100 px apart, against an 86 px clearance. But the epic
    gives `flank_wait_max` precisely so that "a flank whose lead is dead or slow still attacks".
  - Consider letting the `lead_wait_max` / `flank_wait_max` timers fire when the member is merely holding, from a
    bounded off-S distance.
- **N7:** Escalation decision 2, the Assault budget, is closed unilaterally as "a late flank holds and leaves". That
  closure relaxes round-1 B2 ("each LEAD/FLANK fires ≥ 1 round"; the test asserts it only for attackers that ran).
  Nothing ships wrong today, because every level-1 fighter formation is still on rails
  (`level_1_director.gd:308,329,346,378`). But DECISIONS must record decision 2 as still open for the owner, not as
  decided.
- **N8:** §3.3 says "nothing is ever nudged toward the player (the slide is perpendicular to a mate's track)".
  Perpendicular is not "away from the player". The measured clearance (≥ 120 px) supports the outcome, but not that
  claim. Reword it as measured, not by construction.
- **N9:** `_mates()` scans the whole `enemies` group every tick, for every squad fighter in a hold or lead-in
  (`fighter_brain.gd:1330`). Each mate then gets up to 15 predictions, times 6 speed steps. That is fine at V3/W5,
  but read the board's `members()` plus a cached ex-member list if t16 brings larger squads.

## Checked and fine

- **Tests:** each acceptance case is dual where the acceptance line requires it. Each has teeth; I mutated the
  `/tmp` copy and re-ran:

  | Mutation | Cases that go red |
  |---|---|
  | `_give_way` off | 46 sweep asserts |
  | `_slide_aside` off | 36 |
  | `_slow_for_mates` off | 8 |
  | dry-REAR guard removed | `test_rears_fire_nothing` |
  | `_close_window` off | window test, both modes |
  | the LEAD never opens | window test |
  | `_answered_window` reset removed | answer-once test ("reset on reading the window closed", "window 2 is answered") |
  | `_flanks_ready()` always true | LEAD-waits test, both modes |
  | ring tangent cap removed (`outside := false`) | seek-target clearance test |

- **Round-1 points:**
  - B4: the REAR case's precondition holds (each REAR flies a dry pass);
  - B5: collision exceptions are in `_spawn()`;
  - B3: the sweep is the whole grid, with no hand-picked placements;
  - B2: breach passes are asserted.
- **Solo fighters:** they are unchanged. Every squad rule is gated on `member_count() ≥ 2`, and `test_fighter.gd`
  stays at 52/52.
- **Board membership:**
  - joining in `_ready()` happens before a rail's `suspend_ai()` leave, because the `EnemyPathMover` is added after
    `add_child`;
  - leaving on DISENGAGE (`:1209`) and on suspension (`:300`) is as planned.
