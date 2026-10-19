VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` (t8, the Missile Corvette's fight) against epic `cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.4, §2.9,
§2.10, §4.1, §4.3 and the code it builds on. The design is mostly sound and follows §2.10. Three things have to change
before implementation: an existing t7 test that this task will break, a min-range blend whose sign goes against the orbit
and that no test can catch, and an Assault gate row that fails or passes depending on how its setup is written. The
geometry claims were checked with a small offline simulation of `Steering.orbit` / `break_contact`, the mover's
accel/speed caps and the corridor filter. The numbers are quoted below.

## Blocking

### B1. The plan breaks an existing t7 row and does not say so
`tests/integration/test_missile_corvette.gd:365-378` (`test_approach_closes_to_the_held_range_in_each_mode`) ticks 900
frames and asserts `distance ≈ held_range()` **within 25 px**. Under t8 the corvette enters HOLD_ARC within
`range_tolerance` (`3-plan.md` "Phases") and then follows `R + 80·sin(…)`, with an rng period and phase. `rng_seed` is 0
(randomised) in that row. After 15 s the distance is anywhere in about R ± 96 px (simulated), so the row will fail or flake.
The plan's build sequence and test plan never mention it. **Fix:** say how this row changes, without weakening what it
proves. For example, assert that the corvette reaches HOLD_ARC, and that at the HOLD_ARC entry tick
`|d − held_range()| <= range_tolerance` and it is closing. Seed it. Check the `test_enemy_dual_mode.gd:457-467` corvette
case too. It still passes: OS 700 px start → HOLD_ARC at once, but the anchor is at 620 so it still closes.

### B2. The min-range blend pushes against the orbit, and no row can detect the blend at all
- `steering.gd:200` builds the lateral as `away.orthogonal() * side`. Godot's `orthogonal()` is `(y, −x)`. The orbit anchor
  `RIGHT.rotated(angle)` (`steering.gd:42`) moves with tangent `away.rotated(+PI/2)` for increasing `angle`, which is
  `−orthogonal(away)`. So the plan's `break_contact(pos, player, vel, orbit_dir, max_speed)` (literally "side = orbit
  direction") gives a lateral **opposite** to the orbit's direction of travel. The plan's stated rationale ("the orbit term
  keeps the radial share high; the break term adds the sideways escape") does not hold. The break term *subtracts* the
  sideways share: it partly cancels the orbit's tangential request, the cancellation the mover's own header rejects
  (`enemy_mover.gd:11-12`). In simulation, the tangential sign while inside `min_range` is mixed (net +30 ticks along
  `orbit_dir`) with `side = orbit_dir`, and consistent (+133) with `side = −orbit_dir`.
- Worse, the bounded-chase row cannot fail on this rule. Assault R 460, worst case over orbit dir, drift sign, drift
  period 6/7.5/9 and a fixed-line or homing stub:

  | min-range handling | closest approach | back outside 380 after stop |
  |---|---|---|
  | **no blend at all (orbit only)** | 288 px | 0.48 s |
  | blend, `side = orbit_dir` (plan) | 266 px | 0.55 s |
  | blend, `side = −orbit_dir` | 289 px | 0.47 s |
  | pure `break_contact` (rejected alt.) | 175 px | 1.18 s |

  The "rejected alternative" analysis is right: pure `break_contact` fails 228 px. But the row passes with the §2.10 rule
  deleted, so that rule ("inside `min_range` it blends `break_contact` … until back outside") has no test that can catch it
  regressing. In Open Space the chase row never gets inside `min_range` at all: the closest approach is about 444 px from
  620, so it is vacuous there.
- **Fix:** pin the sign so the lateral runs along the orbit's travel (in Godot terms `side = −orbit_dir`), and write that
  mapping into the plan. "Side = orbit direction" in §2.10 is about meaning, so this is not a rename. Add a row that fails
  without the blend: a corvette placed inside `min_range` with a closing stub. Over the ticks it spends inside, its
  velocity's tangential component must have `orbit_dir`'s sense, and its outward radial component must be > 0. After
  leaving, the angle must be re-synced: the anchor bearing equals the actor's bearing on the first tick outside. In the
  Assault chase row, also assert that the corvette actually went inside `min_range`, so the row is known to exercise the
  blend.

### B3. The 1.2 s / 1.0 s Assault rows depend on how the budget is set, and the plan does not pin it
`missile_corvette_brain.gd:48` runs `budget.update(delta)` **before** the phase logic. So the gate in HOLD_ARC reads
`remaining()` after that tick's update has subtracted `delta` (`engagement_budget.gd:212-228`). The gate threshold is
1.14 + 0.05 = **1.19 s**, so the "1.2 s" row has a 0.01 s margin, less than one 1/60 s tick. If the test sets remaining to
1.2 before the tick, the gate reads 1.183 and refuses: the row fails. If it sets remaining to 1.2 one tick early or late,
the outcome changes too. The Ram already solved this (`tests/integration/test_ram_corvette.gd:1174`:
`brain.budget.seconds = left + DT  # 'left' remains after the next tick's update`). **Fix:** state in the plan that both
rows set the budget with that idiom, so 1.2 / 1.0 s is what the gate reads on the TELEGRAPH tick. Also derive
`ATTACK_WINDOW` from config (`salvo_telegraph + (max(salvo_count, warhead_salvo_count) − 1) × salvo_gap`), not a literal
1.14. Recommended: add a 1.17 s row, which also proves the 0.05 margin exists; 1.0 s only proves a gate exists.

## Should fix

### S1. The Warhead pair geometry and setup are underspecified
- `across` for a still stub is "the line of sight's perpendicular", with no origin given and recomputed per shot. The two
  warheads come from different tubes (local (±18, 30), `missile_corvette.tscn`), about 7.6° apart as seen from the stub at
  300 px. They are also 0.22 s apart, while a corvette inside `min_range` is moving at up to 210 px/s. Two perpendiculars θ
  apart give a separation of `180·cos(θ/2)`, which leaves the ±1 px band at θ ≈ 12°. **Fix:** compute `across` once per
  salvo (at SALVO entry, from the corvette's centre, or from the velocity when the player moves). The pair is then exactly
  `2 × warhead_offset` apart by construction, and the row measures along that frozen vector.
- APPROACH only enters HOLD_ARC at `|d − R| <= range_tolerance`, which is d ≥ 340 (Assault) or ≥ 500 (OS). So no natural run
  starts a salvo at 300 px. The row must enter HOLD_ARC through `enter_phase` at 300 px, zero `salvo_cooldown` *after*
  `_start()` has drawn it, and/or use `force_next_kind(WARHEAD)`. Say which. The acceptance's "Warhead pair for a stub at
  300 px" is then the pure `choose_kind(300, …)` row plus the forced-geometry row.

### S2. The 1-in-4 DUMB→PURSUIT swap (§2.10.4) has no test
It is a §2.10 rule and it lives in `_roll_kind()`, outside the pinned pure function, so nothing in the plan covers it.
**Fix:** add a seeded row over N rolls in a DUMB situation. The PURSUIT share must fall in a band around 0.25, for example
0.15–0.35 over 200 rolls. A WARHEAD or CLUSTER situation must never be swapped.

### S3. `choose_kind(distance, player_speed, radial_speed = 0.0)`: the default is a trap
With the default, the acceptance-style two-argument call for a 350 px/s fleeing stub returns DUMB (radial 0 is not > 0),
not PURSUIT. "The two-argument call stays legal" is true but misleading. Make `radial_speed` required. Taking the
`TargetInfo` and actor position directly would also work. The kind-choice rows must pass the radial speed.

### S4. Rows that need their preconditions asserted, or a forced kind
- `test_no_salvo_at_a_player_held_behind_it`: `salvo_cooldown` is drawn on the first tick (plan), so zeroing it before that
  tick does nothing. Assert that the corvette is in HOLD_ARC, that `salvo_cooldown == 0` and that the Assault gate is open
  during the window. Zero telegraphs is then attributable to the cone alone.
- `test_dumb_aim_points_lead_along_the_predicted_path`: the 1-in-4 swap can turn the salvo into PURSUIT. Force DUMB
  (`force_next_kind`).
- `test_budget_expiry_mid_telegraph_defers_to_the_salvo`: also assert the §2.10.9 bound, DISENGAGE within
  `salvo_telegraph + 2 × salvo_gap` + 2 ticks of TELEGRAPH start. Today it only checks the order.

### S5. Untested §2.10 rules
- The tube glow ramps 0→1 over TELEGRAPH and flashes per launch (§2.10.6/7).
- `on_suspended()` clears the glow mid-telegraph (plan "Rails").

These are cheap hand-ticked reads (`TubeLightL.modulate.a`, `missile_corvette.gd:120-122`). Add one row each.

## Minor / notes

- On the TELEGRAPH→SALVO tick the plan runs SALVO's first tick in the same frame. Make sure `_arc_motion` (angle advance,
  drift clock, reversal countdown) and the `salvo_cooldown` decrement run once on that tick, not twice.
- The cone check: reuse `EnemyMover.sprite_forward_angle_of(actor)` (as `_heading()` already does,
  `missile_corvette_brain.gd:136`) and `TargetInfo.relative_angle_from()` (`target_info.gd:52`) instead of hand-rolling the
  nose maths.
- `export_of(kind, property, fallback)`: a caller-supplied fallback can disagree with the script default. All four scenes
  author `cruise_speed` today, so this is harmless, but `max_time_of`'s hard-coded 4.0 shows the pattern. Read the default
  from `EnemyRocket`'s script if you want it exact. It is not a reinvention: `enemy_rocket_scenes.gd:42-50` is the only
  `get_state()` reader in the project.
- Long hand-ticked rows let no frame pass, so rockets never expire. The DUMB pool (3) runs dry on the second DUMB salvo:
  `bullet_pool.gd:80-84` raises a `push_warning` (not a GUT failure), and `rockets_refused` grows. No row should count
  rockets across more than one salvo.
- No REVERSE phase (instant anchor flip): acceptable. The epic's append-only enum has no REVERSE, and the mover's 240 px/s²
  smooths the flip in about 1 s.

## Verified OK (no change needed)

- **Hold range from 1200 px** (simulated with APPROACH `arrive`, HOLD_ARC entry, drift, reversals at 4–7 s, half speed in
  telegraph/salvo, and the corridor's rule 1 for the Assault start above the screen, `assault_corridor_constraint.gd:64-65`):
  the deviation is within ±96 px (OS) and ±92 px (Assault), against ±200. The minimum Σ|Δbearing| over 10 s is 104°, against
  60°. A parked corvette fails it, so the row can fail.
- **Bounded chase in Assault** with the plan's placement ((640, 900) stub, corridor top 820 px behind): 266 px ≥ 228 and back
  out ≤ 0.55 s ≤ 3 s. The blend-vs-pure analysis is correct (pure: 175 px).
- **BurstClock** fires the first shot on the first `advance()` (`burst_clock.gd:150-165`, timer pre-loaded). With SALVO's
  first tick in the same frame, the first rocket leaves at the telegraph's end, and gaps of 14/13 ticks sit within
  `salvo_gap` ± 1 tick.
- **Budget deferral:** a "seen once" flag plus `_disengage_pending` matches the Ram (`ram_corvette_brain.gd:144`, `:256-261`).
  The bound uses max(salvo_count, warhead_salvo_count), which equals §2.10.9's 1.14 s with the shipped config and is no
  deviation.
- **Kind order, salvo sizes, cone half-angle (22.5°), OS cancel at 2× cone (45°), never COMMIT, tow refusal:** all match
  §2.10.
- The `_REFUSING_PHASES` row (`test_base_enemy.gd:346-354`, loop `:491-515`) works through the real `enter_phase` in the OS
  harness.
- **Conventions:** requests only (`Steering.*` + `mover.request_velocity`, which `test_enemy_mover_single_writer.gd:35-54`
  allows), randomness only from `rng`, the player only through `TargetInfo`, no new signals, no UIDs.
- `next_tube_position()` is a read-only getter beside `fire()`.
- **GUT time:** roughly 6–8k hand ticks in total, comfortably within 5.0 s.

---

# Round 2

VERDICT: APPROVED

I re-read `3-plan.md` (the "Side (R1 B2)" paragraph, the rewritten test table and "Revision 1") and checked each claim
against the scratch build in `/tmp/t8work`: `missile_corvette_brain.gd`, `missile_corvette.gd`,
`enemy_rocket_scenes.gd`, `tests/integration/test_missile_corvette.gd` and `tests/integration/test_base_enemy.gd`. I ran
`test_missile_corvette.gd` there: 37/37 pass, 458 asserts, 1.08 s for the whole file, t7 rows included, so the t8 share is
well inside the 5.0 s allotment.

## Round-1 findings: all resolved

- **B1 (t7 approach row).** Rewritten in the scratch test file (lines 367-387). It now starts 860 px out, asserts APPROACH,
  then that HOLD_ARC takes over within `range_tolerance`, then that the corvette holds `R ± (range_drift + range_tolerance)`
  after 15 s. That is the honest t8 form, no longer flaky. The `test_enemy_dual_mode.gd` corvette case is unaffected,
  confirmed as in round 1.
- **B2 (blend side and test).** The brain (scratch line 305) passes `-orbit_dir`, and the comment gives the sign
  derivation. That derivation matches mine: `orthogonal()` is a −90° turn, while the orbit's +1 is +90°.
  `test_a_faster_rusher_gets_inside_and_is_sidestepped` (scratch 508-545) checks five things:
  - a sanity check that the corvette actually gets inside `min_range`;
  - a mean outward radial velocity > 0 while inside;
  - a mean tangential velocity of at least 15 px/s in the arc's sense (`(-y, x)·orbit_dir`, which is the correct tangent
    for increasing `angle`);
  - a closest approach ≥ 190 px;
  - back out within 3 s of the stop.

  The plan reports the mutations: with no blend the sideways speed is −13 px/s, and with the literal side the closest pass
  is 147 px. Each trips a different assert. Both are consistent with my round-1 simulation, so the §2.10.2 rule now has a
  row that fails without it.
- **B3 (budget ordering).** `_assault_gate(left)` (scratch 805-817) uses the Ram's `elapsed + DT + left` idiom and asserts
  `remaining() ≈ 1.2` on the TELEGRAPH tick. The no-start row loops over both 1.0 s and 1.17 s, so the 0.05 margin is
  proven. `attack_window()` is derived from config and has its own row.
- **S1 (Warhead geometry and setup).** `_salvo_across` is fixed at SALVO entry (scratch 132, 349-358). For a still stub both
  base points are the stub itself, and for a moving stub they differ only along the velocity, so the separation is exactly
  180 px in both cases. The row reaches 300 px through `enter_phase(HOLD_ARC)` plus a cooldown zeroed after the first
  tick, and the kind is chosen there, not forced.
- **S2 (swap).** 200 seeded rolls, with a share band of [0.15, 0.35] (±3.3σ). The WARHEAD and CLUSTER situations are never
  swapped.
- **S3.** `radial_speed` is now required. `test_kind_choice` gained the edges: 420 px is exclusive, a closing player gets no
  Pursuit, crossing at 650 px gives DUMB, mostly radial at 800 px gives DUMB, and fleeing at 200 px/s gives DUMB.
- **S4.**
  - The behind-the-nose row asserts that every tick is HOLD_ARC with cooldown 0 and the gate open. It ends with an in-front
    control that telegraphs at once.
  - The DUMB aim row forces DUMB.
  - The deferral row asserts the phase order SALVO → DISENGAGE, three rockets, and the 1.14 s + 2 ticks bound.
- **S5.** There are glow rows for the ramp (monotone, about half-lit halfway, ≥ 0.8 at the end), the flash and its floor,
  dark afterwards, and the rail-mid-telegraph case.
- **Minor.**
  - The same-frame SALVO tick is `_tick_salvo(0.0)`. It skips `_arc_motion` on `delta > 0`, and `BurstClock` still reports
    the first shot because its timer is pre-loaded. The cooldown decrement lives only in `tick()`, so nothing runs twice.
  - `next_tube_position()` is read inside `fire()`'s argument, before `fire()` advances the tube, so each rocket is aimed
    from the tube it actually leaves.
  - Single writer: the brain makes `Steering.*` calls plus `mover.request_velocity` and `face_toward`, and writes no
    motion. Randomness comes only from `rng`, the player only through `TargetInfo`, and no new signals or UIDs were added.

## Non-blocking notes for the implementation

1. **Leak check.** Every single-file run in `/tmp/t8work` prints `ObjectDB instances leaked` / `resources still in use` at
   exit. This also happens for the unchanged t7-only rows, and for `test_enemy_dual_mode.gd -gunit_test_name=sniper`,
   which has nothing to do with this task. So it is a property of filtered runs, not something t8 introduced. Build step 4
   (`scripts/check-test-leaks.sh` on the full suite) is still the check that counts. Do not skip it.
2. **Cruise speed fallback.** The brain reads cruise speeds with fallback `0.0` (scratch 203). That conflicts with
   `export_of`'s own doc ("pass the script default"). If a scene ever dropped its authored value, `intercept()` would fail
   silently and the corvette would aim at the player's current position. The export row's per-kind equality against the
   instantiated scene catches that today, so this is cosmetic. Passing the script default (520) would make the doc and the
   code agree.
3. **`max_time_of` on an unknown kind.** It now returns 4.0 instead of 0.0. This is unreachable for real kinds, because
   `scene_for` already raises `push_error` for an unknown one. Harmless.
4. **Stale brain header.** Lines 21 and 24 of the brain header still say `ATTACK_WINDOW`. The code uses `attack_window()`;
   update the wording.
5. **Log the side reading.** Record the `side = −orbit_dir` reading of §2.10.2 in the DECISIONS t8 line (build step 5).
   It is an interpretation of an epic rule, and any later brain that blends `break_contact` into an orbit (escort, hub
   idle) needs the same sign.
