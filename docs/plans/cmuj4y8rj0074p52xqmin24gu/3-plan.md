# Swarm Drone squad behaviour (t8c) — plan

Task `cmuj4y8rj0074p52xqmin24gu`, epic `cmufs7ek60001nm2x6d0bt2et`. The epic plan (`3-plan.md` §2.4, §2.7, §2.7.2 and
§4 row t8c) is approved and is **not** re-derived here. This plan pins what §2.7.2 leaves open, and fixes the two
places where its numbers or wording cannot work as written (D1, D2 below).

## Problem

Today every Swarm Drone attacks alone, even when a wave spawns four of them as one squad: they all spiral in and ram
in turn, like a queue. After this task a squad reads as a group. The drone closest to you (the LEAD) spirals in and
rams. The next two hold slots off your left and right, and the moment the lead commits (red light) they wind up and
ram from their own sides, a pincer. Everyone else circles you on a wide ring and never rams. When the lead dies, even
mid-ram, the closest survivor takes over and the ring sends someone to fill the empty flank. A drone knocked out of
place drifts back into its slot. In Assault a rear-ring drone can be given a shorter stay than an attacker (a lever
t15 may pull; the default keeps today's 5.5 s).

## Design

### Phases

`enum Phase { APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT, REJOIN, DISENGAGE, FORM }`. FORM is **appended** so the
t8b integer values do not move. `_role()` is `LEAD` when `actor.squad == null` (a squad of one), and
`squad.role_of(actor)` otherwise; `NONE` (a member that has left) is also treated as `LEAD`.

| Phase | Change in t8c |
|---|---|
| APPROACH | Exit radius is `rear_orbit_radius + 100` (360 at default; replaces `APPROACH_EXIT_RADIUS`). Exit goes to **CLOSE_IN if LEAD, else FORM**. Nudges apply |
| CLOSE_IN | Ring target is `flank_distance` (replaces `CLOSE_IN_RADIUS`, 200 at default). If the role is no longer LEAD → FORM. Nudges apply |
| FORM (new) | By role, each tick, below. Beyond `rear_orbit_radius + 200` (460 at default; replaces `APPROACH_REENTER_RADIUS`) → APPROACH. Role LEAD → CLOSE_IN. Nudges apply |
| WINDUP | On entry records `_pass_role = _role()`. Otherwise unchanged (claim, hold, aim with the side offset) |
| BURST | On entry, if `_pass_role == LEAD` and there is a squad: `squad.attack_window_open = true` |
| OVERSHOOT | On exit: if `_role() != _pass_role` the role changed mid-pass, so skip any remaining pass and go to REJOIN ("takes effect after the pass"). No nudges here: the t8b per-tick curve bound assumes one request |
| REJOIN | If `_pass_role == LEAD` and it is still LEAD: `release_lead()` with ≥ 2 members, else close the window itself (`attack_window_open = false`, so a sole member never leaves it stuck open for a later joiner). Then route: far → APPROACH; LEAD → CLOSE_IN; else FORM |
| DISENGAGE | Unchanged. Expiry also fires for a REAR (below) |

### FORM by role

- **REAR** — `mover.orbit(centre, rear_orbit_radius, angle, max_speed)`.
  - `angle = squad.rear_ring_angle + rear_index × TAU / rear_count + phase_offset`.
  - `rear_ring_angle` is a new **shared field on the board** (D3). **Any** REAR in FORM that reads it as `NAN`
    initialises it to its own bearing from the (clamped) centre minus `rear_index × TAU / rear_count` minus its
    `phase_offset`, so that REAR starts where it already is (round 1 B3, N5). Only the member with `rear_index == 0`
    **advances** it, by `rear_orbit_speed × delta` per FORM tick. While rear 0 is not in FORM (still in APPROACH, say)
    the ring stands still; the other REARs hold their slots on it.
  - `rear_count` comes from a new `SquadController.rear_count()`.
  - `centre` is the target position, clamped into `mover.constraint.inner_rect()` shrunk by `rear_orbit_radius` when
    that rect is non-empty (Assault; §2.7.1's "brains clamp orbit centres"). In Open Space it is the target position.
- **FLANK_LEFT / FLANK_RIGHT** — `mover.formation_slot(target.position, heading, slot, max_speed)` with
  `slot = Vector2.RIGHT.rotated(±deg_to_rad(flank_angle_deg)) × flank_distance`, `+` for RIGHT. This uses the same
  cross-product convention as `SquadController._side_for` and `_side_offset`: in y-down, `heading.rotated(+90°)` is the
  right-hand side. `heading` is `_heading_of(target)`.
  - **Attack trigger:** `squad.attack_window_open and not _answered_window and can_start_attack()` → set
    `_answered_window = true` and enter WINDUP.
  - Every tick, in any phase, `if not squad.attack_window_open: _answered_window = false`. So a flank answers **each
    window once**: the lead's second-pass burst re-sets an already-open window and must not trigger a second flank
    attack (review N13's edge-versus-level question).
- **LEAD** — never in FORM (→ CLOSE_IN).
- **REAR never attacks.** It has no path into WINDUP.

The window stays open from the LEAD's first BURST until the board closes it or the sole-member REJOIN above. The
board closes it **whenever the LEAD member changes** (round 1 B4): `_reassign()` compares the lead before and after
and clears `attack_window_open` on any change, whatever caused it (a lead leave, `release_lead`, a flank that
detonated and left, a join, a prune). This replaces t4's two special-case clears. The epic says "cleared when its burst ends". Keeping it open
through the lead's whole cycle lets a flank that is still recovering its slot answer late, and `_answered_window`
already prevents repeats. See D4.

### Role changes

The board recomputes roles on every join, leave and `release_lead` (t4, full recompute). The brain reads `_role()`
every tick and never caches it, except `_pass_role`, which is taken on WINDUP entry.

- A member promoted while in FORM goes to CLOSE_IN on the same tick.
- A member demoted from LEAD while in CLOSE_IN goes to FORM.
- A member whose role changes during WINDUP, BURST or OVERSHOOT finishes that pass, then goes to REJOIN. There it
  does **not** `release_lead` (it did not attack as lead), and it routes by its new role. So "the promoted member
  finishes nothing it had not started".
- When the LEAD is freed mid-burst: t4's `leave()` closes the window and recomputes. With 3 survivors the roles are
  LEAD, FLANK_LEFT and FLANK_RIGHT, so the former REAR necessarily holds a flank role (the vacated flank is filled).

### Nudges (flocking + evade)

In APPROACH, CLOSE_IN and FORM only (never in WINDUP, BURST, OVERSHOOT or DISENGAGE):

```
mates      = squad.members() minus self (positions, velocities); empty without a squad
flock      = separation(pos, mate_pos, separation_radius) × SEPARATION_GAIN (6.0)
           + (alignment(vel, mate_vel) − vel) × ALIGNMENT_GAIN (0.1)   # Reynolds: steer toward the mean
           + cohesion(pos, mate_pos) × COHESION_GAIN (0.05)
evade      = dist_to_target < evade_radius ? Steering.evade(pos, target.pos, target.vel, max_speed, 0.25) : 0
mover.add_nudge((flock + evade).limit_length(flock_nudge_cap × max_speed))
```

A helper `_nudge(target) -> Vector2` returns the capped vector so tests can check it directly. When
`flock_nudge_cap == 0` or the length is 0, `add_nudge` is not called. The gains are **[judgement]**. They are small
on purpose: the REAR ring's centroid is roughly the player, so cohesion pulls inward by at most 0.05 × 260 = 13 px/s,
which the orbit correction (4 px/s per px of error) absorbs in about 3 px.

### Per-role budget

In Assault, a member whose role is REAR and whose phase is APPROACH or FORM expires when `budget.active` and
`budget.seconds − budget.remaining() ≥ rear_engage_seconds` (round 1 N4: no new budget API). Otherwise
`budget.update()` expires at `engage_seconds` as today.

- The REAR limit never cuts a pass: an attacker is never REAR in FORM.
- A lead that finishes its cycle, drops to REAR and is already past `rear_engage_seconds` leaves at once. That is the
  point of the lever.
- A config test pins `rear_engage_seconds ≤ engage_seconds`, so the §2.6 deadline, which uses `engage_seconds`, stays
  an upper bound.

### Config (`SwarmDroneConfig`, new `@export_group("Squad")`, flat)

| Field | Value | Note |
|---|---|---|
| `rear_orbit_radius` | 260 | epic table |
| `rear_orbit_speed` | **0.55 rad/s** | **D1**: the epic's 1.4 rad/s × 260 px = 364 px/s ring speed exceeds `max_speed` 220, so a REAR could never hold the ring (it would fall behind and cut inside, failing the ± 10 % case). 0.55 × 260 = 143 px/s. A config test pins `rear_orbit_speed × rear_orbit_radius ≤ 0.7 × max_speed` |
| `flank_distance` | 200 | epic table; also CLOSE_IN's ring |
| `flank_angle_deg` | 70 | epic table |
| `separation_radius` | 30 | epic table |
| `flock_nudge_cap` | 0.35 | epic table |
| `evade_radius` | 90 | epic table |
| `rear_engage_seconds` | 5.5 | = `engage_seconds`; t15 lever |

`SwarmDrone._apply_config` copies all eight onto the brain.

### Phase offset (R2.3) — D2

`phase_offset` is drawn once in `_ready()`, **after** the existing `cork_phase` and `_spin` draws (so t8b seeds
reproduce), as `rng.randf_range(-MAX_PHASE_OFFSET, MAX_PHASE_OFFSET)` with `MAX_PHASE_OFFSET = 0.35` rad (20°).

The epic's literal "`phase_offset` + `rear_index × TAU / n`" with an offset anywhere in `[0, TAU)` would undo the
index spacing: two REARs could get offsets π apart and share a slot. Bounding the offset to ±20° keeps members at
least 50° apart at the largest REAR count (4 in a squad of 7, 90° spacing). t8d's idle ring uses the same field.

### Board additions (`SquadController`)

- `func rear_count() -> int`: the valid REAR members.
- `var rear_ring_angle: float = NAN`: shared state, initialised by any REAR that finds it `NAN`, advanced by rear 0
  only; not motion, so the single-writer gate is unaffected.
- `_reassign()` clears `attack_window_open` whenever the LEAD member changes (B4).
- Unit cases are added to `test_squad_controller.gd` for `rear_count` and for the window clearing.

### Deviations to log in DECISIONS

- **D1:** `rear_orbit_speed` 0.55 (not 1.4).
- **D2:** `phase_offset` is bounded to ±0.35 rad.
- **D3:** the shared ring angle lives on the board (`rear_ring_angle`), written only by rear 0.
- **D4:** the attack window stays open for the lead's whole cycle, and a flank answers each window once.
- `rear_count()` is new; the board closes the window on any change of lead.
- Nudges are off during OVERSHOOT.

## Build sequence

1. Board: `rear_count()`, `rear_ring_angle`, the window clearing on a lead change, with unit cases.
2. Config rows + `.tres` + `_apply_config`; config pins (ring speed, `rear_engage_seconds ≤ engage_seconds`,
   config-flows extended).
3. Tests for t8c written first (below). They fail.
4. Brain: FORM, role routing, `_pass_role`, window open/answer, REJOIN rules, nudges, per-role budget, repointed
   radii. The transition loop bound goes from 3 to 4 (OVERSHOOT → REJOIN → FORM → WINDUP; round 1 N3). The nudge reads
   a mate's velocity only from a `CharacterBody2D` (a bare `Node2D` mate counts as still; N2). Existing t8b cases updated only where they named the removed constants (they now read the brain fields).
5. Gates: `verify.sh`, `check-test-leaks.sh`. ENEMY.md, DECISIONS (t8c section), global.md/assault.md if they list
   the board API.

## Test plan (all in `tests/integration/test_swarm_drone.gd` unless noted)

The dual cases use `use_parameters(["open_space", "assault"])` with the harness built in the body. The squad cases are
hand-ticked: every drone is ticked each step, in join order. The player is at MID.

**Budget rule (round 1 B1).** In the Assault harness every drone would leave at 5.5 s, and none can wind up after
4.21 s. So every squad case that runs longer than about 4 s, or holds the lead with `windup_seconds = 100`, sets
`engage_seconds = 1000` and `rear_engage_seconds = 1000` on each drone's private config copy. The two
`rear_engage_seconds` cases are the only exceptions.

**Frozen cycle.** "Frozen" below means `windup_seconds = 100` plus the budget rule. The lead then holds in WINDUP in
both modes, no window ever opens, and the roles never rotate.

| Case | Asserts |
|---|---|
| `test_rear_holds_the_orbit_radius` (dual) | Frozen squad of 5 spawned 300 px above the player (round 1 B2). After 4 s of settling, over the next 3 s every REAR stays within `rear_orbit_radius` ± 10 %. Sanity: exactly 2 REARs sampled, both in FORM throughout |
| `test_a_rear_finds_the_ring_while_rear_0_is_still_approaching` (open_space) | Squad of 4; rear 0 is placed 2000 px away (still in APPROACH), rear 1 near the player. Rear 1's velocity and position stay finite every tick, and within 4 s it is within ± 10 % of the ring (round 1 B3) |
| `test_two_attackers_never_share_a_side` (dual) | Squad of 4, 10 s. Each tick, the `_claimed_side` of every member in WINDUP/BURST is pairwise distinct. **Sanity: at some tick ≥ 2 attackers hold claims at once** (else the case proves nothing) |
| `test_flanks_wind_up_only_after_the_leads_burst` (dual) | Squad of 4, budget rule. Both flanks enter WINDUP, each on or after the tick the lead entered its first BURST. No flank WINDUP before it. Over 10 s, **no member ever enters WINDUP while its role is REAR** (N1) |
| `test_no_contact_damage_while_in_form` (dual, real physics) | Frozen squad of 4 around a real player hurtbox (`contact_fixture.gd`). The FLANK and the REAR are teleported onto the player every frame for 10 frames. They stay in FORM and unarmed, and the player's health is unchanged |
| `test_the_lead_freed_mid_burst_hands_over_and_the_flank_is_refilled` (dual) | Squad of 4, budget rule, run until the lead is in BURST, then `free()` it. Immediately: `attack_window_open == false`; roles among 3 survivors are exactly {LEAD, FLANK_LEFT, FLANK_RIGHT}; the former REAR holds a flank role. The promoted member, if mid-pass, reaches REJOIN without a new WINDUP in between, then CLOSE_IN. **The new lead later bursts, the window opens again, and a flank enters WINDUP after it** (N13) |
| `test_formation_recovers_after_a_150_px_displacement` (dual) | Frozen squad of 5 (the lead holds; FORM members stay in FORM). Settle 4 s, then displace every FORM member 150 px (outward for REAR, sideways for FLANK). Within 3 s each is back in tolerance: REAR ± 10 % of the ring; FLANK ≤ 30 px from its slot. **Boundary:** immediately after displacement none is in tolerance |
| `test_phase_offsets_come_from_the_rng` (dual) | `flock_nudge_cap = 0`. Seeds 11/22/33 → `phase_offset` and `cork_phase` pairwise different; `|phase_offset| ≤ 0.35`. **Control: two drones with seed 11 → equal** |
| `test_a_rail_suspended_member_leaves_and_the_squad_reassigns` (dual) | Squad of 3, rail added to the lead. It is no longer a member; the 2 survivors are LEAD + FLANK |
| `test_a_rear_member_honours_rear_engage_seconds` (assault) | Squad of 4 with `rear_engage_seconds = 2.0`. The REAR enters DISENGAGE at 2.0 s ± 1 tick; no other member has disengaged at 2.2 s |
| `test_rear_engage_seconds_does_nothing_in_open_space` | The same squad in Open Space: nobody disengages in 4 s |
| `test_the_rear_ring_centre_stays_inside_the_corridor` (assault) | Frozen squad of 5. The player is 100 px inside the top edge of `inner_rect()`. After 4 s of settling, every REAR is within ± 10 % of `rear_orbit_radius` from the clamped centre, and the centre is inside `inner_rect()` shrunk by the radius. **Boundary: measured from the player itself, the maximum error over the samples is above 10 %** (N6) |
| `test_a_lead_change_closes_the_window_and_the_new_lead_is_answered` (open_space) | Squad of 4, budget rule. While the lead is in OVERSHOOT, the flank nearer the player is freed, with positions arranged so the recompute demotes the lead. The window reads false at once; the new lead's next BURST opens it, and a flank enters WINDUP after that (round 1 B4) |
| `test_the_nudge_is_capped_and_off_outside_formation_phases` (open_space) | Two coincident members plus the player 20 px away: `_nudge()` length ≤ `flock_nudge_cap × max_speed` + ε, and it points away from the player. Cap 0 → zero. In WINDUP a tick leaves the mover's nudge unset (probe `mover._nudge` between the brain tick and the step) |
| Config pins | `rear_orbit_speed × rear_orbit_radius ≤ 0.7 × max_speed`; `rear_engage_seconds ≤ engage_seconds`; config-flows extended to the new fields |
| `tests/unit/test_squad_controller.gd` | `rear_count()` for 1/3/5 members, after a free, and 0 on an empty board |
| `tests/unit/test_squad_controller.gd` (B4) | The window is cleared when a non-lead `leave()` or a `join()` moves LEAD to another member; it is **kept** when a non-lead leaves and the lead stays the same |

Existing gates: single-writer (the brain gains only requests and board/mover field writes), signal arity (no new
signals), config isolation (flat), `check-test-leaks.sh`.

## Risks

- **Interactions in multi-drone runs are chaotic.** A lead bursting through the ring can knock REARs out of
  tolerance. Mitigation: the radius case samples only REARs in FORM and uses seeded runs; if it is still unstable, the
  lead's burst path is not a REAR's fault, so exclude ticks within 60 px of an attacker and say so in the test.
- **Corridor filter vs slots in Assault:** the flank slots at 200 px lie well inside the 1480 px square around MID.
- **Tree-order tick lag:** rear 0 advances the shared angle before or after the others read it, a one-tick lag of
  ≤ 0.01 rad. Harmless.

## Out of scope

Hub idle, `AnchorIdle`, `set_engaged` (t8d). Level spawns (t14/t15). The Razor. Art.

## Response to review round 1

| Finding | Change |
|---|---|
| B1 Assault budget | Budget rule in the test plan: `engage_seconds`/`rear_engage_seconds` 1000 on the private config for long or frozen cases |
| B2 REAR radius sampled through rotation | The radius and corridor cases run a frozen cycle and settle for 4 s |
| B3 `rear_ring_angle` NAN | Any REAR that finds `NAN` initialises it; only rear 0 advances it; new case with rear 0 still approaching |
| B4 window stays open on an indirect lead change | `_reassign()` clears the window whenever the lead member changes; unit and integration cases |
| N1 | "No WINDUP entry while the role is REAR" |
| N2 | Mate velocity read only from `CharacterBody2D` |
| N3 | Transition loop bound 4 |
| N4 | No `EngagementBudget.elapsed()`; `seconds − remaining()` |
| N5 | Ring angle initialised from the clamped centre |
| N6 | Boundary phrased as the maximum error over the samples |
| N7 | No change |

## Amendments from review round 2 (APPROVED with these)

- **A1:** BURST opens the window only when `_pass_role == LEAD and _role() == LEAD` (a lead demoted during its WINDUP
  does not open a window for the new lead). A test covers it.
- **A2:** the rear-0-still-approaching case uses a squad of **5** (two REARs). The far drone joins first so it is
  rear 0, and positions are set before `join()`, with sanity asserts.
- `_reassign()` reads the "lead before" ahead of its empty-board early return; the class comment is rewritten.
- ENEMY.md mentions that `rear_ring_angle` is never reset (a late REAR may cross the ring to its slot). DECISIONS
  records that the window closes after kills that move the lead (expected, from the distance-based recompute).
