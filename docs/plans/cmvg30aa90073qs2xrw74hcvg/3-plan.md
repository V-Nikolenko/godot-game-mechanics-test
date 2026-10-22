# t4 — Enemies steer round hazards with their own temperament (the context-steering stage)

Epic `cmug23om70001m52wqfwclf3l`, phase 6. Builds epic plan §2.4 on top of t1 (registry) and t2 (drift, slow,
`own_velocity`, the `_avoid()` hook). Context: `1-context.md`.

## Problem

Today an AI enemy flies its brain's request straight into a gravity well, a slow field or (later) a wreck: it is
pulled in or grinds along the hull with `move_and_slide`. Players should see each ship type read the battlefield in
its own way: a drone skims a well's edge, a fighter or a sniper keeps clear, a heavy ship only flinches when it is
heading squarely in, and anything **committed** to an attack (Swarm BURST, Razor dash / feint lunge, Ram CHARGE, all
`mover.boost()`) flies straight through, so the player can bait it into a well. A ship that has claimed a wreck as
cover must still be able to park beside it. With no hazard in reach nothing changes, bit for bit.

## Design

The epic plan's design, unchanged in shape: a pure `Steering.context_avoid()` called from `EnemyMover.step()` at
t2's hook (after the slow, before the accel limit), skipped while boosting. Research §2.2 option D, Fray's context
steering (F1/F2). Rejected alternatives (repulsion nudges, priority arbitration, per-brain interest maps) were settled
by the epic research and are not reopened.

### `Steering.context_avoid(pos, desired, infos, avoidance, margin, lookahead, prev_dir) -> Vector2`

Constants on `Steering`: `CONTEXT_SLOTS := 16`, `CONTEXT_LOOKAHEAD := 0.6`, `CONTEXT_PREV_BLEND := 0.5`,
`CONTEXT_MIN_SPEED_RATIO := 0.35`. Slot `i` is `Vector2.from_angle(i · TAU / 16)` (slot 0 = +x).

1. **Early pass-through**: `infos` empty, `desired == Vector2.ZERO` or `avoidance <= 0` → return `desired` (the same
   value, no arithmetic, so −0.0 survives).
2. **Danger** per hazard, merged per slot by **max**: led centre `c = info.position + info.velocity · lookahead`,
   `d = |c − pos|`, `R = info.radius`, `M = margin + |desired| · lookahead`, `w = info.avoid_weight` (skip if `w <= 0`).
   - `skirt = clamp(1 − max(0, d − R) / M, 0, 1)` (skip when 0; `M <= 0` → skip outside, 1 inside);
   - `θ = asin(min(1, (R + margin) / d)) + slot_width` (one slot of widening);
   - slot danger `= w · skirt · clamp(1 − angle(u_i, c − pos) / θ, 0, 1)`.
   **Refinement 1 (inside):** the epic plan writes the inside case as `w · max(0, cos(angle))`. The formula above at
   `d ≤ R` is the outside formula's own limit (skirt 1, `θ = 90° + one slot`), so the danger map is continuous across
   the edge and every slot within 112.5° of the centre is dangerous. With plain `max(0, cos)` the two tangent slots
   carry danger ≈ 0 (float noise decides whether they are masked) and the parabolic refinement can then lean half a
   slot *inward*, so "inside → first step outward" would not hold. Outward slots (≥ 112.5° from the centre) still get
   0, which is what the plan's sentence requires.
   A hazard whose led centre is within 0.001 px of `pos` contributes nothing (no direction; every heading leaves it
   equally).
3. **Profile threshold** (R6.8): `danger_i = max(0, danger_i − (1 − avoidance))`.
4. **Clear way → return `desired` unchanged.** `lo = min(danger)`. If the two slots either side of `desired` (the
   bracket `floor(angle / slot_width)` and the next) both carry `lo`, return `desired` unchanged. This contains the
   plan's "every slot's danger is 0" case. **A `desired` on a slot** (`angle / slot_width` within 1e-4 of an
   integer — review round 2 m1: `Vector2.angle()` is a 32-bit float, so an axis-aligned request other than +x lands a
   hair off its slot, e.g. +y at 4.00000011) is bracketed by that slot alone, `roundi(angle / slot_width) % 16`
   (round 1: checking the next slot too sent a run along slot 0 with danger on slot 1 into the selection, where the
   refinement bent it by ~1e-8 rad of float noise; the containment argument below holds for the single slot, since
   `desired` is within 4e-5 rad (1e-4 of a slot) of it and the one-slot widening dwarfs that).
   **Refinement 4:** step 5 would pick one of those two slots and the refinement would land within half a slot of
   `desired` anyway, so this returns that limit exactly. Without it, a hazard *behind* the ship (danger on other slots
   only) bends the heading by interpolation noise, and a soft profile's ignored pass is not bit-exact. It cannot let
   a ship into a hazard: a cone of half-width `θ ≥ asin(·) + one slot` that contains `desired` always puts danger on
   at least one bracketing slot, because the slot between `desired` and the cone's centre is nearer the centre than
   `desired` is.
5. **Choose**: slots with `danger_i > lo` are masked. Rank the unmasked slots by the
   **blended interest** `s_i = u_i · aim`, where `aim = (1 − B) · want + B · prev_dir` (`want = desired / |desired|`,
   `B = CONTEXT_PREV_BLEND`; `aim = want` when `prev_dir` is zero, **or when the blend collapses** — `|aim|² ≤ 1e-6`,
   a brain that reversed its request — review M3). Highest `s_i` wins.
   **Refinement 2 (hysteresis on the selection):** the plan's "blend with `prev_dir`" is applied to the interest
   map (Fray: "blending in the previous frame's map"), not to the output direction. Prototype (`/tmp`, recorded
   here): blending the *output* with a target straight behind a well alternated between the two symmetric cone edges
   every step — a zig-zag at 35 % speed that had not passed the well after 4 s. Blending the selection keeps the side
   chosen last step; the same scenario passes the well in 3.3 s, minimum speed 40 %.
   **Refinement 3 (ranking by the raw cosine):** `s_i` is the signed dot product, not `max(0, ·)`; with the clamp every
   slot more than 90° from `desired` ties at 0 when the target is straight behind a hazard, and the choice becomes
   arbitrary. The signed value still prefers the slot nearest the desired heading.
6. **Refine**: parabolic interpolation on `s_{i−1}, s_i, s_{i+1}` (neighbours' scores whether masked or not):
   `offset = 0.5 (s_{i−1} − s_{i+1}) / (s_{i−1} − 2 s_i + s_{i+1})`, clamped to ±0.5 slot, applied only when the
   denominator is negative (a maximum; a convex triple has no peak to refine to). The one-slot widening of `θ` is what
   makes a half-slot lean toward a masked neighbour safe: it never crosses the tangent line.
7. **Speed** `= |desired| · max(heading · want, CONTEXT_MIN_SPEED_RATIO)` — the raw (unblended) interest of the refined
   heading; a target directly behind a hazard makes the ship circle the edge at ≥ 35 %, never stall.
   Return `heading · speed`.

### `EnemyMover`

- New private `_avoid_prev: Vector2` (the stage's `prev_dir`).
- `_avoid(desired)` (the t2 hook, called only when `hazards_live` and not boosting):
  - `hazard_avoidance <= 0` or `desired == ZERO` → clear `_avoid_prev`, return `desired`;
  - `infos = Hazards.around(pos, hazard_margin + |desired| · Steering.CONTEXT_LOOKAHEAD)`, dropping every info with
    `line_of_sight_blocker and is_claimed_by(actor)` (the ship's own cover; wells are never dropped);
  - none left → clear `_avoid_prev`, return `desired`;
  - else `out = Steering.context_avoid(pos, desired, infos, hazard_avoidance, hazard_margin, CONTEXT_LOOKAHEAD,
    _avoid_prev)`; `_avoid_prev = out.normalized()`; return `out`.
- `step()`: while boosting, `_avoid_prev` is cleared (a committed run ends with no stale bias), and on the skip path
  too (`hazards_live` false: the last hazard left the registry — review M4; a field write, so the bit-identical rows
  are unaffected). `halt()` clears it.
- Header comment's step 3 rewritten (no longer "a no-op hook").
- No brain is touched. No new API (no "ignore hazards" request).

### Consequences worth stating

- Razor IDLE_BOOST (0.4 s along the idle heading) is a `boost()` too, so it also ignores avoidance — the plan's rule
  ("committed attacks are `mover.boost()`"; never a separate API). It is short (~60 px); noted as a follow-up for t17,
  which places the hub's well.
- `Hazards.around()` is queried at the *current* centre; a drifting hazard is led inside the function only once it is
  within reach. Kept as is (no reach padding); recorded in DECISIONS.md for t15, whose 200 px/s debris has a 120 px
  lead at 0.6 s — t15 can pad the mover's reach by a lead allowance (safe: a zero skirt contributes nothing).
- **DECISIONS.md, Phase 6 section** (review M5): the four refinements (and the on-slot bracket), the Razor IDLE_BOOST
  bypass (t17) and the reach limitation above (t15).

## Build sequence

1. Write `tests/unit/test_context_avoidance.gd` (pure function) — run, watch it fail (no function).
2. Implement `Steering.context_avoid()` + constants; unit file green.
3. Add mover rows to `tests/unit/test_enemy_mover.gd` and dual-mode rows to `tests/integration/test_enemy_dual_mode.gd`
   — watch the stage-dependent ones fail on the no-op hook. Test helpers (review M1): new
   `tests/helpers/fixture_wreck.gd` (a duck-typed `Node2D` registering a `line_of_sight_blocker`, claimable
   `HazardInfo`, `avoid_weight` 0.6; its `.uid` is minted by `--import`, never typed), shared by both files; and
   `tests/helpers/fixture_brain.gd` gains `arrive_point` / `arrive_speed` (`mover.arrive()` instead of the fixed
   request when set).
4. Implement `EnemyMover._avoid()` / `_avoid_prev`; header comment; rows green.
5. Real-brain rows (Swarm skims, Fighter goes round, Swarm BURST captured) — tune the scenario geometry by measurement,
   never the profile values (they are t2's shipped table).
6. Full gate (`bash /agent/verify.sh`), `scripts/check-test-leaks.sh`, `scripts/gate-time.sh` after.
7. Docs: `docs/architecture/modules/global.md` (Hazards section: the avoidance stage), `updating-project-docs` skill.

## Test plan

**`tests/unit/test_context_avoidance.gd`** (pure function; integration by hand, `dt = 1/60`):
- `test_no_info_returns_desired_unchanged` — `var_to_bytes` identical, including `-Vector2(200, 0)` (−0.0) and zero.
- `test_zero_danger_returns_desired_unchanged` — a hazard out of the skirt, one behind the ship, `avoid_weight` 0,
  `avoidance` 0: each returns `desired` bit-identical; and (review round 2 m1) an exact +y request with danger on
  the 112.5° slot (slots 5–8) and none on 90° returns bit-identical (fails without the 1e-4 on-slot tolerance).
- `test_target_straight_behind_a_well_is_reached_round_the_edge` — 4 s: never inside `radius`, speed ≥ 35 % of
  `desired` every step, ends past the far side.
- `test_inside_the_first_step_points_outward` — a sweep of positions inside and 16 desired headings (including straight
  through the centre): `out · (pos − centre) > 0` every time.
- `test_a_narrow_margin_skims_closer_than_a_wide_one` — margin 12 vs 90, min edge distance compared (both > 0).
- `test_half_avoidance_ignores_a_tangential_pass_that_full_avoidance_bends_round` — 0.5 → unchanged every step; 1.0
  → deflected, passes wider.
- `test_soft_avoidance_still_turns_off_a_run_aimed_squarely_at_the_centre` (review C5, R6.8's other half) — 0.5,
  from inside the skirt, straight at the centre: the first step already turns off the centre line; the run stays
  more than half a radius off the centre; control: avoidance 0 flies through the centre.
- `test_a_0_8_profile_sits_between_0_5_and_1_0` (review C5, a value other than 0.5) — 50 px off the edge 0.5 ignores
  what 0.8 bends round; 70 px off it 0.8 ignores what 1.0 bends round. Subtracting `avoidance` instead of
  `1 − avoidance`, or turning avoidance off below 1.0, fails one half.
- `test_heading_between_two_slots_is_not_quantised` — desired at 10° with danger on the far side: heading ≈ 10°,
  strictly between slots 0 and 1, not a multiple of 22.5°.
- `test_a_drifting_hazard_is_led` — off the path and static → unchanged; moving into the path → deflected; moving away
  → unchanged.
- `test_danger_merges_by_max_not_sum` — a second hazard straight behind the first changes nothing.
- `test_surrounded_it_takes_the_least_dangerous_heading` (boundary: every slot dangerous, `lo > 0`) — the output points
  into the gap with the least danger and keeps ≥ 35 % speed.
- `test_prev_dir_keeps_the_side_it_chose` — straight-behind case: `prev_dir` up → goes up; down → goes down; a
  reversed `prev_dir` is no bias (M3); and over the whole run the side changes at most once, and only over the well's
  top (`|y| ≥ radius`) — review round 2 R3: the one change is the turn down toward the target at (−10, −200), so the
  old `x ≥ 0` cutoff counted it. An output-blend zig-zag still fails this.

**`tests/unit/test_enemy_mover.gd`** (mover):
- `test_avoiding_mover_is_bit_identical_with_no_hazard_in_reach` — t2's recorder with an avoiding accel mover
  (avoidance 1, margin 60): registry empty vs a well 2000 px away.
- `test_an_unconfigured_mover_never_avoids` — avoidance 0 next to a hazard: the request passes (velocity = request).
- `test_boosting_flies_straight_through_and_the_same_request_unboosted_bends_round` — pull-free hazard; the boost's
  y stays exactly 0 and it enters the radius; the plain request never does.
- `test_a_los_blocker_claimed_by_the_actor_is_dropped` — fixture wreck (duck-typed, `line_of_sight_blocker` true):
  claimed by the actor → velocity equals the request; unclaimed or claimed by another node → deflected; a well
  claimed by the actor → still deflected.
- `test_the_corridor_filters_after_the_stage` — one step: constrained velocity == a fresh corridor's
  `filter(pos, unconstrained velocity)`.
- `test_boost_halt_and_an_empty_registry_clear_the_avoidance_memory` — a boost step clears `_avoid_prev`; the plain
  steps are taken only once `is_boosting()` is false (review C1: a 0.1 s boost spans several 1/64 s steps);
  `halt()` clears it; the skip path clears it once the last hazard has left the registry (review M4).

**`tests/integration/test_enemy_dual_mode.gd`** (dual-mode where marked):
- `test_a_claimed_wreck_is_ignored_and_the_cover_point_beside_it_is_reachable(mode)` — fixture enemy with the
  Sniper profile (avoidance 1.0, margin 90); `arrive()` to `radius + 50` from the wreck, straight in from 480 px
  out, settles within 10 px when the actor holds the claim. Claimed by another node it is avoided: its closest
  approach to the wreck's centre stays above `radius + 50 + 10` and it never settles on the point (review C2: a build
  with no stage arrives on the point, closest ≈ `radius + 50`, and fails this).
- `test_the_corridor_still_bounds_an_avoiding_enemy(mode)` — the Sniper profile (avoidance 1.0; review C3: a soft
  profile is only kept from heading inward, not forced out) at the corridor's `edge_pressure` (200 px/s). Review
  round 2 R1, the reviewer's measured scenario: a pull-free radius-300 hazard centred 100 px inside the right edge;
  the ship starts at `(rect.end.x − 20, centre.y − 500)` asking for `(0, 200)` (down the edge, past the hazard) for
  8 s, so the way round is out past the edge. Open Space goes further out than the corridor's `soft_band` (≈ 332 px);
  Assault is pushed past the visible edge but held inside the band (≈ 13.6 px); with no stage both stay at −20 px.
  (The round-1 version asked to go back in *through* the hazard; "inside → step outward" is radial, so it slid out
  through the hazard's bottom and never crossed the edge.)
- `test_a_swarm_drone_flying_past_a_well_skims_its_edge(mode)` — real Swarm APPROACH; never inside `radius`; closest
  approach within the skim band (closer than `radius + 60`, the default profile's margin). Control (review C4): the
  same run with `hazard_avoidance = 0` enters the radius.
- `test_a_fighter_approaching_through_a_wells_path_goes_round(mode)` — real Fighter APPROACH; never inside `radius`;
  reaches RUN_IN. Control (review C4): with `hazard_avoidance = 0` the same approach enters the radius. Geometry
  (step 5, measured; review round 3 F1): from (640, −360) the APPROACH runs down, then west along y ≈ −168, then
  round to the pass start; the two modes share the first ~110 ticks, then each curves to its own pass start (no well:
  Open Space RUN_IN at tick 232, S = (160, 200); Assault at tick 205, S = (295, 200)). `engage_seconds = 1000` on a
  private config copy keeps the budget out of the row. A well at (320, −168), radius 100, core 30, pull 200, sits on
  the westward leg's west half: control closest ≈ −96 / −98 px (asserted < −50); avoiding ≈ +56 px, past the well to
  the west (min x < `well.x − radius`, asserted) and RUN_IN via its pass start in both modes (ticks ≈ 316 / 337). A well
  on the leg's east half (x 340–460) lets the Open Space fighter breach-pass (`_begin_breach_pass()`, ~450 px from the
  player) before it reaches the well, which the min-x assertion rejects. (The round-1 start (100, 60) gave a path that
  missed the well and, in Assault, ran out of budget before RUN_IN.)
- `test_a_swarm_burst_across_a_well_is_captured(mode)` — real Swarm BURST from 310 px left of a §2.5 well (pull 520,
  core 90, `damage_radius` 150) at a player 250 px right of it. The boost is never steered and **reaches the core**
  (closest ≈ 67.5 px < 90: carried in, not round); the drone then **stays inside `damage_radius` from the burst's end
  until its next committed run** (its next `boost()`, ≈ 1.2 s later, asserted ≥ 1 s: two 0.5 s stress pulses;
  furthest ≈ 136 px); control: the same burst with no well leaves that radius before its next burst (≈ 164 px).
  **Deviation (review round 2 R4, measured):** "still inside `damage_radius` 2 s later" holds for no geometry, with
  or without the stage, because the drone's own next BURST (480 px/s) always outruns the pull — like plan §2.2's
  "Razor captured at approach speed, escapes by dashing". The non-boost capture physics stays pinned by t2's
  `test_a_swarm_config_cannot_leave_the_core_but_a_fighter_config_can`. Recorded in DECISIONS.md. Mutant
  "avoid while boosting" fails all three of straight / crosses / held.

**Gates unchanged**: all of epic plan §4.1. No hazard is registered in any of them, so the stage never runs there.
One existing t2 row does reach it (review M2): `test_a_ram_corvettes_line_up_inside_a_well...` runs a real Ram
(avoidance 0.5) inside a well, but LINE_UP requests `Vector2.ZERO`, so `_avoid()` returns early and the row is
unchanged.

## Risks

- **Hot path cost**: `Hazards.around()` allocates per step per enemy when any hazard exists. Only when hazards are
  registered (none in level 1 or the hub until t17). Gate time measured before/after.
- **Behaviour regressions** — a later task adds hazards to the hub (t17); the real-brain rows here are the first
  evidence that brains still work beside one.
- **Edge oscillation** (failure mode 2) — mitigated by 16 slots, the one-slot widening, parabolic refinement and the
  selection hysteresis; pinned by `test_prev_dir_keeps_the_side_it_chose`.

## Out of scope

Wreck scenes (t9–t11), cover picking (t12, t13), the Ram's well ticket (t15), hub placement (t17), any brain change,
any profile value change, any "ignore hazards" API.
