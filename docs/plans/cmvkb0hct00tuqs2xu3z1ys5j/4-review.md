## Round 1

VERDICT: CHANGES_REQUESTED

The design follows epic §2.6 faithfully and every number checks out against the real code. One blocking gap remains: no
test row proves `_step_disruption()` is actually called from either ship's `_physics_process`. Without that row, a build
where the clock never runs passes every planned row, and in play every disruption would last forever.

### What I verified (no action needed)

- **Excess-rule arithmetic.**
  - Open Space Shift boost: 420 + 280 × 0.4 = 532.
  - Boost Drive, Open Space: 420 + 1080 × 0.4 = 852 at the start, 420 + 80 × 0.4 = 452 at the end.
  - Boost Drive, Assault: 360 + 1140 × 0.4 = 816.
  - Dash: 180 + 170 × 0.4 = 248.
  - Warp: 120 × 0.4 = 48.
  - The inputs match the code: `player_ship.gd:10,18` (`max_speed` 420, `boost_exit_speed` 700), `engine_boost_module.gd:11-12` (1500 / 500), `dash_state.gd:7,24-25` (120 / 350 / 180) and `move_state.gd:20` (360). `player_fighter.tscn:387-392` does not override `move_speed`.
- **Drive tail tick count** (`engine_boost_module.gd:90-112`). The speed is computed before `_time_left -= delta`. A 0.55 s burst therefore ends on tick 33, at 452 + 400 × (0.01667 / 0.55)² ≈ 452.37, or on tick 34 at ≈ 452.0 if float drift leaves a sliver. Both are inside 452 ± 1, and the burst minimum is ≥ 420.
- **Clock row.** 2.5 s is 150 ticks. After 149 ticks 0.0167 s is left, so efficiency is still 0.4. "1.0 by tick 151" correctly absorbs float drift on tick 150.
- **Never-stacked rows.**
  - `(0.6, 1.0)` then `(0.3, 3.0)` gives 0.4 until 3.0 s. The product would be 0.28, so this row discriminates.
  - `(0.3, 1.0)` then `(0.6, 0.5)` is still live at 0.9 s, which proves a stronger but shorter disruption does not shorten the time.
- **Boundary at 0.85.** In doubles, 1 − 0.85 = 0.15000000000000002, which is ≥ the literal 0.15. The inclusive-floor row passes, but on the safe side of float rounding (see note N3).
- **Bit-identical at 1.0.**
  - `disrupted_speed()` short-circuits at efficiency ≥ 1.0, so `_boost_speed()`, the dash speed and the Drive's `_start_speed` / `_end_speed` all equal today's exports exactly. `120 * 1.0` is exact.
  - No test touches `_BOOST_SPEED`, `_BOOST_END_SPEED` or `_BOOST_DURATION` (I grepped the whole repo; only `engine_boost_module.gd` itself does), so reading the Drive speeds at activation breaks nothing.
  - `test_ram_corvette.gd:495-504` and `test_open_space_boost_wiring.gd:155-166` use `EngineBoostModule` only through `_damage_nearby_enemies` / `engine_boost_active`, which the plan does not touch.
  - `test_player_hazards.gd:203,305-315` (boost and dash × hazard factor) keep their values at efficiency 1.0.
- **Branch structure.** In `player_ship.gd:409-421`, the `elif` binds to `if drive != null:`. A refused Drive press therefore never falls into the default branch, as the plan claims.
- **Check before spend.** The efficiency term sits before `drive.can_activate()` and `try_spend_tank()` in the Drive branch, and before the meter check in the default press.
- **Sustain-cut row.** `BoostMeter.drain()` sets `_delay_left` (`boost_meter.gd:104`), and `step()` does not recharge during that pause. So "`charges` unchanged on the cut tick" really can fail if the cut tick still drains.
- **Dash refusal.**
  - Placing the refusal before the warp branch (`dash_state.gd:49`) refuses both the roll and the warp, as owner question 5 requires.
  - `state_transition.emit(transition_state)` matches the cooldown refusal (`dash_state.gd:53-56`). `transition_state` is `../MoveState` (`player_fighter.tscn:378`), and `change_state` ignores a same-state emit (`state_machine.gd:24`).
  - The `_trace` it reuses is already gated on `OS.is_stdout_verbose()`.
- **Conventions.**
  - No new `Timer`.
  - The signal is declared with one arg. `test_signal_emit_arity.gd` counts the args of `emit(boost_efficiency())` depth-aware (l.113-146), so the nested call is counted correctly.
  - The ring writes only its own `rotation`. `test_ship_rotation_single_writer.gd` sweeps `global/ship_modules/` only.
  - No PNG.
- **Name collisions.** `PlayerBase` subclasses are `AssaultPlayer`, `OpenSpacePlayerShip` and `tests/helpers/player_stub.gd`. None of them defines `cruise_speed`, `boost_efficiency` or `disrupted_speed`. The `cruise_speed()` in `ram_corvette_brain.gd:253` is on an `EnemyBrain`, so it does not collide.
- **`disrupted_speed()`.** It is a justified single implementation of the excess rule, not a redesign, and it is logged for DECISIONS.

### Blocking

**B1. There is no wiring row for `_step_disruption()` on either ship** (plan l.43, l.75 and test plan l.101-107).
- Every clock, signal and readability row drives `_step_disruption(D)` by hand on a ship with physics off.
- If the call is never added to `OpenSpacePlayerShip._physics_process` (`player_ship.gd:202`) or `AssaultPlayer._physics_process` (`player_fighter.gd:72`), or is placed after the dialog / knockback early returns (`player_fighter.gd:73-81`), every planned row still passes.
- In play, a disruption would then never end. A 0.9 pulse would refuse every boost, dash and warp for the rest of the scene, and the ring and the violet bar would never clear.
- This is exactly the "anti-inert" failure CLAUDE.md calls out for `ShipTurnController`.
- The plan also claims the Assault clock "runs in a dialog too" (l.75), but no row tests it.

Add to `test_player_boost_disruption.gd`:
- **Open Space wiring.** `apply_boost_disruption(0.6, 0.1)`, then call `ship._physics_process(D)` directly (physics stays off) 7 times. Efficiency must be 1.0, the ring must be hidden, and `[1.0]` must have been emitted.
- **Assault wiring.** The same on `fighter._physics_process(D)`.
- **Assault in dialog.** Repeat the Assault wiring with `DialogPlayer.is_active = true` (reset it in `after_each`, as `test_player_hazards.gd:38-41` does). It must also end.
- **Knockback (optional).** Repeat with an active knockback (`apply_knockback(Vector2(500, 0))`). This pins "first, before the early returns".

These rows cost a few milliseconds and fit the 1.5 s allotment.

### Non-blocking notes

- **N1. Wrong line numbers in `1-context.md`.** It cites `_step_boost` l.347-435, the Drive branch l.375-383, the default press l.388-401 and the sustain l.408-421. In `player_ship.gd` today these are l.380-466, l.408-416, l.421-433 and l.440-454. The other references are correct.
- **N2. Sustain-cut row: assert the direction, not the whole vector.** On the cut tick `_boosting` goes false inside the sustain, so the `not _boosting` branch (`player_ship.gd:456-466`) decays the ceiling by 400 × D and clamps 700 → 693.3, or 532 → 525.3 when disrupted. The row should assert that the velocity direction is unchanged (not re-aimed along the turned nose) and that its magnitude is ≤ the pre-cut speed. Asserting `velocity == before` would fail on a correct build.
- **N3. Pair the floor boundary.** 0.85 passes only because 1 − 0.85 rounds up to 0.15000000000000002. Pair it with a just-below row (0.86 → efficiency 0.14 → refused), so the boundary is pinned from both sides rather than by 0.9 alone. Compare emitted values (0.4, 0.1) with `assert_almost_eq`, since 1 − 0.9 = 0.09999999999999998.
- **N4. Assert `_boost_hold_left == 0.0` after a refused default press.** This matches `test_a_boost_refused_by_a_module_leaves_no_hold_window_behind` (`test_open_space_boost_verb.gd:326`). A refusal that leaked a hold window would block the first press after the disruption ends.
- **N5. Test the bar's flicker reset.** `BoostBar._process` never runs in a hand-ticked test, so a bar left dim after a disruption would go unseen. Call `bar._process(0.05)` while disrupted, then end the disruption, and assert `bar.modulate.a == 1.0`. Prefer `set_process(true/false)` from the handler over an always-on `_process` with an early return. `boost_bar.gd` has no `_process` today.
- **N6. Name all three existing files the gate must keep green.** The "existing rows pass unchanged" bullet (l.125) should also name `test_open_space_boost_wiring.gd`, which holds the module-precedence / no-charge row (l.155-166) the acceptance criteria refer to.
- **N7. Measure gate time before as well as after.** Build step 5 says "Gate-time after", but the epic's "For every task" and `tests/README.md` → Gate time require a before and an after `scripts/gate-time.sh` measurement, both recorded in the README row.

## Round 2

VERDICT: APPROVED

B1 is resolved, and N1–N4, N6 and N7 are resolved. N5 is only half resolved: its assertion is vacuous as written (R2-N1
below), but it does not block. Nothing in Revision 1 introduces a new risk to existing rows. I checked against the code
as it is today, and against the draft `tests/integration/test_player_boost_disruption.gd`, which already contains the B1
rows (l.171-196).

### B1: the clock is wired (plan l.108-110), resolved

**Open Space row, feasible headless with physics off.**
- `OpenSpacePlayerShip._physics_process` (`player_ship.gd:202-219`) has no early return, so it reaches
  `_step_disruption(delta)` wherever in the body it is placed.
- Everything else it runs is safe when called by hand on a ship in the tree:
  - `_handle_rotation` reads `get_global_mouse_position()` (headless returns a fixed point) and steps `_turn`.
  - `_handle_thrust` reads `Input`; headless it returns false.
  - `move_and_slide()` has zero velocity.
  - `_update_camera_feel` is null-guarded at each step (l.574-584).
- No existing test calls this ship's `_physics_process` by hand. The enemy precedents (`test_support_ship.gd:61`,
  `specialist_exit_probe.gd:140`) show the same call shape working.
- On a build without the call, efficiency stays at 0.4 forever and draft l.179 fails.
- The 3-tick "still 0.4" sanity row (draft l.174-176) also rejects an implementation that ends the disruption on any call.

**Assault rows, feasible.**
- `test_player_hazards.gd:224-271` already drives `f._physics_process(D)` by hand on a physics-off fighter. That includes
  the dialog row (l.250-262) and the knockback row (l.265-271), so the harness is proven.
- **Dialog.** With `DialogPlayer.is_active = true`, `player_fighter.gd:73-76` returns on the first line. A call placed
  after it never runs in 7 ticks, so draft l.188 fails. `after_each` resets the flag (draft l.45).
- **Knockback.**
  - `_KNOCKBACK_DECAY` is 1200 px/s² (`player_base.gd:53`, `move_toward` at l.148). The draft's 5000 px/s impulse
    therefore stays active for about 250 ticks; even 500 px/s would last about 25.
  - The 7-tick window is fully inside the knockback, and the draft asserts `is_knockback_active()` as a precondition
    (l.195).
  - A call placed after `player_fighter.gd:79-81` fails l.196.
  - `apply_knockback_motion` clamps x to 1380, so the large impulse is harmless.
- **Tick count.** 0.1 s is 6 ticks of 1/60. Float drift can leave a sliver, so 7 ticks is the correct bound for "ended".

### The other round-1 notes

- **N1, resolved.** `1-context.md` l.9 now matches `player_ship.gd`: Drive branch 409-415, default press 421-434,
  sustain 440-455. `_step_boost` actually ends at l.466 (the tail clamp), not l.461. This is cosmetic.
- **N2, resolved.** Plan l.116-118 asserts only the direction. The draft (l.257-277) turns the nose before the cut tick
  and has a twin as a control that does re-assert along it, so the row discriminates.
- **N3, resolved.** Plan l.114-115 and l.130; draft l.245-254. Both values are on the right side of the 0.15 floor in
  doubles:
  - 1 − 0.86 = 0.14000000000000001, which is refused.
  - 1 − 0.85 = 0.15000000000000002, which is allowed.
- **N4, resolved.** Plan l.114; draft l.242. The efficiency guard sits after the hold-window floor and before the meter
  check, and `_boost_hold_left` is only written inside the started branch (`player_ship.gd:423`), so the assertion
  holds on a correct build.
- **N6, resolved.** Plan l.131 names `test_open_space_boost_wiring.gd`.
- **N7, resolved.** Plan l.133 records the before time (204.62 s). That is consistent with the last README row
  (`tests/README.md:571`, 203.8 s).

### Non-blocking

- **R2-N1. The bar's `modulate` reset is still vacuous (N5 half done).**
  - **Where:** plan l.129; draft l.410-419.
  - **Problem:** `BoostBar._process` never runs in a synchronous hand-ticked test, so `bar.modulate` is white throughout
    and `assert_eq(bar.modulate, Color.WHITE)` passes on a build whose handler never resets it. In play, a bar could
    stay dimmed after a disruption.
  - **Fix:** before ending the disruption, either call `bar._process(0.05)` a few times and assert
    `bar.modulate.a < 1.0`, or set `bar.modulate.a = 0.5` by hand. Then assert the reset.
- **R2-N2. Optional row: the Assault clock during an H-key Boost Drive.**
  - **Where:** `player_fighter.gd:99-103`.
  - **Gap:** a third early return, `engine_boost_active`, is not pinned. A call placed after it passes every planned
    row, but freezes the clock for each 0.55 s burst (the Drive still runs at any strength up to 0.85).
  - **Impact:** low, since "first" in plan l.75 covers it.
  - **Fix:** set `f.engine_boost_active = true` and run the same 7 ticks. This costs nothing and closes the gap.
