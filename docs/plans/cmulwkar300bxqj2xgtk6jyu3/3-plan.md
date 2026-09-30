# Fighter squads (t9-fighter-squad) — task plan, Revision 1

> **Status (2026-09-30): escalated, not approved.** Round-1 review `4-review.md` requested changes (B1: D4–D6 need
> the owner). The numbers in this revision came from a harness contaminated by fighter–fighter physics collisions
> against unstepped spawn positions (B5); the clean re-measurement and the decisions needed are in
> `5-escalation.md`. Read that first.

Task `cmulwkar300bxqj2xgtk6jyu3`, epic `cmufs7ekv000lnm2x7nbswijy`. Builds §2.5 of the epic's approved `3-plan.md`
(Revision 2, "the epic plan") on top of t8b (`docs/plans/cmulwkar000btqj2x1e58sfd4/`, as built in DECISIONS "Phase 3,
built in t8b"). The epic plan is not re-derived here: this file says **how** each §2.5 rule is built, and names each
place where building it literally does not work, with the number from a prototype run.

**Prototype.** A kinematic sweep through a real `WaveManager` (60 Hz, the real `fighter.tscn`, the real mover and
brain) over {V3, W5} × {3 player positions} × {3 formation offsets} × {Open Space, Assault}, from spawn until the
LEAD's second RUN_IN (Open Space) or the whole life (Assault, shipped `engage_seconds` 6.0), plus a wider sweep over
{V3, V4, V6, line4, W5} × 4 players × 3 offsets × 2 modes (120 runs). Metric: minimum centre distance between any two
live members, and minimum distance from any member to the player. It lived in `tests/integration/test_zz_*.gd` as a
scratch file and is deleted before the commit (the load-integrity gate compiles every `.gd`); the committed test keeps a
reduced version (§4).

## Problem

Today a formation of fighters is a set of solo fighters that happen to spawn together: each one flies its own attack
runs and ignores the others. Three fighters bunch up on the same line, pass through each other and attack the player
one after another from arbitrary sides.

After this task a formation fights as a squad. The nearest fighter leads and comes **head-on** down one side of the
player; the next two close as a **pincer** from the player's left and right on two separate lanes, and start the
moment the leader starts. A fourth and later fighters wait their turn on an outer ring and make **dry passes** (no
fire, no warning light) — at most three fighters attack at once (epic X9). When an attacker dies, the nearest waiting
fighter takes its place at once, and the formation re-spaces. Fighters in a squad never fly through each other.

## Design

### 1. Joining and leaving the board

- `Fighter.squad: SquadController` is the duck-typed slot `WaveManager` (and later `SectorHub`) writes before
  `add_child`. `Fighter._ready()` calls `squad.update_target(P, h)` then `squad.join(self)` (the Swarm precedent), so
  roles exist before the first tick.
- The brain calls `update_target(P, heading_ref())` every tick. `heading_ref()` (t8b's `_heading_ref`, now public) is the
  same `h` the pass geometry uses, so a flank role's side and its pass's bearing side agree.
- A fighter leaves the board on DISENGAGE entry and on `on_suspended()` (a rail), explicitly; a freed fighter leaves
  through `tree_exiting` (the board's own `join()` connection). Its `squad` field keeps pointing at the board, which
  the give-way (§3.3) uses so a disengaging ex-member is still avoided.
- **A squad of one is a solo fighter**: `role_of()` gives LEAD and `member_count() == 1`, and every squad rule below is
  gated on `member_count() ≥ 2`. t8b's solo alternation is unchanged.

### 2. Roles → pass kinds (epic §2.5 table)

Roles are read from `role_of()` **every tick** and never cached (Ph2 t4). The role only chooses the kind when the pass is
derived, which t8b does every tick **before** RUN_IN and never between RUN_IN entry and EXTEND's end:

| Role | Pass kind | `b` / `l` (epic §2.4.1) | Fires |
|---|---|---|---|
| LEAD | FRONTAL | `b = h`, `l = right(h)·σ·pass_offset`, σ taken from the side the fighter is on the first time it derives a FRONTAL pass, then alternating per pass (t8b re-read σ every tick; a LEAD spawned on the heading line flipped it and its S jumped across the player) | yes |
| FLANK_LEFT | FLANK_LEFT | `b = left(h)`, `l = h·pass_offset` | yes |
| FLANK_RIGHT | FLANK_RIGHT | `b = right(h)`, `l = h·(pass_offset + flank_lane_gap)` (the squad lane, as t8b's `forced_pass_kind` seam already did) | yes |
| REAR | new `PassKind.REAR` | `b = right(h)·s_r`, `s_r` the side it is on when it becomes REAR (then kept, so its S never swings across the player); `l = h·(pass_offset + (2 + rear_index)·flank_lane_gap)`, from `rear_standoff_radius` (560) — one lane per REAR outside both flanks' | **no** |

- **The pass is latched with its role.** `pass_role` is set at RUN_IN entry together with `b`, `u`, `l` and the kind,
  and nothing re-derives them until EXTEND ends (t8b's latch). A role change mid-pass (a death reassigning roles)
  therefore takes effect only when the pass is next derived, in TURN/REPOSITION. That is the epic's side-change rule,
  asserted as stated (§4), not as an absolute side.
- **REAR passes are dry:** `_try_open_burst()` returns at once while `pass_role == REAR`, so no telegraph, no light, no
  round. A REAR promoted mid-pass stays dry until its next pass; a FLANK demoted mid-pass (a closer join) keeps firing its
  latched pass.
- Corridor rules (t8b) apply to every kind unchanged. In Assault a flank's bearing can flip to the other side when its run
  would be shorter than `min_run_length` (the player near a wall); the two flanks then come from the same side on lanes
  100 px apart. That is t8b's corridor rule, not a new one.

### 3. The attack: rendezvous, window, stagger

#### 3.1 Every member flies to its S and holds there

- APPROACH and REPOSITION fly to S as t8b does (Dubins lead-in clear of the player). **Deviation D1:** a squad member's S
  is a *station*, not a run start: it plans its lead-in to arrive along its own approach (goal heading = direction of
  arrival) rather than along the run, and once within 2 plan radii of S with a straight segment clear of the player it
  simply `arrive()`s. The hold then turns the nose onto the run. *Why:* a run-aligned Dubins lead-in from close to S is
  often a near-full loop (the goal heading is up to 180° off the arrival direction), which throws a member across its
  mates' paths; a station only has to be reached.
- At S it **holds** (REPOSITION with `_hold_time ≥ 0`): t8b's loiter request (`v_P` + a correction capped at 60 px/s,
  nose along `u`). A holding member is *settled* once its speed is below 0.3 × `max_speed`. A member that drifts more
  than 160 px off its (moving) S, or whose role changes so that it no longer holds, flies back to its S.
- **Deviation D2 — the LEAD holds too.** The epic has the LEAD open the window on RUN_IN entry, and flanks answer only
  once loitering at S (review N3). The LEAD's S is ahead of the player and the flanks' are 480 px to its sides, so the
  LEAD usually arrives first (it spawns closest, by the role rule, and its S is the nearest to the formation). Opening then would leave both flanks in APPROACH, not
  answering — every pincer would decay into three `flank_wait_max` runs. So the LEAD holds at its S until **every FLANK
  is settled**, or at most `lead_wait_max` (new config field, 3.5 s), then starts its run.

#### 3.2 The window

- The LEAD sets `attack_window_open = true` on RUN_IN entry, only when the role latched for that pass is LEAD — i.e. it
  still leads (Ph2 t8c rule).
- It sets it `false` on its own EXTEND entry, only if it still leads; if it lost the lead meanwhile, `_reassign()`
  already closed the window and any open window belongs to the new LEAD.
- A FLANK answers **each window once**: on the first tick it reads the window open while it is *settled at S*, it sets
  `_answered_window` and starts its run. The flag resets on any tick it reads the window closed (the Swarm rule). A FLANK
  still in APPROACH or flying back to S does not answer (review N3).
- **`flank_wait_max` (2.0 s)** is counted while the FLANK is settled **and the LEAD is not holding** (D2: a holding LEAD
  is timing the attack, not dead or slow). After it, the FLANK goes anyway — a flank whose lead is dead, disengaged or
  stuck still attacks.
- A REAR answers **every second** window with a dry pass (the epic's "every other cycle"), and never goes on the wait.

#### 3.3 Separation

**Deviation D3 — `flank_stagger` generalised.** The epic's one pre-approved separation fix is a FLANK_RIGHT start delay,
`flank_stagger` (0.4 s). Built as a fixed per-role delay it depends on σ (which side the LEAD passes) and on the Assault
bearing flips. It is built instead as the rule it stands for: when a member is about to start a run, it computes, for
every mate already in RUN_IN or EXTEND, where their two lines cross and when each would reach the crossing at
`max_speed`; if it would arrive there within `flank_stagger` of the mate, it waits the difference (re-checked when the
wait ends). Parallel same-direction runs on neighbouring lanes wait until they trail by `2 × flank_stagger × max_speed`.
In a V3 pincer this is exactly the FLANK on the LEAD's σ side, as the epic's estimate says.

**Deviation D4 — a squad give-way layer.** The prototype shows `flank_stagger` alone does not keep members apart:

| Build | Shipped-config sweep (54 runs) | Wide sweep (120 runs) |
|---|---|---|
| no give-way (stagger only) | **47 fail**, worst separation 0.5 px — members converge in APPROACH from their formation slots at 0.6–1.2 s | — |
| ad-hoc rank + side-step rules (earlier attempt) | 7 fail (60 s budget only) | 19 fail, and a side-stepped fighter flew **2.7 px** from the player |
| **this design** | **0 fail** at the shipped budget; 2 fail only with `engage_seconds` 60 (never shipped) | 6 fail (§5) |

The design, all in `FighterBrain` (no new class; the Swarm's flocking nudge is the precedent for a brain-side squad
nudge through `EnemyMover.add_nudge()`):

1. **Who.** Every other fighter whose `squad` field is this fighter's board, **including a mate that has left it to
   DISENGAGE**. Never a stranger: two unrelated solo fighters do not interact (t8b's lock-step `aim_mode` test runs two
   of them on top of each other).
2. **What.** ORCA (van den Berg, Guy, Lin and Manocha, *Reciprocal n-Body Collision Avoidance*, 2011 — the RVO2
   library's construction): for each mate, `u` = the smallest change to the relative velocity that keeps the two
   centres ≥ `GIVE_WAY_HULLS × hull` (4 × 28.6 = 114 px) apart over `GIVE_WAY_HORIZON` (1.0 s), or ZERO when their
   straight tracks already do; already inside, `u` pushes straight apart to restore it within 0.3 s. The request this
   tick (`mover.requested_velocity()`) is projected onto each half-plane `{v : (v − (v_self + share·u))·û ≥ 0}` in turn,
   and the difference is offered as the nudge. (Adding `u` to the request instead, the first build, cancels itself the
   tick after it works and oscillates: 41–48 px.)
3. **Shares by phase** (`give_way_rank()`, read duck-typed): the run and the turn back in (RUN_IN, TURN step 0 — the
   two legs a burst is fired from) take **none** against anything else, which takes **all**; between two of them, or
   between any other two, it is split ½–½. A run or turn-in's own nudge is reduced to its **along-track part** (it gives
   way by timing, never by bending its line — lane geometry and the nose-on snapshot are t8b's tested contract).
4. **Never toward the player.** The nudge's component toward the player is removed.
5. **Deviation D5 — the brain steers from its intent.** `turn_toward` in every phase started from the *velocity's*
   heading (t8b's `_heading()`). A persistent nudge rotates the velocity by up to 0.033 rad per tick while the brain
   corrects at most `turn_rate × dt` = 0.03 rad, so the drift builds (measured: a LEAD walked 200 px off its FRONTAL lane
   into the player). `_heading()` now returns the direction of the brain's **own last primary request** while moving, so
   a nudge displaces the fighter without turning its plan; path following then corrects the offset. With no nudge the two
   are the same direction, so t8b's 52 cases are unaffected (verified). A velocity jump bigger than the mover's
   `max(acceleration, braking) × delta` between ticks is an outside write (a test pose; nothing in the game — the
   single-writer gate) and drops the intent.
6. **Deviation D6 — one additive getter on a shared component:** `EnemyMover.requested_velocity() -> Vector2`
   (read-only `_primary`), so a brain can shape a nudge against what it has already requested. No behaviour change.

### 4. Config

`FighterConfig` (flat, Tactics group): existing `rear_standoff_radius` 560 and `flank_wait_max` 2.0 are now read; new
`lead_wait_max` 3.5 (D2) and `flank_stagger` 0.4 (D3). `test_config_instance_isolation.gd` keeps it flat. The give-way
numbers are controller constants in the brain, not balance.

## Build sequence

1. **Clean the restored tree.** Keep the squad join, role → kind, hold, window, REAR and stagger code of the earlier
   attempt; replace its ad-hoc give-way (ranks + side-steps + an `OS.get_environment("NO_GW")` debug switch, and a scan of
   every enemy in the tree) with §3.3. Remove every debug field.
2. **`EnemyMover.requested_velocity()`** + a unit case in `tests/unit/test_enemy_mover.gd`.
3. **`FighterBrain.avoidance()`** (static, pure) + unit cases (new `tests/unit/test_fighter_avoidance.gd`).
4. **`tests/integration/test_fighter_squad.gd`** (§4 of this file), written against the real `WaveManager`; watch the
   window, reassignment and separation cases fail on the base t8b brain (stash) before the squad code.
5. **Delete the scratch sweeps** `tests/integration/test_zz_one.gd`, `test_zz_sweep.gd`.
6. `test_fighter.gd` stays green unchanged (52 cases); gate; leak check; docs (`updating-project-docs`), DECISIONS.

## Test plan

`tests/integration/test_fighter_squad.gd`. Harness: `enemy_ai_harness.gd` Open Space / Assault worlds, a
`Camera2D`/`ArenaCamera` made current, a real `WaveManager` whose `enemy_container` is the harness root, one wave at
`trigger_time` 0 with **stagger 0** (no `SceneTreeTimer` — the tests/README leak trap). Fighters are hand-ticked at
60 Hz with the player holding. "Dual" = both harnesses.

| Case | Asserts |
|---|---|
| `test_a_v3_is_one_squad_of_lead_and_both_flanks` (dual) | one board; roles {LEAD, FLANK_LEFT, FLANK_RIGHT} |
| `test_the_pincer_and_the_frontal_pass` (Open Space) | each member's first RUN_IN latches its role's kind; FLANK_LEFT comes from `left(h)`, FLANK_RIGHT from `right(h)`, LEAD FRONTAL; closest approach to the player of each run = its lane (`pass_offset`, `pass_offset + flank_lane_gap`, `pass_offset`) ± 40 px |
| `test_the_window_opens_on_the_lead_run_in_and_closes_on_its_extend` (dual) | recorded per tick: the window's first open tick is the LEAD's RUN_IN entry tick; it reads closed from the LEAD's EXTEND entry tick |
| `test_each_flank_answers_a_window_once_and_resets_on_reading_it_closed` (dual) | every FLANK RUN_IN entry happens while the window is open or after `flank_wait_max`; at most one entry per window per FLANK; `_answered_window` is false on the first tick after the window closes |
| `test_a_flank_whose_lead_never_opens_goes_after_flank_wait_max` | the LEAD's brain is never ticked (holds no S, opens nothing); each FLANK enters RUN_IN within `flank_wait_max` + 2 ticks of settling |
| **`test_the_lead_does_not_open_before_its_flanks_settle`** | the LEAD's RUN_IN entry comes after both flanks settled, or at `lead_wait_max` |
| `test_members_never_come_within_two_hull_radii` (dual, V3 and W5, 3 placements each) | minimum centre distance between live members ≥ 2 × 28.6 px, from spawn to the LEAD's second RUN_IN (Open Space) / to the last fighter freed (Assault, shipped budget); no member within hull + player hurtbox of the player |
| `test_killing_the_lead_reassigns_in_the_same_call` | `free()` the LEAD; before any tick, the closest remaining member is LEAD and the window is closed |
| `test_a_w5_flank_killed_promotes_the_closest_rear_in_the_same_call` | W5, kill a FLANK; before any tick, the REAR closest to the player hint holds a FLANK role and `rear_count()` fell by one |
| **`test_a_role_change_mid_run_keeps_the_latched_pass_until_reposition`** | kill the LEAD while a FLANK is in RUN_IN (it becomes LEAD): its `pass_kind`, `pass_bearing`, `pass_dir`, `pass_lane`, `pass_role` are unchanged every tick until EXTEND ends; its next RUN_IN is FRONTAL |
| `test_every_reposition_seek_target_clears_the_reposition_radius` (dual) | on every REPOSITION tick that is not a hold and starts outside `reposition_min_radius`, the segment fighter → `seek_target` clears `reposition_min_radius` − 2 px |
| `test_rears_fire_nothing` (dual, W5) | over a cycle, 0 rounds from any pass latched as REAR, and no CHARGING light on those passes; the attackers fire ≥ 1 |
| **`test_a_squad_of_one_flies_the_solo_alternation`** | a one-slot formation alternates FLANK_LEFT/FLANK_RIGHT kinds like t8b's solo fighter |
| `test_a_disengaging_fighter_leaves_the_board` (Assault) | after DISENGAGE entry `members()` no longer has it, and the remaining roles are recomputed |
| `test_strangers_do_not_give_way` | two solo fighters on top of each other request no nudge (t8b's lock-step case is the regression guard) |

`tests/unit/test_fighter_avoidance.gd` (`FighterBrain.avoidance`): no conflict → ZERO; **tracks passing exactly
`radius` apart → ZERO**; head-on at 600 px/s closing, 300 px apart → a non-zero `u` after which the closest approach over
the horizon is ≥ `radius` − 1e-3; overlapping and closing → `u` points straight apart; a slow overtake from behind →
through the cut-off circle. `tests/unit/test_enemy_mover.gd`: `requested_velocity()` is ZERO before a request and the
request after one, and ZERO again after `step()`.

## Risks

- **Residual failures in wider layouts** (V4/V6, the player in a far corner): 6 of 120 in the wide sweep. 3 are
  separation (worst 24 px: two fighters in the break-away turning into each other, which a straight-line
  prediction sees too late for the mover's 700 px/s² to resolve). Level 1's formations are 3–6 fighters and are t16's;
  it re-runs the separation check on the real level spawns. Recorded in DECISIONS as a known gap, not hidden.
- **Hand-ticked timing.** The committed separation case covers 12 runs; the runtime of the file must stay under ~20 s
  (measured before commit).
- **D5 touches every phase's steering.** Guarded by all 52 t8b cases.

## Out of scope

- Gatling Interceptor squads (t10/t11), the hub idle (t12), level-1 migration and its density gates (t16/t17).
- Avoidance of non-squad enemies, of the player's bullets, or of terrain; a shared avoidance component for other
  families (the pure `avoidance()` is where Ph14 would lift it from).
- The DISENGAGE exit can pass within 30 px of the player (t8a/t8b's straight exit to the nearest edge): pre-existing,
  noted as a follow-up.
