# t14 — The Fighter waits behind a wreck before its pass

Epic plan `docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md` §2.12 (approved). This task plan adds the details §2.12
leaves open and settles the epic review's items for t14: **N2** (the Assault gate can never open), **N3** (release
the claim on every exit) and **N8** (a LEAD in cover dissolves the pincer).

**Revision 1** (after `4-review.md` round 1, CHANGES_REQUESTED):
- **M1:** an arrival latch at C, the Sniper's, so the fighter holds at rest nose-on and leaves with that heading.
- **M2:** the Assault reserve exit is trip-aware (`+ |X − S| / max_speed`, with the pass derived in COVER as APPROACH
  would). Two new Assault rows (a squad LEAD; a solo that needs a lead-in) and a pre-agreed fallback.
- **M3:** a `cover_max` boundary row.
- **M4:** the level-1 reach is stated honestly, and the wreck-guard replay counts COVER entries.
- **m1:** the guard is run 3× before and after.
- **m2:** `_enter_calm()` clears `_cover_used`, with a row for both clears.
- **m3:** a "no longer LEAD" exit.
- **m4:** no player → APPROACH.
- **m5:** row 11's Assault case sets the reserve to 0.
- **m6:** row 13's Assault wreck drifts.
- **n2:** explosive wrecks are accepted as bait (`ENEMY.md`).
- **n3:** row 3's control runs with the wreck gone.
- **n1 is declined:** a shared `_inside_other_hazard` is five lines, and sharing it would touch the Sniper, which this
  task otherwise leaves alone. It is listed as a follow-up.

**Revision 2** (during implementation; reality contradicted the plan, so this is measured, not reviewed):
- **Row 15 failed, and not on the reserve.** A solo leaving a cover point beyond its breach radius flies a Dubins
  lead-in from rest, nose on the player, with its own wreck 65 px ahead on the way to S. Once the claim is released the
  wreck's avoidance skirt pushes it sideways. More than `REPLAN_OFF_PATH_PX` off the path, it re-plans from a pose close
  to S with the wrong heading, and the shortest clear path is a ~1,800 px loop.
- **The sweep.** 270 layouts (fighter 450–650 px out, wreck 250–480 px, 12–24 bearings, both modes), each against a
  control flown from the exit pose with no wreck:
  - 84/144 Open Space and 81/126 Assault solos reached RUN_IN 3–6 s late, and most of the Assault ones never attacked.
  - Squad LEADs whose S was more than 2 plan radii from C: 11/73 Assault LEADs lost their attack.
  - Every case with C inside the breach radius (solo), or near S (LEAD), was fine.
- **Fix: one more entry rule, the swoop rule** (`_swoops_from(c, target)`), mirroring two decisions APPROACH already
  makes:
  - **Solo:** C must be inside APPROACH's breach radius less `COVER_HOLD_PX`: `|C − P| < min(standoff, |S − P̂|) − 1 −
    BREACH_MARGIN − 30`. It then breaches out of cover the tick it leaves.
  - **Squad LEAD:** `|C − S| <= STATION_ARRIVE_PLAN_RADII × plan radius − 30`, with the segment C→S clear of the player
    by `reposition_min_radius`. It then slides straight onto S (`_fly_to_start`'s direct arrive).
  - The pass is derived once in `_take_cover()` (only with a hazard registered and a wreck within reach) so S is known.
  - With the rule: 0 of 216 solo and 0 of 112 LEAD covers late in Open Space; 2 of 184 in Assault, both fighters
    starting below the corridor floor (no level spawns there), and both still attacked.
- **Consequence for Assault.** `_clamp_run` pulls S 395 px inside the corridor edge, so for a centred player the solo
  breach radius is ~355 px and the swoop band only 300–325 px. Assault cover stays mostly a LEAD behaviour. This adds to
  M4's "rare in level 1".
- **Rows.**
  - Row 15 is replaced by:
    - 15a: the solo swoop boundary, ±5 px, dual;
    - 15b: the LEAD station boundary, ±5 px, dual;
    - 15c: a 24-layout solo sweep per mode, each cover left straight into RUN_IN.
  - Rows 6 and 10 get layouts that satisfy the rule.
  - `COVER_WRECK` moves 10 px in, so C is 315 px out, inside the Assault band with margin.
  - Row 13's sampler holds its nodes through a dictionary: GUT resumes the body inside a `physics_frame` emission, and
    can free the harness while that emission still owes the disconnected lambda its call.

## Problem

Today a Fighter that notices the player flies straight onto its lead-in and runs in, wherever the wrecks are. With
Phase 6 wrecks on the field, a fighter should use one: slip behind a wreck that lies on its way in, wait there out of
the player's sight for a beat, then swoop out on its pass from that spot. Only the squad's leader (or a lone fighter)
does it, at most once before each run, and never at the price of its attack (Assault) or of the squad machinery.

**Where it shows (review M4).** COVER in level 1 is rare; it is mainly an Open Space behaviour (the hub, t17's
battleground). The reasons:
- In Assault the first APPROACH tick is the spawn tick.
- Level-1 fighters spawn 60–260 px outside the corridor (`level_1_director.gd:968-988`), so only a wreck near the entry
  edge, within 500 px of the spawn, qualifies.
- Assault wrecks drift down and away from the top.

The Assault half stays:
- The rows run in both harnesses, as §2.12 asks.
- A level-1 fighter that does find a wreck by its entry edge uses it.
- The wreck-guard replay now reports how many COVER entries it saw.

Running the check on the first APPROACH tick *inside the corridor* instead would make Assault cover common. But it
departs from the task's "first tick", so it is raised as an owner option in the final report and in DECISIONS, not
built.

## Design

### The phase

`enum Phase { APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING, COVER }` — COVER is
appended (value 9), so no value moves. `phase_changed` is emitted for it like for every phase (`enter_phase()` stays
the only transition path).

New brain state:
- `cover: HazardInfo`: the claimed wreck, null outside COVER, read-only outside the script.
- `cover_point: Vector2`: this tick's C, for tests.
- `_cover_used: bool`.
- `_cover_check_pending: bool = true`.
- `_cover_hold_time: float`.
- `_cover_settled: bool`: the arrival latch.

New controller tolerances:
- `COVER_HOLD_PX := 30.0`.
- `COVER_ARRIVE_PX := 10.0`: the latch. It releases beyond twice that (20 px), which is below `COVER_HOLD_PX`.

### Entry: APPROACH's first tick

APPROACH is entered in three ways:
- at spawn (the default `phase`, never through `enter_phase()`);
- from NOTICING (`_tick_anchor_idle`, COMBAT);
- through the test seam.

`REPOSITION` never hands to APPROACH. So in practice COVER happens at most once per engagement: in Assault only on the
spawn tick, in Open Space each time the hub idle wakes the fighter (`_enter_calm()` clears `_cover_used`, below).
`_cover_check_pending` is true from construction and set again by `enter_phase(APPROACH)`. `_tick_approach()`, right
after its existing `has_target` guard and before `_derive_pass()`:

```
if _cover_check_pending:
    _cover_check_pending = false
    if Hazards.count() > 0 and _take_cover(target):
        enter_phase(Phase.COVER)
        _tick_cover(delta, target)
        return
```

`Hazards.count() > 0` is the first test. With no hazard registered, the only new work is one bool write and one
compare: no rng, no allocation, no state the pass reads.

`_take_cover(target) -> bool` — all must hold (cheapest first):
1. `not _cover_used`, `forced_pass_kind < 0`, and `_role() == SquadController.Role.LEAD`.
   - The role check is true for a solo fighter, a squad of one, and a squad's LEAD.
   - It is false for FLANK_LEFT / FLANK_RIGHT / REAR (S15).
   - A LEAD demoted mid-cover leaves (see below).
2. Assault: `budget.remaining() >= config.cover_min_budget` (`remaining()` is INF in Open Space).
3. A candidate from `Hazards.around(actor.global_position, config.cover_search_radius)`, **sorted nearest first** by
   centre distance to the fighter. It takes the first candidate that passes every rule below **and** whose
   `try_claim(actor)` succeeds:
   - `info.kind == &"wreck"` and `info.line_of_sight_blocker`, and its `source` is a live node that is not queued for
     deletion and not `is_retiring()` (duck-typed).
   - **On the fighter's way in:** the wreck is nearer the player than the fighter is (`|W − P| < |X − P|`). This rule
     is new, not in §2.12.
     - Without it, a wreck behind the fighter would send it *away* from the player to hide.
     - In the hub a C up to ~1,100 px from the player is beyond `lose_radius` (900). The idle would send it RETURNING
       mid-cover; it would release, notice again, and loop.
     - With the rule, `|C − P| < |X − P| + radius + cover_gap`, so hiding never takes the fighter meaningfully farther
       away.
   - `C = W + (W − P).normalized() · (radius + cover_gap)` lies farther than `cover_break_range` from the player
     (otherwise the first COVER tick would break it).
   - Assault: C is inside the corridor shrunk by the hull, `_corridor().grow(-_hull_radius).has_point(C)`. The
     corridor constraint discards outward motion before the fighter has entered, so a C outside it is unreachable.
   - C is outside every *other* hazard's `radius + config.hazard_margin`. This is the reachability rule of epic §2.4,
     as the Sniper's `_inside_other_hazard()`; the fighter keeps a local five-line copy (review n1).
   - **(Revision 2) The swoop rule**, `_swoops_from(C, target)`, on the pass derived this tick. A solo needs
     `|C − P| < min(standoff, |S − P̂|) − 1 − BREACH_MARGIN − COVER_HOLD_PX`. A squad LEAD needs
     `|C − S| <= STATION_ARRIVE_PLAN_RADII · plan radius − COVER_HOLD_PX`, with C→S clear of the player by
     `reposition_min_radius`.

   Explosive wrecks pass these rules like any other (review n2). C is inside the 110 px blast, so a player who shoots
   the wreck hurts the fighter hiding behind it. That is the same bait the Sniper offers; it is written in `ENEMY.md`.

`W` is read from `(info.source as Node2D).global_position`, which is always current, unlike `info.position` (only a
`hazard_info()` call refreshes that). `P` is `target.position`, the live player, not P̂.

### In COVER (`_tick_cover`)

Every tick, in this order (review round 2, R1: S must be derived before the reserve exit reads it — on the entry tick
`pass_start` is still its default `Vector2.ZERO`):
0. **No player** (`not target.has_target`, review m4) → leave for APPROACH, which already requests zero then.
   Otherwise `_derive_pass(target)` (step 2's call, moved first), then:
1. **Exit** to APPROACH (below) on the first of:
   - **Demoted:** the fighter is no longer its squad's LEAD (`_role() != LEAD`). A later `join()` re-sorts roles by
     distance (review m3); this exit keeps S15 true on every tick, not only at entry.
   - **The cover is gone:**
     - `cover` is no longer `is_claimed_by(actor)` (a `retire()` clears the claim and unregisters);
     - its `source` is freed, queued for deletion or `is_retiring()`;
     - in Assault, C has left the shrunk corridor.
   - **Player close:** the player is within `cover_break_range` (300) of the fighter.
   - **Timeout:** `_phase_time >= cover_max` (5.0 s).
   - **Assault reserve, trip-aware** (review M2): `budget.remaining() <= cover_pass_reserve + |X − S| / max_speed`,
     where S is `pass_start` as derived this tick (step 2).
   - **Hold done:** `_cover_hold_time >= cover_hold` (1.2 s).
2. Otherwise:
   - (`_derive_pass(target)` has already run, in step 0: exactly what APPROACH does every tick before RUN_IN, so S is
     the start the fighter will fly to on leaving. `_derive_pass()` itself is not changed.)
     - Nothing is latched before RUN_IN.
     - The one first-derivation latch, `_frontal_sigma`, is then taken at the spawn position as it is today, not at C.
   - C is recomputed, so it stays on the far side as the player moves; `cover_point = C`, `seek_target = C`.
3. **Arrival latch** (review M1; the Sniper's `_travel()` latch, `sniper_brain.gd:354-367`).
   - **Why:** `Steering.arrive` has a zero slowing radius at rest. Re-seeking a point the fighter is already on
     chatters at full speed round it and leaves `_heading()` pointing anywhere.
   - **Latch:** `_cover_settled` is set within `COVER_ARRIVE_PX` (10) of C and cleared beyond `2 × COVER_ARRIVE_PX`
     (20).
   - **Settled:** `mover.request_velocity(cover.velocity)`. That is zero for a still wreck and the wreck's own drift for
     an Assault one (60 px/s down), so the fighter rides along with it.
   - **Unsettled:** `mover.arrive(C, config.max_speed)`.
   - **Both:** `mover.face_toward(P)`.
   - **Result:** a held fighter is at rest (Open Space) with its nose on the player, and leaves cover with `_heading()`
     = the nose.
4. **Hold clock**, after the request, on this tick's position.
   - `_cover_hold_time += delta` while the fighter is within `COVER_HOLD_PX` of C **and** `can_see_player()` is false.
   - Otherwise it is reset to 0 (the hold is continuous).
   - The hold therefore completes on the tick its accumulated time reaches `cover_hold`, and the exit happens at the
     start of the next tick.

The claimed wreck is skipped by the mover's avoidance (§2.4, `EnemyMover._avoid()`), so its skirt cannot push the
fighter off C; every other hazard still applies. No burst can open (bursts need RUN_IN or TURN). The light stays OFF.

**Budget expiry in COVER** behaves as in APPROACH. `tick()`'s existing `budget.update()` calls
`_request_disengage()`, which enters DISENGAGE that tick (no burst can be running). So the engagement-deadline
arithmetic is unchanged. With the shipped reserve it cannot happen, because the reserve exit always comes first. It is
still handled, and row 11 forces it.

### Exit and the claim (N3)

`_leave_cover(delta, target)` calls `enter_phase(Phase.APPROACH)`, then `_tick_approach(delta, target)` on the same
tick, so no tick goes without a request (the same idea as `_steer_run_in` on RUN_IN entry).

APPROACH then derives the pass from wherever the fighter is, exactly as it always does. It may plan a lead-in, or breach
straight into a FRONTAL-shaped RUN_IN when the fighter left cover inside the breach radius. `_derive_pass()`, the RUN_IN
latch and the squad hold machinery are not touched.

- **`_cover_used`** is set to true on **COVER entry**. It is cleared in two places:
  - in `_enter_run_in()`, for "once per RUN_IN";
  - in `_enter_calm()` (IDLE / RETURNING entry): the fight is over, so the next wake is a new engagement (review m2).

  Since REPOSITION never hands to APPROACH, in play that means at most one cover per engagement. The RUN_IN clear is
  observable through the `enter_phase(APPROACH)` test seam, and is tested there.
- **The claim is released on every exit from COVER**, in one place: `enter_phase(p)` calls `_release_cover()` when the
  phase it leaves is COVER. That covers `APPROACH`, `DISENGAGE`, and the anchor idle's `IDLE` / `NOTICING` /
  `RETURNING`.
  - `on_suspended()` (a rail takes over; no `enter_phase()`) also calls it.
  - A freed fighter frees its claim through the instance id (`HazardInfo.try_claim`).
- `enter_phase(COVER)` resets `_cover_hold_time` and `_cover_settled`, and clears any lead-in path.

### N2 — the Assault budget gate

`engage_seconds` is 6.0, and `budget.update()` runs before the phase dispatch. So on APPROACH's first tick
`remaining()` is `6.0 − 1/60`, and the §2.12 gate `remaining() >= 6.0` never opens. COVER would be Open Space-only,
which fails the task's own dual-mode rows. The fix:
- **`cover_min_budget` = 5.0 s** (not 6.0). It opens for the shipped fighter on its spawn tick. The "less than
  `cover_min_budget` → no COVER" row keeps its meaning: the boundary is tested one tick either side of it.
- **New flat field `cover_pass_reserve` = 3.0 s, used trip-aware** (review M2). In Assault, COVER also ends once
  `remaining() <= cover_pass_reserve + |X − S| / max_speed`.
  - The `|X − S|` term pays for the straight flight to S, whatever the trip to C took.
  - The 3.0 s is the run itself plus room for the lead-in's turning or a LEAD's short hold. S is 480 px out at
    300 px/s, so ≈ 1.6 s to the closest approach; `run_budget_slack()` adds 0.25 s.
  - A solo that breaches from C pays the `|X − S|` term without flying it. That is conservative, never late.
  - The reserve is a [judgement] value **checked, not argued**, by three Assault rows. Each asserts RUN_IN starts with
    `run_budget_slack() > 0` and a burst opens before DISENGAGE:
    - row 12: a solo that breaches from C;
    - row 14: a squad LEAD, which never breaches: it flies to S, holds, and `_go()` refuses once
      `run_budget_slack() <= 0`;
    - row 15: a solo whose C lies beyond the breach radius, so it flies a lead-in.
- **Pre-agreed levers if rows 14 / 15 fail**, in order:
  1. Raise `cover_pass_reserve` (≤ 3.5 s).
  2. For the squad LEAD only: keep squad LEADs out of **Assault** COVER (one more entry rule; Open Space LEADs are
     unchanged), and record it in DECISIONS. The FLANK/LEAD row's Assault case then asserts the LEAD takes no cover.

  Never change `engage_seconds`.
- A config row pins `cover_min_budget ≥ cover_pass_reserve + cover_hold` (4.2), so the gate never admits a cover with
  no room for its own hold.

This is a seventh field beyond §2.12's six; it goes in DECISIONS.

### N8 — a LEAD in cover and its squad

Recorded as **accepted** (the review's second option), because the task forbids touching the hold machinery.
- While the LEAD is in COVER it is not holding, so each FLANK's `_wait_time` runs. The FLANK goes alone after
  `flank_wait_max` (2.0 s), as it does today for any late LEAD.
- The FLANK's pass draws the player's attention, then the LEAD swoops in from cover.
- The LEAD then flies to its S, and the squad's normal rules time its run (`_flanks_ready()` or `lead_wait_max`), so it
  may wait in the open at S before it goes.
- COVER delays the LEAD's window by at most `cover_max`.
- Mates treat a LEAD in COVER like any mate that is not on a lead-in (`_slow_for_mates`).
- `predicted_position()` falls through to `pos + velocity·t` for it. Neither function changes.

### New `FighterConfig` fields (`@export_group("Cover")`, flat)

| Field | Value | Meaning |
|---|---|---|
| `cover_search_radius` | 500.0 px | A wreck within this of the fighter (`Hazards.around` reach) can be taken. |
| `cover_gap` | 40.0 px | C sits this far beyond the wreck's edge (the hull is 28.6 px, so ≈ 11 px clear). |
| `cover_hold` | 1.2 s | Continuous seconds hidden within 30 px of C before it goes. |
| `cover_break_range` | 300.0 px | The player this close breaks cover at once. |
| `cover_max` | 5.0 s | COVER never lasts longer. |
| `cover_min_budget` | 5.0 s | Assault: no COVER with less budget than this left. |
| `cover_pass_reserve` | 3.0 s | Assault: COVER ends with this much budget left, plus the straight trip to S (new). |

### Alternatives rejected

- **Moving S to the cover point** — rejected in §2.12 (S, `b`, `l` and the run heading are derived together).
- **COVER Open Space-only** (N2's other option) — the task's acceptance rows are dual-mode.
- **A per-wreck travel-time entry gate** (the Ram's t16 shape) — the trip-aware reserve exit bounds the same thing
  every tick, from where the fighter actually is, and rows 12, 14 and 15 check it.
- **Running the Assault check on the first APPROACH tick inside the corridor** (review M4) — it would make level-1
  cover common, but it departs from the task's "first tick" and needs `cover_min_budget` re-derived. Offered to the
  owner, not built.
- **Pausing a FLANK's wait while its LEAD is in COVER** (N8's first option) — touches the hold machinery.
- **Checking for cover on every APPROACH tick** — a wreck appearing mid-lead-in would re-plan the approach; §2.12 says
  first tick.

## Build sequence

1. **Config.** The seven fields in `fighter_config.gd` (`@export_group("Cover")`) and `fighter_config.tres`. Config row
   green.
2. **Failing tests.** The rows below go in `tests/integration/test_fighter.gd`, in a new `# ── Cover (Phase 6 t14)`
   section. Run them; all but the config / enum rows fail.
3. **Brain.** In this order:
   - the enum value and the new state;
   - `_take_cover`, `_tick_cover` (with the arrival latch), `_leave_cover`, `_release_cover`;
   - the `enter_phase` hook;
   - `_enter_run_in` and `_enter_calm` clearing `_cover_used`;
   - `on_suspended`;
   - the header comment.

   Rows green.
4. **Measure** the Assault rows 12, 14, 15 and the live-physics row. Apply the pre-agreed levers only if needed.
5. **Wreck guard.** `test_level1_fighter_exit.gd` gains a COVER-entry count in its existing `gut.p` line (no new
   assertion). It counts fighters seen in COVER at the end of a frame, so a same-tick enter / exit never inflates it
   (R4).
   - Run the guard 3× before the brain change and 3× after, and report the maximum clear time.
   - If it fails, see who leaves last. Use the reserve only if a fighter is last. Otherwise use the epic §2.9 levers in
     order: Assault wreck `avoid_weight` 0.3, then halve the Assault `wreck_chance`.
   - Never change the timeout (review m1).
6. **Regression.**
   - Test files: `test_fighter.gd`, `test_fighter_squad.gd`, `test_gatling*` (shares nothing; a sanity check),
     `test_level1_fighter_*`, `test_engagement_deadline.gd`, `test_enemy_dual_mode.gd`, `test_sector_hub_patrol.gd`, and
     the single-writer and config-isolation gates.
   - Then `bash /agent/verify.sh`, `scripts/check-test-leaks.sh` and `scripts/gate-time.sh` (before ≈ the baseline
     taken at the start of this task).
7. **Docs.**
   - `fighter/ENEMY.md`: COVER in the phase list, a Cover section, and explosive wrecks as bait.
   - A t14 line in DECISIONS.md:
     - the seventh field and the trip-aware exit;
     - `cover_min_budget` 5.0;
     - the "on its way in" rule and the corridor rule;
     - the "no longer LEAD" exit;
     - `_enter_calm` clearing `_cover_used`;
     - N8 accepted;
     - the real level-1 reach and the corridor-entry option.
   - The `updating-project-docs` skill.

## Test plan

All in `tests/integration/test_fighter.gd`.
- "Dual" = `func test_x(mode: String = use_parameters(["open_space", "assault"]))`, with the harness built in the body.
- Wherever a ray must see the wreck, a **real** `wreck_medium.tscn` (r 25) is used, held still
  (`set_physics_process(false)`), with `await wait_physics_frames(2)` after placing it, as in `test_sniper.gd`.
- Where only the registry matters, the body-less `fixture_wreck.gd` is used, with its radius set.
- Fighters are hand-ticked with `_tick()` and seeded, solo unless stated.
- Geometry: the player at `MID`, the wreck on the line from the fighter to the player. For example, the fighter at
  `MID + (560, 0)` and the wreck at `MID + (260, 0)` give C = `MID + (325, 0)`: inside the Assault corridor, 325 px
  from the player, 235 px from the fighter. Final numbers are set when the rows are first run, with the same layout in
  both modes.

1. `test_cover_is_appended_after_returning` — `P.COVER == 9`; APPROACH..RETURNING keep 0..8.
2. `test_the_cover_fields_ship_with_a_gate_assault_can_open`:
   - the seven shipped values;
   - `cover_min_budget < engage_seconds − DT` (N2: the gate opens on the spawn tick);
   - `cover_min_budget >= cover_pass_reserve + cover_hold`.
3. **Dual** `test_a_solo_fighter_hides_behind_a_wreck_then_runs_in`:
   - COVER on the first tick, with the wreck claimed by the fighter.
   - It reaches C (≤ `COVER_HOLD_PX`) and **holds within 30 px for ≥ `cover_hold`** with the avoidance stage active
     (`mover.hazard_avoidance > 0`, `Hazards.count() > 0`), and `can_see_player()` is false on every hold tick.
   - It leaves COVER for APPROACH (the next phase emitted is APPROACH) on the tick after the hold completes, and the
     claim is released then. `t_exit ≤ cover_max`.
   - COVER is entered exactly once over the whole run.
   - **RUN_IN starts within `t_exit + T_lead + 0.5 s`.** `T_lead` is a control fighter's spawn→RUN_IN time from the exit
     pose (same position, velocity, rotation): "its usual lead-in" from there. The control runs after the subject and
     its wreck are freed, because the registry is static (review n3).
   - **Open Space, exit pose (M1):** at the exit tick `velocity.length() <= HEADING_MIN_SPEED`, and the nose is within
     `nose_cone_deg` of the player — read on the state the brain saw on that tick (the pre-tick record), since after the
     tick's APPROACH and mover step it is already accelerating (R3).
   - In Assault, additionally, a burst opens before DISENGAGE (the attack after cover fits the budget).
4. **Dual** `test_the_player_within_break_range_breaks_cover_at_once`:
   - In COVER, the player moved to `cover_break_range − 5` px from the fighter: that tick the fighter leaves COVER,
     `phase_changed` carried APPROACH, and the claim is free.
   - Boundary control: at `cover_break_range + 5` px it is still in COVER.
5. **Dual** `test_two_solo_fighters_and_one_wreck_only_one_takes_cover` — two fighters, each with the wreck on its way
   in. Over 2 s exactly one is ever in COVER, and it is the claimer; the other never enters COVER.
6. **Dual** `test_a_flank_never_takes_cover_and_its_lead_does` — a squad of two, a wreck on each member's way in:
   - The LEAD enters COVER on its first tick.
   - The FLANK never does over 3 s, and its wreck stays unclaimed.
   - Plus (m3): a LEAD in COVER demoted by a closer member joining enters APPROACH that tick, and the claim is released.
7. **Dual** `test_a_wreck_freed_mid_hold_sends_it_to_approach_next_tick`:
   - Holding, `wreck.free()`: the next tick the fighter is out of COVER, with APPROACH emitted.
   - A second case retires the wreck (`retire()`) instead, with the same result (Open Space only; `retire()` is
     mode-blind).
8. **Assault** `test_assault_with_less_than_cover_min_budget_takes_no_cover` — a boundary pair on the fighter's
   private config:
   - `engage_seconds = cover_min_budget + 0.5·DT` (remaining after the first update `< cover_min_budget`): no COVER,
     and the wreck stays unclaimed.
   - `+ 1.5·DT`: COVER.
9. **Dual** `test_with_no_wreck_in_reach_the_pass_is_identical_to_the_control`:
   - Control: no hazard registered.
   - Subject: a fixture wreck 5,000 px away. It is registered, so `Hazards.count() > 0` and the cover search runs and
     finds nothing.
   - Both are ticked until the first TURN entry (≤ 8 s). The phase sequence and every tick's position and velocity are
     equal, COVER is never entered, and the next `rng.randf()` is equal.
10. `test_a_wreck_that_breaks_a_cover_rule_is_never_taken` — Open Space, one case per rule, each with a control that
    passes:
    - the wreck farther from the player than the fighter;
    - C within `cover_break_range` of the player;
    - C inside another hazard's `radius + hazard_margin`;
    - a wreck already claimed by another node;
    - a FORCED pass kind;
    - a wreck beyond `cover_search_radius`.

    Plus one **Assault** case: C outside the corridor.
11. **Dual** `test_every_exit_from_cover_releases_the_claim` (N3):
    - **Open Space:** the player moved beyond `lose_radius` sends the idle-woken fighter RETURNING and frees the claim.
    - **Assault:** the budget expiring in COVER enters DISENGAGE that same tick and frees the claim. The row sets
      `cover_pass_reserve = 0` and raises `cover_hold` / `cover_max` on the private config, because with the shipped
      reserve the reserve exit always comes first (m5).
    - **Both:** `on_suspended()` frees it.
    - **Both:** the player removed from the tree → APPROACH next tick, with the claim free (m4).
12. **Assault** `test_assault_cover_leaves_with_the_pass_reserve_and_still_attacks`:
    - `cover_hold` is raised on the private config, so the hold cannot end COVER.
    - COVER ends on the tick `budget.remaining() <= cover_pass_reserve + |X − S| / max_speed`.
    - Then RUN_IN starts with `run_budget_slack() > 0`, and a burst opens before the budget expires.
13. **Dual, live physics** `test_on_real_physics_the_fighter_hides_beside_the_solid_wreck`:
    - On the 8× clock (the `_scale_clock` pattern from `test_sniper.gd`, restored in `after_each`), the fighter runs on
      the engine's own physics.
    - It reaches C beside the real wreck body (its centre farther than `radius + hull − 2` from W), completes the hold
      and leaves for APPROACH, with no engine error.
    - **In Assault the wreck drifts** (its physics on, 60 px/s down; m6). COVER ends on the hold or on the corridor
      rule, either way with the claim released and APPROACH emitted.
14. **Assault** `test_an_assault_squad_lead_still_attacks_after_cover` (M2 a):
    - A squad of two, with the wreck on the LEAD's way in, and `cover_hold` raised so the reserve exit ends COVER.
    - The LEAD flies to S, its RUN_IN starts with `run_budget_slack() > 0`, and a burst opens before DISENGAGE.
15. *(Revision 2: replaced by 15a–15c, below. The case it describes is now refused at entry.)*
    15a. **Dual** `test_a_solo_takes_cover_only_where_it_breaches_straight_out_of_it`:
    - the swoop radius is read from a probe brain's own pass;
    - C 5 px inside it → COVER, left straight into RUN_IN on the exit tick;
    - C 5 px outside it → no COVER, and the wreck stays unclaimed.

    15b. **Dual** `test_a_squad_lead_takes_cover_only_where_it_slides_straight_onto_its_station`: S is read from a probe.
    - C at `2 × plan radius − 30 − 5` from S → COVER, then on its station (REPOSITION) or RUN_IN within 1.5 s of leaving;
    - `+ 5` → no COVER.

    15c. **Dual** `test_every_solo_cover_is_left_straight_into_the_run`: 12 bearings × 2 wreck distances (Assault: the
    bearings above the player, C inside the 300–325 px band). At least 20 take cover, and every one leaves straight
    into RUN_IN.

    Original row 15, kept for the record — **Assault** `test_an_assault_solo_that_needs_a_lead_in_still_attacks_after_cover` (M2 b):
    - A solo whose C lies beyond the breach radius: C is more than `min(standoff, |S − P̂|) − BREACH_MARGIN` from the
      player, asserted as a precondition. `cover_hold` is raised.
    - It flies a lead-in from C, RUN_IN starts with `run_budget_slack() > 0`, and a burst opens before DISENGAGE.
16. **Open Space** `test_cover_ends_at_cover_max_when_the_hold_cannot_complete` (M3):
    - `cover_hold` is raised past `cover_max` on the private config.
    - It is still in COVER at `cover_max − DT`, APPROACH is emitted at `cover_max` (± 1 tick), and the claim is
      released.
17. **Open Space** `test_cover_is_once_per_run_in_and_once_per_engagement` (m2):
    - (a) Cover, leave, then the `enter_phase(APPROACH)` seam with no RUN_IN in between: no COVER.
    - (b) The same after a RUN_IN: COVER again. Only the COVER entry is asserted: a forced `enter_phase(RUN_IN)`
      leaves `_latched` true (R4).
    - (c) An idle-woken fighter takes cover; the player leaves beyond `lose_radius` (RETURNING, no RUN_IN) and comes
      back. On the re-notice it takes cover again.

**Unchanged (must stay green with no edit to an assertion):**
- the 168-layout squad sweep (`test_fighter_squad.gd`);
- every Ph3 fighter spec;
- `test_level1_fighter_spawns.gd` / `_fire_density.gd` / `_exit.gd`. That includes the wreck guard
  `test_cloud_descent_clears_in_time_with_wrecks_left_behind`, the one level-1 gate where fighters now meet wrecks; its
  `gut.p` line gains a COVER-entry count (a print, not an assertion);
- `test_engagement_deadline.gd` and the attack-in-budget rows;
- `test_enemy_mover_single_writer.gd`, `test_config_instance_isolation.gd` and `test_sector_hub_patrol.gd`.

## Risks

- **The wreck guard in `test_level1_fighter_exit.gd`.**
  - COVER is rare there (M4: the check runs on the spawn tick, and spawns are outside the corridor).
  - A fighter's life is bounded by the budget, which COVER cannot extend.
  - The replay already varies 8.15–9.15 s run to run (`tests/README.md`), so it is run 3× before and after and the
    maximum reported. Levers as in build step 5.
- **Arrive lag on a moving C.** C moves on a circle of radius `radius + gap` round W as the player moves sideways (≈
  `65 · v⊥ / |W − P|` px/s).
  - The latch re-seeks beyond 20 px, and a drifting wreck's own velocity is fed forward while settled.
  - A fast-strafing player may still keep the hold from completing. `cover_max` (row 16) and the reserve bound it.
- **Heading after cover in Assault** is the wreck's drift (down) rather than the nose, because the settled fighter
  rides the wreck. Down is toward the player in the corridor, so the lead-in or breach starts sensibly. Rows 12, 14 and
  15 check the attack still lands.
- **Heading after cover on a drifting Open Space wreck** (review round 2, R2): death wrecks inherit 25 % of the dead
  ship's velocity (up to ≈ 75 px/s), so a fighter riding one leaves with `_heading()` = the drift, not the nose. Bounded
  (no budget in Open Space) and cosmetic — a lead-in may start with a turn. Written in `ENEMY.md`; no row.
- **(Revision 2) The swoop rule is checked at entry only.**
  - A player who moves away while the fighter hides can leave C beyond the swoop radius at exit. The fighter then flies
    the lead-in the rule exists to avoid.
  - Bounded: Open Space has no budget, and the APPROACH deadline breaches. In Assault the reserve still pays for the
    straight trip to S, and the budget's DISENGAGE stays on time.
  - No exit was added for it: leaving early, still beside the wreck, hits the same loop.
- **A LEAD waits in the open at S after cover** (N8, accepted). A possible follow-up: let a LEAD leaving cover go
  straight in. Out of scope here.
- **Gate time** (+3 s allowance): rows 3–12 and 14–17 are hand-ticked (≤ 8 s simulated each); row 13 is ≈ 3 s
  simulated at 8×.

## Out of scope

- Cover between passes (REPOSITION never hands to APPROACH).
- Cover for the Gatling or any other brain.
- A minimum wreck size: a small r 13 wreck still blocks the centre ray, which is what `can_see_player()` means.
- Any change to `_derive_pass()`, the RUN_IN latch, the squad hold, the weapons layer, `Wreck`, `HazardInfo` or the
  mover. `_derive_pass()` is *called* from COVER, as from APPROACH, but not changed.
- Assault cover checked at corridor entry (M4) — an owner option.
