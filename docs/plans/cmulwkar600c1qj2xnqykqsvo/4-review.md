VERDICT: APPROVED

# Review — t10-gatling-windows task plan, Revision 1

Reviewed against `agent/auto-dev` at 34984b6. I checked the code, not the plan's account of it, and redid the arithmetic.
I ran one throw-away probe from `/tmp` (headless Godot, nothing written to the repo) to settle D7 numerically.

The plan builds its slice of the epic correctly. The one deviation (D2) is real and justified, and it is the smallest
fix that keeps every epic rule. Nothing below needs a re-plan. Each problem has one stated resolution, so they are
**binding notes A1–A8** rather than blockers: the implementer applies them, and `5-progress.md` records how. Two of
them (A1, A2) correct geometry claims that are false as written. Do not skip them because the tests might pass anyway.

## What I verified and found sound

**D2 (3-plan.md:68-103): the deviation is justified.**
- Tangent route: √(380² − 220²) = 309.8 px per tangent. The arc is 220 × (π − 2·acos(220/380)) = 220 × 1.235 = 271.8 px,
  so the total is 891 px, or 3.43 s at 260 px/s.
- Going round the 380 ring, from where a stream actually ends (|φ| ≈ 108–119° after the strafe and the COOLDOWN drift) to
  within 300 px of the far `F` (−81°), is ≈ 146° of arc ≈ 970 px ≈ 3.7 s. The literal REPOSITION (≤ 1.5 s) plus SWING_IN
  (≤ 1.5 s) cannot cover either distance.
- The epic review saw the same thing from the t11 side: N3 says "the ≈ 760 px crossing is often unfinished"
  (`cmufs7ekv000lnm2x7nbswijy/4-review.md:284-290`).
- The fix keeps every epic rule:
  - REPOSITION still lasts at least its rng 1.0–1.5 s;
  - SWING_IN is still capped at `swing_in_max`;
  - CHARGING still covers only SWING_IN + SPIN_UP and is always followed by a stream;
  - the budget entry rule is unchanged.
- With `F` within 300 px, SWING_IN covers ≈ 240 px in ≈ 0.92 s plus turning, so it fits inside 1.5 s. The taper
  `√(2·900·d)` only bites below d ≈ 37 px, so it costs nothing.
- The rejected faster swing does break the pin: 2.0 × 360 = 720 > 600.
- D2 also helps t11. A LEAD now enters SWING_IN only once it is near its new flank, so N3's "LEAD's position names the
  old side" mostly goes away.

**Pool sizing (3-plan.md:259-265).**
- `min_window_period` = 0.25 + 7 × 0.09 + 0.4 + 1.0 = 2.28 s.
- AI need: `pool_size_for(12, 1400/240 = 5.83, 2.28)` = 12 × ceil(2.56) = **36**.
- Rail need: `pool_size_for(1, 1400/220 = 6.36, 0.09)` = ceil(70.7) = **71**. This matches
  `enemy_rounds.gd:21-22` and `gatling_stream_round.tscn` (240 px/s, 8 s, 1400 px).
- Using `max_burst` with the period of a `min_rounds` stream is conservative. Good.

**Bearing convention (3-plan.md:137-145).**
- `UP.rotated(π/2)` = (0·0 − (−1)·1, 0·1 + (−1)·0) = (1, 0) = `RIGHT`.
- `UP.angle_to(RIGHT)` = 0 − (−π/2) = +π/2. So φ = +90° is the `right(h)` flank in y-down space, as stated.
- |φ| ∈ [55°, 125°] is exactly the epic's 90° ± 35°.
- `h` is `FighterBrain._heading_ref()` verbatim (`fighter_brain.gd:281-288`).

**Corridor numbers.**
- `inner_rect()` = (640, 360) ± (740, 740) = x −100..1380, y −380..1100 (`assault_corridor_constraint.gd:96-101`,
  `arena_camera.gd:39-43`).
- Hull = 14 × 1.8 = 25.2 px (`gatling_interceptor.tscn`). The clamp edge is 1380 − 65.2 = 1314.8.
- The player really can be anywhere in that rect (`player_fighter.gd:99-100`), so "100 px from the right wall" is
  x = 1280.

**D5 worked checks (3-plan.md:183-187).**
- Player at x = 490: the first `F.x` is 870. The flipped one is 110, inside the −34.8 clamp, and |110 − 490| = 380, so it
  alternates.
- Player at x = 1280: the first side is −1, `F.x` = 900. The flip clamps to 1314.8, and |1314.8 − 1280| = 34.8 < 220,
  so the flip is skipped.
- The disabled-exception run (`min_flank_range = 0`) makes `|Δx| < 0` impossible, so that run flips. The case can
  therefore fail (but see A5).

**D5 deferral (3-plan.md:188-195).**
- The budget check runs before the phase logic (`fighter_brain.gd:185-205`, the shape being copied).
- SWING_IN needs `remaining() ≥ swing_in_max` (`engagement_budget.gd:50`) and never outlasts it. So expiry lands, at
  the latest, on its last tick (or one tick into SPIN_UP from float accumulation; harmless).
- The solo worst case is 0.25 + 11 × 0.09 = 1.24 s, which is ≤ 2.08. That satisfies the AC.

**D6 rail fallback.**
- `EnemyPathMover` is added after the ship enters the tree (`wave_manager.gd:209/223`, `station_reinforcements.gd:261`).
  Its `_ready()` therefore calls `suspend_ai()` (`enemy_path_mover.gd:71`) **after** `GatlingInterceptor._ready()`, and
  the rail pattern is not overwritten by `_apply_config()`.
- `AttackController._timer` starts at 0, because the pattern is null at its `_ready()`. So the first rail round leaves
  at 0.09 s, well inside `test_rail_reinforcements_fire`'s 2 s (`test_station_reinforcements.gd:533-552`).
- `_bullet_pool_of()` takes the first `BulletPool` (`:107-111`), which is `StreamPool`. `_interceptor_half_extent()`
  reads `Sprite2D`, which is kept.
- The default `spawn_offset` (0, 10) and `rng = null` reproduce the legacy pattern exactly (`gatling_attack_pattern.gd`).

**D7 lifetime sweep.**
- `_gatling_speeds()` → `round_speed` / `rail_stream_speed`. Stream min 220: 1400/220 = 6.36 ≤ 8.
- Replacing `GatlingInterceptorConfig.new().bullet_speed` (`test_enemy_bullet_lifetime.gd:74-75`) leaves the global
  minimum at 150. Heavy Shell at its scene default is not a typed number. The AC is met.

**Conventions.**
- Single writer: the brain requests only, and the root script has no per-frame code (the same as `fighter.gd`).
- The config is flat (floats and ints) and privatised by `BaseEnemy`.
- `phase_changed(new_phase: int)` has arity 1.
- New `ext_resource` lines are UID-less, like `fighter.tscn`. The brain's `.uid` sidecar is minted by `--import`.
- Contact damage is applied from config (`ShipConfig.collision_damage` defaults to 20 = the scene's 20).
- No node names or shapes change, so the geometry, flip and transparency gates are untouched.

**Scope.**
- Nothing from t11 is built: no squad, no `convergence_*`, `aim_point` stays INF. `sync_wait_max` is in the epic's
  config list, and here it is only read in a bound.
- Nothing from t12, t15 or t16 is built.
- Everything §3 gives t10 is present: the solo brain, the side rule, the budget rule, the rail fallback, the lifetime
  switch and the dual-mode specs. The ENEMIES_CLEARED boundary row is t17's.

**Epic §4 row coverage.** Every clause of the `test_gatling_interceptor.gd` row maps to a case:
- root pool and ≥ 36 / ≥ 20 / starvation → 2–3;
- rhythm → 7–9;
- seed sweep → 10;
- side-on → 11;
- sides, with N7 applied → 13–16;
- predicted aim → 12;
- budget → 18–19;
- rail → 5–6.

## Binding notes (non-blocking; apply each as resolved)

**A1 — D4's strafe rule contradicts the Open Space routing (3-plan.md:149-151, 158-160).**
- The strafe latches the tangent whose dot with `h` is ≤ 0, on the premise that "the Gatling arrives at `F` from ahead".
  That holds in Assault (plain Δ, always via ahead). It does not hold in Open Space.
- With the wrapped Δ, a stream that ended at ≈ +111° (≈ +119° after COOLDOWN's drift) gives a plain Δ to `F` at −90° of
  −209°. Wrapped, that is +151°, so the swing goes **via behind** on essentially every later window.
- The Gatling then arrives moving toward ahead, and the SPIN_UP latch reverses it. That is Δv = 400 px/s at braking 900
  (`enemy_mover.gd:190-193`), or 0.44 s, longer than SPIN_UP. So it is still reversing during STREAM.
- It probably stays inside 125° (≈ 111° by my estimate). But it is a visible stop-and-back-up every window, and the stated
  rationale is false.
- **Resolution:** at SPIN_UP entry, latch the tangent sign that **continues the current velocity**
  (`tangent·actor.velocity ≥ 0`). Fall back to "dot `h` ≤ 0" only below 40 px/s.
  - Assault is unchanged: it arrives from ahead and slides behind.
  - Open Space via behind: hand-over at |φ| ≈ 99°, a slide of ≈ 27°, so it ends ≈ 72°, inside [55°, 125°].
  - Correct the D4 text to match. Case 11 measures it, as planned.

**A2 — the Assault "via ahead" route cuts across a player near the corridor top (3-plan.md:149-153).**
- Ring waypoints are clamped into `inner_rect().grow(−65)`, whose top is y = −315. The player may sit anywhere down to
  y = −380 (`player_fighter.gd:100`).
- With the player at y = −250, the ahead waypoint `P̂.y − 380` = −630 clamps to −315: **65 px above the player**. The
  swing then flies straight over it. That breaks the plan's own "never cuts across the player". This is the Gatling
  version of the fighter's "lane flips behind near the corridor top" (epic §2.4.1).
- **Resolution:** in Assault, if any clamped route waypoint would be closer than `min_flank_range` to `P̂`, take the
  other way round for that swing (Δ ∓ 360°, i.e. via behind). Via behind always fits near the top, since
  P.y + 380 ≤ 1035.
- Add a **boundary case**: Assault, with the player 130 px below the corridor top and `engage_seconds` raised. Between
  windows, the body never comes within `min_flank_range` of the player. Also show it fails with the fallback disabled.

**A3 — `side` during APPROACH is undefined (3-plan.md:120, 175-178).**
- APPROACH seeks `F`, and `F` needs `side`, yet the first side is "decided on APPROACH's exit, once".
- **Resolution:** re-derive `side` every APPROACH tick by the first-window rule (Open Space: the current side; Assault:
  opposite the player's x, tie → +1). Latch it on APPROACH's exit.
- State this in the brain's header comment. Case 13 asserts the latched value at the first SWING_IN, as planned.

**A4 — D7 is simpler than the plan fears. Measured: drop the "constant + delta" branch, and make the round lifetime
truthful.**
- My probe reproduced `_LEGACY_PEAK_SHOTS_PER_S[deep_space]` = 31.25 (`test_level1_fighter_spawns.gd:158-162`) with
  the test's own interval and rate logic.
- The interceptor pair's intervals are [0, 2.96] and [0.4, 3.36], and **they are not in the peak window**. Its
  composition implies 9 forward fighters + 1 aimed, all uncapped (`9 × 1/0.3 + 1/0.8`).
- The peak stays 31.25 at every rate I tried:
  - 3.30 shots/s per Gatling (pool 36 against the legacy round's 2400 px);
  - 5.66 shots/s (pool 36 against Gatling Stream's real 1400 px at 220).
  It moves only at the uncapped 11.1 (38.89).
- So the equality stays green, and the "live = constant + 2 × (36 − 20)/life" mechanism (3-plan.md:225-230) is dead
  code. It is also ill-posed: the peak window can move, and "life" changes as well as the pool.
- **Resolution:**
  - (a) Drop the delta branch. State the measured result in `5-progress.md` and DECISIONS.
  - (b) `_attack_stats_of()` should read each ship's round lifetime from **its own pool's** `bullet_scene`
    `ProjectileLifetime.max_distance`, not the legacy `enemy_bullet.tscn` (`:63-66, 343-348, 369-371`). That shared
    path has been false for the fighter since t8a and becomes false for the Gatling here. Rerun: all three sections stay
    at their constants, since fighters are uncapped either way.
  - (c) Do not re-freeze any constant.
  - If a later change ever does pull the pair into the peak, the B6-consistent answer is to **freeze the legacy
    interceptor's attack inputs** (pool 20, legacy round, 220 px/s, 0.09 s) as constants beside the peaks, because t10
    deletes those inputs. Do not add a derived delta.
- Widening `_attack_stats_of()`'s `suspend_ai()` trigger to "has a `Brain` child" is right. Keep the
  `ForwardPool`/`ForwardAttack` skip.

**A5 — the test budget: several cases need more than one window, and Assault gets about one at 7 s (D2's own
consequence).**
- **Case 7, Assault parameter.** "→ SWING_IN (a second window)" needs `engage_seconds` raised on the private config, as
  case 14 already does.
- **Case 15.** Raise `engage_seconds` too, and assert `windows_done ≥ 3` in the main run. Otherwise "every window is
  on the left" can pass with a single window. The disabled-exception run must also show ≥ 2 windows and an actual side
  change.
- **Case 18.**
  - Stage the Gatling within `swing_in_reach` of `F`, so APPROACH really calls `_begin_window()` with
    `remaining < swing_in_max`. Assert that REPOSITION is entered (the hold), not that APPROACH simply expired. An
    expiry in APPROACH passes the case vacuously.
  - Add the complementary boundary: with `remaining` one tick above `swing_in_max`, it does enter SWING_IN.
- **Case 19.** Keep the AC bound of 2.08 s. Also assert the solo bound `spin_up + (max_rounds − 1) × interval` + 2 ticks
  (≈ 1.27 s). A solo SPIN_UP that wrongly waited 0.75 s would still pass 2.08.
- **Case 21.** Assert containment only after the Gatling first enters the rect. It spawns above it.
- **Case 3.** Read `max_distance` from `StreamPool.bullet_scene`'s `ProjectileLifetime`, as `test_fighter.gd::_lifetime()`
  does, not the literal 1400.

**A6 — REPOSITION when `F` is already within reach (the wall-exception, no-flip window).**
- REPOSITION seeks at full speed for at least 1.0–1.5 s. Once the Gatling is within reach of an unflipped `F`, it will
  overshoot and loop (turn radius 130 px) around `F` until the minimum ends.
- **Resolution:** once `F` is within `swing_in_reach`, REPOSITION uses SWING_IN's taper (`min(max_speed,
  √(2·braking·d))`), so it settles on the flank instead of circling.

**A7 — record these hand-offs in DECISIONS (the *built in t10* note).**
- **For t16.** The *average* window period is ≈ 5.8 s, but the *minimum* (`min_window_period()`, 2.28 s, reachable in
  the no-flip wall case) is below the epic's 2.8 s.
  - A shots/s numerator built on `max_rounds / min_window_period()` is 5.26, against the epic's 12/2.8 = 4.29. So
    "density is lower" holds only on average. State both, and let t16 pick the bound it uses.
  - Also flag prominently that an Assault Gatling at `engage_seconds` 7.0 usually gets **one** window, so R3.7's
    "attacks from the other side" is rarely seen in Assault. The owner should see this when t16 tunes it.
- **For t11.** `min_window_period()` bounds the pool only if every path into SWING_IN passes through REPOSITION's
  minimum. A FLANK that answers from COOLDOWN (N3's recommendation) skips it. The period then falls to ≈ 0.9 s, the need
  to 12 × ceil(5.83/0.9) = 84, and the pool of 36 would starve silently.
  - t11 must either answer only from REPOSITION after `reposition_min`, or recompute the pool assertion.
  - Also note that a FLANK entering SWING_IN directly bypasses the `swing_in_reach` gate. That is fine, because
    `swing_in_max` still caps it.

**A8 — small corrections.**
- 3-plan.md:167: SPIN_UP's post-braking slide is ≈ 0.12 s × 140 ≈ 17 px, not 35. The conclusion is unchanged.
- 3-plan.md:194: the solo bound uses (12 − 1) × 0.09 while the t11 bound uses 12 × 0.09. Write the t11 one as the
  epic's conservative `max_rounds × interval`, and say so.
- `Steering.turn_toward` takes `delta` (3-plan.md:155).
- Step 5 docs: per CLAUDE.md, invoke `updating-project-docs` after adding the brain class. Where it would touch hub docs
  t18 owns (`docs/enemy-roster.md`, `assault.md`, `global.md`), defer them to t18 explicitly. Do not leave a rewritten
  `ENEMY.md` still saying "always fires forward". Either fix that line now or leave the file's old behaviour section
  untouched for t18.

## Checked and fine

- `GatlingAttackPattern` already has `rng`, `aim_point` and `accuracy`, and `aim_point` INF falls back to
  `TargetInfo.aim_direction(…, accuracy)`. So case 12 (leading a 150 px/s player at `accuracy` 0.8) can fail on an
  `accuracy = 0` build.
- The seed sweep is deterministic, and 40 seeds over 5 values all but guarantees both ends: P(8 missing) = 0.8^40 ≈ 1e-4,
  and a fixed seed set makes it reproducible anyway.
- `BulletPool` keeps idle rounds under itself (`bullet_pool.gd:50-57`), so prewarming 36 adds nothing to the container.
  Level/clear counts are unaffected.
- The hand-ticked `_simulate()` uses no awaits. `check-test-leaks.sh` is the right final check.
- Build order (shell + rail first, gate-checked, before the window machine) matches the t8a/t8b precedent.
