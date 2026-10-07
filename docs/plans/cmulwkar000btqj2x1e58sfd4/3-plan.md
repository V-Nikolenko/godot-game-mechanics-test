# Fighter attack runs (t8b-fighter-run) — task plan, Revision 2

Task `cmulwkar000btqj2x1e58sfd4`, epic `cmufs7ekv000lnm2x7nbswijy`. Builds §2.4.1 and §2.4.2 of the epic's approved
`3-plan.md` (Revision 2, "the epic plan" below) on top of the t8a shell. The epic plan is not re-derived here: this
file says **how** each §2.4 rule is built, and names each place where building it literally does not work, with a
numeric reason from a prototype run.

Revision 2 (2026-09-29) answers the round-1 review (`4-review.md`, B1–B4 and non-blocking 1–8); §8 maps every point.
The prototype is a kinematic sim of exactly this controller (300 px/s, 1.8 rad/s, 60 Hz, the corridor rect, entry
from above the screen), `/tmp/sim/sim9.gd` + `/tmp/sim/dubins_path.gd` (not committed: the load-integrity gate
compiles every `.gd` in the repo).

## Problem

Today an AI fighter (Open Space, or Assault once level 1 leaves its rails) flies at the player, stops 480 px away and
hangs there without firing. After this task it flies attack runs: it lines up, passes a set lane beside the player
with an aimed Pulse burst, extends past, makes a visible wide turn back in toward the player and sprays a close
Scatter burst when its nose comes on, breaks away and comes round for the next pass. The yellow light warns 0.3 s
before each burst. In Assault the passes are horizontal sweeps across the corridor, and the fighter leaves when its
budget or its passes run out, finishing a burst first.

## Design

### 1. Pass geometry — the epic's §2.4.1

- `h`: Open Space = player velocity direction above 40 px/s, else `TargetInfo.facing`; Assault = `Vector2.UP`
  (whenever `mover.constraint.inner_rect()` has area).
- A pass is `(kind, b, u = −b, l)`; `S = P̂ + b·standoff_radius + l`; the pass line is `P̂ + l + u·t`.
- Kinds and lanes as the epic table: FLANK_LEFT `b = left(h)`, `l = h·pass_offset`; FLANK_RIGHT `b = right(h)`,
  `l = h·(pass_offset + flank_lane_gap)`; FRONTAL `b = h`, `l = right(h)·σ·pass_offset`, σ starting at
  `sign(right(h)·(X − P̂))` (0 → +1) and flipping each FRONTAL pass; solo alternates FLANK_LEFT/FLANK_RIGHT **both at
  `pass_offset`**, the first matching `right(h)·(X − P̂) ≥ 0 → FLANK_RIGHT`.
- **When the pass is fixed (B3-i).** During APPROACH, TURN and REPOSITION the pass is **re-derived every tick** from the
  current `h`, P̂ and the pass-kind source (the solo alternation's next kind, `forced_pass_kind`, and in t9 `role_of()`),
  and the lead-in path re-plans when S moves more than 24 px. **Everything — kind, `b`, `u`, `l` and P̂'s lead — is
  latched on RUN_IN entry** (the epic's rule, which t9's "a role change takes effect at the next REPOSITION" builds on)
  and released on EXTEND's end. The solo alternation advances its "next kind" once per completed pass (at EXTEND's
  end), and the first pass's kind is re-derived from the side the fighter is on until RUN_IN.
- `P̂ = P + v_P·lead`, `lead = clamped_lead_time(|X − P|, max_speed, 0.3, 0.8)` each tick before RUN_IN, **latched at
  RUN_IN entry**, so during the run P̂ moves with exactly the player's velocity. A lead recomputed every tick of the run
  shrinks from 0.8 to ≈ 0.53 s and drags a FLANK lane ≈ 54 px sideways for a 200 px/s player — most of the ±40 px
  budget. This is how N1's "the tick's P̂" is made well defined.
- Read-only for tests and t9: `pass_kind`, `pass_bearing` (b), `pass_dir` (u), `pass_lane` (l), `pass_anchor` (this
  tick's P̂), `pass_start` (S), `seek_target`, `passes_done`.
- **Test seam `forced_pass_kind: int = -1`.** ≥ 0 makes every pass that kind with its *role-shaped* lane (FLANK_RIGHT
  at `pass_offset + flank_lane_gap`), which is what t9's roles will select. −1 = the solo alternation.

### 2. RUN_IN — the epic's path following, plus a velocity feed-forward

Each tick: `A = P̂ + l`, `s = (X − A)·u`, `proj = A + u·s`, **`seek_target = proj + u·lookahead`** (always exactly
`lookahead` ahead along `u`, so it never stalls). The request is `turn_toward(heading, desired, turn_rate)` at
`max_speed`, with

`desired = v⊥ + dir(seek_target − X)·√max(max_speed² − |v⊥|², 0)`, `v⊥ = v_P − u(v_P·u)`.

For a holding player `v⊥ = 0` and this is the epic's rule verbatim. For a moving player it adds the line's own
sideways motion: without it a pure-pursuit follower of a FLANK lane sliding 200 px/s sideways settles 196.8 px behind
the line (`e = 200·220 / √(300² − 200²)`), i.e. through P̂. The **run heading** the fighter holds on the line is
`g = normalize(v⊥ + u·√max(max_speed² − |v⊥|², 0))` (`g = u` for a holding player). With `|v⊥| ≥ max_speed` (the
Open Space player cruises at 420) the square root is clamped to 0 and the fighter only matches the lane's sideways
motion; RUN_IN then ends by `run_in_max`.

RUN_IN ends on the first tick with `(P̂ − X)·u < 0` (epic), or after `run_in_max` (new config field, 4.0 s).

### 3. The pass cycle: APPROACH → RUN_IN → EXTEND → TURN → REPOSITION → RUN_IN

**Why the epic's TURN/REPOSITION cannot be built literally.** The epic's REPOSITION "seeks S" and hands over "within
`start_tolerance` of S with the heading within 30° of `u`"; its TURN is "`turn_toward` S until within 20°"; opportunity
(b) is "in TURN, the tick the nose comes within `nose_cone_deg` of the player". Review note N8 found the solo
alternation degenerate: after a FLANK_LEFT pass the fighter extends to x ≈ +311 on `y = −160`, and the next S =
(480, −160) is dead **ahead** with `u` pointing **back**, so TURN ends at once and seeking S arrives 180° wrong (a
turn-limited seek then orbits S). N8's own fix (seek `S − u·lookahead`) is dead ahead too. And round 1 of this
review measured that a turn toward S never brings the nose onto the player in any pass kind once REPOSITION's
288 px routing applies, so FORWARD (the close burst in this task's title) would never fire.

**The cycle as built** — two independent pieces:
1. **TURN = turn back in and snapshot.** The visible wide turn is a full-rate turn toward the player (radius
   `max_speed / turn_rate` = 166.7 px, the epic's number) until the nose is within `nose_cone_deg` of the player — which
   *is* opportunity (b), by construction, once per cycle. Then a **break-away**: the first arc of the REPOSITION path
   (below), flown still inside TURN. TURN ends when that arc ends.
2. **REPOSITION = a Dubins lead-in to S** (arrive at S already pointing along `g`), entirely outside
   `reposition_min_radius`, so the epic's §2.5 side-change rule ("REPOSITION never seeks within
   `reposition_min_radius`") holds for all of REPOSITION.

**`DubinsPath`** — new, `global/enemy_ai/dubins_path.gd`, `class_name DubinsPath extends RefCounted`, pure maths, no
node, no motion writes (it sits in the single-writer sweep and passes it). The shortest curve between two poses for a
vehicle with a minimum turn radius is at most three pieces, each a full-rate arc or a straight (Dubins 1957; LaValle,
*Planning Algorithms* §15.3.1):
- `static func candidates(p0, h0: float, p1, h1: float, r: float) -> Array[DubinsPath]`, **sorted by length**: the
  4 CSC paths (the inner-tangent pair only when the circle centres are ≥ 2r apart), the CCC paths (both middle-circle
  choices, when the centres are ≤ 4r apart), and a single arc when start and goal share a circle.
- Per path: `kind`, `length`, `segments` (arc: centre, sign, angle; line: from, to), `first_arc_angle()`,
  `end_heading()` (analytic), `sample(step) -> PackedVector2Array`.
- Sign convention in Godot's y-down frame: +1 = heading angle increasing.
- Mode-neutral: later attack-run enemies (the Ph4 Bomber/Ram passes) can plan with it.

**Planning** (`_plan_to_start()`), shared by APPROACH, TURN's break-away and REPOSITION:
- Goal pose (`S`, `g`), radius `r_plan = 1.1 × max_speed / turn_rate` (183 px), so the tracker keeps 10 % of turn
  authority for error correction (non-blocking 3). For a moving player the goal is where S will be on arrival: plan to
  S, `T = length / max_speed` (capped 3 s), re-plan once to `S + v_P·T`.
- **The first candidate in length order that is clear** (non-blocking 5): every 16 px sample `q_i` is at least the
  phase's clearance from **where the player will be then** (`P + v_P·(i·16 / max_speed)`), and in Assault, while the
  fighter is itself inside `inner_rect().grow(60)`, every sample is inside that rect too (a fighter still entering from
  above the screen is exempt, so it can plan its way in). For the break-away plan only, samples within the first arc
  use `BREAK_CLEARANCE` (120 px = 0.75 × `pass_offset`) and the rest `reposition_min_radius`.
- **Tracking**: advance the path index to the nearest of the next 12 samples (8 px spacing); `seek_target` = the sample
  3 ahead (≈ 24 px), or past the end along `g`; `turn_toward(heading, seek_target − X, turn_rate)` at `max_speed`.
  Re-plan when S moved > 24 px since planning or the fighter is > 40 px off the path. (Round-1 prototype: replanning
  every tick and steering by the first arc's sign zig-zags at ≈ 0.6 rad/s; plan-then-track is stable.)

**Per phase:**
- **APPROACH** — Dubins lead-in to the first pass's S. **Clearance and breach radius are derived from S (B1):**
  `clear = min(standoff_radius, |S − P̂|) − 1`, breach radius `= clear − BREACH_MARGIN` (24 px, non-blocking 1). In
  Assault the corridor clamp (below) can put S at 380–411 px from a centred player; a fixed 480 clearance would then
  have no clear path and always breach (the round-1 failure). Breach → RUN_IN at once as a FRONTAL-shaped pass from
  the current bearing: `b = dir(X − P̂)`, `u = −b`, and (N9) `l = right(u)·σ·pass_offset`, σ = the side the fighter is
  already drifting to, `sign(right(u)·heading)` (0 → +1). No clear path → the epic's REPOSITION ring routing (below).
  Handover to RUN_IN on the REPOSITION criterion.
- **EXTEND** — the epic's rule (hold heading; ends at ≥ 350 px after ≥ 0.6 s, or at 1.5 s). Assault adds: it ends as
  soon as `X + heading·(r + hull)` would leave `inner_rect()`, so the turn that follows has room.
- **TURN** — (i) *turn-in*: `turn_toward` the player's direction at full rate, the short way; in Assault, if the
  short-way turn circle (centre `X + right_or_left(heading)·r`) would leave `inner_rect().grow(60 − r)`, and the other
  one would not, it turns the long way (prototype: the player 100 px under the corridor top). It ends on the first tick
  with the nose within `nose_cone_deg` of the player, or after `π / turn_rate + 0.3` s. (ii) *break-away*: plan the
  REPOSITION path with the break-away clearance and fly its first arc. With no such path, *peel*: `turn_toward` the
  direction away from the player until outside `reposition_min_radius`. TURN ends when the arc (or the peel) does.
- **REPOSITION** — fly the planned path (re-planning with `reposition_min_radius`). **Handover: within
  `start_tolerance` of S with the heading within 30° of `g`** (the epic's criterion; `g = u` for a holding player).
  No clear path → **the epic's ring routing, verbatim**: seek `P̂ + b_now.rotated(±min(90°, remaining)) ×
  standoff_radius`, the shorter way round, clamped into `inner_rect()` shrunk by `r` in Assault.
- **Liveness caps (B3-ii).** APPROACH and REPOSITION each get a **deadline = (duration of the first successful plan in
  that phase, `length / max_speed`) + `reposition_max`** (3.0 s, the epic's field; `reposition_max` alone when no plan
  was ever found). On the deadline the fighter starts RUN_IN as the FRONTAL-shaped breach pass from its current bearing
  (above) — the epic's "after `reposition_max`, from wherever it is", made safe by giving it a lane that is
  perpendicular to where the fighter actually is. A player it cannot catch (420 px/s) therefore still gets an attack
  run every few seconds; RUN_IN is capped by `run_in_max`.
- **Passes** (epic): counted at EXTEND's end. After `passes` passes, Assault → DISENGAGE; Open Space → the next
  REPOSITION, on reaching the handover criterion, **loiters at S** for `regroup_seconds` (new config field, 1.5, the
  epic's number) before RUN_IN: velocity request `v_P + (S − X)·2` with only the correction term capped at 60 px/s
  (non-blocking 6), nose along `u` via `mover.face_toward(X + u)`. t9 reuses this loiter for flanks.

**Assault (epic R3.5), built as:**
- `h = UP`. **Lane flip**: a FLANK lane `P̂.y − |l|` within the hull radius of `inner_rect().position.y` flips behind
  (`l → −l`); a FRONTAL lane `P̂.x + σ|l|` within the hull radius of a side wall flips σ.
- **S is clamped along the run axis only** (so it stays on the pass line) into `inner_rect()` shrunk by
  `2·r_plan + hull` along that axis — so the Dubins lead-in loop that ends at S fits the corridor. The epic said
  "clamped into `inner_rect()`"; clamped to the bare rect, a lead-in near a wall has no clear path. With the
  APPROACH clearance now derived from S (B1), the tighter clamp no longer forces a breach.
- **Bearing flip**: if the run `(A − S)·u` is shorter than `min_run_length` after clamping, the pass takes `−b`
  (recomputed and clamped the same way). Player 150 px from the left wall (x = 50): FLANK_LEFT's S clamps to
  x = −100 + 2·183.3 + 28.6 = 295, the run is `50 − 295 < 0`, so the pass comes from the right.
- Containment is asserted against `inner_rect().grow(soft_band)`, the dual-mode file's existing definition.

**Prototype (`sim9.gd`), holding player unless stated:**

| Scenario | Closest approach per pass (lane) | TURN nose-on distance | Min distance to player | Pass-to-pass |
|---|---|---|---|---|
| Open Space solo, 4 alternating flank passes | 159.4 / 159.8 / 159.8 / 159.8 (160) | 308 / 304 / 304 | 159.4 | ≈ 10.1 s |
| Open Space FRONTAL ×4, σ alternating | 160.5 / 160.2 / 160.3 (160) | 307 / 306 / 307 | 142.5 | ≈ 13 s |
| Open Space FLANK_LEFT ×3 (peel fallback used) | 159.7 / 159.7 / 159.7 (160) | 305 / 308 | 159.7 | ≈ 9.7 s |
| Assault, centred player, entry from above, **shipped 6 s budget** | first RUN_IN at 3.77 s, **FLANK, `u = (−1, 0)`**, 160.5 | — (budget ends in EXTEND) | 160.5 | — |
| Assault, same, 30 s budget | 160.5 / 159.5 / 159.7 | 307 / 308 / 305 | 159.5 | ≈ 9.4 s |
| Assault, player at y = 600 | 160.5 / 159.5 | 307 | 159.5 | — |
| Assault, player 100 px under the top (lane flips behind; long-way turn-in) | 159.5 / 160.5 | 524 (outside `fire_range`: no burst) | 159.5 | — |
| Assault, player 150 px from the left wall (bearing flip) | 160.2 / 159.7 | 157 | 154.1 | — |

No run left `inner_rect().grow(120)`. A moving player (200 px/s) is covered by the feed-forward and goal prediction;
the round-1 sim measured 158.2–163.6 px against P̂ for flank and frontal passes, and a slow cycle (the fighter has only
100 px/s on the player) — the tests stage a spawn near S for it, and the liveness cap covers a player it cannot catch.

### 4. Weapons — the epic's §2.4.2, as a small independent layer

Weapons tick every AI tick before the phase logic, regardless of phase.
- **Legs.** Leg A = RUN_IN (+ EXTEND), reset on RUN_IN entry; leg B = TURN, reset on TURN entry. At most one burst per
  leg (epic (c)).
- **Opportunities.** (a) any RUN_IN tick with leg A unspent and `d ≤ fire_range`; (b) the TURN tick on which the nose
  comes within `nose_cone_deg` of the player, `d ≤ fire_range`, leg B unspent. Both also need: no burst running, at
  least `min_burst_period` since the last **burst start** (= telegraph start) (N4: the brain enforces it), not
  DISENGAGE-pending, a target.
- **Mode**, `select_weapon_mode(d)`: `< forward_range` → FORWARD, `≥ forward_range + mode_hysteresis` → AIMED,
  between → the last *used* mode (initial AIMED). A FORWARD choice with the nose off-cone is **skipped and not spent**
  (the leg stays open, nothing is latched, `weapon_mode` does not change).
- **`forward_range` 300 → 325 (B2; the epic's pre-approved K5 lever, "tune `forward_range`, not the mechanism").** The
  turn-in's nose-on distance is the tangent length from the turn circle, ≈ 305 px after the epic's 350 px EXTEND
  (prototype 304–308 in every scenario). At 300 every snapshot would fall in the hysteresis band and repeat the RUN_IN
  burst's AIMED, so FORWARD would still never fire. 325 keeps the task's acceptance numbers valid: 250 → FORWARD,
  400 ≥ 385 → AIMED, 330 inside the band [325, 385). So a pass cycle naturally fires **AIMED at ≈ 506 px (RUN_IN) and
  FORWARD at ≈ 305 px (TURN)** — the epic's "one fighter naturally uses both modes in a single run".
- **Burst.** Start: latch the mode, emit `weapon_mode_changed(mode)` only if it differs from `weapon_mode`, draw the
  count from `rng` (`aimed_min..max` / `forward_min..max`), light CHARGING for `burst_telegraph`. Then AIMED locks
  `aim_point` on the aimed pattern to the player's lead point (`TargetInfo.intercept` at `aimed_speed`, blended by
  `aimed_accuracy`, as `aim_direction` does) — "re-evaluated through the telegraph and locked when the burst starts";
  `BurstClock.start(count, gap)`, light ARMED; each tick `fire_now()` once per shot due on the latched controller
  (`AimedAttack` / `ForwardAttack`). End: light OFF, `aim_point = INF`.
- **FORWARD bursts keep the nose on the player** through telegraph and burst with `mover.face_toward(player)` — only
  the *nose* (rotation, which the forward pattern fires along); the *path* is untouched, so the fighter slides along its
  break-away arc and never closes to spray. The bearing rate to the player on that arc is ≤ ≈ 1.2 rad/s, inside the
  mover's 1.8 rad/s rotation cap. (Round 1 rejected steering *at* the player: 250 → 70 px.)
- **Deferred DISENGAGE.** Any entry to DISENGAGE (budget expiry, passes done in Assault) while a telegraph or burst
  runs is held until the burst ends: worst case `burst_telegraph + (aimed_max − 1)·aimed_gap` = 0.7 s ≤ the epic's
  0.8 s term.
- `on_suspended()` also stops any burst and clears `aim_point`.

### 5. Config and constants (non-blocking 7)

New `FighterConfig` fields (flat floats, `.tres` and `.gd` default): `run_in_max` 4.0 and `regroup_seconds` 1.5
(Tactics). Changed: `forward_range` 300 → 325. Constants in the brain are controller tolerances, not balance:
`REPLAN_GOAL_PX` 24, `REPLAN_OFF_PATH_PX` 40, `PLAN_RADIUS_FACTOR` 1.1, `PLAN_SAMPLE_PX` 16, `TRACK_SAMPLE_PX` 8,
`BREACH_MARGIN` 24, `BREAK_CLEARANCE_FACTOR` 0.75 (of `pass_offset`), `CORRIDOR_SLACK` 60, `LOITER_SPEED` 60,
`GOAL_PREDICT_MAX` 3.0.

### 6. Rejected alternatives
- **Literal "seek S + 30° criterion"**: degenerate (N8).
- **U-turn + pure-pursuit merge** (N8's idea extended): closest approach 222–278 px against 160.
- **Replan every tick, steer by the first arc's sign**: zig-zags at a third of the turn rate.
- **TURN = the Dubins path's first arc (Revision 1)**: zero nose-on events in every scenario (round-1 B2); relaxing
  only that arc's clearance to 120 px still gave zero (this revision's check) — shortest paths turn away.
- **Steering at the player during a FORWARD burst**: 250 → 70 px.
- **Opportunity (b) also in REPOSITION**: more shots against the t16 density gate, and no nose-on events there anyway.

## Build sequence
1. `DubinsPath` + `tests/unit/test_dubins_path.gd` (failing first).
2. Brain: pass selection/geometry and latching (§1), RUN_IN (§2), APPROACH/EXTEND/TURN/REPOSITION/caps/passes (§3),
   with the `test_fighter.gd` geometry specs first.
3. Assault rules with their boundary specs.
4. Weapons (§4) with the selection/cadence/telegraph/deferral specs; rewrite the two t8a-only cases.
5. Gate: `bash /agent/verify.sh`, `scripts/check-test-leaks.sh`; docs (`updating-project-docs`: `global.md` gains
   `DubinsPath`, the fighter `ENEMY.md`); DECISIONS lines (§7).

## Test plan
`tests/unit/test_dubins_path.gd`:
- Goal straight ahead on the same heading → the shortest path's length = the distance, arcs ≈ 0.
- **Quarter turn (0,0)/0 → (r, r)/+π/2 → a pure arc of length `r·π/2`.**
- For 12 seeded random pose pairs, every candidate: the last sample within 1e-3 px of the goal; `end_heading()` within
  1e-4 rad of the goal heading (analytic; the sampled last chord is off by `step / 2r`, non-blocking 4); `length`
  equal to the 1 px polyline length within 0.5 %; candidates sorted by length.
- The solo reversal ((450, −160)/0 → (480, −160)/π) shortest candidate is CCC and ≤ 1250 px.
- **Coincident circles → a single arc; centres < 2r apart → no inner-tangent CSC; > 4r apart → no CCC.**

`tests/integration/test_fighter.gd` (extended; "dual" = `use_parameters(["open_space","assault"])`; cases that need a
second pass or passes-done in Assault raise `engage_seconds` on the **private** config, and say so):
- Dual: the phase sequence APPROACH → RUN_IN → EXTEND → TURN → REPOSITION → RUN_IN.
- **Open Space, holding player, the epic's worked check**: forced FLANK_LEFT closest approach `pass_offset ± 40` with
  `(X − P)·h > 0`; FLANK_RIGHT `pass_offset + flank_lane_gap ± 40`, ahead; FRONTAL `pass_offset ± 40` on side σ.
  Latched `b, u, l` equal the table within 1e-3.
- **Moving player (200 px/s along h)**, fighter spawned 100 px beyond S along `b` facing `g`: the same three against
  the tick's `pass_anchor` (N1), plus the live "ahead" check for the flanks.
- **Latching (B3-i)**: `pass_bearing/dir/lane` never change during RUN_IN while the player turns (`h` changes); during
  REPOSITION they follow a player that turns.
- Solo alternation FLANK_RIGHT → FLANK_LEFT → FLANK_RIGHT, every pass at `pass_offset ± 40` (the N8 reversal works).
- TURN radius within 15 % of `max_speed / turn_rate`, measured on the turn-in (asserted to turn ≥ 90°, N8).
- **No hurtbox overlap**: min distance ≥ hull (28.6, from the scene) + player hurtbox (13.5) over 25 s of solo passes
  **and** over the breach case below (the case where it is plausible).
- **Breach (N9, B4)**: fighter spawned 380 px from the player heading at it → the first RUN_IN is FRONTAL-shaped,
  `pass_bearing` = `dir(X − P̂)` within 1e-3, `pass_lane ⟂ pass_dir`, σ = the drift side; closest approach
  `pass_offset ± 60`. Second case: a player closing at 250 px/s on an approaching fighter breaches the same way.
- **RUN_IN seek target always ≥ `lookahead − 1` ahead along `u`**, every RUN_IN tick.
- **Liveness (B3-ii)**: a player running at 420 px/s along `h`: APPROACH ends by its deadline into a FRONTAL RUN_IN;
  RUN_IN ends by `run_in_max`.
- **Passes done (B4)**: Assault with `engage_seconds` 60: DISENGAGE on the second pass's EXTEND end — and, staged with
  a burst running at that moment, only after the burst's last shot. Open Space: after the second pass, the fighter
  holds within `start_tolerance` of S for `regroup_seconds ± one tick` before RUN_IN.
- **Assault**: **the intent case — shipped config, centred player, spawn above the screen: the first RUN_IN is a
  FLANK-shaped lateral pass** (`|u.x| = 1`) within the budget; flank/solo RUN_IN is lateral (`|vel.x| > |vel.y|` every
  RUN_IN tick after its first 0.2 s); **player 100 px under the corridor top → lane behind** (`pass_lane.y > 0`,
  closest approach behind); **player 150 px from the left wall → bearing from the right** (`pass_bearing.x > 0`);
  inside `inner_rect().grow(soft_band)` from first entry until DISENGAGE.
- **Weapons, natural play (the B2 intent case)**: a solo Open Space fighter's first full cycle fires exactly one AIMED
  burst (Pulse) in RUN_IN and one FORWARD burst (Scatter) in TURN.
- **Weapons, staged**: TURN nose-on at 250 px → FORWARD, 5–7 Scatter shots, each along the nose (`angle_difference` <
  `forward_spread` + 1e-3, allowing the `(0, 10)` spawn offset); at 400 px → AIMED, 3–5 Pulse shots, toward the locked
  point; **`select_weapon_mode`: 324/325/384/385 boundaries; 330 after AIMED → AIMED, after FORWARD → FORWARD**;
  **FORWARD with the player 30° off the nose → no burst, the leg still open, and a later on-nose tick fires**; the mode
  stays latched while `d` crosses 325 mid-burst; `weapon_mode_changed` once per change, never for a repeat.
- **Cadence**: shot gaps 0.10 / 0.05 s ± one tick; one burst per leg; CHARGING starts `burst_telegraph ± one tick`
  before the first shot; **`min_burst_period` boundary: a TURN nose-on staged 0.5 s after a RUN_IN burst start gives no
  burst before 1.2 s, and one after**.
- **Deferral**: Assault, budget expiring mid-telegraph → the phase is unchanged until the last shot, DISENGAGE within
  0.8 s of expiry; expiry with no burst → DISENGAGE the same tick.
- Rewritten t8a cases: `aim_mode` on an AI fighter changes nothing (same seed → same motion and the same shots);
  APPROACH hands over to RUN_IN near S (no longer "holds at the standoff").
- Unchanged and must stay green: the t8a rail cases, `test_level1_fighter_spawns.gd`, `test_station_reinforcements.gd`,
  every invariant gate; `scripts/check-test-leaks.sh` clean.

## Risks
| # | Risk | Mitigation |
|---|---|---|
| R1 | Dubins maths bug | Unit tests on exact cases and a polyline/analytic cross-check of every candidate |
| R2 | The real mover diverges from the sim (accel limit, rotation cap, `face_toward`) | 700 ≥ 540 px/s² (pinned in t8a); `r_plan` = 1.1 r; off-path > 40 px re-plans; every test runs the real scene |
| R3 | No clear path in a tight corridor | Epic ring fallback; S clamp sized for the loop; the liveness cap; the budget ends Assault runs |
| R4 | Cycle time ≈ 10 s per pass (the turn-in snapshot costs ≈ 3 s over Revision 1's ≈ 6.6 s) | It is also a second burst per cycle; Assault's 6 s budget allows one pass either way. Named for t16's tuning and the playtest |
| R5 | The t16 shots/s gate | Unchanged upper bound (`max_burst / (burst time + min_burst_period)`); two bursts per ≈ 10 s is well under it |
| R6 | CPU | Sorted candidates, stop at the first clear one; plans are rare for a holding player |

## Out of scope
Squad roles, the LEAD window, flank loiter-and-answer, REARs (t9); idle (t12); level-1 migration (t16/t17); art (t14).

## 7. Deviations to log in DECISIONS (phase 3 section)
1. TURN = turn back in toward the player (the snapshot, opportunity (b)) + a break-away arc; REPOSITION = a Dubins
   lead-in (`DubinsPath`, new in `global/enemy_ai/`), all outside `reposition_min_radius`.
2. `forward_range` 300 → 325 (K5 lever) so the TURN snapshot can be FORWARD.
3. APPROACH clearance/breach radius derived from S; APPROACH/REPOSITION deadline = first plan's duration +
   `reposition_max`, then the FRONTAL breach pass.
4. P̂'s lead latched at RUN_IN entry; RUN_IN feeds forward the lane's sideways velocity; the handover heading is `g`.
5. Assault S clamp shrinks the rect by `2·r_plan + hull` along the run axis; EXTEND ends early at the corridor edge;
   the Assault turn-in may take the long way.
6. FORWARD bursts hold the nose (not the path) on the player; opportunity (b) stays TURN-only.
7. New config fields `run_in_max`, `regroup_seconds`.
8. For t16: at `engage_seconds` 6.0 an Assault fighter completes one pass, so the lever "`assault_passes` 2 → 1"
   changes nothing today.

## 8. Response to round 1

| # | Point | Where answered |
|---|---|---|
| B1 | Assault S clamp inside the breach radius; first pass never lateral | §3 APPROACH (clearance/breach from S); prototyped (table rows 4–8); intent test "first RUN_IN is a lateral FLANK at the shipped budget"; the worked-example figure corrected to 295 |
| B2 | (b) never fires; FORWARD unreachable | §3 TURN = turn-in snapshot; §4 `forward_range` 325 (K5 lever); prototype nose-on 304–308 every cycle; natural-play intent test |
| B3-i | Latching unspecified | §1 "When the pass is fixed" + a latching test |
| B3-ii | No upper time bound | §3 liveness caps + a 420 px/s player test |
| B4 | N9 / passes-done / regroup / `min_burst_period` untested | §Test plan: breach cases, passes-done (with deferral), regroup, the staged period boundary; "burst start" defined |
| NB1 | APPROACH clearance = breach, no margin | `BREACH_MARGIN` 24 |
| NB2 | √ of a negative | clamped to 0; `run_in_max` tested |
| NB3 | No spare turn authority | `r_plan` = 1.1 r |
| NB4 | End-heading test tolerance | analytic `end_heading()` |
| NB5 | CPU | sorted candidates, first clear wins |
| NB6 | Loiter cap | only the correction term is capped |
| NB7 | Tuning constants | `run_in_max`, `regroup_seconds` are config; the rest are named controller tolerances |
| NB8 | `aim_point` spawn offset | tests allow the `(0, 10)` offset |
