# t11 — The Mine Layer crosses sideways ahead of the player laying curved or zig-zag mine lines one pass at a time

**Revision 3** (answers `4-review.md` round 2: findings 15–16 blocking, 17–19 taken; Revision 2 answered round 1: findings 1–5 blocking,
6–14 taken). Builds epic plan
`docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.12 (with "For every task", §2.11, §2.17), approved. This file
does not redesign §2.12: it fixes the code shape, the details §2.12 leaves open (marked **(pinned)** with the reason) and the test
list. Where it says "§2.12", the epic plan wins. Context: `1-context.md`.

## Problem

Today (t10 shell) a Mine Layer in APPROACH flies straight at the player and never lays a mine outside a rail; in Assault it
leaves when its budget ends. After this task it flies to a point beside the player's path (or, for a standing player, between the
player and itself), turns onto the line's axis, and crosses sideways laying six mines in a zig-zag or a bow. In Open Space it then
breaks away, circles at a standoff for 5–7 s and lays the next line somewhere else, so the unsafe area grows one line at a time and
never fills the screen; at most 18 of its mines are live, the oldest fading when a 19th is laid. In Assault it lays one line across
the view and leaves sideways. A player who chases it from behind gets a mine dropped in their face every 2.5 s.

## Design

### Config (`mine_layer_config.gd`, new `@export_group("Passes")`; script defaults = §2.12's numbers, `.tres` unchanged)
`velocity_smoothing` 0.5, `frame_speed` 60, `pass_length` 600, `mine_step` 100, `mines_per_pass` 6, `zigzag_amplitude` 35, `arc_depth` 110,
`arc_chance` 0.5, `ahead_distance` 260, `fence_distance` 320, `assault_ahead` 220, `lead_horizon` 3.0, `lead_scan_cap` 6.0, `run_in` 150,
`commit_distance` 200, `path_lookahead` 60, `min_pass_separation` 380, `approach_max_seconds` 6.0, `break_speed` 260, `break_seconds` 1.2,
`standoff_range` 600, `pass_period_min` 5.0, `pass_period_max` 7.0, `tail_range` 280, `tail_cone_deg` 60, `tail_drop_cooldown` 2.5,
`view_margin` 64. All flat numbers (`test_config_instance_isolation.gd` stays green).

### `EnemyMine.is_live() -> bool` (one additive line, `enemy_mine.gd`) **(pinned)**
`return _launched and not _done and not _fizzling`. The FIFO, the spread's "pass with a live mine" and no-stacking need it; reaching
into `_done` from a brain would be worse. A recycled pooled mine reads false until its next `launch()`.

### `MineLayerBrain` (`mine_layer_brain.gd`)

```gdscript
enum Shape { ZIGZAG, ARC }
signal phase_changed(new_phase: int)          # existing
signal mine_dropped(mine: EnemyMine)          # every drop the brain makes (pass + tail); tests and t13's wake read it
const ARRIVAL_SCAN_STEP := 0.1
const ARRIVAL_BISECTIONS := 5
const REPOSITION_LEAD := 0.4                  # the Bomber's
const NO_STACK_PAD := 40.0                    # §2.12: trigger_radius + 40
const CHARGE_TIME := 0.3                      # StateLight CHARGING before each drop
const TIE_PX := 1.0                           # the frame-sign tie (§2.12)
```

**Test seams (all read-only vars unless noted):** `pass_centre`, `pass_start`, `pass_end`, `pass_run_in_point`, `pass_axis` (u),
`pass_normal` (n̂), `pass_shape`, `pass_form` (`&"lead"` / `&"fence"` / `&"assault"` **(pinned: Assault's plan is neither form)**),
`plan_frozen`, `frame_f`, `arrival_time`, `spread_fallbacks`, `fence_fallbacks`, `planned_rest_points: Array[Vector2]`,
`planned_variants: Array[int]`, `drops_this_pass`, `skipped_this_pass`, `passes_started`, `tail_drops`, `run_in_active`, `abandoned_passes`;
`pass_spread_fallback`; methods `flight_time(point)`, `freeze_plan()`, `plan_pass(p, v_bar, earlier)`, `lead_run_in_point(p, v_bar, t)`, `live_mine_count()`,
`live_mines()`, `live_pass_centres()`, `smoothed_velocity()`, `path_points()`, `lay_mine(variant, rest_point)`.

**Tick order** (`tick(delta)`): `_start()` once → `_phase_time += delta` → v̄ update (the Bomber's `_update_prediction()`: seeded from the
first sample, then `alpha = 1 − exp(−delta / velocity_smoothing)`) → budget (`update()`; expired: LAY → `_disengage_pending`, any other
non-DISENGAGE phase → DISENGAGE) → tail drop → phase dispatch. `_start()` calls `_enter_approach()` (no emit), as the Bomber does.

**Frame (`_latch_frame(p)`).** Called on APPROACH's first plan and on every moving/standing switch before the freeze (`moving =
|v̄| ≥ frame_speed`, compared against `_frame_moving`). Standing: `frame_f = (layer − P).normalized()` (fallback: the layer's heading
when coincident). Moving: `frame_f = v̄.normalized()`, re-read every tick after (sign kept). Sign: `u0 = f.orthogonal()`; `d =
u0·(layer − P)`; `|d| ≥ TIE_PX` → `sign = −signf(d)` (so `(−u)·(layer − P) > 0`); else `dv = u0·own_velocity`, `|dv| ≥ 1e-3` →
`sign = −signf(dv)`; else `+1`. `u = f.orthogonal()·sign`. A re-latch also re-chooses the candidate (below). **(Revision 2, review
finding 1)** The sign rule is a function `_axis_sign(f, p)` and is **re-applied to the rotated f** whenever the fence spread rotates the
frame (step 2): after a non-zero rotation `orth(f_rot)·(layer − P)` is no longer a tie, so S (and R) stay on the layer's side as §2.12
requires; rotation 0 keeps the velocity tie. The fence fallback does the same.

**Geometry (`_set_plan(c, u, n)`)** builds S, E, R, the rest points and the path from C, u, n̂, `pass_shape`:
`S = C − u·L/2`, `E = C + u·L/2`, `R = S − u·run_in`; mine k at `C + u·x_k + n̂·y_k`, `x_k = (k − (n−1)/2)·mine_step`, ZIGZAG `y_k = ±A`
(+ for even k), ARC `y_k = 4·arc_depth·t(1−t)`, `t = k/(n−1)`. Path = `[S, m0 … m5, E]` and its cumulative coordinates; each mine's
coordinate is its vertex's. n̂ = the unit normal of u with `n̂·(P − C) > 0`; tie (`< 1e-3`) → `−f` (Open Space) / `+y` (Assault).

**Open Space plan (`plan_pass(p, v_bar, earlier)`)** — one planning step, exactly what a pre-freeze APPROACH tick does (the tick calls
it with `TargetInfo.player().position`, `_v_bar`, `live_pass_centres()`). No-op once frozen.
1. First plan of this APPROACH, or a moving/standing switch → `_latch_frame(p)` and `_choose_candidate = true`.
2. **Standing → fence form** (`_plan_fence`): `C0 = P + f·fence_distance`. Candidate rotations `[0, +θ, −θ, +2θ, −2θ]`,
   `θ = 2·asin(min(1, (min_pass_separation + 10) / (2·|C0 − P|)))`; on `_choose_candidate` the first rotation whose `C0.rotated about P`
   is ≥ `min_pass_separation` from every `earlier` centre is latched, and **f is rotated by it** (`frame_f` reads the rotated f) and u is
   rebuilt from the rotated f with `_axis_sign()` re-applied (above); none legal → rotation 0, `spread_fallbacks += 1` **and `pass_spread_fallback = true`** (every spread fallback sets the flag, at choose
   time and at the freeze; `_enter_approach()` clears it; review finding 17), verbose line. Later ticks: `C = P + f·fence_distance` with
   the latched (rotated) f **and the latched u: the sign is computed only when the frame is latched or a candidate is chosen, never per
   tick, so S cannot flip mid-approach** (review finding 19).
3. **Moving → lead form** (`_plan_lead`): on `_choose_candidate`, for `shift` in `[0, min_pass_separation + 10]`: `_scan(shift)`; the first
   feasible and legal one is latched; feasible but none legal → the first feasible, `spread_fallbacks += 1` and `pass_spread_fallback = true`; **none feasible → fence
   fallback**: `_latch_frame` as standing (f = P → layer), `_plan_fence` with its spread, `plan_frozen = true`, `fence_fallbacks += 1`,
   `pass_form = &"fence"`, verbose line. Later ticks: `_scan(latched shift)`; infeasible → **lost-feasibility guard**: keep the last plan,
   `plan_frozen = true` (no counter moves).
4. `_scan(shift)`: `t = 0, 0.1, …` while `t ≤ lead_scan_cap + 1e-6`; `R(t) = lead_run_in_point(p, v_bar, t)` with
   `t_lead = t + run_in / lay_speed + min((L/2) / lay_speed + mine_arm_delay, lead_horizon)` and `C = P + v̄·t_lead + f·(ahead_distance + shift)`;
   first `flight_time(R(t)) ≤ t` → bisect `ARRIVAL_BISECTIONS` times between the previous `t` and it (none when `t = 0`); `arrival_time = hi`.
5. `flight_time(R) = |R − pos| / max_speed + (max_speed − v0)² / (2·acceleration·max_speed)`, `v0 = clamp(own_velocity·unit(R − pos), 0,
   max_speed)` (`mover.own_velocity()`).

**Assault plan** (same entry point, `pass_form = &"assault"`): no scan, no fallback. u = ±x latched at APPROACH start with the same sign
rule against `(layer − P)`, C = `(P.x, P.y − assault_ahead)` re-read every tick until frozen, then clamped so C, S and E lie in
`EnemyWorld.view_rect(tree).grow(−(view_margin + max(zigzag_amplitude, arc_depth)))`: `C.x ∈ [rect.x + L/2, rect.end.x − L/2]`,
`C.y ∈ [rect.y, rect.end.y]` (a 932 × 372 box for a 600 px line, so S and E are inside it). n̂ = ±y toward P.

**APPROACH tick:**
- `_approach_time += delta`. Not frozen → `plan_pass(...)`; then `dist(pos, R) ≤ commit_distance` → `plan_frozen = true`.
- **Freeze-time spread re-check (Revision 2, review finding 7):** on the tick a plan freezes (commit distance, fallback or guard), if its
  C is < `min_pass_separation` from any `earlier` centre and the plan has not already counted a spread fallback, `spread_fallbacks += 1`
  and `pass_spread_fallback = true` (a lead C keeps moving after the candidate is chosen, so legality at the choice does not imply it at
  the freeze). Nothing is re-chosen. The gradual row exempts exactly the plans with `pass_spread_fallback`.
- Open Space backstop: not frozen and `_approach_time ≥ approach_max_seconds` → fence fallback (as step 3). **(pinned, addition;
  Revisions 2–3, review findings 6 and 15)** Abandon guard, Open Space only, three separate clocks, any one of which abandons the pass
  (`abandoned_passes += 1`, verbose line; the layer goes to REPOSITION):
  - frozen, **within `commit_distance` of R** (clock from the first such tick) and the run-in **not started** for `approach_max_seconds`
    (the circling-R case the guard exists for);
  - frozen and **never within `commit_distance`** for `2 × approach_max_seconds` from the freeze;
  - frozen and **in the run-in** for `RUN_IN_STALL_SECONDS` 20 s from the freeze (a const). A run-in past an older line crawls at the
    context floor (≈ 0.35 × 170 ≈ 60 px/s): the reviewer's model, 209 LAYs, measured 2.3 s median, 7.5 s p90 and 15.0 s max from commit
    distance to LAY, so a 6 s run-in clock aborted healthy run-ins in 15 of 40 seeds; 20 s aborted none. Told to the owner, not asserted. §2.12 has no rule for a frozen R the layer cannot reach (an R inside an older line's avoidance footprint
  holds an avoidance-0.8 ship ≈ 145 px off it for ever); without one it would circle R. The seeded standing scenario asserts
  `abandoned_passes == 0`, so the guard cannot hide a regression there.
- Seek: not in run-in → `mover.seek(R, max_speed)`; `dist(pos, R) ≤ path_lookahead` (after the freeze check, so frozen) → `run_in_active`.
- Run-in: `s = (pos − R)·u`; aim `R + u·(s + path_lookahead)`; `request_velocity(unit(aim − pos)·lay_speed)`. Track `_s_from_S =
  (pos − S)·u`; previous `< 0` and now `≥ 0` → `enter_phase(LAY)` and `_tick_lay()` the same tick.

**LAY** (`_enter_lay`): `passes_started += 1`, a pass record `{centre, mines: []}` is appended to `_passes`, `drops_this_pass = 0`,
`skipped_this_pass = 0`, the variants are drawn (one per rest point from the flat `w_*` weights by `rng`; a second HOMING draw is redrawn
with the HOMING weight 0), light ARMED. Each tick:
- centre coordinate `s_c` and Dispenser coordinate `s_d` = closest-point coordinates on the path (all 7 segments searched; cheap).
- while `_next < n` and `s_d ≥ coord_k + eject_lead` (`mine_eject_speed·mine_eject_time/2` = 18): drop k (below).
- light: CHARGING while `coord_next + eject_lead − s_d ≤ lay_speed·CHARGE_TIME`, else ARMED.
- `s_c ≥ path_length` or `_phase_time ≥ path_length·1.2/lay_speed + 0.5` → drop the rest (an ARC pass's mine 5 always goes here: the plus rule needs the centre at 662.6 on a 656.6 path; review
  finding 13, recorded in DECISIONS), then `_disengage_pending` or Assault →
  DISENGAGE, Open Space → BREAK_OFF.
- motion: aim at the path point `s_c + path_lookahead` (past E: along u); `request_velocity(unit(aim − pos)·lay_speed)`. **Lever (§2.12,
  pre-approved), in its acceleration-limited form (Revision 2, review finding 4):** if the "stays on its path" row fails because of an
  older pass's mines, LAY instead computes `v = mover.own_velocity().move_toward(unit(aim − pos)·lay_speed, config.acceleration·delta)`
  and calls `mover.boost(v.normalized(), v.length(), delta)`: still `boost()` (avoidance skipped, the committed-run bypass), but the
  velocity turns at the mover's own acceleration, so the speed is not exactly `lay_speed` while it turns. A raw `boost(dir, lay_speed,
  delta)` removes the acceleration limit and puts the perpendicular arrival at 39.8° of the 40° bound (reviewer model). Recorded if used.
- Path coordinates use `Geometry2D.get_closest_point_to_segment` (the `fighter_brain.gd` idiom).
- **Drop k:** Open Space no-stacking: if any live mine that is not one of this pass's own, found through `Hazards.around(rest, 200)`
  (kind `&"mine"`) **or** this layer's FIFO, has its centre within its own `trigger_radius + NO_STACK_PAD` of the rest point → skip
  (`skipped_this_pass += 1`). **(pinned: checked at drop time, against the live set then; this pass's own mines are exempt, because ARC
  chords are 100–106 < 120.)** Otherwise `lay_mine(variant_k, rest_k)`.

**`lay_mine(variant, rest)`** (pass and tail drops): prune the FIFO (`is_instance_valid` and `is_live()`); while `count ≥ cap`
(`max_live_mines`, Assault `assault_max_live_mines`) `retire()` the oldest and drop it; `actor.drop_mine(variant, rest)`; on a mine, remove
the same object from the FIFO **and from every pass record** (a recycled pooled mine: `BulletPool.acquire()` is LIFO, so a retired mine
of pass 1 comes back in pass 4 and would otherwise make pass 1 read live again; Revision 2, review finding 5), append it, add it to the
current pass record if LAY, `drops_this_pass += 1` (LAY), emit `mine_dropped(mine)`. Returns the mine or null.

**BREAK_OFF** (Open Space): entry sets `mover.max_speed = maxf(max_speed, break_speed)` **(pinned: the mover caps a request at
`max_speed` 240, so 260 would otherwise never be reached)** and `side` so that `(away.orthogonal()·side)·u > 0` (lateral away from the
fresh line, which lies along −u from E). Each tick `mover.break_contact(P, v̄, side, break_speed)`; after `break_seconds` → REPOSITION.

**REPOSITION** (Open Space): entry: `mover.max_speed = max_speed`, `_reposition_time = rng.randf_range(pass_period_min, pass_period_max)`,
`_orbit_sign = ±1` from `rng`. Tick: the Bomber's orbit (`angle = (pos − P).angle() + sign·REPOSITION_LEAD`, `Steering.orbit(...,
standoff_range, ...)`, `turn_toward` at `max_turn_rate`). After the period → APPROACH.

**APPROACH entry** (`_enter_approach`): `mover.max_speed = config.max_speed` (when it is not the exit), clear the plan (`plan_frozen =
false`, `_frame_latched = false`, `run_in_active = false`, `_approach_time = 0`), draw `pass_shape` (`rng.randf() < arc_chance` → ARC).

**DISENGAGE:** unchanged entry (`release_constraint()`, `max_speed = exit_speed`). Exit direction: `pass_axis` when `passes_started > 0`
(continuing off the far side of the line), else the heading on entry (the shell's rule, which `SpecialistExitProbe` measures).

**Tail drop** (APPROACH, BREAK_OFF, REPOSITION, DISENGAGE; never LAY, IDLE/NOTICING/RETURNING): `_tail_clock += delta`; player within
`tail_range` and `angle(stern, P − dispenser) ≤ tail_cone_deg / 2` and `_tail_clock ≥ tail_drop_cooldown` → `lay_mine(PROXIMITY,
dispenser.global_position)` (no eject), `_tail_clock = 0`, `tail_drops += 1`. `_tail_clock` starts at the cooldown, so the first chase
drop is immediate. **(pinned: "the rear 60° cone" is ±30° about the stern, the nose direction `rotation + sprite_forward_angle`
reversed; DISENGAGE counts as engaged.)**

**Facing** is the mover's (velocity heading, `sprite_forward_angle` PI/2). **`accepts_tow()`** unchanged (false only in LAY).

### Existing row whose premise changes
`test_enemy_dual_mode.gd::test_mine_layer_approach_closes_on_the_player` asserts that one second of APPROACH closes the gap to the
**player**. §2.12 makes APPROACH seek the run-in point R (450 px beside the line's centre), so from (640, 60) the layer flies away from a
player at (640, 360). The row becomes `test_mine_layer_approach_closes_on_its_run_in_point`: the gap to `pass_run_in_point` closes by
> 60 px in 1 s, phase still APPROACH, and in Assault the layer is still inside the soft band. Recorded in DECISIONS.

## Build sequence
1. Config fields + `EnemyMine.is_live()`; the geometry (`_set_plan`, rest points, path, coordinates) and the pure Open Space / Assault
   planner (`plan_pass`, `_scan`, `flight_time`, fence spread, fallback, guard). Rows: geometry, scan, spread, guard, fallback (pure).
2. APPROACH (freeze, seek, run-in, backstops) and LAY (drops, light, stall, no-stacking, FIFO / cap / `lay_mine`). Rows: standing, lead,
   fence fallback, run-in, sideways, path, placement, cap.
3. BREAK_OFF, REPOSITION, DISENGAGE along u, budget deferral, tail drop. Rows: Assault one pass, deferral, tail, tow.
4. The two 60 s scenarios (gradual, hazard-aware). Lever if the path row needs it.
5. Dual-mode row update, ENEMY.md, DECISIONS "Built in t11", `tests/README.md` Gate time; invoke the `updating-project-docs` skill (a
   mechanic was added; the bulk of the roster docs stays with t16); `verify.sh`, `check-test-leaks.sh`, gate time (also measured early,
   after step 2).

## Test plan (`tests/integration/test_mine_layer.gd`, new section "Passes"; hand-ticked with the existing `_tick()`; the test also
ticks every acquired mine with `mine._physics_process(DT)` so ejects and fizzles run; numbers read from `layer.config` / scenes)

**Determinism (Revision 2, review finding 2).** Every row whose outcome depends on a draw (shape, variants, REPOSITION period, orbit
sign) spawns its layer with a pinned `Brain.rng_seed` set before `add_child` (one file constant `SEED`, chosen before the first run and
never changed to turn a row green). The helpers also set `brain.start_engaged = true` (review finding 11), so t12's hub idle does not
put these Open Space layers into IDLE. **Every mine the brain lays has `set_physics_process(false)` called on it by the test, from a
`mine_dropped` handler (review finding 16):** the test ticks every mine itself, and `acquire()` / `reset()` touch only `process_mode`, so
the frames the scenarios yield (to flush the pools' deferred `_recycle()`) add no wall-time-dependent mine ticks and a seeded run is
reproducible. The scenarios log (`gut.p`) every approach's freeze time, form and the counters. **Policy:** if
the seeded standing scenario reaches the 6 s backstop or the abandon guard, the task ends `Result: ESCALATE` with that log; it does not
reseed and does not move a bound.

Shapes are forced through the instance's private config (`layer.config.arc_chance = 0.0 / 1.0`, safe: `privatise()`).

- `test_zigzag_rest_points_alternate_35_on_122_chords(mode)` — both modes: consecutive spacing 122.1 ± 2, `(rest − C)·n̂` alternates sign
  with |y| = 35 ± 1, axis coordinates step 100 ± 1.
- `test_arc_rest_points_follow_the_formula_on_the_players_side(mode)` — each within 2 px of `C + u·x_k + n̂·y_k`, offsets measured along
  the test's own P-ward normal ≥ −0.5 (and `pass_normal·(P − C) > 0`, so a flipped n̂ fails), spacing in [98, 125].
- `test_every_mine_lands_within_4_px_of_its_planned_point(mode)` — a full pass from a natural approach; each dropped mine's position at
  the end of its eject (drop + `eject_time` + 2 ticks) vs its planned point; exactly 6 drops (nothing to skip with no earlier pass).
- `test_assault_mines_lie_inside_the_view_on_a_horizontal_axis` — |u.y| < 0.01, every rest point and every laid mine inside
  `view_rect().grow(−64)`; boundary: a player at the view's top edge clamps C (`C.y == rect.y`) and still passes.
- `test_a_standing_player_gets_a_fence_plan_frozen_from_a_latched_frame(bearing)` — 0 / 90 / 180°, layer at rest 600 px away: frozen
  ≤ 2.5 s, `fence_fallbacks` 0, `pass_form == &"fence"`, `frame_f` (± 0.001) and `pass_run_in_point` (± 1 px) equal from APPROACH start to the
  freeze, C on the stub→layer segment 320 ± 2 px from the stub.
- `test_a_moving_player_gets_a_lead_plan_on_its_track` — 100 px/s stub, layer at rest 600 px ahead: frozen ≤ 2.5 s, `fence_fallbacks` 0,
  lead, C lateral ≤ 2 px from the track, C > 80 px ahead of the live stub when mine 2 **and** mine 3 arm; abeam (90°): lead, frozen ≤ 5.0 s.
- `test_the_arrival_scan_finds_the_earliest_feasible_time` — pure: `flight_time(R(T)) ≤ T + 0.001`, `flight_time(R(T − 0.004)) > T − 0.004`.
- `test_lost_feasibility_freezes_the_last_lead_plan` — pure: plan, teleport the layer 1500 px behind the stub, plan again → same centre,
  frozen, lead, `fence_fallbacks` 0.
- `test_a_reversing_player_does_not_move_a_frozen_line` — stub reverses at LAY entry; rest points unchanged from the freeze and every
  laid mine within 4 px of them.
- `test_a_player_too_fast_to_lead_gets_a_frozen_fence_on_the_first_tick` — layer at rest 600 px behind a 220 px/s stub: after tick 1
  frozen fence, `fence_fallbacks` 1, C on the segment stub(tick 1)→layer 320 ± 2 px from it; LAY reached. Control: the lead row's setup →
  `fence_fallbacks` 0.
- `test_the_run_in_starts_within_60_px_and_lay_starts_on_the_crossing` — per tick (positions as the brain saw them): `run_in_active` first
  true on the first tick ≤ 60 px from R; LAY on the tick `(pos − S)·u` goes < 0 → ≥ 0 and never earlier; no `mine_dropped` before LAY.
- `test_lay_flies_sideways_and_on_the_path(arrival)` — "aligned" (on the axis 100 px before R moving along u at 240) and "perpendicular"
  (300 px from R along n̂, moving toward R at 240), both `freeze_plan()`ed: from LAY start to its end, velocity within 40° of ±u and centre
  ≤ 40 px from the polyline; and "earlier pass" (the aligned arrival with a live ZIGZAG line of real PROXIMITY mines centred 380 px away
  on the fence spread's rotation **toward the E end**, so the older line crosses the new one near its mine 5 / E end, ≈ 236 px from C;
  Revision 2, review finding 3) — the same bounds. The older mines are `PLAYER`-hostility PROXIMITY mines (an `ALL` mine would be set off
  by the layer itself), launched by hand at speed 0 (not `placed`: that setup is deferred and needs a frame), and the row first asserts
  each `is_live()` and that `Hazards.around()` reports every one of them (review finding 18). Lever (accel-limited form) applied only if this row needs it.
- `test_open_space_passes_are_gradual(scenario)` — "standing" and "circling" (120 px/s on a 700 px circle), 60 s each, computed once per
  file (member cache) and yielding one frame every 60 ticks so the pools' deferred recycles run: LAY end → next LAY start ≥ 6.2 s; ≤ 6
  drops a pass; for every pass that did not take the spread fallback, its frozen C ≥ 380 px from every earlier pass centre live at its
  freeze (plans with `pass_spread_fallback` exempt); live count ≤ 18 throughout; ≥ 3 passes (anti-inert); standing: `fence_fallbacks` 0
  and `abandoned_passes` 0. Counts and per-approach freeze times logged.
- `test_the_layer_keeps_clear_of_older_lines_while_approaching_and_repositioning` — from the standing scenario: in APPROACH (run-in
  included), REPOSITION, DISENGAGE, closest approach to every live mine of every pass other than the one currently planned > 100 px
  (LAY / BREAK_OFF ticks and tail mines excluded); and, so the row is not vacuous, that closest approach was inside the avoidance reach
  (< `trigger_radius + hazard_pad + hazard_margin + 0.6·max_speed` = 308 px) at least once in those phases (review finding 10). The control
  (`registers_hazard = false` mines) is not built (§2.12: "logged, not asserted"); **(pinned: dropped to stay in the gate allotment — it
  asserts nothing; the reach assertion stands in for it.)**
- `test_the_pure_plan_spread_rows` — fence: earlier centres at 0°, ±75.1° on the 320 circle → C at +150.2° (± 1 px), ≥ 380 from all three,
  `frame_f` rotated by +150.2° (± 0.01 rad), `spread_fallbacks` 0; fence boundary: earlier at 0°, ±75.1°, ±150.2° → C at 0° and
  `spread_fallbacks` 1; lead: an earlier centre at the unshifted C → C shifted ≥ 300 px further along f, lateral ≤ 2 px, ≥ 380 from it,
  `spread_fallbacks` 0.
- `test_the_live_cap_retires_the_oldest` — 18 `lay_mine` calls → 18 live; the 19th → `live_mine_count()` 18, the first mine
  `is_fizzling()`, the 19th live; Assault cap 8 the same way.
- `test_assault_lays_one_pass_then_leaves_sideways` — a natural Assault pass: `passes_started` 1, 6 drops, DISENGAGE after LAY with
  `constraint_released()` and velocity along `pass_axis` (dot > 0.9); no second LAY before it is freed.
- `test_an_assault_budget_expiring_mid_lay_lets_the_pass_finish` — `engage_seconds` set (private config) to 1 s after the LAY start of the
  same seeded run: all 6 dropped, LAY lasted ≤ the stall guard, then DISENGAGE with `constraint_released()`.
- `test_a_chasing_player_gets_a_tail_mine` — stub kept 200 px behind the stern: a mine within one tick, still one at 2.5 s − 1 tick, two by
  2.5 s + 1 tick, laid at the Dispenser; control: 200 px in front → none in 2.6 s; LAY never tail-drops (stub behind during a LAY → only pass
  mines).
- `test_accepts_tow_is_false_in_lay_only` (existing) gains: true in REPOSITION and BREAK_OFF.
- `test_enemy_dual_mode.gd::test_mine_layer_approach_closes_on_its_run_in_point(mode)` (renamed row, above).

Boundary cases: the TIE sign rule (standing → velocity side, zero → +1) is exercised by the bearing rows; the fence no-legal-candidate
row; the 19th drop; the Assault clamp at the view edge; the S-crossing tick (projection exactly 0 counts as crossed).

## Risks
- **Older lines near the run-in or the line's ends** (adjacent fence lines at ±75.1° intersect ≈ 236–245 px from their centres, right
  at mines 0 / 5): avoidance can push the run-in off the axis and LAY off its path. The lever covers an older line across the **E end**
  only. An older line across the **S end / run-in** deflects the run-in (APPROACH, which the lever does not and must not cover: the
  hazard-aware row asserts > 100 px there), so LAY then starts off the path; that case is measured by the scenarios (logged), not
  asserted. The abandon guard covers an unreachable R; no-stacking covers mines on mines.
- **The 4th pass of a standing scenario almost always takes the spread fallback** (three live lines block all five candidates; reviewer
  model). Expected, logged, and told to the owner in the report and DECISIONS.
- **Gate time** (4.5 s): two 60 s scenarios with up to 18 ticked mines each. If over, tick only mines that still move or fade (eject,
  fizzle, HOMING), a behaviour-identical test-side saving.
- **Pool recycling** in hand-ticked runs is deferred; the scenarios yield a frame every second. Laid mines have their own physics
  processing switched off by the test (finding 16), so those frames only flush the recycles.
- **A run-in past an older line can crawl at ≈ 60 px/s for 10–15 s** (reviewer model). Measured, not asserted; told to the owner.

## Out of scope
Hub idle / `start_engaged` / NOTICING (t12), hatch and wake art (t13), hub and level-1 placement (t14/t15), docs beyond ENEMY.md and the
phase record (t16).

## As built (2026-10-27)
- Built as planned. The LAY lever **was needed** and is applied in its acceleration-limited form: `test_lay_flies_sideways_and_on_the_path` "earlier
  pass" measured 85.5° / 178.2 px with `request_velocity()` and 32.7° / 11.4 px with the lever (the same as the aligned arrival with no older line).
- Small addition: the tick a LAY ends also ticks the phase it hands over to (BREAK_OFF / DISENGAGE), as the APPROACH → LAY handover already did, so no
  tick passes with no request.
- Scenario log (seed 4242): standing 4 passes, 0 fence / 0 spread fallbacks, 0 abandoned, closest approach to older lines 151 px; circling 3 passes,
  3 fence fallbacks, 1 abandoned. The Risks entry "the 4th standing pass almost always takes the spread fallback" did not show with this seed.
- Gate time: GUT 207.67 → 209.85 s (+2.18 s of the 4.5 s allotment). Recorded in DECISIONS (Phase 7, "Built in t11") and `tests/README.md` → Gate time.
