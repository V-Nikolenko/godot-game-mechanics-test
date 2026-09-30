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
