VERDICT: CHANGES_REQUESTED

# Review: Hacker Frigate shell and movement (Phase 9 t8), round 1

I checked the plan against epic §2.10, §2.15, §2.18, §2.19 and "For every task", and against the real code. The core design holds up. The
cone sign convention, the orbit reduction, the break-off numbers, the tow-table change and the cone timings all check out (I re-simulated the
timings independently, see below). Four details are wrong or under-specified, and as written they would leave a row that cannot pass or a
control that does not fail. Each is a small text fix. No redesign is needed.

## What I verified (no change needed)

- **Cone sign convention.** `TargetInfo.facing = Vector2.UP.rotated(rotation)` (`global/enemy_ai/target_info.gd:42`). Godot's
  `a.angle_to(b)` is `angle(b) − angle(a)`. `_orbit_angle` is synced to `offset.angle()` with `offset = pos − target`
  (`missile_corvette_brain.gd:396`). So `+orbit_dir` raises the bearing's angle and therefore `a`, which makes `signf(a)` the direction
  toward the nearer edge. That is correct.
- **`Steering.orbit(pos, anchor, 0.0, 0.0, max_speed)`** (`global/enemy_ai/steering.gd:41-45`). This gives `anchor = center +
  RIGHT.rotated(0)·0 = center`, then `clamp(4·dist, 60, max)` toward it. With an unclamped anchor `target + RIGHT.rotated(angle)·radius`,
  this is the corvette's call with the same float ops, so it is bit-identical in Open Space.
- **Break-off radial.** `break_contact` doubles the lateral weight when `threat_vel.dot(away) > 0` (`steering.gd:199-201`). That gives
  0.25 → 0.5 and a radial of 360/√1.25 = 322.0 px/s. `EnemyMover.boost` ignores `max_speed` and the accel limit (`enemy_mover.gd:115,
  224-246`). The control (`min_range` 0) is robust: radial ≤ 230 against a 300 px/s rusher closes ≥ 70 px/s, so the gap is < 320 px after
  4 s. A boost blocks a tow (`base_enemy.gd:243`).
- **Tow table** (`tests/integration/test_base_enemy.gd:358-371, 505-529`). The unlisted-phase fallback is
  `APPROACH → ENTER → FORM`, so a Hacker entry with no fallback change would index a missing key. The plan's extension to `HOLD_ARC` is
  necessary and enough. `_MIN_ROSTER_SIZE` 23 → 24 is right (l. 57-62). `_AUTHORED_CONTACT_MODES` needs the COLLISION entry.
- **Cone timings.** I independently simulated the plan's exact rule: 1/60 s ticks, `move_toward` at 700, the 4·d/60/230 correction, the
  un-synced `_orbit_angle`, a 2.0 s warm-up from rest, a ±10° snap, and a re-snap with the same case rule.
  - **Nose, 720 and 520 px, main:** exits 1.55 / 1.70 / 1.27 s (720) and 1.55 / 1.63 / 1.27 s (520), all through the near edge.
    Far-way time is 0.17–0.30 s.
  - **Nose controls:** 3.88 s and 2.33 s, so both are still inside at 2.2 s and at 1.9 s. The 0.30 rad/s control has only 0.13 s of
    margin at 720.
  - **Route rows:** main 1.10–1.33 s, controls 2.00 s and 3.32 s (bound 1.8 s).
  - **Conclusion:** the no-resync design meets every bound, and every control fails it.
- **Assault cone geometry** (player at (640, 620); view (0,0,1280,720), confirmed by `tests/unit/test_enemy_world.gd:36`; clamp rect
  (68..1212, 68..652)). The 520 ring's anchor stays inside the clamp rect up to about 93.5° from straight up. Every row's path stays
  within about 65° (the far-way cases) or about 51° (the near-way case started 45° off). So `view_clamp_bound == false` and the 8 px pad
  hold. The plan's "≈ 86° of arc" for the near-way run is really about 96°, but the conclusion still holds (non-blocking N2).
- **Exit probe.** `ph9_exit_keys.gd` mirrors `tests/helpers/ph8_exit_keys.gd`. Runs come to 19 × 19 × 3 × 2 = 2166
  (`specialist_exit_probe.gd:53-77`). Speeds `[max_speed, 10]` are right because the Assault Hacker never boosts. The tender's 2166 runs
  cost 1.95 s (`tests/README.md:623`), so 4.0 s is a credible allotment.
- **Justified deviations:** the `VIEW_CLAMP_PAD` (the 60 px/s floor wobble is real, and the rows assert `grow(−60)`); the
  `break_exit_margin` field; the `Polygon2D` placeholder (the epic's own parenthetical, plus the jammer precedent at
  `jamming_structure.tscn`); NOTICING → HOLD_ARC (the enum has no APPROACH); and the idle `k` asymmetry.
- **`config` is safe to write before `add_child`.** No enemy `.tscn` sets `config`, so `_init()`'s `privatise()` copies the script default
  (`ship_config.gd:63-66`).

## Required changes

**R1. The Assault BREAK_OFF target formula is double-scaled (plan l. 78-79).** `dir = break_contact(..., max_speed, ...)` already has
length `max_speed` (`steering.gd:202`). `pos + dir · max_speed · BREAK_LOOKAHEAD` therefore puts the point about 52,900 px away. Clamping
that per component sends the hull to a corner of the clamp rect rather than along `dir`. Use `pos + dir · BREAK_LOOKAHEAD` (230 px ahead),
or normalise `dir` first.

**R2. Pin `engage_seconds` for every Assault row except the life row.** `EngagementBudget` is active in the Assault harness (an
`ArenaCamera` is present) and expires at 9.0 s. Three rows overrun it as written:
- **Holds range:** 20 s, so it fails outright.
- **Asymmetric arcs and reversals:** 10 s or more.
- **Assault nose cone:** 2.0 + exit + 3.5 + exit is 8.7 s as I simulated it and 9.3 s at the bounds. It would enter DISENGAGE mid-row.

Say that `_spawn` writes `engage_seconds = 1000` by default (the Support Ship tests' precedent, `test_support_ship.gd:1344`), and that the
life row and the probe keep the shipped 9.0 s.

**R3. Pin the Assault geometry for holds range, arcs and reversals.** The 520 px ring is taller than the 720 px view, so part of it is
always clamped.
- **Player at the view centre:** the clamped anchor straight above or below is 292 px away. That is below `min_range` 420, which fires
  BREAK_OFF, and below the 370 px lower edge of the holds-range band.
- **Player at the bottom (the cone rows' placement):** the trouble starts once the hull sweeps past about 120° from straight up.
- **What sweeps it there:** the bare harness player faces UP by default, so the nose cone pushes the hull off the vertical. The 0.18/0.30
  asymmetry drifts it net one way. Reversals take 3–6 s.

State these for each of the three rows:
- the player's position (e.g. (640, 620), like the cone rows);
- the start bearing;
- the cone settings (cones 0 for the arcs and reversals rows, as written; say what holds range uses);
- a measuring window that keeps the hull in the upper half (e.g. the arcs rate over at most 4 s after a 1 s settle in Assault).

Without this, a seeded Assault run can leave the band or drop into BREAK_OFF, and the row is unpassable for reasons unrelated to the
behaviour under test. Optionally, the life row could also say that clamp-induced break-offs are expected with a centred player, so that
nobody "fixes" them.

**R4. Make the hub-idle distances hull-relative, or size them for the ring (plan l. 160-161).** The hull orbits up to `idle_radius` 160 px
(plus a little overshoot) from the anchor.
- **As written, if the distances are measured from the anchor:** a player 900 px from the anchor comes within about 700–740 px of the hull
  (< 760), so the "IDLE for 4 s" main row notices. The "player at 780 → still IDLE" control notices too.
- **Fix:** re-place the player every tick at 900 / 740 / 780 px from the hull, along a fixed direction. That keeps the tight 760 boundary
  meaningful. Alternatively, follow the corvette precedent `perceive_radius + idle_radius + 100` (`test_missile_corvette.gd:1177`) and
  drop the tight boundary.

## Non-blocking

- **N1.** Plan l. 52-53 says `cone` "returns 0" when the bearing is exactly on the axis. l. 66-67 says it returns the current `orbit_dir`.
  The second is correct (§2.10 (b): the escape speed applies on the centre line). Fix the first.
- **N2.** The near-way Assault run is about 96° of arc, not about 86°: 20.6° warm-up + 20° + 36° + 20°. Started 45° off, it ends about 51°
  past straight up, which is still fine.
- **N3.** On the tick BREAK_OFF is entered, `_tick_hold_arc` returns after `enter_phase`, so no request is made and the hull brakes for one
  tick before the boost. Consider running the break tick on entry.
- **N4.** "BREAK_OFF on the first tick inside 420" has an off-by-one. The brain tests the pre-move distance and the test reads the
  post-move one, so allow one tick.
- **N5.** "Radial 322 ± 2 px/s" only holds on a burst's first tick: against a re-aiming rusher the line of sight swings toward the
  velocity and the radial grows. Say so.
- **N6.** Cheap rows worth adding:
  - the `_disengage_pending` deferral through the stubs (`enter_phase(TELEGRAPH)` at budget expiry → DISENGAGE on the next tick, not
    HOLD_ARC);
  - `on_suspended()` (light OFF, `anchor_idle` null).
- **N7.** Two existing rows are weak:
  - Measuring `_orbit_angle`'s rate is close to tautological. Measuring the hull bearing's rate after a 1 s settle would show the body
    actually follows the asymmetric arc.
  - The "start on `held_range()`, 20 s in band" half passes for a ship that never moves. Its teeth are only the far-start half and its
    `max_speed 1` control.

## Round 2

VERDICT: APPROVED

I re-read the revised `3-plan.md` and checked the new geometry against the same code: the clamp rect `view_rect().grow(-68)` is
(68..1212, 68..652) on the 1280 × 720 view (`tests/unit/test_enemy_world.gd:36`, `arena_camera.gd:102-104`); the corridor is
(−100..1380, −380..1100) (`assault_corridor_constraint.gd:94-100`); and `AnchorIdle.update` uses the hull position (`anchor_idle.gd:52-69`).
For the numbers below I re-ran my simulation of the exact mover rule.

### Round-1 findings: all resolved
- **R1** (plan l. 79-81): `dir` is normalised and the point is 230 px ahead. Fixed.
- **R2** (l. 127-130): `_spawn` writes `engage_seconds = 1000` before `props`. Only the Assault-life rows put 9.0 back, and the probe
  uses the shipped scene. Fixed.
- **R3**: the Assault geometry is now pinned, and I checked it:
  - **Holds range** (l. 137-141). Starting at −30° and forced +1 at 0.18 rad/s for 6 s gives 62° of travel, ending at +32°.
    - The 520 ± 90 ring stays in the clamp rect, except straight up at r 610, where the clamp gives 552 px (still in band).
    - The far start (640, −280) is inside the corridor, so the latch is entered at once and the filter is the identity. It reaches 670 px
      in about 1.2 s, under the 3 s bound.
    - The `max_speed` 1 control stays at 900 > 670.
  - **Arcs** (l. 142-144). Simulated hull bearing rate over [1 s, 4 s]: 0.1797 / 0.2996 rad/s at 520 and 0.1798 / 0.2997 at 720, inside
    ± 0.01. The ±40° starts keep the run within 41° of straight up.
  - **Reversals** (l. 145-146). Starting straight above, the worst draw (−1 for 6 s) reaches about 103°. The clamp still holds the hull in
    view there, and the row does not assert `view_clamp_bound`. See N-a for the one marginal case.
- **R4** (l. 170-173): the player is re-placed every tick at a fixed distance from the hull. `AnchorIdle` reads the pre-move hull
  position against that player, so these hold:
  - 900 px stays IDLE;
  - 740 px goes to NOTICING on that tick;
  - COMBAT comes 21 ticks (± 1) later;
  - the 780 px control stays IDLE.
- **N1–N7**: all addressed. N1 is fixed at l. 53. N2 is corrected to 96°, which matches my 96.7°. N3 is the same-tick break on entry. N4
  and N5 are reworded. N6 adds the deferral and suspension rows. N7 measures the hull bearing.

### Non-blocking (for the builder)
- **N-a. The Assault rows with live range drift sit about 10 px above `min_range`.** The drift trough is r 430 against a 420 break-off.
  - **Holds-range row:** simulated minimum about 428–431 px.
  - **Reversals row:** one extreme draw dips just under 420: first direction −1, first reversal at about 6.0 s, drift phase 0 with a period
    of about 8 s (419.6 px).
  - **Effect:** that would trip BREAK_OFF and fail the "never left HOLD_ARC" assertion for a reason unrelated to reversals.
  - **Fix:** set `range_drift` 0 in the reversals row (it tests the clock, not the drift). Keep the holds-range row's drift; its 10 px margin
    is deterministic under seed 1.
- **N-b. The suspension row** (l. 177) can only pass: nothing in t8 turns the light on. Set the `StateLight` to a non-OFF state first, and
  give `anchor_idle` a non-null value with an Open Space cold start, so that "turns OFF / drops it" can fail.
- **N-c. The deferral row's control** (l. 175-176) does not tell the two cases apart by timing. Because the stub leaves TELEGRAPH on the
  same tick it is ticked, both cases reach DISENGAGE on the expiry tick. What this row really catches is a stub that drops
  `_disengage_pending`; that would land in HOLD_ARC and never leave, because `_expiry_seen` is already true. To pin it, assert the
  `phase_changed` sequence TELEGRAPH → DISENGAGE with no HOLD_ARC in between, rather than relying on tick timing.
