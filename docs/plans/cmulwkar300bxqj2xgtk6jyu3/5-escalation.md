# t9-fighter-squad — escalation to the owner (2026-09-30)

**Result: ESCALATE.** The task's own acceptance line ("body separation ≥ 2 × hull radius — the only pre-approved fix is
`flank_stagger`") cannot be met by `flank_stagger` or by any other in-scope fix I could measure. The one mechanism
that does meet it, a reactive avoidance layer, is a scope change that the plan reviewer ruled only you can approve
(`4-review.md` B1). The Assault engagement budget is a second, independent problem that also needs your decision (B7).

**Nothing is shipped.** The fighter code is back at HEAD (t8b). Everything built and measured is kept, as patches that
apply cleanly to HEAD, in `prototype/` (see its README), so the next run starts from the code rather than from nothing.

## What was built and works (both variants carry it)

These parts are sound. The reviewer confirmed each one against the code:
- `Fighter.squad`, joining in `_ready()` (the Swarm precedent), and leaving on DISENGAGE or a rail.
- Role → pass kind:
  - LEAD → FRONTAL, with σ latched on its first derivation;
  - FLANK_LEFT / FLANK_RIGHT → the pincer lanes;
  - REAR → a new dry `PassKind.REAR` on an outer lane.
- `pass_role` latched with the pass at RUN_IN entry.
- The window: the LEAD opens it on RUN_IN entry while it leads, and closes it on its own EXTEND entry.
- FLANKs answer each window once, only when settled at S (N3); `_answered_window` resets on reading the window closed.
- `flank_wait_max`.
- REAR dry passes: no burst, no light.
- Same-call reassignment on a death (`SquadController`, unchanged).
- The crossing-time generalisation of `flank_stagger` (D3).
- The LEAD holds at its S until its flanks settle (D2, `lead_wait_max`).
- An Assault budget bound on every hold (below).
- The ring fallback's seek target now clears `reposition_min_radius` (the acceptance line's seek-target rule; it did
  not hold in t8b's `_fly_ring`: 231–249 px against 288).
- The draft spec `prototype/test_fighter_squad_draft.gd.txt`: 15 cases, green on the ORCA variant.

## The measurement (clean harness, deterministic)

Harness: a real `WaveManager` spawns the formation in both `enemy_ai_harness.gd` worlds, and the fighters are
hand-ticked at 60 Hz against a holding player, at the shipped budget (`engage_seconds` 6.0).

**Fighter–fighter physics collision is excepted in the harness** (`add_collision_exception_with`, test-only), per the
reviewer's B5. Without it, the never-stepped physics space leaves every fighter colliding with its mates' spawn
positions. Every number in `3-plan.md` Revision 1 came from that contaminated harness, and it was also
**non-deterministic between runs**: the same layout gave 260 px in 3 runs and 12.7 px in 1. With the exceptions,
3 of 3 runs are identical.

- **Shipped set:** {V3, W5} × 3 player positions × 3 formation offsets × 2 modes = 36 runs.
- **Wide set:** {V3, V4, V6, line4, W5} × 7 players × 6 offsets × 2 modes = 420 runs.
- **Metrics:**
  - `SEP`: two live members closer than 57.2 px (2 × hull radius);
  - `HIT`: a member closer than 42.1 px to the player (hull + player hurtbox);
  - `BREACH`: a squad member's RUN_IN not entered from a hold at its S. That is a deadline or breach pass that
    answered no window.
  - `SILENT` (Assault only): a LEAD or FLANK that fired nothing in its life.

| Build | Shipped 36: SEP / BREACH / SILENT (of 18) | Wide 420: SEP / HIT / BREACH / SILENT (of 210) |
|---|---|---|
| **HEAD (t8b): the formation is independent solo fighters** | 29 / – / 6, worst 0.1 px | 293 / 1 / – / 36, worst 0.0 px |
| Squad roles + holds + `flank_stagger` (the pre-approved scope) | 28 / 0 / 3, worst 1.3 px | 290 / 5 / 0 / 21 |
| + squad-aware routing in the Dubins planner (review B1 option i) | 13 / 6 / 10, worst 15 px | 162 / 1 / 69 / 98 |
| + ORCA give-way, intent heading, `EnemyMover.requested_velocity()` (D4–D6) | **1** / 7 / 8, worst 50 px | **5** / 4 / 37 / 72 |

Assault time to the LEAD's first run is a median of 2.6–3.6 s depending on the build, against a 6.0 s budget.

### Why `flank_stagger` alone cannot pass

Of the 290 failing wide-set runs, **271 have their closest moment in the first 2 s**. By phase pair at that moment:
- 119 are APPROACH/APPROACH;
- 157 are APPROACH against a mate in REPOSITION (flying to or holding at its S);
- 12 are REPOSITION/REPOSITION.

This is the formation fanning out from its spawn slots, which are 80 px apart (below the 86 px a lead-in needs), all
nose-down, with a 167 px turn radius. No run exists yet for a stagger to delay. **Today's game already does this:**
HEAD's solo fighters overlap in 293 of 420 layouts. The squad work does not introduce the problem; the acceptance
line asks this task to fix it.

### Why the in-scope routing (option i) is not enough

Each member plans its Dubins lead-in clear of:
- its higher-priority mates' own predicted positions (`predicted_position(t)`, read from their paths, turns and
  runs);
- every holding mate;
- every mate on a leg that never re-plans.

It re-checks every 0.2 s. It halves the separation failures but cannot remove the spawn ones: six fixed-radius
Dubins shapes offer no way to *wait*. It also lengthens lead-ins, which triples the silent Assault squads.

### Why ORCA works, and what it still gets wrong

ORCA works because it controls speed as well as direction (van den Berg et al. 2011, the RVO2 construction). Two
parts of the variant matter:
- **Along-track only for the run and the turn-in:** those two legs give way only along their own direction of travel,
  so they keep their line and their nose-on snapshot.
- **D5, the heading source:** without it, a persistent nudge out-turns the 0.03 rad-per-tick steering and walks a
  fighter off its lane into the player.

What is left against it:
- **B2, stalls:** a member stalls at the edge of a *holding* mate's 114 px disk, because the planner keeps routing
  through it. It then breach-passes from the wrong place (37 of 420) and, in Assault, never gets to fire.
- **Separation:** 5 of 420 wide-set layouts still fail. The worst is 43 px. In the reviewer's re-run (on the
  earlier, contaminated harness) the worst were a V3 and a W5, the formations this task ships (B3).

## Decisions needed from you

1. **Separation mechanism** (the acceptance line's "only pre-approved fix is flank_stagger"). Choose one:
   - **(a) Approve a squad give-way layer** (D4 ORCA, D5 the brain steers from its own last request, D6 the
     read-only `EnemyMover.requested_velocity()`), and let the next run combine it with the routing variant's
     "route round holding mates" planner check, which targets B2's stalls. The combination has not been measured
     yet. ORCA is the only measured path to the criterion.
   - **(b) Relax the criterion:** separation asserted from the first hold onward, not from spawn. The spawn fan-out
     is pre-existing behaviour, shared by every level-1 formation today. With (b) the pre-approved scope is closer, but not
     proven: at least 19 of the 290 failing runs also fail after 2 s. That is a lower bound, because each run only
     records its worst moment.
   - **(c) Change the spawn layouts for fighters** (wider slots, or staggered spawn delays), which is t16's
     territory.
2. **Assault squads within the budget** (review B7). Even with no avoidance, 3 of 18 shipped Assault squads have a
   silent attacker: a flank that reaches its S too late for any run to fit. Pre-approved lever 1 (6.0 → 4.5 s) would
   make most squads silent. Choose one:
   - no rendezvous hold in Assault (each member runs on arrival, and the roles still pick the lanes);
   - a longer squad budget;
   - Assault stations nearer the spawn;
   - or accept "a late flank holds and leaves".

   The prototype already bounds every hold by the budget. A member stops waiting once only its run and the shortest
   extension still fit, and never starts a run whose closest approach would come after expiry. The expiry otherwise
   sends a fighter out mid-run, straight across the player. A prototype trace (before the harness
   fix) measured 13 px.
3. **In-game fighter bodies collide** (layer 1 "environment", mask 1, since before this phase). Is fighter–fighter
   physics collision intended? If not, a mask change on `fighter.tscn` removes the bumping, but not the visual
   overlap.

## Review points carried to the next run (still valid whatever you decide)

- B4: make the REAR case non-vacuous. Run until each REAR has flown ≥ 1 dry pass, with a long private
  `engage_seconds` in Assault.
- B6: make the reassignment, W5 promotion and mid-run role-change cases dual. Give the pincer case an Assault
  variant.
- N3: gate `_try_open_burst` on the current role as well as the latched one, so a mid-pass demotion cannot make
  four shooters.
- N4: assert the W5 promotion as the full recompute, not "it holds a FLANK role".
- N5–N7: list the REAR lane spacing, the t8b latch release at EXTEND's end, and the `_ready()` join as deviations.

---

# Round 2 (2026-10-05): BLOCKED after the last review round

**Result: BLOCKED.** The task was re-queued with no recorded owner decision on the three questions above. This run
dropped the ORCA layer (D4–D6) and built Revision 2 inside the task's scope (`3-plan.md`): the roles, window, holds,
REAR dry passes and crossing stagger, plus two brain-local give-way rules — a member *holding* its station slides
aside, perpendicular to a moving mate's planned track; a member *flying to* its station slows along its own track for
a mate on a run, a turn or an exit — and two rendezvous rules (only a member settled on its station answers a window;
under budget pressure it still starts only settled or already lined up). Round-2 review: **CHANGES_REQUESTED**, the
second and last round. **Nothing is shipped**; the fighter code is at HEAD (t8b). The build is
`prototype/revision2_variant.patch` (applies cleanly to `f753884`), its test `prototype/test_fighter_squad_rev2.gd.txt`
(15 cases, all green on the patch, each mutation-checked by the reviewer).

## What Revision 2 achieved (deterministic clean harness, `prototype/sweep_harness.gd.txt`)

| Dense set, 168 runs (V3, W5 × 7 players × 6 offsets × 2 modes), shipped budget | CYC | SEP | BREACH | SILENT |
|---|---|---|---|---|
| Stagger only (the pre-approved scope) | 23 | 137 | 0 | 12 |
| + routing round mates' plans (round-1 option i) | 9 | 59 | 34 | 48 |
| + routing round holding mates only | 12 | 117 | 36 | 16 |
| **Revision 2** | **0** | 19 | **0** | 7 |

CYC = two members under 2 × hull radius (57.2 px) between the LEAD's first window and its **second** RUN_IN (Open
Space) / everyone leaving (Assault). SEP = the same from spawn. BREACH = a squad run not started from a hold. SILENT =
an Assault LEAD/FLANK that fired nothing (all 7 are budget holds: a flank that crossed most of the corridor and whose
run no longer fit, held rather than sent out mid-run).

## Why it is blocked (round-2 B1)

The window above stops at the LEAD's second RUN_IN, which is exactly when the REARs first fly (a REAR answers every
second window). The reviewer extended it to a full two-pass cycle (to the LEAD's third RUN_IN, both windows):

| Open Space, full cycle | Failing layouts | Worst |
|---|---|---|
| V3 | 0 of 42 | 77.4 px |
| **W5** | **35 of 42** | **3.5 px** — a REAR's dry-pass TURN against the LEAD's or a FLANK's TURN, in the second window |

With a long budget in Assault (two passes), V3 fails in 11 of 42 and W5 in 27 of 42. TURN never gives way in
Revision 2, and the stagger only spaces run starts. Restoring the two-gap parallel trail does not help (35 of 42,
worst 2.2 px). In game the bodies collide, so these REARs would ram their attackers.

## Decisions needed from you (these replace decision 1 above; 2 and 3 stand)

1. **Which interval the separation criterion covers.**
   - (a) **A full cycle, both windows** (the reviewer's reading): the next run must design REAR / turn separation and
     re-measure. Candidates the reviewer named, none measured: a REAR dry pass that never shares a window with the
     attackers' runs (answer on the window *close*, or start after the last attacker leaves TURN); a separation rule
     for TURN; REAR lanes or standoff further out.
   - (b) **The first window only** (Revision 2 as built, green): ship `revision2_variant.patch` with its test as is,
     recording the second-window REAR overlaps as a known gap.
2. **Assault budget** (unchanged from above). Revision 2 took "a late flank holds and leaves" (7 of 84 dense Assault
   layouts, 14 of 210 wide); the reviewer ruled that is your call, not this task's. Still open.
3. **Fighter body collision** (unchanged). Still open.

Review non-blocking notes N1–N9 (round 2) apply to the patch whichever you choose; N1 (a stale comment) is already
fixed in it.
