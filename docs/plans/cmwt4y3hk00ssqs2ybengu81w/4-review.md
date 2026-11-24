VERDICT: CHANGES_REQUESTED

# Review 1 — t6 Space Fortress movement (3-plan.md)

Checked against the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` ("For every task", §2.5.5, §2.6, §2.16) and the code @ `2f10b38`:
`fortress_brain.gd`, `space_fortress.gd`, `space_fortress.tscn`, `space_fortress_config.gd`, `global/enemy_ai/enemy_mover.gd`, `anchor_idle.gd`, `steering.gd`,
`target_info.gd`, `base_enemy.gd:126-139, 178-208`, `carrier_brain.gd:110-245`, `tests/integration/test_space_fortress.gd`, `test_carrier.gd:118-121`,
`test_heavy_gunship.gd:1135-1155`, `test_enemy_mover_single_writer.gd`.

The design itself is sound and matches §2.6: the facing formula is right (mover target rotation = `heading.angle() - sfa` = `bearing - L`, so the sector at local
bearing L points at the player; `enemy_mover.gd:261-270`); with `turn_lerp` 0 a 1 rad lead is capped to exactly `rate · dt`, and the row-6 boundary arithmetic is right
(`lerp_angle(r, r + 1, 0.3/60)` = 0.005 rad/tick = 0.3 rad/s < the 0.5 cap); `AnchorIdle`'s fifth argument is `p_home_radius` (`anchor_idle.gd:32`) and its distances are
actor → target (`:78-79`); `arrive` with decel 0 is full speed (`steering.gd:31-35`, overshoot ≤ 1.5 px/tick < the 2 px arrival band); `hold_position` is exactly zero
inside tolerance (`:77`); EMP needs nothing new (`base_enemy.gd:129-134`: mover steps with no request → v 0, heading length 0 → no rotation write); `on_boss_phase`
for `batteries` really does run from `driver.bind()` inside the root's `_ready()` (`space_fortress.gd:128-129, 248`), so the lazy mode read is needed; no bays exist yet
(`test_space_fortress.gd:672`), so `is_engaged()` turning true changes nothing in t5's rows (all hand-driven with physics off). Circling numbers hold: OS
`cruise_speed()` = `max_speed` 420 (`player_ship.gd:483`) → 0.84 − 0.22 = 0.62 rad/s → 2.5 rad in 4 s; Assault 360 → 0.72 − 0.30 = 0.42 → 1.68 rad > 1.5. The
Thrusters split (`visible` phase-driven, `modulate.a` travel-driven) is a sensible resolution of §2.5.5 vs §2.6 and keeps the §25 key clean.

The changes requested are all in the test plan: three rows as written cannot fail on a plausible wrong implementation, and one is machine-speed flaky.

## Must fix

1. **Row 3's recomputation must be independent of the brain** (3-plan.md:50-53, :82-84). The plan makes `pick_station_point(current, player_ahead)` public "so the
   test can recompute it". If the row calls that function to get its expected value, it is tautological for the rule (nearest-instead-of-farthest, a wrong ring
   radius, a missing ≥ 250 px filter or the wrong tie order all pass); the acceptance criterion says "recomputed by the test". The test must build the 8 candidates
   itself from the config (`anchor + Vector2.from_angle(k·TAU/8) · station_ring_factor · zone_radius`), filter, argmax, and compare; it may additionally compare with
   the brain's function. Also make the 60 s loop non-vacuous: assert the number of station-point changes (picks at t = 0, 8, …, 56 → 8; or ≥ 7) — as written, a brain
   whose clock never fires asserts nothing and passes.

2. **The turn rate is only bounded above, never pinned** (3-plan.md:75-76). "per-tick rotation change ≤ `turn_rate · dt`" passes on a hull that turns slower
   (or not at all until the 0.02 rad end check after an unlimited wait), and in Assault it passes with the OS rate 0.22 instead of `assault_turn_rate` 0.30 — the
   circling row also passes at 0.22 there. On the north → south swap (≈ π rad) assert the per-tick change **equals** the mode's rate · dt (almost_eq, 1e-6) for the
   first N ticks, in both harnesses; that distinguishes 0.22 / 0.30 and the turn_lerp trap.

3. **The tie and halving cases cannot fail on a naive rule** (3-plan.md:42-43, :76-77). The only tie case (north 2 · 0.5 = 1.0 vs south 1, current north) keeps
   north under both "tie keeps current" and the naive `north if north >= south`; and since north 2 > south 1 without halving too, the presented side cannot reveal a
   missing halving either (only a `sector_strength()` value assert would). Add: (a) a tie with **current south** (from start, kill one south battery: 2 vs 2 → stays
   south; a `>=`-north rule flips), and (b) a halving case that **changes the presented side** (south generator dead: 3 · 0.5 = 1.5 < north 2 → north turns to the
   player).

4. **Hand-ticked facing while the hull moves reads the idle delta** (3-plan.md:104, rows 5 and any facing assertion during ENTER / bob / travel). `_tick`
   (`test_carrier.gd:118-121`) fixes the position, but `EnemyMover.step()` computes the heading from the position *after* `move_and_slide()` (`enemy_mover.gd:258,
   262`), which outside a physics frame moved by velocity × the last idle delta; the face point is only 100 px from the pre-move position, so a 0.14 s idle frame at
   55 px/s biases the facing target by ≈ 0.08 rad. This is exactly the Ph10 rule in CLAUDE.md (`test_heavy_gunship.gd:1135-1146`). Row 5's "the rotation follows it"
   during the bob must either run under a copied `_fresh_idle_delta()` (and then await no physics frame — a frozen clock never delivers one, so do the part kills
   without `_settle()`, which present_side does not need) or the brain uses a long lever (e.g. 1e5 px instead of 100; the lever length is not load-bearing in §2.6).
   Spins are immune (a 1 rad lead), and rows 1, 2 and the circling row hold still. Say which in the plan. Related: the Assault rows other than row 5 must spawn at
   y = `assault_hold_y` (the t5 `SPAWN` y 360 is "below" 180, so HOLD climbs the hull 180 px at 90 px/s through the first 2 s of every Assault row — the circling and
   spin rows would be measuring a moving hull).

5. **Row 6's SceneState read must not require the key to be present** (3-plan.md:20, :91). Godot's packer drops a property equal to its default on save
   (`turn_lerp = 0.0` equals the script default `enemy_mover.gd:56`), so the first harmless editor re-save of `space_fortress.tscn` strips the line and a
   "the scene authors it" check fails with nothing wrong. Assert the resolved value — the SceneState value if the key is present, else the script default — is 0,
   plus the instance value; the `turn_lerp` 0.3 boundary is what makes it load-bearing.

## Should fix

6. **The thruster alpha has no row** (3-plan.md:57-59). `is_travelling()` → `Thrusters.modulate.a` 1.0 / 0.35 can regress silently. One assertion in row 3 (OS
   travelling vs holding) and row 5 (bob vs hold), plus "the §25 `visuals` key is identical travelling and holding".

7. **The Assault x correction is untested** (3-plan.md:56, :88-89). Nothing in the harness displaces x (mask 0, no drift), so "x within 1 px" holds for an
   implementation with no `x_fix` at all. Add a boundary: offset x by 30 px, assert |vx| ≤ `assault_x_correct_speed` and convergence to the anchor x.

8. **Pick ties are float noise** (3-plan.md:51-52). With `from_angle(k·TAU/8)` two candidates symmetric about the player line differ by ~1e-5 px, so "strict `>`,
   lowest index wins" is decided by rounding, and an independent recomputation (finding 1) that orders operations differently can disagree. Use a small epsilon in
   both (`d > best + 1e-3`) so the documented tie rule actually holds.

## Notes (no change required)

- 3-plan.md:50: `pick_station_point` reads the anchor and config, so it is an instance method, not "static"; harmless wording.
- The mover's `hazard_resistance` is 0 (`enemy_mover.gd:65`): a hub Gravity Field near the anchor (t13) would drift the hull off its zone / x. Outside §2.6; worth a
  line in DECISIONS for t10 / t13.
- `THRUSTER_IDLE_ALPHA` is a brain constant, not config; acceptable for a visual, but say so in DECISIONS with the thruster deviation.
- Row 1's notice transition: `_notice_elapsed >= notice_time` after 48 additions of 1/60 may land on tick 48 or 49; assert a bound, not an exact tick.
- Row 5's "spawn x" must be read after `_ready()` (the `world_anchored_x` shift, `space_fortress.gd:104-105`).

## Round 1 — author's response (revision 2 of 3-plan.md)
- R1-1: row 3 now builds the candidates from the shipped config itself and asserts exactly 8 picks over 60 s.
- R1-2: row 2 asserts the per-tick change **equals** the mode's rate during both large turns (OS 0.22 vs Assault 0.30).
- R1-3: tie cases from both sides, and a halving case that flips the side (south generator dead: 1.5 vs 2).
- R1-4: the brain's face lever is `FACE_REACH` 10 000 px; Assault facing rows spawn at y 180 and run under `_fresh_idle_delta()`.
- R1-5: row 6 checks the resolved value (0) on the instance, not the `.tscn` line.
- R1-6: new row 9 (thrusters alpha, `visible` untouched). R1-7: an x-offset correction case in row 5. R1-8: `PICK_EPS` 0.001 in both brain and test.
- Notes: `pick_station_point` is an instance method; row 1 notice asserts a tick range; spawn x read after `_ready()`.

## Round 2

VERDICT: APPROVED

Re-read revision 2 of `3-plan.md` from disk and re-checked the changed points against the code. Every round-1 finding is answered:

- **R1-1** (3-plan.md:77-78, :96-99): the expected pick is now the test's own, built from the shipped config (`anchor + from_angle(k·TAU/8) · 0.6 · 600`, the
  ≥ 250 px filter, farthest from position + velocity × 1 s, `PICK_EPS` ties), never the brain's helper. "Exactly 8 picks" holds: the clock is zeroed on
  `core_exposed` (pick at t 0), the start_engaged fortress has no leash so it stays engaged, every candidate is 360 px from the anchor (so the first pick always
  changes the point), and the ≥ 250 px filter means every later pick does too. The pick at 64 s falls outside the 3600-tick window, so float drift of ±1 tick per period
  cannot add or remove one.
- **R1-2** (:84-86): per-tick change **equals** the mode's rate (1e-5) on both ~π turns. That tells 0.22 from 0.30 (0.0037 vs 0.0050 rad/tick) and catches a
  slow or lerped turn. Float32 `rotation` noise near π is ~2.4e-7, well inside the tolerance.
- **R1-3** (:87-89): (a) a tie with south current (2 vs 2) fails a `north >= south` rule and (b) a tie with north current fails a `south >= north` rule, so together
  they pin "tie keeps current". "South generator dead → north" (1.5 < 2) makes halving change the presented side. `EnemyModule.destroy()` works on a locked
  generator (`enemy_module.gd:207-212`: no lock check), so the cases are reachable on fresh fortresses.
- **R1-4** (:41-43, :76, :107-108): `FACE_REACH` 10 000 px cuts the idle-delta skew to ~1e-3 rad (12.6 px at a 0.14 s frame and 90 px/s), and float32 keeps ~1e-3 px
  at that magnitude, so the direction stays exact. Assault rows spawn on the hold line. Row 5 also uses `_fresh_idle_delta()`.
- **R1-5** (:109): it now checks the resolved instance value, and the `turn_lerp` 0.3 boundary still proves the value matters.
- **R1-6** (:118-119), **R1-7** (:105-106: 30 px → clamp(120, ±20) = 20 px/s for ~1.25 s, then the ×4 decay to < 1 px in ~0.4 s; fails with no `x_fix`),
  **R1-8** (:54, :98): all addressed. Row 1's notice is now a range (48 or 49 ticks after NOTICING), which still fails if it engages early.

Minor notes for the implementer (no re-review needed):

1. **Row 5 under the frozen clock** (:107-108): reaching `critical` needs the core's deferred `set_vulnerable(true)` (`space_fortress.gd:238`; a locked part ignores
   damage). Under `_fresh_idle_delta()` a `physics_frame` never arrives, so the t5 `_settle()` would hang. Flush the deferred call with `await get_tree().process_frame`
   (the message queue is flushed every idle frame), or freeze only after the last unlock. Add the Ph10 `_thaw_idle_clock()` to this file's `after_each()`.
2. **Row 2's "until it settles"** (:84-85): assert equality only while the remaining error to the target exceeds `rate · dt`, so the final partial tick is excluded.
   Then add the end assertion (within 0.01 rad).
3. **`FACE_REACH`** departs from §2.6's literal `· 100`. That is harmless (only the direction is used), but log it in DECISIONS under `### Phase 11, built in t6`,
   together with the thruster alpha split and the `THRUSTER_IDLE_ALPHA` constant.
4. Row-5 facing equality is already exact because of the turn-rate cap (the target is far away). The 10 000 px lever and the frozen clock are belt and braces, so if
   freezing complicates the unlock sequence, the lever alone is sufficient for that row.
