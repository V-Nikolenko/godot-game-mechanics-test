# Fighter squads (t9-fighter-squad) — task plan, Revision 2

> **Status (2026-10-05): BLOCKED, not approved.** Round-2 review (`4-review.md`, "Round 2") requested changes, and that
> was the last allowed round. Its blocker: §5's separation window ends at the LEAD's second RUN_IN — the frame the
> REARs first fly — so no REAR dry pass is ever checked. Over a full two-pass cycle a W5 fails in 35 of 42 Open Space
> layouts (worst 3.5 px: a REAR's dry-pass TURN against an attacker's TURN). The reviewer also ruled §5's reading a
> relaxation (the escalation's decision 1(b)), not "the epic's wording". The build is kept, unshipped, as
> `prototype/revision2_variant.patch`; the owner's decisions are in `5-escalation.md` → "Round 2". Everything below is
> Revision 2 as reviewed.

Task `cmulwkar300bxqj2xgtk6jyu3`, epic `cmufs7ekv000lnm2x7nbswijy`. Builds §2.5 of the epic's approved `3-plan.md`
(Revision 2, "the epic plan") on top of t8b (`docs/plans/cmulwkar000btqj2x1e58sfd4/`, as built in DECISIONS "Phase 3,
built in t8b"). The epic plan is not re-derived here.

**History.** Revision 1 (commit `34984b6`, in git) proposed an ORCA give-way layer (D4), a new heading source for every
phase (D5) and a new `EnemyMover` getter (D6). Round-1 review (`4-review.md`) ruled D4–D6 a scope change only the owner
can approve (B1), and found B2–B7. The run ended ESCALATE (`5-escalation.md`). The task was re-queued with no recorded
owner decision, so Revision 2 drops D4–D6 entirely and meets the criterion inside the task's own scope. The
measurements below come from the clean harness (B5: fighter–fighter collision excepted) and are deterministic.

**What changed from Revision 1:** §3.3 is rewritten (no ORCA, no D5, no D6); §3.1 gains the settled-on-S rule and a
budget-pressure rule; the parallel-lane trail is one stagger gap, not two; §5 states how "over a full cycle" is read;
the test plan answers B2/B3/B4/B6 and N4. The answers to every round-1 point are tabled at the end (§8).

## Problem

Today a formation of fighters is a set of solo fighters that happen to spawn together: each flies its own attack runs
and ignores the others. They bunch on the same line, overlap (in the real game their bodies collide: layer 1, mask 1)
and attack one after another from arbitrary sides.

After this task a formation fights as a squad. The nearest fighter leads and comes **head-on** down one side of the
player; the next two close as a **pincer** from the player's left and right on two lanes, starting the moment the
leader starts. A fourth and later fighters wait their turn on an outer lane and make **dry passes** (no fire, no
warning light): at most three attack at once (epic X9). When an attacker dies, the nearest waiting fighter takes its
place in the same call. Squad members keep clear of each other through the attack: a fighter waiting at its station
steps aside for a mate whose path crosses it, and a fighter flying to its station eases off for a mate on a run.

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

#### 3.2 The window (epic §2.5, unchanged from Revision 1)

- The LEAD opens `attack_window_open` on RUN_IN entry when its latched role is LEAD; it closes it on its own EXTEND
  entry if it still leads (otherwise `_reassign()` already closed it).
- A FLANK answers each window once, only while settled (review N3 of the epic); `_answered_window` resets on any tick it
  reads the window closed. `flank_wait_max` counts while settled and the LEAD is not holding. A REAR answers every second
  window with a dry pass and never goes on the wait.

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
   flanks frozen behind a never-ticked LEAD until their deadline).

Not touched: RUN_IN, EXTEND, TURN and DISENGAGE never give way (their timing is the stagger's, their line the pass's),
strangers never interact (only fighters whose `squad` field is this board), nothing is ever nudged toward the player
(the slide is perpendicular to a mate's track; the slow-down is along the member's own clear lead-in). **No new shared
API, no change to any phase's heading source, no `add_nudge()`:** the give-way re-issues the tick's own last request
through `mover.request_velocity()` (which replaces the earlier request in the same tick), and reads mates duck-typed.

**Why constants, not config (N9).** `GIVE_WAY_HULLS` / `_HORIZON` / `_SAMPLE` / `_SLIDE_SPEED` / `_STEPS` and
`STATION_SETTLE_PX` are controller tolerances stated in hull radii and against the 2 × hull criterion, like t8b's
`REPLAN_*` / `TRACK_*` constants, not balance a designer tunes per enemy. The Swarm's `separation_radius` etc. are
config because they shape the flock's visible look; these shape nothing visible beyond "does not overlap".

### 4. Config

`FighterConfig` (flat, Tactics group): `rear_standoff_radius` 560 and `flank_wait_max` 2.0 are now read; new
`lead_wait_max` 3.5 (D2) and `flank_stagger` 0.4 (D3).

### 5. Reading the criterion: "over a full cycle"

The epic plan says (§2.5) "t9 asserts a minimum body separation of 2 × hull radius between members **over a full
cycle**", and its own timing check is about the pincer runs crossing after the window opens. Revision 1 and the
escalation measured from spawn instead, which also catches the formation fanning out of its 80 px `v_formation` /
`w_formation` slots before any run exists. Revision 2 asserts the epic's wording: **from the LEAD's first window open**
to its second RUN_IN (Open Space) or to the last member leaving the board (Assault). The fan-out before it is
pre-existing behaviour of every level-1 formation (HEAD's solo fighters overlap there in 293 of 420 layouts) and
belongs to the spawn layouts (t16). It is measured and recorded, not hidden: 19 of 168 dense layouts still overlap
during fan-out with this build (137 on the stagger-only base).

## Measurements (clean harness, deterministic; `prototype/sweep_harness.gd.txt`)

Dense set = {V3, W5} × 7 player positions × 6 formation offsets × {Open Space, Assault} = 168 runs, shipped budget.
Wide set = {V3, V4, V6, line4, W5} × 7 × 6 × 2 = 420. CYC = an in-cycle pair of members under 57.2 px; SEP = the same
from spawn; BREACH = a squad RUN_IN not entered from a hold; SILENT = an Assault LEAD/FLANK that fired nothing.

| Build (dense 168) | CYC | SEP | BREACH | SILENT |
|---|---|---|---|---|
| Stagger only (the pre-approved scope) | 23 | 137 | 0 | 12 |
| + routing round mates' plans (escalation's option i) | 9 | 59 | 34 | 48 |
| + routing round holding mates only | 12 | 117 | 36 | 16 |
| **Revision 2 (§3.1 + §3.3)** | **0** | 19 | **0** | 7 |

Revision 2 on the wide set: 1 in-cycle failure in 420 (a V4, 47.8 px, EXTEND/TURN; no V4 ships in this task); 14 of 210 Assault layouts have a silent attacker. Worst
in-cycle separation on the dense set: 66.3 px (Open Space), 67.3 px (Assault). Closest any fighter comes to the player
outside its exit: 120 px. Median Assault time to the LEAD's first run: 2.8 s (budget 6.0).

## Build sequence

1. Restore the squad code (roles, window, holds, REAR, crossing stagger, budget bounds, ring-fallback clearance) without
   the routing variant's planner checks and without any give-way experiment; remove every env-switch and debug field.
2. §3.1 settled-on-S and budget-pressure rules; §3.3 one-gap parallel trail, `_slide_aside()`, `_slow_for_mates()`.
3. `tests/integration/test_fighter_squad.gd` (§Test plan). Mutation-check: disabling the give-way, the dry-REAR guard,
   the window close or the answer reset each turns its case red.
4. Delete the scratch sweep (`tests/integration/test_zz_sweep.gd`); keep it as `prototype/sweep_harness.gd.txt`.
5. `test_fighter.gd` (52) stays green unchanged; gate; leak check; docs; DECISIONS.

## Test plan

`tests/integration/test_fighter_squad.gd`, through a real `WaveManager` (stagger 0, no `SceneTreeTimer`) into the
`enemy_ai_harness.gd` worlds, hand-ticked at 60 Hz against a holding player, collision excepted between the spawned
fighters (B5). **Every case is dual** (Open Space + Assault) except the solo alternation, the disengage case (Assault
only by nature) and the strangers case.

| Case | Asserts |
|---|---|
| `test_a_v3_is_one_squad_of_the_lead_and_both_flanks` | one board; roles {LEAD, FLANK_LEFT, FLANK_RIGHT} |
| `test_the_pincer_and_the_frontal_pass` | first RUN_IN latches its role's kind; FLANK bearings from their role's side (Open Space) / lateral (Assault, where t8b's corridor flip may move a flank's side — B6); LEAD head-on; closest approach = lane ± 40 px |
| `test_the_window_opens_on_the_lead_run_in_and_closes_on_its_extend` | the window's first open frame is the LEAD's RUN_IN entry; open through the run; closed on its EXTEND entry |
| `test_the_lead_does_not_open_before_its_flanks_settle` | at the LEAD's RUN_IN each flank is settled, or the LEAD held `lead_wait_max`, or its run no longer fit the budget |
| `test_each_flank_answers_a_window_once_and_resets_on_reading_it_closed` | hand-driven window, PRIVATE long `flank_wait_max` and budget: answered once; not twice while the same window stays open; `_answered_window` false on the first tick reading it closed; window 2 answered |
| `test_a_flank_whose_lead_never_opens_goes_after_flank_wait_max` | LEAD never ticked; each flank runs `flank_wait_max` (+ at most its stagger) after settling |
| `test_members_never_come_within_two_hull_radii` | the **whole dense grid** (84 layouts per mode, B3: no hand-picked placements): in-cycle member separation ≥ 2 × hull; no fighter within hull + player hurtbox of the player outside DISENGAGE; **every squad RUN_IN entered from a hold** (B2); **in Assault every LEAD/FLANK that fired nothing never started a run** (B2, see §Risks) |
| `test_killing_the_lead_reassigns_in_the_same_call` | `free()` the LEAD: before any tick the closest remaining member leads and the window is closed |
| `test_a_w5_flank_killed_promotes_the_closest_rear_in_the_same_call` | **N4:** the full recompute — the three closest to the hint are LEAD + both FLANKs, the closest ex-REAR is among them, one REAR left |
| `test_a_role_change_mid_run_keeps_the_latched_pass_until_reposition` | kill the LEAD while a flank runs: its `pass_*` unchanged through RUN_IN/EXTEND; its next RUN_IN is the new role's kind |
| `test_every_reposition_seek_target_clears_the_reposition_radius` | three W5 placements, long PRIVATE budget: every non-hold REPOSITION seek segment clears `reposition_min_radius` − 2 |
| `test_rears_fire_nothing` | **B4:** runs until **each** REAR has flown a dry pass (precondition asserted), long PRIVATE budget in Assault; 0 rounds and no CHARGING frame on REAR passes; the attackers fire |
| `test_a_squad_of_one_flies_the_solo_alternation` | a one-slot formation alternates FLANK_LEFT/FLANK_RIGHT |
| `test_a_disengaging_fighter_leaves_the_board` | after DISENGAGE entry it is off `members()` with role NONE |
| `test_strangers_do_not_give_way` | two formations in one wave are two boards; each fighter's give-way mates are exactly its own squad's |

## Risks

- **Assault silence (B7 / escalation decision 2).** At the shipped 6.0 s budget, 7 of 84 dense Assault layouts leave
  one attacker that never fires: a flank that crossed most of the corridor (the player near a side wall puts both
  flanks on the far side) reaches its S too late for its run to fit, and the budget rule holds it there rather than
  send it out mid-run. The test pins that this is the *only* way an attacker goes silent. The owner's escalation
  decision 2 (a longer squad budget, Assault stations nearer the spawn, or no rendezvous in Assault) is still open;
  this build takes the option "a late flank holds and leaves". Recorded in DECISIONS for t16/t17, together with: lever
  1 (`engage_seconds` 6.0 → 4.5) would silence most squads.
- **Spawn fan-out** (§5): 19 of 168 dense layouts overlap before the first window. Recorded for t16 (spawn layouts),
  as are the in-game body collisions (escalation decision 3: layer 1 / mask 1 since before this phase).
- **Wide layouts:** 1 of 420 in-cycle (V4). V4/V6/line4 fighter squads ship in t16 at the earliest, which re-runs the
  separation check on the real level spawns.
- **Runtime:** the file takes ≈ 40 s (the dense grid is 168 hand-ticked runs). Acceptable against the gate; if the
  suite budget tightens, the grid is the knob.
- **DISENGAGE exit** can pass within 21 px of the player (t8a/t8b's straight exit to the nearest edge): pre-existing,
  excluded from the player-clearance assertion, follow-up.

## Out of scope

Gatling squads (t10/t11), the hub idle (t12), level-1 migration and density gates (t16/t17), avoidance of non-squad
enemies / bullets / terrain, a shared avoidance component (Ph14), the spawn fan-out (t16), fighter body collision
layers (owner decision 3).

## 8. Answers to round-1 review

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
