# t11 plan review

## Round 1

VERDICT: CHANGES_REQUESTED

Reviewed `3-plan.md` and `1-context.md` against epic §2.11, §2.12, §2.17 and "For every task", the Phase 7 DECISIONS (t1–t10 notes),
and the code: `mine_layer_brain.gd`, `mine_layer.gd`, `mine_layer_config.gd/.tres`, `mine_layer.tscn`, `bomber_brain.gd`, `enemy_mover.gd`,
`steering.gd`, `enemy_mine.gd`, `enemy_ordnance.gd`, `bullet_pool.gd`, `hazards.gd`, `engagement_budget.gd`, `enemy_brain.gd`,
`assault_corridor_constraint.gd`, `arena_camera.gd`, `test_mine_layer.gd`, `test_enemy_dual_mode.gd:1056-1080`, `enemy_ai_harness.gd`.

The context file is accurate. The plan covers every §2.12 row and acceptance criterion and reuses the right pieces: the Bomber's EMA and scan
shapes, `Steering.orbit` / `break_contact` / `turn_toward`, `drop_mine()`, `retire()` and `Hazards.around()`. It keeps the conventions:
requests only, accumulated clocks, `brain.rng`, signal arity, verbose-gated logs, and writes only to the private config. Several pins are
good catches:
- BREAK_OFF raising `mover.max_speed`, because the mover caps a non-boost request at `max_speed`;
- this pass's own mines are exempt from no-stacking, because the ARC chords of 100 and 106 are under 120;
- `pass_form = &"assault"`;
- the renamed dual-mode row. Its premise really does change: I computed R = (1090, 40) in Open Space and (190, 174) in Assault.

I checked the numbers with a point-mass model in `/tmp/ml_review/*.js`, outside the repo. The model uses the mover's 240 px/s and 420 px/s²
limits, an exact port of `Steering.context_avoid` and `EnemyMover._avoid`, mines with radius 140 and weight 1.0, and the plan's phase
rules. It reproduces the epic's own figures: lead freeze 1.53 s (epic 1.52 s), abeam freeze 3.87 s (epic 3.83 s), standing freeze 1.68 s
(epic 1.67 s), path lengths 732.4 and 656.6, and run-in/LAY within 33° and 20 px of the path. Each claim below comes from that model, not
from the engine.

### Blocking

1. **The sign rule is applied before the fence rotation, which breaks §2.12's "S on the layer's side" for rotated candidates, and it makes
   the standing scenario's headline rows fail often** (`3-plan.md:54-58`, `:68-71`; epic `3-plan.md:732-734`, `:755`).
   - The plan computes `sign` on the unrotated standing frame, where it is always a tie and falls back to the velocity side. It then
     rotates u with f.
   - After a rotation by θ, `(−u)·(layer − P) = −sign·|layer − P|·sin θ`. That puts S, and so R, on the far side of P for half of all
     rotated candidates. It contradicts the explicit rule `(−u)·(layer − P) > 0`, which allows a velocity fallback only on a real tie.
     After a rotation there is no tie.
   - The far-side R makes the layer cross the ring of older lines. Context steering then slides it along that wall at the 0.35 speed floor
     (`steering.gd:215`): about 84 px/s, seen in the trace.
   - 60 s standing scenario, 40 seeds:

     | Measure | Plan as pinned | Sign re-applied after the rotation |
     |---|---|---|
     | Seeds with `fence_fallbacks` > 0 | 8 | 2 |
     | Seeds with `abandoned_passes` > 0 | 3 | 0 |
     | Fewest passes in a run | 2 | 3 |

     The plan as pinned breaks the row's `fence_fallbacks 0` and `abandoned_passes 0`, and can also break "≥ 3 passes".
   - **Fix:** after the spread rotation, re-run the sign rule against the rotated f. `d = orth(f_rot)·(layer − P)` is non-zero for any
     rotation other than 0, and rotation 0 keeps the velocity tie. Do the same in the fence fallback's `_plan_fence`. Record it in
     DECISIONS as the reading of §2.12 (`:732-734` together with `:755`).

2. **No row pins its rng seed, and the standing scenario stays seed-sensitive even after fix 1** (`3-plan.md:157-196`; `enemy_brain.gd:48-50`).
   - `rng_seed` defaults to 0, which calls `randomize()` in `_ready()`. Shape, variants, the REPOSITION period and the orbit sign are all
     drawn from it.
   - Only the budget row mentions a "seeded run" (`:205`). The two 60 s scenarios, the hazard-aware row, the natural-approach rows and
     the Assault one-pass row are therefore nondeterministic.
   - In the model, about 5% of seeds still hit the 6 s backstop after fix 1. These are the ±2θ rotations, which put R opposite the
     layer, across older lines. §2.12's "no scenario should reach it" (`:809`) is not guaranteed.
   - **Fix:** pin a seed for every row whose outcome depends on a draw (set `brain.rng.seed` before the first tick, or `rng_seed` before
     `add_child`). Log the per-approach freeze times and counters. State the policy: if the seeded standing scenario hits the backstop, the
     task ends `Result: ESCALATE` with that log. It does not reseed until green, and it does not touch the bound.

3. **The "earlier pass" LAY row's geometry is not pinned, and one of its two readings cannot pass with the design plus the pre-approved
   lever** (`3-plan.md:185-188`; risk `:217-219`; epic `:877-878`, `:898-901`).
   - "Centred 380 px away on the fence spread's rotation" puts the older line across one end of the new line: it intersects about 236 px
     from C. The plan does not say which end.
   - **E end** (the end the layer lays toward):
     - Without the lever, avoidance pushes LAY up to 151 px off the path. The row fails, so the lever is needed.
     - With it, the worst LAY heading is 29–36° and the centre stays within 19–20 px of the path. The row passes.
   - **S end:**
     - The run-in from R to S is APPROACH, which the lever does not cover. Avoidance holds it about 151 px off the axis.
     - LAY therefore starts 170 px off the path, at up to 80° from u, with or without the lever.
     - Boosting the run-in is not an answer either: the hazard-aware row asserts > 100 px from older mines during the run-in.
   - The risk text's "the lever covers LAY" is therefore wrong for an older line near the run-in.
   - **Fix:** pin the earlier line across the E end. State in Risks that an older line crossing the run-in deflects it and that LAY then
     starts off the path. That case is measured by the scenarios, not asserted.

4. **The lever as pinned (raw `boost(dir, lay_speed, delta)`) removes the acceleration limit and pushes the sideways row to its bound**
   (`3-plan.md:107-109`; `enemy_mover.gd:223-245`).
   - Finding 3 makes the lever effectively mandatory.
   - With a raw boost, the specified perpendicular ZIGZAG arrival reaches 39.8° against a 40° bound.
   - Arrivals within ±30° of perpendicular and 250–350 px away reach 41.5°, so the sideways property is lost in play.
   - An acceleration-limited boost keeps 31.7° worst case and passes the E-side earlier-pass row at 29°. It is still `boost()`, still
     skips avoidance, and still bypasses the mover's request path: the brain passes the direction and length of
     `mover.own_velocity().move_toward(desired, config.acceleration * delta)`.
   - **Fix:** pin that form. Record that the speed is not exactly `lay_speed` while the velocity turns.

5. **Pooled-mine reuse corrupts the pass records** (`3-plan.md:99`, `:115-118`; `bullet_pool.gd:85`).
   - `lay_mine()` removes a recycled object's old FIFO entry, but not its entry in an older pass record's `mines`.
   - `BulletPool.acquire()` is LIFO, and a retired mine (fizzle 0.3 s) is back in `_idle` on the next yielded frame. In the 60 s scenarios
     pass 1's retired mines are reused by pass 4 or 5. Pass 1 then reads "has a live mine" again.
   - That spoils `live_pass_centres()` (the spread and the gradual row) and the hazard-aware row's pass membership.
   - **Fix:** on a successful drop, remove the object from every pass record and from the FIFO. Alternatively, key records by object plus
     a per-life counter.

### Non-blocking

6. **The abandon guard's clock starts at the freeze, but a fence fallback freezes at any distance** (`3-plan.md:90-94`).
   - In the model, a backstop fallback froze R about 930 px away behind an older line. The guard fired 6 s later with the layer
     145 px from R and closing at 240 px/s: a healthy approach abandoned.
   - Suggest starting the guard when the layer first comes within `commit_distance` of R. Also consider covering a run-in that never
     reaches S ("no LAY yet" rather than "no run-in yet").
7. **The circling scenario's spread is checked once but the frozen C drifts** (`3-plan.md:72-75`; epic `:782`).
   - In the circling scenario a lead C moves 90–900 px between the candidate choice and the freeze, so "≥ 380 at freeze" does not follow
     from the design.
   - The model found 0 violations in 40 seeds, because most circling passes are fence fallbacks. So this is not blocking.
   - Suggest a one-line re-check at the freeze. If it is illegal there, re-choose the candidate, or count it in `spread_fallbacks`
     (recorded in DECISIONS), so the row cannot fail by luck.
8. **The arc row cannot catch a flipped n̂** (`3-plan.md:164-165`).
   - "Offsets ≥ −0.5" measured along the brain's own `pass_normal` is still ≥ 0 if n̂ points away from P.
   - Also assert `pass_normal.dot(P − C) > 0`, or measure the offsets along the test's own P-ward normal.
9. **The 4 px row's anti-inert check is weak** (`3-plan.md:166-167`). With no earlier pass there is nothing to skip, so assert 6 drops,
   not ≥ 1.
10. **The dropped `registers_hazard = false` control leaves the hazard-aware row possibly vacuous** (`3-plan.md:193-196`).
    - This is allowed: it is logged and asserts nothing. But nothing then shows that the > 100 px bound is what avoidance buys.
    - A free replacement: assert that the closest approach was within the avoidance reach (< 164 + 0.6·240 px) at least once in those
      phases. The model's minimum is 125–160 px.
11. **Forward compatibility with t12:** `start_engaged` (`mine_layer_brain.gd:29`) is unread today. t12 will put an un-engaged Open Space
    layer into IDLE, which breaks every t11 Open Space row. Set `brain.start_engaged = true` in the t11 helpers now.
12. **Gate time is tight.**
    - Rough estimate: two 3600-tick scenarios with about 20 hand-ticked mines plus the avoidance stage are about 1.5–2 s each. The full-pass
      rows add about 2 s. That is close to the 4.5 s allotment.
    - Measure early.
    - Use `Geometry2D.get_closest_point_to_segment` for the path coordinates, as `fighter_brain.gd:1766` does.
13. **Informational:**
    - The ARC's mine 5 is always dropped by the end-of-path rule, not the "plus" rule. It needs the centre at 662.6 on a 656.6 path. The
      ZIGZAG's mine 5 clears the plus rule by 5 px.
    - The 4th pass of the standing scenario almost always takes the spread fallback, because three live lines block all five candidates.
    - Worth one line each in DECISIONS, and the second is worth telling the owner.
14. CLAUDE.md requires invoking `updating-project-docs` after a mechanic is added. Step 5 should say so, even if it defers most of the work
    to t16.

## Round 2

VERDICT: CHANGES_REQUESTED

I re-checked Revision 2 against the code and re-ran the round-1 model (`/tmp/ml_review`, outside the repo) with the revised rules. All five
round-1 blocking findings are fixed as asked:
1. `_axis_sign()` is re-applied to the rotated f, and in the fence fallback (`3-plan.md:59-62`, `:72-76`).
2. The seed is pinned, `start_engaged` is set, the scenarios log, and the ESCALATE policy is stated (`:179-184`).
3. The earlier-pass row now puts the older line across the E end. This matches the model's passing case (the older line crosses at
   +236 px; worst LAY heading 29.4°, centre 19.8 px from the path, with the lever). The Risks text is corrected (`:213-215`, `:247-251`).
4. The lever uses the acceleration-limited `boost()` (`:119-124`). With it, the perpendicular arrival is 28.7° and near-perpendicular
   arrivals are at most 31.7°.
5. `lay_mine()` purges a recycled mine from every pass record (`:131-135`).

The non-blocking items taken are also correct, except the abandon guard: its new wording creates finding 15.

### Blocking

15. **The revised abandon guard aborts slow run-ins, and in the model it trips the ESCALATE policy in about 40% of seeds**
    (`3-plan.md:99-105`). This comes from my own round-1 suggestion 6 ("cover a run-in that never reaches S"), and it was a mistake.
    - With "6 s from the first tick within `commit_distance`, **run-in included**", 15 of 40 seeds of the 60 s standing scenario end with
      `abandoned_passes` > 0 (round-1 wording, after fix 1: 0 of 40).
    - Every abandon happens inside the run-in. The layer is held 158–174 px from an older line's mine and crawls at the context floor
      (0.35 × 170 ≈ 60 px/s); one trace was 3 px short of S. Most are the 4th pass, the spread-fallback pass that stacks next to an existing
      line.
    - These run-ins do finish. With no guard, over 40 seeds × 90 s (209 LAYs), the time from coming within commit distance to LAY is
      2.3 s median, 7.5 s at p90 and 15.0 s at most. 30 LAYs need ≥ 6 s and 4 need ≥ 12 s.
    - Guard variants, standing model, 40 seeds:

      | Guard | Seeds with an abandon |
      |---|---|
      | As revised | 15 |
      | Run-in excluded from the 6 s clock, 12 s cap from the freeze still covering the run-in | 2 |
      | Run-in excluded from the 6 s clock, run-in capped at 20 s from the freeze | 0 |

    - **Fix:**
      - The 6 s clock covers only "frozen, within commit distance, run-in not started". That is the circling-R case the guard exists for.
      - The 2 × 6 s cap covers only "frozen, never within commit distance".
      - The run-in gets its own generous stall cap, or none: about 20 s from the freeze clears every run-in in the model.
    - Separately, tell the owner in the report that a run-in past an older line can crawl at about 60 px/s for 10–15 s. That is measured,
      not asserted.

16. **Yield frames tick the hand-ticked mines a variable number of extra times, so the seeded scenarios are not reproducible**
    (`3-plan.md:216-217`, `:256-257`; `bullet_pool.gd:91`).
    - `acquire()` sets `process_mode = INHERIT`, so every laid mine also runs its own `_physics_process` on the real physics steps of each
      yielded frame.
    - How many steps run depends on wall time: the hand-ticked block before the yield takes real milliseconds, so it is 0–2 steps per
      yield and varies from run to run.
    - The extra ticks move ejecting and HOMING mines (creep at 60 px/s) and advance fizzles. That shifts the hazard positions the layer
      avoids, and context steering amplifies the difference.
    - The Risks line "nothing asserted depends on a mine's exact clock" misses this. Positions move, not just clocks.
    - Determinism is what finding 2's ESCALATE policy rests on, and the harness re-runs the gate after the worker. A marginal seeded
      outcome could therefore flip between runs.
    - **Fix:** in the `mine_dropped` handler, the test calls `mine.set_physics_process(false)`, since it ticks every mine itself. This is
      not reset by `acquire()` / `reset()`, which only touch `process_mode`. The yield frames then only flush the pools' deferred
      `_recycle()`.

### Non-blocking

17. **State that every spread fallback sets `pass_spread_fallback`, at choose time as well as at the freeze** (`:75`, `:78`, `:95-98`).
    The gradual row exempts "exactly the plans with `pass_spread_fallback`". Steps 2 and 3 only say `spread_fallbacks += 1`, so the 4th
    standing pass (almost always a choose-time fallback, C within 380 px of a live centre) would fail the row. Clear the flag in
    `_enter_approach()`.
18. **Make the earlier-pass row's older line provably live** (`:213-215`).
    - Use `PLAYER`-hostility mines. An `ALL` mine is set off by the layer itself (group `enemies`), and with the lever the layer flies
      within about 3 px of mine 5.
    - If they are `placed`, their `_start_if_placed()` is deferred, so without a frame they never launch or register. The row would then
      pass with no hazard at all.
    - Launch them by hand, or yield a frame, and assert each `is_live()` and that `Hazards.around()` sees them before the run.
19. **Say u is latched once `_axis_sign()` has been re-applied on the choose tick** (`:59-62`, `:74-76`). "Later ticks: `C = P + f·…`"
    implies it, but re-evaluating the sign every tick could flip S mid-approach, and the standing row asserts R does not move.

## Round 3

VERDICT: APPROVED

This round checks only the round-2 findings against Revision 3.

- **15 (abandon guard): fixed** (`3-plan.md:102-110`).
  - There are now three separate clocks:
    - within `commit_distance` with the run-in not started, 6 s from the first such tick;
    - never within `commit_distance`, 12 s from the freeze;
    - in the run-in, 20 s from the freeze.
  - I re-ran the standing model with exactly these clocks. Over 40 seeds × 60 s, 0 seeds abandon a pass (Revision 2's wording: 15 of 40).
    Over 90 s, which no row asserts, 1 of 40 does.
  - What remains is the 6 s backstop: about 2 of 40 seeds reach it (3 of 40 over 90 s). That residual risk is already covered by the
    stated ESCALATE policy (`:193-195`), which forbids reseeding or moving a bound. The crawl note for the owner is in Risks (`:270`).
- **16 (yield-frame mine ticks): fixed** (`:189-193`, `:266-267`).
  - Calling `set_physics_process(false)` from the `mine_dropped` handler persists through `BulletPool.acquire()` (`process_mode` only) and
    `EnemyOrdnance.reset()` (which re-enables only the `ProjectileLifetime` child).
  - The direct `mine._physics_process(DT)` calls still run.
  - The lifetime child still ticks on yield frames, but its 240 s backstop cannot matter in a 60 s run.
- **17 (`pass_spread_fallback`): fixed** (`:76-77`, `:81`, `:98-101`). It is set at both choose time and at the freeze, and cleared in
  `_enter_approach()`.
- **18 (earlier-pass mines): fixed** (`:225-227`). They are `PLAYER`-hostility PROXIMITY mines launched by hand. `launch()` sets
  `_launched` and registers them at once, and `placed` is false, so the deferred setup is a no-op. The row asserts `is_live()` and that
  `Hazards.around()` sees them.
- **19 (u latched): fixed** (`:78-79`). The sign is computed only on a latch or a candidate choice.

### Non-blocking (for the implementer; no new round needed)

20. Add `pass_spread_fallback` and the within-commit clock to the explicit `_enter_approach()` clear list (`:152-153`). Today they are
    stated only in step 2 and the guard text.
21. Clear `pass_spread_fallback` when a re-latch re-chooses the candidate. A stale `true` from an earlier choice in the same APPROACH only
    exempts a plan, so it is lenient, but it should not leak.
