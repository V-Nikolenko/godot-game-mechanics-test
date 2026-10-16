VERDICT: CHANGES_REQUESTED

# Review of `3-plan.md` (epic t11: Support Ship ward selection, follow, retarget, Assault clamp), round 1

Read: this plan and `1-context.md`; the epic plan's "For every task", §2.4, §2.5, §2.11, §2.12, §4.1 and §4.3; the code
listed below; `CLAUDE.md`; `tests/README.md` (engine-error and signal-arity traps).

## What is right

- It follows §2.12 closely. The filter order, the threat formula, the stability rules (`min_ward_seconds` and the 1.3
  margin bracketed by 1.2× and 1.4× rows), the claim meta with stale-id handling, retargeting on `tree_exiting` plus
  per-tick validation, `ward_keep_radius`, the Assault `ward_view_band` drop, `is_supporting()`, the
  `ward_changed(new_ward: Node)` arity, the grace being Assault-only (`EngagementBudget.active`,
  `global/enemy_ai/engagement_budget.gd:29`), and release on switch, DISENGAGE and `_exit_tree()` all match.
- Reading "next tick" as "a ward lost via `tree_exiting` is replaced on the next brain tick, and one lost via validation is
  replaced on the tick that sees the loss" is correct. Killing a ward through `health` calls `queue_free()`
  (`assault/scenes/enemies/base_enemy.gd:240`), so `tree_exiting` does not fire that frame and only the
  `is_queued_for_deletion()` check catches the death. The plan has that check.
- The "ward 300 px above the view top" row reads §2.12 correctly. A ward at y −300 is outside `view.grow(120)` (view
  (0,0)–(1280,720) from `tests/helpers/enemy_ai_harness.gd:49-52` and `arena_camera.gd:102-104`), so it is no candidate. The
  support stays in SEEK_WARD with its hold point clamped. Setting `offset = (0, −300)` is visible in the same frame because
  `enemy_view_rect()` reads `global_position + offset` directly, so one tick then selects the ward.
- Re-pointing the t10 rows is legitimate and does not hide a regression. `fixture_enemy.tscn` has no config, so its
  `score_value` is 0 (`base_enemy.gd:96-100`) and it is not a candidate. Under §2.12, Assault with no ward must DISENGAGE
  after 1.5 s, so the Assault halves of `test_it_holds_near_an_ally_at_follow_distance` (360 ticks),
  `test_it_closes_on_a_far_ally_and_picks_the_nearest_of_two` (360) and `test_with_no_ally_it_drifts_in_place` (240)
  (`tests/integration/test_support_ship.gd:172-232`) are now wrong by spec. The Assault SEEK_WARD path is still covered by
  the grace row and the 300 px row. Giving the dual-mode ally `score_value = 25` (`test_enemy_dual_mode.gd:486-501`) makes it
  a real ward, which is the right move.
- No convention is broken in the design. It only makes requests (`arrive`, `add_nudge`, `face_toward`), draws randomness
  from `rng`, and reads the player only through `TargetInfo`. Nothing is reinvented: `nearest_ally()`,
  `Steering.break_contact`, `mover.add_nudge` and `EnemyWorld.view_rect` are all reused.

## Findings (must fix)

### 1. The evasion term barely does anything, and the evasion row cannot fail for the right reason
Checked: `global/enemy_ai/enemy_mover.gd:190-197`, `global/enemy_ai/steering.gd:26-36` and `:192-202`.

The plan composes FOLLOW as `mover.arrive(anchor, max_speed)` plus an evasion nudge
`break_contact(..., evade_speed)`, with "the mover sums and caps at `max_speed`". `Steering.arrive` returns full `max_speed`
(270) toward the anchor once the ship is more than `v²/(2·accel)` from it, which is about 1–16 px at these speeds. The
evasion nudge is 240. Pointing directly away from the anchor, the sum is about 30 px/s back toward the anchor. So the
support stays within a few px of the anchor whether or not the evasion term exists. Evasion only "works" when the anchor
geometry happens to keep the player away, because the anchor is `|ward − player| + follow_distance` from the player.

As a result, the row `test_evades_an_approaching_player` (plan line 129) either:
- **fails:** a stub aimed at the support passes close to the ward (the support sits almost on the player→ward line;
  `follow_lateral` 40 makes only a ~4° offset). As the stub crosses the ward, the anchor swings around a 155 px circle and
  the support is within about 155–200 px of the stub, below the 240 px limit; or
- **passes with evasion deleted:** for any geometry where it passes, the anchor geometry alone holds the distance.

The plan gives no start geometry for the stub. It does not say whether the stub flies a straight line or pursues: a
pursuing stub at 200 px/s beats `break_contact`'s 0.64 × 240 ≈ 154 px/s radial escape even with no anchor term. There is
also no control. §4.1 requires every row to be able to fail, and this is an acceptance criterion ("never within 0.8 ×
`evade_radius` of an approaching stub").

**Required:**
- (a) Pin a blend in which evasion actually wins near the player. For example, inside `evade_radius` make the
  `break_contact` the primary request and the anchor seek a nudge, or scale the arrive speed down with the player's
  closeness, or push the anchor out to at least `evade_radius` from the player before the arrive. §2.12 says only
  "blended in", so this is an open choice the plan should pin.
- (b) Pin the stub: start position, a straight line at 200 px/s for 3 s, and a path that crosses the ward.
- (c) Add a control: the same run with the evasion term disabled (for example `evade_speed = 0` on the private config)
  must come within 240 px.

### 2. The jink is inert for the same reason, and nothing tests it
Same lines as finding 1. A 60 px/s nudge against a full-speed arrive gives a sub-pixel equilibrium offset. The Risks
section (line 156) even wants "the arrive term must dominate the 60 px/s jink". That makes the §2.12 jink (and R5.23 "high
evasiveness") invisible, and no row asserts that the jink exists. Use whatever composition fixes finding 1 so the jink is
visible, for example perturbing the anchor or arriving at less than `max_speed` while settled. Then add one cheap row:
after settling, the support's position over a few `jink_period`s spans more than some px, and with `jink_strength = 0` it
does not. Keep the 60 px anchor row's tolerance consistent with that.

### 3. Two filters have no row that could fail
Checked: `assault/scenes/enemies/bonus_drone/bonus_drone.tscn` (no `Brain`, no `EnemyMover` node) and
`bonus_drone_config.tres:10`.

- **`counts_toward_wave_clear`.** The Bonus Drone has no brain, so `is_ai_driven()` already rejects it. The
  gunship/bonus-drone row still passes if the `counts_toward_wave_clear` clause is deleted, even though §2.12 calls that
  clause **explicit**. Add a fixture enemy (AI-driven) with `score_value = 500` and `counts_toward_wave_clear = false`
  beside a fighter, and assert the fighter wins.
- **`ward_search_radius` (900).** It has no boundary row; only `ward_keep_radius` does. Add a fixture at 890 px
  (selected) and at 910 px (not selected), Open Space. This is cheap.

### 4. `_set_ward(null)` on a ward it never connected will raise an engine error, and GUT fails on that
Checked: `tests/README.md:537-541` ("GUT fails a test on any unexpected engine error") and
`tests/integration/test_support_ship.gd:282-283` (`brain.ward = ally; ship.suspend_ai()`).

Lifecycle step 1 (plan line 40) says "disconnect our `tree_exiting` handler" whenever the old ward is valid. Line 25 says
`_set_ward(null)` "tolerates a ward it never claimed", but nothing in the steps provides that tolerance. Disconnecting a
connection that does not exist logs an error and reds that t10 row. Pin the following:
- store the exact bound `Callable` in a member when connecting;
- disconnect only `if ward.tree_exiting.is_connected(_ward_exit_callable)`;
- remove the meta only if it equals our id (already stated).

## Findings (should fix; small)

### 5. When the Assault grace clock starts
Plan step 5 (line 61) accumulates `_no_ward_time` from the first tick. Supports and their allies spawn above the screen.
The epic's t17 places a support "with the deep_space ram line" at an offset off the top edge, and allies are not
candidates until they are inside `view.grow(120)`. So a support can DISENGAGE about 1.5 s after spawning, before its
allies have entered the view. The epic's t17 attack-in-budget row (`is_supporting()` before the budget expires) would
then catch it late.

§2.12 leaves this open. Either:
- start the clock only once the support itself is inside `view.grow(view_band)`, with a row, or
- state that it runs from spawn,

and in both cases record the choice in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` for t17.

### 6. Phase log is missing
The epic's "For every task" rule requires appending a "t11 as built" entry to DECISIONS.md, as t10 did at line 2063.
t12 and t13 build directly on `_set_ward`, `ward_changed` ordering (null, then the new ward), `ward_held_for`,
`anchor == Vector2.INF`, the claim semantics and the grace-start choice. Add the entry to build step 4. Step 1 should
also say to run `scripts/gate-time.sh` *before* (§4.3).

### 7. SEEK_WARD is "unchanged", but `support_ship_brain.gd:99` assigns `ward = nearest_ally()`
Left as written, that line overwrites `ward` with a non-candidate (for example the lone swarm drone) on the very tick
that makes it SEEK_WARD. The next tick's validation would then keep it and enter FOLLOW. The "written only by
`_set_ward()`" rule implies a local variable, and `test_a_lone_swarm_drone_is_no_ward` would catch the mistake. Still,
say it explicitly in the SEEK_WARD section.

### 8. The 300 px row's geometry is tight
After the pan, `is_supporting()` needs the support within `beam_range` 380 of the ward at y −300. The clamped hold
point is at y ≥ 48, which is already 348 px away. So the support must reach y ≈ 48 within the 1.2 s window, and stay
within about 150 px of the ward's x. Pin a spawn (for example (ward.x, 120)) so the row is not timing-sensitive.

Also, `is_supporting()`'s own ward-band clause is never exercised independently, because validation drops the ward on
the next tick anyway. In `test_assault_a_ward_that_leaves_the_view_is_dropped`, assert `is_supporting()` is false in
the same frame as the pan, before any tick.

### 9. Dual-mode re-point tolerance (`test_enemy_dual_mode.gd:498`)
"Within `follow_distance + follow_lateral + 60` of the ward" (≤ 250 px) is much looser than today's 150 ± 30.
`assert_almost_eq(d, Vector2(150, 40).length(), 60)` keeps a two-sided bound at no cost.

## Summary
The design is a faithful reading of §2.12 in its rules, its retarget semantics, its Assault view handling and its
re-pointed rows. It is held back by the motion composition: as specified, the evasion and the jink are both cancelled by
a full-speed `arrive`. The evasion row (an acceptance criterion) therefore either fails or proves nothing, and has no
control. Add the missing boundary rows for `counts_toward_wave_clear` and `ward_search_radius`, fix the
unguarded disconnect, and this should be approvable without another full pass.

---

VERDICT: CHANGES_REQUESTED

# Round 2

I re-read the revised `3-plan.md`. To check the numbers rather than reason about them, I ran the pinned FOLLOW set-up
against the brain as it now sits in the working tree. `support_ship_brain.gd` is modified and uncommitted; its
`_tick_follow()`, lines ~306-344, is the round-2 plan's blend line for line. The probe is a throwaway `SceneTree` script in
`/tmp`, run with `godot --headless -s`. It hand-ticks exactly like `test_support_ship.gd::_tick`: ward fixture (score 25)
at (640, 360), player at (640, 760), support spawned at (640, 400), 3 s settle, then the stub flies a straight line from
(640, 760) at 200 px/s for 3 s. Nothing in the repo was written.

## Round-1 findings: resolved

- **1–2 (inert jink and evasion):** FOLLOW is now one `request_velocity` of a soft seek (gain 2.0) plus a lateral jink
  plus `break_contact`, with the anchor giving way across 0.8–1.0 × `evade_radius` (plan lines 73–90). The probe confirms
  the jink and anchor rows. Over seeds 1/2/3/7 in both modes, the distance to the anchor at 4 s is 16.7–29.8 px and the
  maximum while settled is 29.4 px, so it is inside 60. The across-line span over 4 `jink_period`s is 44.9–56.7 px; with
  `jink_strength = 0` it is 0.0 (control holds). The `evade_speed = 0` control comes within 19.5 px, so it fails as
  intended.
- **3:** `test_a_non_combatant_is_never_a_ward` (an AI-driven fixture, 500, `counts_toward_wave_clear = false`) and the
  890/910 `ward_search_radius` boundary are added (lines 131–134). Both can fail.
- **4:** `_ward_exit_cb` is stored and the disconnect is guarded by `is_connected` (lines 40–45). The t10 direct-assign
  suspend row stays as the guard (line 155).
- **5:** the grace clock now runs only while the support is inside `view.grow(view_band)`. The SEEK_WARD hold point,
  including the no-ally case, is clamped into view, so the clock always starts (lines 63–68, 94–98). It is pinned by
  `test_assault_grace_starts_only_once_the_support_is_in_view` and logged for t17. This is a legitimate pin of an open
  choice.
- **6–9:** before-time recorded (line 106); "t11 as built" DECISIONS entry (lines 110–113); `ward` written only by
  `_set_ward()` with SEEK_WARD using a local (lines 94–96); 300 px row spawn pinned at (640, 120), giving 348 px after the
  pan, inside `beam_range` 380 (line 175); the ward-leaves-view row asserts `is_supporting()` false in the same frame
  (lines 179–181); the dual-mode tolerance is restored to two-sided (line 191).

## New finding (must fix)

### R2-1. The pinned evasion row fails for most seeds once the stub carries its velocity
Checked: `global/enemy_ai/steering.gd:192-202`, plan lines 86–89 and 164–166.

When the threat is closing (`threat_vel·away > 0`), `Steering.break_contact` doubles its lateral share from the default
`lateral_weight` 0.6 to 1.2. That leaves a radial (opening) component of `240 / sqrt(1 + 1.2²) ≈ 154 px/s`, below the
stub's 200 px/s. The support also starts from rest at 300 px with 60 px of margin and `acceleration` 700. So the stub keeps
closing for the first fraction of a second, and the minimum distance lands right on the 240 px line.

Probe results with `player.velocity` set to the stub's real velocity, which is what a real player has and what
`TargetInfo` reads (`target_info.gd:41-42`):

| seed | min distance (both modes) |
|---|---|
| 1 | 239.7 |
| 2 | 234.3 |
| 3 | 233.5 |
| 7 | 256.4 |

So three of four seeds fail `≥ 240`. With the stub moved by position only (velocity left zero, so the doubling never
triggers) it reads 263.1 and passes. As written, the row either fails, or passes only by an accident of seed choice or by a
stub that does not report its velocity. Neither is a meaningful gate, and the plan's "fixed `rng_seed`" (line 158) would
hide that.

**Required, both:**
- (a) Pin that the stub sets `player.velocity` every tick, so the closing-threat branch is what is tested.
- (b) Pin a `break_contact` lateral weight whose radial share beats the stub: `240 / sqrt(1 + (2·lw)²) > 200` needs
  `lw < 0.33`.
  - Suggested: `const EVADE_LATERAL_WEIGHT := 0.3`, giving about 206 px/s radial and still a 31° sidestep. It is passed
    as `break_contact`'s existing optional sixth argument, so there is no new Steering code.
  - My kinematic model of the plan's blend gives a minimum of 261–268 px with 0.3, against 219–234 px with 0.6. That is
    consistent with the probe.
  - Record it in the DECISIONS entry with the other judgement numbers. §2.12 names the call without a weight, so this
    pins an open choice rather than changing a rule.
- Then assert the row over several seeds (e.g. 1, 2, 3, 7 in a loop, still hand-ticked and cheap) rather than one. Keep
  the `evade_speed = 0` control.

## Notes (no change needed)
- With a more radial escape, an Assault support fleeing a stub that comes up through the ward will leave the top of the
  view (y < 0) while it evades. §2.12 accepts this: it stops supporting outside `view_band`, and the anchor clamp pulls
  it back once the player is beyond `evade_radius`. Nothing in the acceptance criteria asserts otherwise.
- The jink row's span assertion (> 15 px) is comfortably met on every seed probed (≥ 44.9 px), so a single fixed seed is
  fine there.

## Summary
Every round-1 finding is addressed, and the jink, anchor and control rows are confirmed numerically. One substantive gap
is left: as pinned, the evasion row, which is an acceptance criterion, fails for most seeds with an honest stub. It is a
one-constant fix (a `break_contact` lateral weight of about 0.3, plus the stub's velocity set and a multi-seed assertion).
With that in, this is approvable.

---

VERDICT: APPROVED

# Round 3

I re-checked only the round-2 change, against the plan and the draft code.

- **Plan.** `3-plan.md:86-91` pins `const EVADE_LATERAL_WEIGHT := 0.3`, passed as `break_contact`'s sixth argument, with
  its reason: about 206 px/s of radial escape against the 200 px/s stub. It is logged for DECISIONS.md. `3-plan.md:164-169`
  now sets `player.velocity` every tick, asserts seeds 1, 2, 3 and 7, and keeps the `evade_speed = 0` control (seed 1).
  This is exactly the round-2 request. It pins an open choice: §2.12 names the call but no weight. No rule changes.
- **Draft brain.** `support_ship_brain.gd:53-56` declares the constant with its reason, and `:346-347` passes it. No new
  Steering code was added.
- **Draft test.** `test_support_ship.gd:680-704` (`_evasion_min_distance`) sets `player.velocity` before the loop and
  moves the stub by that velocity, so `TargetInfo` sees a closing threat. Each seed is applied before the first tick, so
  `follow_side` and the jink come from it. It asserts all four seeds plus the control.
- **Measured.** I ran `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_support_ship.gd`.
  `test_evades_an_approaching_player` passes in both modes, for every seed and the control (10 asserts). The row can now
  pass honestly and can still fail: with no escape term the stub gets inside 240 px.

## One note for the build (not a plan defect)
The same run has one red: `test_it_jinks` fails in Assault on the control (`span 26.5 >= 3.0`, `test_support_ship.gd:682`).

- **Cause.** The draft samples 8 jink periods (384 ticks) after a 180-tick settle, which is 9.4 s. That is past the
  Assault `engage_seconds` of 9.0. The budget expires, the brain enters DISENGAGE, and the ship curves away. I probed it:
  `brain.anchor` is `INF` at the end because there is no ward, and the x drift is the exit, not a jink.
- **Effect on the positive case.** Its 108 px span is also partly exit motion.
- **Fix.** Either sample the plan's 4 periods (`3-plan.md:165`, 6.2 s in total), or raise `engage_seconds` on the
  private config for that row. The plan's row as written is fine.
- **Other rows.** Any other dual-mode row that runs for 9 s or more in Assault needs the same care.
