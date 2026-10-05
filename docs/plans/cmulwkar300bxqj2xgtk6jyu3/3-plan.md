# Fighter squads (t9-fighter-squad) — task plan, Revision 3

> **Status (2026-10-05): Revision 3, built and measured, under its own review (`4-review.md`, "Round 3").** Round 2
> (`4-review.md`, "Round 2") requested changes on Revision 2, the second and last round: §5's separation window ended
> at the LEAD's second RUN_IN, the frame the REARs first fly, and over a full two-pass cycle a W5 failed in 35 of 42 Open
> Space layouts (worst 3.5 px, a REAR's dry-pass TURN against an attacker's TURN). The escalation (`5-escalation.md`,
> "Round 2") put two options to the owner: (a) design REAR / turn separation and measure over the full cycle, or
> (b) accept first-window-only separation. The task was re-queued with no recorded owner decision, so Revision 3 takes
> **option (a)**, the reviewer's own reading, which relaxes nothing and therefore needs no owner approval. Owner
> decisions 2 (the Assault budget) and 3 (fighter body collision) are still open and are not closed here.

**What changed from Revision 2** (Revision 2 is in git at `5c9e122`, its patch was `prototype/revision2_variant.patch`):
- **§3.4 (new): the dry pass has its own slot.** A REAR no longer flies the moment it answers a window, alongside the
  attackers. It becomes *due* on every second window and flies after the window closes, once no mate is on a pass and
  every attacker holds its station. The LEAD holds its next window, and a FLANK its `flank_wait_max` run, while a REAR
  is due or on its dry pass. This is the round-2 reviewer's first named candidate ("a REAR dry pass that never shares a
  window with the attackers' runs").
- **§3.3: a member on a lead-in that no slow-down keeps clear slides aside** from a mate on a pass, like a holder, and
  its lead-in deadline pauses while it gives way (measured load-bearing: without it, Open Space W5 drops to 38 px).
- **§3.3: round-2 N5** — a member yields to a higher-priority mate that is braking onto its station.
- **§3.1: round-2 N6** — a member held off its S still goes after `UNSETTLED_WAIT_FACTOR` × its own wait.
- **§5: the separation check covers a full cycle** (Open Space: to the LEAD's first RUN_IN at or after its third, once
  every REAR has finished a dry pass; asserted, round-2 N3) and counts fighters on their exit (round-2 N4).
- Tests: round-2 N2 (a FLANK demoted mid-run fires nothing), N6, and the Assault REAR case rewritten (§Test plan).
- Answers to every round-2 point are tabled at the end (§9).

Task `cmulwkar300bxqj2xgtk6jyu3`, epic `cmufs7ekv000lnm2x7nbswijy`. Builds §2.5 of the epic's approved `3-plan.md`
(Revision 2, "the epic plan") on top of t8b (`docs/plans/cmulwkar000btqj2x1e58sfd4/`, as built in DECISIONS "Phase 3,
built in t8b"). The epic plan is not re-derived here.

**History.** Revision 1 (commit `34984b6`, in git) proposed an ORCA give-way layer (D4), a new heading source for every
phase (D5) and a new `EnemyMover` getter (D6). Round-1 review (`4-review.md`) ruled D4–D6 a scope change only the owner
can approve (B1), and found B2–B7. The run ended ESCALATE (`5-escalation.md`). Revision 2 dropped D4–D6 and met the
criterion inside the task's own scope, measured over one window; round 2 found the second window failing. Revision 3
keeps Revision 2 and adds the dry-pass slot. The measurements below come from the clean harness (B5: fighter–fighter
collision excepted) and are deterministic.

## Problem

Today a formation of fighters is a set of solo fighters that happen to spawn together: each flies its own attack runs
and ignores the others. They bunch on the same line, overlap (in the real game their bodies collide: layer 1, mask 1)
and attack one after another from arbitrary sides.

After this task a formation fights as a squad. The nearest fighter leads and comes **head-on** down one side of the
player; the next two close as a **pincer** from the player's left and right on two lanes, starting the moment the
leader starts. A fourth and later fighters wait their turn on an outer lane and make **dry passes** (no fire, no
warning light) in the gap between two attacks, never alongside one: at most three attack at once (epic X9).
When an attacker dies, the nearest waiting fighter takes its place in the same call. Squad members keep clear of each
other through the attack: a fighter waiting at its station steps aside for a mate whose path crosses it, and a fighter
flying to its station eases off for a mate on a run.

## Design

### 1. Joining and leaving the board

- `Fighter.squad: SquadController` is the duck-typed slot `WaveManager` (and later `SectorHub`) writes before
  `add_child`. `Fighter._ready()` calls `squad.update_target(P, h)` then `squad.join(self)` — the Swarm precedent, so
  roles exist before tick 1 (**deviation N7** from the epic's "on its first tick").
- The brain calls `update_target(P, heading_ref())` every tick; `heading_ref()` is the `h` the pass geometry uses.
- A fighter leaves the board on DISENGAGE entry and on `on_suspended()` (a rail); a freed one through `tree_exiting`.
- **A squad of one is a solo fighter**: every squad rule is gated on `member_count() ≥ 2`; t8b's alternation is unchanged.

### 2. Roles → pass kinds (epic §2.5 table)

Roles are read from `role_of()` every tick and never cached. The role chooses the kind when the pass is derived, which
t8b does every tick before RUN_IN and never between RUN_IN entry and EXTEND's end:

| Role | Pass kind | `b` / `l` | Fires |
|---|---|---|---|
| LEAD | FRONTAL | `b = h`, `l = right(h)·σ·pass_offset`; σ latched on the first FRONTAL derivation, then alternating per pass | yes |
| FLANK_LEFT | FLANK_LEFT | `b = left(h)`, `l = h·pass_offset` | yes |
| FLANK_RIGHT | FLANK_RIGHT | `b = right(h)`, `l = h·(pass_offset + flank_lane_gap)` | yes |
| REAR | new `PassKind.REAR` | `b = right(h)·s_r` (`s_r` latched when it becomes REAR); `l = h·(pass_offset + (2 + rear_index)·flank_lane_gap)` from `rear_standoff_radius` | **no** |

- **Deviation N5 (REAR spacing).** The epic says a ring at `rear_standoff_radius` "spaced by `rear_index/rear_count`".
  The build gives each REAR its own lane, one `flank_lane_gap` further out per `rear_index`, on its latched side;
  `rear_count` is unused. IDEAS §17's "the formation contracts" is realised by the index dropping when a REAR is
  promoted: the remaining REARs' lanes move in by 100 px.
- **The pass is latched with its role** (`pass_role`, `b`, `u`, `l`, kind at RUN_IN entry). **Deviation N6:** the latch
  is t8b's as built — released at EXTEND's end, and TURN re-derives the next pass — not "until the next REPOSITION".
  TURN's break-away arc (120 px first-arc clearance, t8b) is the one exemption from the seek-target rule.
- **Dry passes.** `_try_open_burst()` returns while `pass_role == REAR` **or the current role is REAR** (review N3): a
  FLANK demoted mid-pass by a closer join stops firing, so at most three fighters ever fire. A REAR promoted mid-pass
  stays dry until its next pass.
- **When a REAR flies:** in Open Space it is due a dry pass on every second window and flies it in the slot after that
  window (§3.4). In Assault it never does: an Assault fighter leaves after `passes` passes (t8b), the epic's "every other
  cycle" is never reached, and its REARs are promoted as the attackers leave instead.

### 3. The attack: rendezvous, window, stagger, give-way

#### 3.1 Every member flies to its S and holds there

- APPROACH and REPOSITION fly to S as t8b does. **D1:** a squad member's S is a *station*: it plans a lead-in arriving
  along its own approach, and within 2 plan radii with a clear straight line it brakes onto S (`Steering.arrive`).
- At S it **holds** (REPOSITION with `_hold_time ≥ 0`): `v_P` + a correction toward S capped at 60 px/s, nose along `u`.
  A member is **settled** when it is holding, **within `STATION_SETTLE_PX` (32 px) of S**, and slower than
  0.3 × `max_speed`. Only a settled member answers a window or counts as ready for the rendezvous: a run started off S
  converges onto its line at an angle no stagger predicted (measured: the cause of every residual RUN_IN/RUN_IN overlap).
- A member more than 32 px off S (it slid aside, §3.3) returns at up to `GIVE_WAY_SLIDE_SPEED` rather than 60 px/s;
  beyond `HOLD_DRIFT_PX` (160) it re-plans a lead-in to S, as before.
- **D2 — the LEAD holds too**, until every FLANK is settled or `lead_wait_max` (3.5 s), then runs.
- **Assault budget (B7).** Every hold is bounded by the budget: a member stops waiting once only its run and the
  shortest extension still fit (`_budget_short()`), and never starts a run whose closest approach would come after
  expiry (`run_budget_slack() ≤ 0`). Under that pressure it still starts only when settled **or already heading within
  30° of its run** (t8b's handover rule): a member sliding in fast across its line would otherwise swing a turn radius
  off it toward the player (measured 22 px before this rule).
- **A hold off S is bounded (round-2 N6).** A member continuously unsettled for `UNSETTLED_WAIT_FACTOR` (2) × its own
  wait (`lead_wait_max` for the LEAD, `flank_wait_max` for a FLANK) goes anyway — two holders pushing apart, or a mate
  crossing its station again and again, would otherwise hold it forever in Open Space, where no budget ends a hold. The
  counter (`_unsettled_time`) restarts whenever it settles, so a member that has waited settled and then slides aside for
  a mate does not go at once. REARs are excluded: they fly only in their slot (§3.4).

#### 3.2 The window (epic §2.5; the REAR line changed in Revision 3)

- The LEAD opens `attack_window_open` on RUN_IN entry when its latched role is LEAD; it closes it on its own EXTEND
  entry if it still leads (otherwise `_reassign()` already closed it).
- A FLANK answers each window once, only while settled (review N3 of the epic); `_answered_window` resets on any tick it
  reads the window closed. `flank_wait_max` counts while settled and the LEAD is not holding. A REAR reads every window
  once too; every second one makes it **due** a dry pass, which it flies in the slot after the window (§3.4), never on
  the window itself, and it never goes on the wait.

#### 3.3 Separation: `flank_stagger` plus a brain-local give-way

**D3 — `flank_stagger` generalised (as Revision 1).** At `_go()`, for each mate on RUN_IN/EXTEND: where the two lines
cross and when each reaches it at `max_speed`; if within `flank_stagger` (0.4 s) of the mate, wait the difference.
**Changed:** a parallel same-direction run on a neighbouring lane trails by **one** stagger gap (`flank_stagger ×
max_speed` = 120 px), not two. Lanes are 100 px apart, so the diagonal gap is ≥ 156 px. Two gaps (240 px) left the
second flank of a same-side Assault pair unable to fit its run in the budget (19 → 10 silent layouts in the dense set),
with no separation benefit measured.

**`flank_stagger` alone does not meet the criterion even within the cycle.** Its in-cycle failures (23 of 168 dense
layouts) are not run crossings: they are a LEAD's REPOSITION lead-in to its next station flying through the two REARs
holding on the same side (19 of 23), and approaching/repositioning members meeting an attacker's turn (4). Neither is a
run start that a stagger can delay. So two more rules, both inside `FighterBrain`, both on the "a member waiting or
flying to its station gives way, an attack never does" principle:

1. **A holding member slides aside** (`_slide_aside()`). For each moving mate it samples the mate's own planned track
   (`predicted_position(t)`, t8b's lead-in path, turn arc or straight line) every 0.1 s over 1.5 s. If the track comes
   within `GIVE_WAY_HULLS` × hull (3 × 28.6 = 86 px) of the holder, the holder moves **perpendicular to the track**, to
   the side it is already on, at `GIVE_WAY_SLIDE_SPEED` (180 px/s) — the shortest way off it (≤ one clearance), never
   along it, where the mate would keep pushing it ahead of itself (measured: pushed 160 px off S, dropped its hold, flew
   a lead-in loop and missed the attack). Two holders closer than the clearance push apart. A station is a place to
   wait, so moving it a little costs nothing; the hold then returns to S (§3.1).
2. **A member flying to its S slows along its own track** (`_slow_for_mates()`), never turns. It picks the largest of
   {1, 0.8, 0.6, 0.4, 0.2, 0} × its request such that, flying its own plan at that speed, it keeps the clearance from
   every mate it yields to over the horizon. It yields to a mate on a run, a turn, an extension or an exit, and to a
   mate ahead of it in `squad_priority()` (LEAD, FLANK_LEFT, FLANK_RIGHT, REARs by index) on a lead-in. **Never to a
   mate slower than 0.3 × `max_speed`**: slowing cannot wait out an obstacle that is not going anywhere (measured: two
   flanks frozen behind a never-ticked LEAD until their deadline). **Except a mate braking onto its station**
   (`is_braking_onto_station()`: a lead-in inside the arrive zone, slower than 0.3 × `max_speed`): a member yields to
   it when it is ahead in `squad_priority()` — round-2 N5's hole, where a member neither slid from nor yielded to a
   mate about to stop. Yielding to *every* braking mate was measured and rejected (Open Space W5 2/42, Assault V3 2/42
   failures); so was the reviewer's other suggestion, a braking mate sliding aside like a holder (Open Space V3 3/42,
   worst 1.2 px).
   **Revision 3: when no speed keeps the clearance** (the mate's own track runs over the point the member would stop
   at), the member **slides aside like a holder** from the mates it yields to that are on a pass (RUN_IN, EXTEND, TURN,
   or counting down a stagger to one). Its lead-in deadline does not run while it waits (`_deadline += delta`, scaled
   by the slow-down otherwise): waiting for a mate is not failing to arrive, and a deadline breach would start a run
   from wherever it waited. Measured load-bearing: with the slide off, Open Space W5 fails at 38 px. Sliding aside from
   lead-in mates as well was measured and rejected (Open Space V3 8/42, 5 breach passes).

Not touched: RUN_IN, EXTEND, TURN and DISENGAGE never give way (their timing is the stagger's and the dry-pass slot's,
§3.4; their line is the pass's),
strangers never interact (only fighters whose `squad` field is this board), nothing pushes a member at the player by design (the slide is perpendicular to a mate's track and the slow-down is along
the member's own lead-in; perpendicular is not "away from the player", so this is measured, not guaranteed: the closest
any fighter comes to the player outside its exit is 109.3 px on the full-cycle grid — round-2 N8). **No new shared
API, no change to any phase's heading source, no `add_nudge()`:** the give-way re-issues the tick's own last request
through `mover.request_velocity()` (which replaces the earlier request in the same tick), and reads mates duck-typed.

**Why constants, not config (N9).** `GIVE_WAY_HULLS` / `_HORIZON` / `_SAMPLE` / `_SLIDE_SPEED` / `_STEPS`,
`STATION_SETTLE_PX` and `UNSETTLED_WAIT_FACTOR` are controller tolerances stated in hull radii and against the 2 × hull criterion, like t8b's
`REPLAN_*` / `TRACK_*` constants, not balance a designer tunes per enemy. The Swarm's `separation_radius` etc. are
config because they shape the flock's visible look; these shape nothing visible beyond "does not overlap".

#### 3.4 The dry pass has its own slot (Revision 3)

Round 2's blocker was a REAR flying its dry pass *on* the window it answered, so its TURN met the attackers' TURNs below
the player (35 of 42 Open Space W5 layouts, worst 3.5 px). TURN never gives way and the stagger only spaces run starts,
so the fix is in *when* the REAR flies, not how:

- **Due, not gone.** A holding REAR reads each window once (the same `_answered_window` flag). Every second window
  makes it due a dry pass (`_rear_due`); it does not start on the window.
- **The slot** (`_rear_slot_free()`): a due REAR goes the first tick the window is closed, **no mate is on a pass**
  (`is_on_pass()`: RUN_IN, EXTEND, TURN with its break-away, or counting down a stagger) **and every attacker (LEAD,
  FLANK) is holding**. "Holding" rather than "not on a pass" because a holder slides off a crossing track (§3.3), while a
  member still on its lead-in could only slow and stall behind the REAR. Then `_go()` as usual (budget, stagger).
- **The attack waits for it** (`_rear_slot_taken()`): while a REAR is on its dry pass, or is due and settled (so it can
  go the moment it is free) with budget for its run, the LEAD does not open its next window and a FLANK does not take
  its `flank_wait_max` run. A window that is already open is not affected: a settled FLANK still answers it.
- **Bounded.** A dry pass ends (RUN_IN → EXTEND → TURN → REPOSITION), so the slot is taken for one pass at most. A due
  REAR that is not settled does not take it. `_rear_due` is cleared when the REAR starts its run and when it stops
  being a REAR (a promoted REAR flies its new role's pass at the next window, as before).
- **Assault:** never reached (§2: an Assault fighter leaves after `passes` passes, so the window a REAR would be due on
  is the attackers' last, and they leave instead of holding). The rule costs Assault nothing: the LEAD's and FLANKs'
  waits only see a REAR that is due, and none ever is there.

Two REARs on one board both go in the same slot. Their lanes are one `flank_lane_gap` apart on their own latched sides,
so they cross the player's track 100 px apart or come from opposite sides; measured, the full-cycle W5 grid's worst pair
is 69.3 px.

### 4. Config

`FighterConfig` (flat, Tactics group): `rear_standoff_radius` 560 and `flank_wait_max` 2.0 are now read; new
`lead_wait_max` 3.5 (D2) and `flank_stagger` 0.4 (D3).

### 5. Reading the criterion: "over a full cycle"

The epic plan says (§2.5) "t9 asserts a minimum body separation of 2 × hull radius between members **over a full
cycle**". Revision 2 stopped at the LEAD's second RUN_IN, which round 2 showed is the one window in which no REAR ever
flies (B1). Revision 3 asserts the reviewer's reading — **every window up to and including the first one each REAR
flies a dry pass on**:
- **Open Space:** from the LEAD's first window open to its first RUN_IN at or after its third, once every REAR has
  finished its dry pass. The case asserts it got there (`lead_runs ≥ 3`, every REAR's dry pass done: round-2 N3); the
  cap is 50 s and the slowest W5 layout needs 44.2 s.
- **Assault:** from the first window to the last member leaving the board. At the shipped budget every member flies
  one pass; REARs never dry-pass there (§2), they are promoted as the attackers leave.
- **A fighter on its exit still counts** (round-2 N4). Measured both ways: excluding or including role-NONE pairs gives
  the same result on the grid (0 failures, same worst pairs), so the case includes them.

The fan-out before the first window is pre-existing behaviour of every level-1 formation (HEAD's solo fighters overlap
there in 293 of 420 layouts) and belongs to the spawn layouts (t16). It was measured for Revision 2 (19 of 168 dense
layouts overlap before the first window; 137 on the stagger-only base) and Revision 3 changes nothing there except the
N5 yield.

**What the criterion does not cover**, measured and recorded (§Risks): separation after a squad member dies, and an
Assault squad whose budget would let it fly a second pass.

## Measurements (clean harness, deterministic; `prototype/sweep_harness.gd.txt`)

Dense set = {V3, W5} × 7 player positions × 6 formation offsets × {Open Space, Assault} = 168 runs, shipped budget,
over the full cycle of §5. FAIL = a pair of members under 2 × hull = 57.2 px; BREACH = a squad RUN_IN not entered from
a hold; SILENT = an Assault LEAD/FLANK that fired nothing.

| Revision 3, dense set | FAIL | Worst pair | Closest to the player (outside the exit) | BREACH | SILENT | REAR rounds |
|---|---|---|---|---|---|---|
| Open Space V3 | 0 / 42 | 76.9 px | 109.3 px | 0 | — | — |
| Open Space W5 | **0 / 42** (Revision 2 over the same interval: 35 / 42, worst 3.5 px) | 69.3 px | 120.2 px | 0 | — | 0 |
| Assault V3 | 0 / 42 | 67.4 px | 143.7 px | 0 | 3 | — |
| Assault W5 | 0 / 42 | 70.9 px | 121.9 px | 0 | 4 | 0 |

How Revision 3 got there (each a measured step on the same grid, full cycle):

| Build | Open Space W5 FAIL / worst |
|---|---|
| Revision 2 (REAR flies on its window) | 35 / 42, 3.5 px |
| + §3.4 slot, no lead-in slide fallback | fails, worst 38.0 px |
| + §3.3 lead-in slide fallback (shipped) | **0 / 42, 69.3 px** |
| Mutation: slot never "taken" (LEAD/FLANK don't wait for a due REAR) | fails, worst 1.8 px |
| Mutation: slot always "free" (REAR goes on any closed window) | fails, worst 29.2 px |

Outside the criterion (recorded, §Risks):

| Case | Result |
|---|---|
| Wide formations, full cycle: V4 Open Space / Assault | 0 / 42, 0 / 42 (worst 76.9 / 67.4 px) |
| V6 Open Space / Assault | 1 / 42 (25.4 px: a FLANK's run against a REAR's lead-in, third REAR, 36 s) / 0 / 42; 5 Open Space V6 layouts need more than 45 s for three REARs to fly |
| line4 | not measured: `line_formation()`'s stagger awaits a `SceneTreeTimer` the hand-ticked harness never runs |
| A member killed (Open Space; `free()` at t, then 20 s) | LEAD at 2.5 s: V3 1/42, W5 3/42; at 6 s: V3 2/42, W5 9/42; at 12 s: V3 6/42 (7.3 px), W5 5/42; FLANK_LEFT at 4 s: V3 1/42, W5 0/42 |
| Assault with a 20 s budget (two passes) | V3 13/42, W5 25/42, worst 0.9 px (Revision 2: 11/42, 27/42) |

## Build sequence (as built)

1. Revision 2 restored from its patch (roles, window, holds, REAR, crossing stagger, budget bounds, ring-fallback
   clearance, give-way, settled-on-S and budget-pressure rules).
2. §3.4 dry-pass slot: `_rear_due`, `is_on_pass()`, `_rear_slot_free()`, `_rear_slot_taken()`; the LEAD's window and
   the FLANK's `flank_wait_max` run wait on `_rear_slot_taken()`.
3. §3.3 lead-in slide fallback and deadline pause; `_slide_aside(mates)` returns whether it requested.
4. Round-2 N5 (`is_braking_onto_station()`), N6 (`_unsettled_time`, `UNSETTLED_WAIT_FACTOR`, `_own_wait_max()`), N1
   (stale "two gaps" comment).
5. `tests/integration/test_fighter_squad.gd`: full-cycle separation with its end point asserted, exiting fighters
   counted, N2 and N6 cases, the Assault REAR case. Mutation-checked (§Test plan).
6. Scratch sweep deleted from `tests/`; kept as `prototype/sweep_harness.gd.txt`.
7. `test_fighter.gd` stays green unchanged; gate; leak check; docs; DECISIONS.

## Test plan

`tests/integration/test_fighter_squad.gd`, through a real `WaveManager` (stagger 0, no `SceneTreeTimer`) into the
`enemy_ai_harness.gd` worlds, hand-ticked at 60 Hz against a holding player, collision excepted between the spawned
fighters (B5). **Every case is dual** (Open Space + Assault) except the solo alternation, the off-station hold (Open
Space only: Assault's budget already bounds every hold), the disengage case (Assault only by nature) and the strangers
case. 17 cases, ≈ 67 s.

| Case | Asserts |
|---|---|
| `test_a_v3_is_one_squad_of_the_lead_and_both_flanks` | one board; roles {LEAD, FLANK_LEFT, FLANK_RIGHT} |
| `test_the_pincer_and_the_frontal_pass` | first RUN_IN latches its role's kind; FLANK bearings from their role's side (Open Space) / lateral (Assault, where t8b's corridor flip may move a flank's side — B6); LEAD head-on; closest approach = lane ± 40 px |
| `test_the_window_opens_on_the_lead_run_in_and_closes_on_its_extend` | the window's first open frame is the LEAD's RUN_IN entry; open through the run; closed on its EXTEND entry |
| `test_the_lead_does_not_open_before_its_flanks_settle` | at the LEAD's RUN_IN each flank is settled, or the LEAD held `lead_wait_max`, or its run no longer fit the budget |
| `test_each_flank_answers_a_window_once_and_resets_on_reading_it_closed` | hand-driven window, PRIVATE long `flank_wait_max` and budget: answered once; not twice while the same window stays open; `_answered_window` false on the first tick reading it closed; window 2 answered |
| `test_a_flank_whose_lead_never_opens_goes_after_flank_wait_max` | LEAD never ticked; each flank runs `flank_wait_max` (+ at most its stagger) after settling |
| `test_a_flank_kept_off_its_station_still_goes` | **N6:** a flank pinned 50 px off S (never settles, no window) runs after `UNSETTLED_WAIT_FACTOR × flank_wait_max`, not before |
| `test_members_never_come_within_two_hull_radii` | the **whole dense grid** (84 layouts per mode) over the **full cycle** of §5, exiting fighters included: separation ≥ 2 × hull; in Open Space the LEAD's third run reached and every REAR's dry pass done (N3); no fighter within hull + player hurtbox of the player outside DISENGAGE; **every squad RUN_IN entered from a hold** (B2); **in Assault every LEAD/FLANK that fired nothing never started a run** (B2) |
| `test_killing_the_lead_reassigns_in_the_same_call` | `free()` the LEAD: before any tick the closest remaining member leads and the window is closed |
| `test_a_w5_flank_killed_promotes_the_closest_rear_in_the_same_call` | the full recompute — the three closest to the hint are LEAD + both FLANKs, the closest ex-REAR is among them, one REAR left |
| `test_a_role_change_mid_run_keeps_the_latched_pass_until_reposition` | kill the LEAD while a flank runs: its `pass_*` unchanged through RUN_IN/EXTEND; its next RUN_IN is the new role's kind |
| `test_every_reposition_seek_target_clears_the_reposition_radius` | three W5 placements, long PRIVATE budget: every non-hold REPOSITION seek segment clears `reposition_min_radius` − 2 |
| `test_rears_fire_nothing` | long PRIVATE budget. Open Space: runs until **each** REAR has flown a dry pass (precondition asserted). Assault: each REAR held through a window as REAR, never dry-passed, was promoted and then fired. Both: 0 rounds and no CHARGING frame while REAR (role or latched pass); the attackers fire |
| `test_a_flank_demoted_to_rear_mid_run_fires_nothing_after` | **N2:** a running FLANK demoted through `_reassign(force_rear)` fires 0 rounds for the rest of the pass, its latched pass unchanged; a control run of the same seeded squad without the demotion fires on that very pass |
| `test_a_squad_of_one_flies_the_solo_alternation` | a one-slot formation alternates FLANK_LEFT/FLANK_RIGHT |
| `test_a_disengaging_fighter_leaves_the_board` | after DISENGAGE entry it is off `members()` with role NONE |
| `test_strangers_do_not_give_way` | two formations in one wave are two boards; each fighter's give-way mates are exactly its own squad's |

**Mutations run on Revision 3 (each turns its case red):** the current-role REAR fire gate removed → the N2 case, both
modes; the off-station go removed → the N6 case; `_rear_slot_free()` always true → separation (Open Space W5, 29.2 px);
`_rear_slot_taken()` always false → separation (12+ W5 layouts, worst 1.8 px); the lead-in slide fallback off →
separation (38.0 px). Round 2's mutations of the Revision 2 rules (give-way, dry-REAR guard, window close, answer reset,
`_flanks_ready()`, ring tangent cap) are unaffected by Revision 3 and were not re-run.

## Risks

- **Separation after a death** is not in the criterion and is not asserted. When a member dies, `SquadController`
  recomputes every role by distance, which can swap two members' stations or leave a squad mid-pass with a new LEAD
  whose FRONTAL turn meets a flank's turn; TURN does not give way. Measured (table above): up to 9 of 42 W5 layouts
  overlap after the LEAD dies at 6 s, worst 7.3 px for a V3 LEAD killed at 12 s. For scale, HEAD's solo fighters
  overlap in 293 of 420 layouts with nobody dying. A fix (re-synchronise the squad through the rendezvous after a
  reassignment, or a TURN separation rule) is a follow-up.
- **Assault budget (escalation decision 2, still open).** At the shipped 6.0 s budget, 7 of 84 dense Assault layouts
  leave one attacker that never fires: a flank that crossed most of the corridor reaches its S too late for its run to
  fit, and the budget rule holds it there rather than send it out mid-run. The test pins that this is the *only* way an
  attacker goes silent. This build keeps Revision 2's handling ("a late flank holds and leaves"), which is a choice the
  owner has not made: DECISIONS records decision 2 as **open** (round-2 N7). If the owner picks a longer Assault squad
  budget, a second Assault pass fails separation as measured (V3 13/42, W5 25/42, worst 0.9 px: flank lead-ins and
  turns converging in the corridor, and a LEAD/FLANK station swap after a member leaves) — that option needs its own
  separation work first. Lever 1 (`engage_seconds` 6.0 → 4.5) would silence most squads.
- **Fighter body collision (escalation decision 3, still open).** In game the fighters collide (layer 1, mask 1); the
  test excepts collision between squad mates. With 0 overlaps over the full cycle the bodies should not touch in the
  measured layouts, but after a death they can (above), and they then bump rather than overlap.
- **Spawn fan-out** (§5): measured for Revision 2, recorded for t16.
- **Wide layouts:** V6 fails 1 of 42 in Open Space (third REAR), and 5 V6 layouts need more than 45 s for all three
  REARs to fly. V4/V6/line4 fighter squads ship in t16 at the earliest, which re-runs the separation check on the real
  level spawns.
- **Runtime:** the file takes ≈ 67 s (the full-cycle grid is 168 hand-ticked runs, the slowest 44 s of game time).
  Acceptable against the gate; if the suite budget tightens, the grid is the knob.
- **DISENGAGE exit** can pass within 21 px of the player (t8a/t8b's straight exit to the nearest edge): pre-existing,
  excluded from the player-clearance assertion, follow-up.
- **`_mates()` scans the `enemies` group** every tick for every squad fighter on a hold or lead-in (round-2 N9). Fine at
  V3/W5; if t16 brings larger squads, read the board's `members()` plus a cached list of exiting ex-members.

## Out of scope

Gatling squads (t10/t11), the hub idle (t12), level-1 migration and density gates (t16/t17), avoidance of non-squad
enemies / bullets / terrain, a shared avoidance component (Ph14), the spawn fan-out (t16), fighter body collision
layers (owner decision 3).

## 8. Answers to round-1 review (from Revision 2, still standing)

| Point | Answer in Revision 2 |
|---|---|
| B1 (D4–D6 need the owner) | D4, D5, D6 dropped. The criterion is met with `flank_stagger` + §3.1 rendezvous rules + §3.3's two brain-local give-way rules: no avoidance layer, no heading-source change, no shared API (option i's spirit; routing itself was measured and rejected, table above) |
| B2 (breach passes, silent attackers) | 0 breach passes on the dense grid, asserted; silent attackers asserted to be budget holds only, 7/84 recorded |
| B3 (residual failures in V3/W5) | The committed case runs the whole measured grid: 0 in-cycle failures |
| B4 (vacuous REAR case) | Precondition: each REAR flies a dry pass; long private budget in Assault |
| B5 (ghost collisions) | Collision exceptions in the test harness, with a comment; all numbers re-measured |
| B6 (dual) | Every acceptance case dual; the pincer's Assault variant asserts lateral bearings (corridor flip) |
| B7 (Assault timing) | Holds bounded by the budget; median LEAD first run 2.8 s; the silence trade-off recorded |
| N1, N2 | Obsolete with D4 (the give-way reads only its own board's members, and ex-members of it on their exit) |
| N3 | Current-role REAR gate added |
| N4 | Full-recompute assertion |
| N5, N6, N7 | Listed as deviations (§1, §2) |
| N8 | Wide numbers re-measured (§Measurements) |
| N9 | Constants, justified (§3.3) |

## 9. Answers to round-2 review

| Point | Answer in Revision 3 |
|---|---|
| Question 1: the give-way is within scope; "over a full cycle" was a relaxation | The give-way is kept. §5 now measures the full cycle the reviewer asked for (option (a)), so nothing is relaxed and no owner decision is assumed |
| B1 (W5 35/42 over a full cycle, REAR dry-pass TURNs) | §3.4: the dry pass has its own slot after the window; plus the §3.3 lead-in slide fallback. Full-cycle grid: 0 / 168 (Open Space W5 worst 69.3 px). The separation case asserts the full cycle's end point |
| Supporting data: Assault two-pass budget fails | Still fails (V3 13/42, W5 25/42); it is not reachable at the shipped budget and is recorded against the open decision 2 (§Risks) |
| N1 (stale comment) | Fixed |
| N2 (current-role REAR gate untested) | `test_a_flank_demoted_to_rear_mid_run_fires_nothing_after`, with a control run; the gate's mutation turns it red |
| N3 (`_cycle` never asserts its end point) | Asserts the LEAD's third run and every REAR's dry pass in Open Space |
| N4 (role-NONE exclusion) | Measured both ways (identical); the case now includes exiting fighters |
| N5 (braking mate hole) | `is_braking_onto_station()`: a member yields to a higher-priority braking mate. The two broader variants (yield to every braking mate; a braking mate slides like a holder) were measured worse and rejected (§3.3). The 0.9 px long-budget case the reviewer attributed to N5 is a LEAD/FLANK station swap after a member leaves, not braking (§Risks) |
| N6 (possible Open Space stall) | `_unsettled_time` / `UNSETTLED_WAIT_FACTOR`; `test_a_flank_kept_off_its_station_still_goes` |
| N7 (decision 2 closed unilaterally) | DECISIONS records it as open |
| N8 ("never nudged toward the player") | Reworded as measured (§3.3) |
| N9 (`_mates()` cost) | Recorded (§Risks); fine at V3/W5 |
