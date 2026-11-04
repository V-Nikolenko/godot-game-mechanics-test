VERDICT: CHANGES_REQUESTED

## Round 1

Reviewed `3-plan.md` and `1-context.md` against the code at `7597711`, plus epic plan §2.12–§2.14, §2.20 and "For every task". The design follows
§2.14 closely and reuses what exists: `AnchorIdle`, `Steering.orbit`, `StateLight.blink_once()`, the Mine Layer's `_tick_anchor_idle` shape,
`SpecialistExitProbe` and its memo, and t13 docking. The Assault paths are not touched: `budget.active` means no `AnchorIdle`, an Assault tender
never recalls its drones, and the unarmed rule is Open Space only. One state-machine dead end has to be closed before implementation (B1). Everything
else is non-blocking.

I measured the probes in a scratch headless run (a `SceneTree` script under `/tmp` that calls `SpecialistExitProbe.worst_disengage()` with this
plan's arguments; no repo file touched):

| Probe | Worst exit | Runs / capped | Wall cost |
|---|---|---|---|
| drone `[420, 10]`, no prepare | 5.37 s, from (-720, -720) heading (0.707, 0.707) at 10 px/s | 2166 / 0 | 3.20 s |
| drone `[420, 10]`, stub-strip prepare | 5.37 s (same) | 2166 / 0 | 3.17 s |
| drone `[10]` only | 5.37 s (same start) | 1083 / 0 | 1.65 s |
| tender `[380, 10]`, no prepare | 3.82 s, from (-80, 0) heading (1, 0) at 380 px/s | 2166 / 0 | 3.11 s |
| tender `[380, 10]`, `drone_scene = null` + stub strip | 3.82 s (same) | 2166 / 0 | 2.46 s |

From the same run: a static-function `Callable` taken twice compares equal, hashes equal, and hits the same `Dictionary` key inside an `Array`.
The plan's memo-key claim holds. Both probes fit their allotments (3.5 / 4.0 s) as planned, and both exits are well under 10 s, even with the 0.46 s
reversal term added to the drone's.

### Blocking

**B1 — A recalled pair whose tender dies is stuck idle forever** (`twin_laser_drone_brain.gd` / `twin_laser_pair.gd`; plan §A "Launched pair recall"
and `_mirror(IDLE)`).

How it happens:
- The recall check only runs for "the leader of an intact pair with a **live** controller". That check is the only thing that calls `engage()` for a
  controlled pair.
- A controlled pair never builds an `AnchorIdle`. `_setup()` builds one only when `pair.controller == null`, and for a launched pair `controller` is
  the tender (`twin_laser_pair.gd:114`, set by `laser_tender.gd:130`).
- So if the tender is killed while the rig is IDLE (recalled), nothing ever takes the rig out of IDLE:
  - the brains mirror RETURNING toward a freed controller (unguarded, `arrive(controller)` reads a freed node; guarded, they hover at its last
    position);
  - they never attack again and never notice the player standing next to them.

How likely: the recall runs while the tender is in IDLE / NOTICING / RETURNING, so the tender can still be killed. A long-range Sniper Shot, a mine,
or another pair's beam can do it (friendly fire is on for every energy weapon).

Compare t13: a launched pair whose tender dies keeps fighting Attack A cycles. The recall is the only new way into this state.

Fix (one rule, plus a row in `test_laser_tender.gd`):
- Define the controller as "live" exactly as the SOLO code does (`twin_laser_drone_brain.gd:171`: valid and not queued for deletion).
- When the rig is IDLE and the controller is not live, the leader calls `engage()`. That matches t13: an orphaned pair fights.
- Or the leader builds a fallback `AnchorIdle` on the spot. Either is fine, but the plan must say which.
- Make "RETURNING with a controller → `arrive(controller)`" read the same liveness test.
- Row: recall a pair, kill the tender while the rig is IDLE, and assert the rig leaves IDLE within a tick. Assert there are no errors from a freed
  controller.

### Non-blocking

**N1 — The drone probe's `exit_speed` runs can never be the worst; use `[10.0]`** (`ph8_exit_keys.gd::drone_exit`; plan §C "Speeds").

The drone's frameless DISENGAGE exits along its own velocity heading (`twin_laser_drone_brain.gd:205`, `_heading()`, line 225). So every
`exit_speed` start flies the same straight path as the 10 px/s start with the same heading, and is ahead of it at every instant.

Measured: the same 5.37 s from the same start, at 1.65 s instead of 3.20 s. That frees about 1.5 s of a phase that ends 1.5 s under its 238 s
stop line (§2.20).

This is still faithful:
- The reversal term is already measured against the 10 px/s baseline.
- The term increases with `u`, so it also covers a near-rest start.
- t19 gets the same key through the helper.

Keep `[exit_speed, 10.0]` for the tender. Its heading points away from its exit, so the fast start is its worst (measured: the worst start is at
380 px/s).

**N2 — The reversal term is correct but untested, and probably redundant** (plan §C "Drone start-velocity term"; C1).

The term is correct:
- `EnemyMover.step()` caps the non-boost desired velocity at `max_speed` (`enemy_mover.gd:227-229`, nudge included).
- It changes velocity with `move_toward` at `acceleration`, because the drone's braking is 0 (`enemy_mover.gd:240-246`).
- The released constraint adds nothing in DISENGAGE.
- FORM / TELEGRAPH carry at most 300 px/s in any direction. ADVANCE boosts along `-n`, BREAK moves along `±u`, and LAUNCHED is frameless.
- So the worst case is 300 px/s straight against `-n`. Against the 10 px/s probe baseline that costs
  `(u + 10)/a + (u² − 10²)/(2aV)` = 0.344 + 0.119 = **0.46 s**, as the plan says.

It is needed in principle, because the probe cannot pose a framed start. But C1's "`drone_reversal_seconds()` equals the formula from config" can
never fail.

Recommended: one measured row. Take a real bound pair in the probe world at a long axis-aligned start, kill B in FORM with A's velocity at
`+n · max_speed`, and hand-tick A's DISENGAGE with the probe's loop. Compare against the frameless 10 px/s exit from the same start, and assert:
- the difference is > 0;
- the difference is ≤ `drone_reversal_seconds()` + 1 tick.

That ties the analytic figure to the real mover. It costs about 2 runs.

Also log in DECISIONS: framed Assault exits are axis-aligned (`n` ∈ {UP, ±RIGHT}; launched walls come from `assault_points()`, horizontal or
vertical). So the worst framed exit is about 1608 px / 420 + acceleration + 0.46 ≈ 4.8 s, below the 5.37 s frameless diagonal the probe reports.
The added term is therefore conservative. It is fine to keep, but t19 should know it is slack, not a measured need.

**N3 — How the static `prepare_probe` reaches the tree** (`tests/helpers/specialist_exit_probe.gd:131-133`).

`prepare.call(ship)` runs **before** `root.add_child(ship)`, so `ship.get_tree()` is null. Ph7's hook was a bound test method using the test's own
`get_tree()`. The static version must:
- use `(Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"player")`;
- guard `drone_scene` with `"drone_scene" in ship` or `ship is LaserTender`, because the drone has no such property.

The hook also removes *every* player in the tree from the group, not just the probe's stub. So C2 / C3 must not call it while a row's own harness
player should stay targetable. In C3, run "without" before "with": the strip is permanent for that world. Say so in the hook's doc comment.

**N4 — The stub trick changes nothing for either brain; say that plainly.**

I confirmed:
- `BaseEnemy._physics_process` (`base_enemy.gd:115-120`) reads no player.
- The drone's `tick()` skips `pair.tick` / `_decide` in DISENGAGE (`twin_laser_drone_brain.gd:56-61`).
- The tender's `tick()` returns before `TargetInfo.player()` (`laser_tender_brain.gd:75-78`).
- Measured: the drone probe costs 3.20 vs 3.17 s with and without the strip.

Rule 3 is applied as the task asks, and C3 pins that it is harmless. The real saving is `drone_scene = null` on the tender (3.11 → 2.46 s). Report
it that way, so nobody later attributes the saving to the stub.

**N5 — Recall duck-typing must check `has_method(&"recalls_drones")`.**

`test_twin_laser_drones.gd:627` binds a fixture enemy as controller, and Ph10 / Ph11 carriers may not define the method. Treat a missing method as
false. With B1's fix, also treat a controller that is not live as false.

**N6 — B7 ordering, and the rearm clock lost across the hub transition** (`laser_tender_brain.gd:217-225`).

If the pair dies while the tender is in WAIT:
- the existing rule enters REARM;
- if the tender is then sent home, REARM (not busy) gives way to RETURNING, and the idle rearm clock starts again from 0;
- so "cradles full `rearm_seconds` after the last drone died" only holds if the drones die after the tender is already in IDLE / NOTICING /
  RETURNING (for example, shot during the recall flight).

Either:
- write the row in that order; or
- simpler: keep one rearm clock that runs whenever `docked_count() < 2` and no launched drone lives, in REARM or any idle phase, so the progress is
  not thrown away.

The same applies to the "hold" case.

**N7 — The tender's idle motion must not sit behind `_move()`'s no-target early return** (`laser_tender_brain.gd:299-301`). IDLE orbit and RETURNING
should run with no player present, as the Mine Layer's do.

**N8 — Update the enum pin.** `test_twin_laser_drones.gd:333` pins `TwinLaserPair.Phase.keys()` and needs `"IDLE"` appended. Mention it in step 2 so
it is not mistaken for a regression.

**N9 — C2's source sweep vs C2's own boundary.** If the lambda-memo boundary in `test_laser_tender.gd` calls `worst_disengage` with
`TwinLaserDroneBrain.Phase.DISENGAGE` / `LaserTenderBrain.Phase.DISENGAGE`, the sweep flags the file it lives in. Use a different scene/phase for the
boundary, or exempt the boundary explicitly.

**N10 — Does a lone drone with `start_engaged` orbit or arrive?** The plan does not say whether the lone-SOLO orbit applies when `start_engaged` is set.

Both satisfy t12's SOLO row (`test_twin_laser_drones.gd:476`). I checked the geometry: the survivor is ≥ 210 px from the shared midpoint anchor, so
its ring point lies on the line to the anchor. Pick one and state it.

### Claims checked and found sound

- **30 s orbit tolerance.** Simulated `Steering.orbit` (`steering.gd:41-45`, speed `clamp(4d, 60, max)`) with `move_toward` acceleration:
  - drones (300 / 900, ring 140 at 70 px/s): settle from ±210 well inside 3 s, steady radius 139.0, both drones lag equally so they stay opposite;
  - tender (200 / 400, ring 160 at 80 px/s): never beyond 161.4 from the anchor;
  - SOLO from 1000 px: settles within 4 s.
  - All inside `idle_radius + 8`.
- **Notice timing.** `AnchorIdle.update()` (`anchor_idle.gd:53-70`) enters NOTICING on the tick the leader is within `perceive_radius` (`<=`).
  COMBAT comes 21–22 ticks later, inside ±2 ticks of 0.35 s. 649 / 651 and 1499 / 1501 sit on the right sides of the `<=`.
- **Stand-down ordering.** The leader's `_tick_anchor_idle` runs before `pair.tick()`:
  - in Open Space, BREAK goes to WAIT (`twin_laser_pair.gd:315`), so a pair losing the player mid-attack does one WAIT tick, then `stand_down`
    (A6 should allow that tick);
  - `engage()` → FORM sets `_fresh_frame` (`twin_laser_pair.gd:470-471`), so the first frame takes the bearing outright.
- **Docking flow.** A RETURNING drone docks via `dock()` → `queue_free()`. `_live()` reads queued-for-deletion (`twin_laser_pair.gd:503-504`), so the
  leader's next tick breaks the pair. The survivor goes SOLO toward the live tender and docks through t13's existing path.
- **Memo-key equality.** Scene path, phase, the `Array[float]` built in one helper, cap, deterministic corridor starts, and a static-function
  `Callable` are all equal across files (verified above).
- **Tow table.** It already iterates every phase (`test_base_enemy.gd:502-526`).
- **Other rows needing `start_engaged`.** The dual-mode cases (`test_enemy_dual_mode.gd:1295`, `:1342`) and the `_pair()` / `_tender()` helpers are
  the only Open Space users. The friendly-fire row binds a controller, so it builds no `AnchorIdle`.
- **Gate time.** The rows are short hand-ticked runs (A3 ≈ 1980 ticks × 2 drones). The 8.5 s allotment is realistic: ≈ 6.7 s measured, or ≈ 5.1 s
  with N1.

## Round 2

VERDICT: CHANGES_REQUESTED

I re-read the revised `3-plan.md` (Revision 1) against the code, and simulated where a row depends on numbers. B1 and N1–N8 and N10 are fixed. The
fix for N9 does not work, so the C2 source sweep still fails on correct code (B3 below). The single rearm clock as worded can lose the carried value,
which fails row B7 "hold" (B2 below). Both fixes are one sentence each. Nothing else in Revision 1 introduces a dead end.

### Round 1 findings: status

- **B1: fixed** (plan lines 48–53, row B8).
  - `_recalled()` requires a live controller (`_controller_live()`, the SOLO test) that has `recalls_drones()` and returns true. Anything else,
    while the rig is IDLE, makes the leader call `engage()`. RETURNING `arrive`s only while the controller is live.
  - The tender's death runs `died` and then `queue_free()`, so it already counts as not live on the next drone tick. The leader engages on its
    next tick, and FORM with a player present is ordinary Attack A.
  - No dead end is left. The orphaned pair now fights without an `AnchorIdle`, as t13's orphans do; this was accepted in round 1.
  - Row B8's setup can be reached: an engaged tender launches, the player is moved beyond 1600, the pair is recalled, then the tender is killed.
    The tender's `wreck_chance` 0.35 spawns nothing in a harness with no hazard container, which is the Ph6 rule.
- **N1: fixed.** The drone runs at `[10.0]` (1083 runs) and the tender at `[exit_speed, 10.0]` (2166). C1 is updated, and the deviation from
  §2.14 is logged.
- **N2: fixed by row C4.** I simulated C4 discretely, with the probe's loop, `move_toward` at 900, V 420 and the strict exit check:
  - from the start against the exit at 300 px/s, versus 10 px/s along it, the difference is **0.4667 s** from y = -360 / -300 and **0.4500 s**
    from y = 0 / 300;
  - the bound is 0.4630 + 1 tick = **0.4797 s**;
  - so "> 0 and ≤ term + 1 tick" passes on correct code with a margin of ≥ 0.013 s, and would fail if the term were understated.
  - The setup works:
    - the test writes the rig fields `normal = UP` and `has_frame = true`, and A's `velocity = UP * 300`;
    - B's death sets `_gone`, so on A's next tick `_decide` sees the pair broken and enters DISENGAGE. Exit along `-n` = DOWN
      (`twin_laser_drone_brain.gd:207-208`). The constraint is released before `mover.step`;
    - `disengage_seconds()` calls `enter_phase()` before its loop, and here DISENGAGE starts inside the first tick. Both put the first DISENGAGE
      motion step on tick 1, so the timing matches.
- **N3, N4, N5, N7, N8, N10: fixed** as worded (lines 94–99, 48–50, 71, 131–132, 56–57).
- **N6: the design is right, but the wording breaks it.** See B2.
- **N9: not fixed.** See B3.

### Blocking

**B2 — The rearm clock resets "when the condition fails", and that condition includes being in an idle phase, so the carry into REARM reads 0**
(plan lines 76–81).

As written, `_rearm_elapsed` "runs while IDLE / NOTICING / RETURNING with `docked_count() < 2` and no intact pair … it resets to 0 when the
condition fails". The failure in B7 "hold":

1. The tender is in NOTICING with the clock at, say, 4 s.
2. On the tick NOTICING turns into COMBAT, `_tick_anchor_idle` enters APPROACH.
3. The tender is no longer in an idle phase, so the condition fails and the clock resets to 0.
4. Then `_decide`'s unarmed rule enters REARM "carrying `_rearm_elapsed`", which is now 0.
5. The cradles fill 7 s after re-engaging, not at the same time ± 2 ticks, so the row fails.

The same works out correctly only if the implementer happens to put the reset after `_decide`. The opposite reading has its own hazard: if the clock
resets only inside idle phases, a stale value survives. Example: the tender enters RETURNING from WAIT on the very tick its pair died (the anchor
idle runs before `_decide`'s WAIT → REARM rule), and it would start from an old count. Either reading leaves a row to luck.

Fix: state the rule exactly.
- Every tick, in every Open Space phase: `_rearm_elapsed = 0` whenever `docked_count() == 2` or `_pair_lives()`.
- It **advances** only in IDLE / NOTICING / RETURNING.
- It is **never** reset by a phase change.
- It is **consumed** (set to 0) when `rearm_cradles()` fires, and when it seeds REARM's `_phase_time`. The seeding happens after `enter_phase()`,
  because `enter_phase()` zeroes `_phase_time` (`laser_tender_brain.gd:95`).
- Entering an idle phase from REARM seeds it from REARM's `_phase_time`, as written.
- The unarmed rule runs before `_decide`'s REARM check, so it can still cascade into HOLD → LAUNCH on the same tick.

With that rule, both B7 cases hold on correct code. A one-tick double count at the REARM → idle seam stays inside B7's ± 2 ticks. I traced both cases:
- "idle": the pair dies in WAIT, so REARM starts at `_phase_time` 0. The player is then moved away, so the tender enters RETURNING with the clock
  seeded. The cradles fill 7 s after the death.
- "hold": the player returns and the tender goes NOTICING → APPROACH. The unarmed rule enters REARM carrying the clock, the cradles fill at the same
  time, then HOLD → LAUNCH. Hand-ticked rows skip the line-of-sight check (`laser_tender_brain.gd:242`).

**B3 — C2's source sweep flags `test_laser_tender.gd` itself, so it fails on correct code** (plan lines 180–183).

The sweep fails any file other than `ph8_exit_keys.gd` that contains both `worst_disengage` and `TwinLaserDroneBrain.Phase.DISENGAGE` /
`LaserTenderBrain.Phase.DISENGAGE`.
- `test_laser_tender.gd` **already** contains both phase literals today: `:714` and `:745` (`LaserTenderBrain.Phase.DISENGAGE`) and `:730`
  (`TwinLaserDroneBrain.Phase.DISENGAGE`).
- C3 adds more of them (its `disengage_seconds()` calls need the drone's and the tender's DISENGAGE phases).
- So once C2's own Bomber boundary calls `worst_disengage` in the same file, the file matches. Moving the boundary onto the Bomber does not help.

Fix: match the **call**, not the file. For every `worst_disengage(` call in `tests/**/*.gd` outside `ph8_exit_keys.gd`, its argument text (up to the
closing parenthesis) must not name `twin_laser_drone.tscn`, `laser_tender.tscn`, `TwinLaserDroneBrain` or `LaserTenderBrain`.
- That reads `test_level1_specialist_spawns.gd`'s current calls and C2's Bomber boundary as clean.
- It still catches a hand-built Ph8 probe call, which is what the sweep is for.
- Add a synthetic positive (a string holding such a call) so the sweep is shown to fire.
- Remember the gate's rule that a doc comment containing `worst_disengage(` also counts as a call. Strip comments first, as
  `test_enemy_mover_single_writer.gd`'s `_code_only()` does (it is `static`).

### Non-blocking

**N11** — B5 "inside" (1599 px) is in APPROACH / HOLD with full cradles, so a long enough run would LAUNCH and enter WAIT, making "still APPROACH /
HOLD" false. Keep the run under the time it takes to reach the hold range (≈ 4 s at 200 px/s from 1599 to 650 ± 80), or assert "not RETURNING /
IDLE" instead.

**N12** — The plan dropped the round-1 "a lone drone on its way home → stay". The unarmed rule now REARMs whenever no pair lives. That is simpler and
has no dead end: the lone drone docks during REARM, `dock()` clamps the count at 2 (`laser_tender.gd:148`), and REARM still completes. Fine, but say
so in DECISIONS, since it differs from round 1's text.

## Round 3

VERDICT: APPROVED

Scope: B2 and B3 from round 2, and whether the Revision 2 edits added anything new. I read `3-plan.md` Revision 2 (lines 74–87 and 186–192)
against `laser_tender_brain.gd`, `laser_tender.gd`, `global/enemy_ai/anchor_idle.gd`, the three test files and the probe. I also ran the C2 sweep as a
headless prototype (`/tmp/r3/sweep.gd`: `_code_only()` per line, then cross-line paren matching over `res://tests`). **B2 and B3 are fixed.** Nothing
in Revision 2 creates a dead end or makes a row fail on correct code. Three implementation traps in C2's wording and one sensitivity gap in B7 follow
as non-blocking notes N13–N16. The implementer should apply them as written. None of them needs another plan round.

### B2: fixed (plan lines 76–87, row B7)

How the code orders a tick: `_phase_time += delta` (`laser_tender_brain.gd:68`), then `_dock_returning()` (`:80`), then (planned)
`_tick_anchor_idle`, then `_decide` (`:82`). `enter_phase` zeroes `_phase_time` (`:95`). REARM completes in `_decide` (`:217–219`), and WAIT
moves to REARM only in `_decide` (`:224–225`). The rule is now **independent of where the `_rearm_elapsed` update sits in the tick**:
- its reset depends only on `docked_count() == 2` or `_pair_lives()`, never on the phase;
- it advances only in idle phases;
- it is consumed only by `rearm_cradles()` or by the REARM seed.

I traced each placement (before `_tick_anchor_idle`, between it and `_decide`, and after `_decide`):
- **"idle"** (pair killed in WAIT, then the player is moved past 1600 mid-REARM):
  - While the pair lives in WAIT, the clock is reset every tick, so no stale count survives. That closes the round-2 stale-value case. A tender
    that leaves WAIT for RETURNING on the tick its pair dies starts from 0.
  - At the teleport, AnchorIdle goes COMBAT → RETURNING (`anchor_idle.gd:62–64`). REARM is not busy, so the tender enters RETURNING, seeded with
    REARM's `_phase_time`, which already includes this tick's delta.
  - If the advance runs after `_tick_anchor_idle`, this tick is counted twice. The fill is then at most one tick early. Measured from a kill between
    ticks, that is exactly 7.0 s, not earlier, so "never earlier" and ± 2 ticks both hold. Any other placement fills at 7.0 s + 1 tick.
  - No drone survives to dock, so the reset never fires spuriously.
- **"hold"** (the player comes back while the tender is RETURNING or IDLE):
  - The tender goes RETURNING/IDLE → NOTICING (`anchor_idle.gd:66–67`, `:55–57`) → COMBAT → APPROACH, and the unarmed rule enters REARM on the
    same tick, before `_decide`'s REARM check.
  - The clock was neither reset (docked 0, no live pair) nor consumed before the seed, so the carried value arrives intact in every placement. At
    worst this tick's delta is dropped once: `_phase_time += delta` ran in NOTICING, then `enter_phase` zeroed it.
  - The net seam error is in [−1, +1] ticks, inside ± 2. REARM → HOLD → LAUNCH then cascades (`:217–221`). Off the physics frame the line-of-sight
    check is skipped (`:242`).
- Other paths I checked:
  - **Recall with one drone killed on the way home:** the clock runs from the break, and the survivor docks via `dock()`, which clamps at 2
    (`laser_tender.gd:148`).
  - **The idle threshold fires during NOTICING:** the cradles are full, so APPROACH takes no unarmed rule.
  - **REARM → idle → REARM round trip:** the value is preserved.

  None loses or duplicates more than one tick.

### B3: fixed (plan lines 186–192)

The per-call rule reads every current call as clean and still fires on a Ph8 call. The prototype found 12 `worst_disengage(` calls:
- `test_level1_specialist_spawns.gd:389, 391, 393, 578, 580, 584`;
- `test_engagement_deadline.gd:549, 551, 553`;
- `specialist_exit_probe.gd:81, 92, 101`. The definitions match too, because `_measure_worst_disengage(` contains the needle as a substring. Their
  parameter lists are clean.

None is flagged. Two more sources read clean:
- `test_laser_tender.gd`'s existing phase literals (`:714`, `:730`, `:745`) sit outside any call, so they are not read.
- C3/C4's `disengage_seconds(` does not contain `worst_disengage(`.

C2's Bomber boundary (`BomberBrain.Phase.DISENGAGE`, a static or lambda `prepare`) names no needle. A multi-line synthetic positive that names
`TwinLaserDroneBrain` is flagged (1/1).

Is `_code_only()` workable? Yes, with the caveats below. It is `static func _code_only(line: String) -> String`
(`test_enemy_mover_single_writer.gd:63–87`) and is reachable through `preload` (precedent: `test_twin_laser_drones.gd:18`). It does two things:
- It removes a `#` comment. Doc comments that quote `worst_disengage(` (`test_level1_specialist_spawns.gd:604, 794`, `specialist_exit_probe.gd:97`)
  are dropped.
- It **blanks the contents of string literals**. This helps in two ways:
  - the synthetic positive, held in a string literal in `test_laser_tender.gd`, does not flag its own file;
  - a `(` or `)` inside a string cannot unbalance the matcher.

### Non-blocking (apply when implementing C2 / B7)

- **N13 — `_code_only()` takes one line.**
  - Apply it to each line, then join the lines with `"\n"` before matching the closing parenthesis. Real calls span two lines
    (`test_level1_specialist_spawns.gd:389–390`, `:578–579`).
  - Passed a whole file, `_code_only()` returns everything before the first `#`. The prototype got **length 0** for
    `test_level1_specialist_spawns.gd`, so the sweep passes vacuously, and a single-line synthetic positive still fires.
  - So C2 must also assert that the sweep **found** calls: at least the 9 in `test_level1_specialist_spawns.gd` and `test_engagement_deadline.gd`,
    plus this file's Bomber boundary.
  - Write the synthetic positive across lines (with `\n` escapes), with the class name on the second line and a leading `##` line, so it proves
    the per-line strip and the cross-line match.
- **N14 — never write the synthetic positive as a `"""` block.** `_code_only()` keeps no quote state across lines, so the lines inside a
  triple-quoted string are read as code. The prototype flags such a file (1/1), so `test_laser_tender.gd` would fail on correct code. Use a `"..."`
  literal with `\n` escapes, or a concatenation of single-line literals.
- **N15 — the two `.tscn` needles can never match.** The scene path always sits inside a string literal, which `_code_only()` blanks. The
  prototype's path-only call (`load(".../laser_tender.tscn")`, phase `5`) is **not** flagged.
  - The sweep's real teeth are the two class names. That is enough for the intended case, a hand-built probe call that names the brain's DISENGAGE
    phase.
  - The plan's line 190 should not claim the path needles do anything. Either drop them, or match the path against the call's raw text with
    comments stripped but strings kept. Do the latter only for the argument span, so the synthetic literal elsewhere in the file still stays out.
  - Logging it in DECISIONS is enough.
- **N16 — make B7 sensitive to a lost seed.** Two placements are wrong code that ± 2 ticks would only catch late or not at all:
  - the REARM → idle seed read after `enter_phase()` (it would read 0, because `:95` zeroes it before any `match` arm). Read REARM's
    `_phase_time` **before** calling `enter_phase()`, mirroring line 81's "after" for the REARM seed;
  - the idle → REARM seed lost.

  So "idle" should move the player away well into REARM (e.g. ≥ 2 s after the death), and "hold" should spend ≥ 1 s in the idle phases before
  the player returns. A dropped value then lands far outside ± 2 ticks. In "hold", return the player at least `notice_time` + a few ticks before the
  fill, so that the fill happens in REARM, not during NOTICING.

### Did Revision 2 introduce anything new?

No dead end and no contradiction:
- **Placing the unarmed rule at the top of `_decide()`** (line 85) only pre-empts `:215`'s APPROACH → HOLD when cradles are short. A live pair
  goes to WAIT, and `:224` keeps it there while the pair lives. No pair goes to REARM, which can cascade to HOLD → LAUNCH.
- **Line 83's "± a tick"** matches B7's ± 2 ticks and "never earlier" (traced above).
- **N11's B5 wording and N12's DECISIONS entry** change no other row.
