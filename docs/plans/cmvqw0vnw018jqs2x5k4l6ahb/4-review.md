VERDICT: APPROVED
## Round 1

Reviewer: independent subagent. I read the plan (`3-plan.md`), `1-context.md`, the epic plan's "For every task" section and §2.1, §2.3, §2.4, §2.12 and §2.19,
`CLAUDE.md`, and the Phase 8 section of `DECISIONS.md` (t2, t4, t5, t9–t11 built notes). I checked the plan against the committed code at `d865fa2`. I looked
at the uncommitted draft only to see whether the plan can be built; the verdict is about the plan.

The design is sound and follows §2.12 closely. The rig is a RefCounted with leader-only transitions. Strain is counted on the rig clock, and the beam's own
phase gates the move from TELEGRAPH to ADVANCE. Assault frames are planned inside an inset `inner_rect()`. The spawner copies `TurretGroup`, and the collapse
copies `LaserFence`. It reuses what exists and adds no new mechanism. Three things must change before it is built, though. One is a motion bug the real
`EnemyMover` causes. The other two are test rows that fail, or prove nothing, on a correct build.

### Blocking

**B1. The ADVANCE boost keeps running after a collapse or a kill** (plan l.156 against `global/enemy_ai/enemy_mover.gd:113-121, 221-246, 272-273`).
- **The problem.** The plan has each drone call `mover.boost(pair.advance_dir(), advance_speed, pair.advance_left)` every ADVANCE tick. That sets the mover's
  `_boost_left` to *the time left in the whole advance*. While `_boost_left > 0`, `step()` ignores every request, nudge, `max_speed` and the acceleration
  limit. `EnemyMover` also has no way to cancel a boost.
- **What breaks.** After a strain COLLAPSE mid-ADVANCE, or after a partner is killed mid-ADVANCE, the surviving drone(s) keep flying along `-n` at 240 px/s
  for up to the remaining `advance_left`: about 1.4 s after a kill on ADVANCE tick 30 (row 7), and about 1.2 s after the wreck row's collapse. During that
  time every request is ignored:
  - BREAK's `request_velocity(u · side · break_speed)` (l.158);
  - SOLO's `arrive` (l.160);
  - DISENGAGE's `request_velocity(exit_dir · exit_speed)` (l.167).
- **Effect in Open Space.** A collapsed pair coasts on (beam off) through the player's latched position and spends most of `break_seconds` (1.2 s) still
  advancing. This contradicts §2.12's "survivors BREAK and re-FORM" and the plan's own BREAK motion.
- **The normal end works only by coincidence.** At the advance's normal end the two clocks happen to run in step: the rig's `advance_left` and the mover's
  `_boost_left` are decremented by the same `delta`. A float residue below `EPS` still leaves one extra boosted step.
- **No row catches it.** Rows 7, 8, 9 and 17 assert phases and beam state, never motion.
- **Fix.** Renew the boost for one step only, `boost(dir, advance_speed, delta)`, so the rig's `advance_left` stays the one clock. Alternatively, cancel it on
  leaving ADVANCE with `boost(Vector2.ZERO, 0.0, 0.0)`.
- **Assertions to add.** In rows 7, 8 and 9, on the tick after the kill or the collapse: `mover.is_boosting()` is false, and the survivor's `own_velocity()`
  turns toward its new request: along `±u` for BREAK, toward the anchor for SOLO, `exit_speed` for DISENGAGE.
- **Note.** The draft brain already uses the one-step boost (`twin_laser_drone_brain.gd:154`). The plan is the spec, so it must say this.

**B2. Row 5's 200 px/s case cannot pass as written and does not test what R8.24 asks** (plan l.217-219, l.234-239, Risks l.319-321).
- **Why the boundary fails.** The test geometry spawns the drones on their slots, and the plan itself says "the first TELEGRAPH comes within a tick or two".
  The FORM-to-TELEGRAPH condition is "within `slot_tolerance` 24 of the slots, error ≤ 16". It holds on tick 1: the slots have moved 200/60 = 3.3 px and the
  drones are at rest. The latch therefore comes after FORM has moved the centre 3.3 px. The in-row boundary "centre changed by > 100 px before the latch"
  fails on a correct build.
- **Why the case tests nothing new.** TELEGRAPH and ADVANCE are latched. TELEGRAPH motion is `arrive(slot)` with no feed-forward (l.155), and ADVANCE is a
  boost. So the 200 px/s case measures exactly what the standing case measures: drones that are at rest at the latch.
- **The named risk is never exercised.** The plan's own Risk 1 (l.319) is that a drone moving at 200 px/s must stop on the latched slot. `Steering.arrive`'s
  slowing radius is `v²/(2·accel)` (`steering.gd:26-35`), so from 200 px/s at 900 px/s² the overshoot is about 22 px. No case ever latches while the drones
  are moving.
- **The geometry note is wrong too.** l.219 says "FORM convergence is exercised by the moving stub". That is only true after this fix.
- **Fix.**
  - Spawn the moving cases off their slots, trailing by at least 120 px along `-u` (the draft does this, `test_twin_laser_drones.gd:355`). FORM then tracks the
    stub for over 0.5 s.
  - Keep the > 100 px boundary.
  - Add "both drones' own speed on the latch tick ≥ 100 px/s", so the latch-while-moving case is proven to happen.
  - Keep the length check on every TELEGRAPH tick; that is where the overshoot happens.

**B3. The wreck row has no no-hazard control, and its stated control is not derived** (plan l.282-285).
- **The missing control.** The acceptance criterion says "a well or a wreck strains and collapses it (with no-hazard controls)". The well row has its control
  (l.254). The wreck row's "control: A advanced > 200 px meanwhile" is not a no-hazard control.
- **Where the strain actually starts.**
  - `wreck_large.tscn`'s body is r 40 (`wreck_large.tscn:10-11`). Placed at `body_radius + 60` = 73 px, it leaves a 20 px gap, so B stops after about 20 px.
  - The strain needs `sqrt(L² + d²) − L > 16`, i.e. a lag `d > 117` px. So the strain starts with A about 137 px into the advance, and COLLAPSED comes
    0.15 s later with A at about 173 px.
- **Why the 200 px figure means nothing.** Whether "A > 200 px" passes depends on when it is read:
  - about 173 px at the collapse;
  - about 220 px once A has decelerated into BREAK;
  - the full 460 px under B1's bug.
- **Fix.**
  - At the collapse tick, assert A's progress minus B's is above the lag derived from `rig_length` and `length_tolerance`, and that B stopped short (< 60 px).
  - Add a real no-hazard control. Either run the same real-physics attack without the wreck in one mode for the same ~1.6 s of game time (about 0.2–0.3 s of
    GUT) with zero strained ticks. Or check in the same run: zero strained ticks before B's first contact (B's own speed along `-n` drops below
    `advance_speed / 2`), and the first strained tick after it.

### Non-blocking

- **N1. Re-FORM after an Open Space attack is undefined** (l.118-121, "the first frame takes it outright").
  - *The problem.* After ADVANCE the drones sit `overshoot` (200 px) past the player, so `n_target` is `−n_old`. If `has_frame` survives BREAK and WAIT, `n`
    has to turn 180° at 90°/s (2 s). Meanwhile the slots, 334 px from P (the length of (260, 210)), swing at up to 525 px/s, faster than `max_speed` 300. The
    drones chase slots round or back past the player and can hit `form_timeout` 3.0.
  - *This is live.* The draft keeps `has_frame` (`twin_laser_pair.gd:264`).
  - *Fix.* State that FORM entry from BREAK or WAIT takes `n_target` outright, keeping the `u` hysteresis.
  - *Row 15 (Open Space)* should assert that the second frame lies on the drones' side (`n·(mid − P) > 0`) and that the second TELEGRAPH starts within
    `form_timeout` of the FORM entry.
- **N2. `died` fires before `queue_free()`** (`base_enemy.gd:246-249`). So inside `_on_drone_gone`, `is_queued_for_deletion()` is still false. `leader()` and
  `is_intact()` (l.85-86) must read the rig's own broken/gone flag, not only queued-for-deletion. "COLLAPSED for good" implies such a flag; name it.
- **N3. The rig is outside the single-writer gate.** `test_enemy_mover_single_writer.gd` (l.9-20) sweeps `*_brain.gd`, `global/enemy_ai/*.gd` (through the
  receivers `actor.`, `_actor.`, `body.`, `_body.` and `self.`) and mover-driven roots. `twin_laser_pair.gd` and `twin_laser_pair_spawn.gd` hold the drones
  as `drone_a` / `drone_b` / `d`, so the context's claim that "the rig only computes frames" is not gated. Add a row in the new test file that rejects any
  velocity or rotation write, or any `move_and_slide`, through any receiver in those two files (with a synthetic boundary). Or extend the sweep.
- **N4. The ARMED light is never asserted.** §2.3 (epic l.242-244) says ACTIVE shows ARMED, but only CHARGING is checked (the dual-mode case). In row 5 or
  row 7, assert ARMED on every lit tick and OFF after the beam goes out.
- **N5. Row 18 reads the midpoint too late** (l.288-290). On real physics the drones are already AI-driven "after a few frames", and FORM will have moved
  them. For example, a spawn at cam + (0, −200) = (640, 160) moves toward a centre at (640, 100) for a player at (640, 360). Read their positions on the
  `enemy_spawned_orphan` emission or on the first frame, or use a tolerance.
- **N6. The rail-suspension path has no row.** `release()` frees the beam when A is suspended (l.89-90), and `is_intact()` reads `is_ai_suspended()`. Add one
  hand-ticked case: `A.suspend_ai()` in TELEGRAPH means the beam and its hazard are gone after one frame; `B.suspend_ai()` means A fades the beam to OFF.
- **N7. Row 16 should test the worst case** (l.276-279). The tight case is a budget that expires on the latch tick:
  - DISENGAGE then comes 47 + 1 + 115 = 163 ticks (2.717 s) after the latch tick k. The beam goes ACTIVE on its 48th tick (k+47); the rig reads
    `beam.phase()` one tick later and enters ADVANCE (k+48); then come 115 ADVANCE ticks.
  - The bound is 0.8 + 1.917 + 2/60 = 2.75 s, a margin of 2 ticks.
  - The 0.3 s-into-TELEGRAPH case keeps 0.33 s of slack, so it would also pass a bound that was a tick or two wrong. Use the latch-tick expiry, or both.
- **N8. Docs** (l.209-210). t9–t11 each added to the Phase 8 gates paragraph of `CLAUDE.md`; list it here as well (the skill would get there anyway). The
  epic's §7 gives t12 the R8.25 IDEAS §43 design checklist, which belongs in `ENEMY.md`.

### Checked and correct (no change needed)

- **Tow table.** `test_base_enemy.gd:501-518` at HEAD needs `start_engaged` and `enter_phase()` on a lone drone, and falls back APPROACH → ENTER. Adding FORM
  as the third fallback is right, and `_MIN_ROSTER_SIZE` 18 → 19 is right.
- **The corridor numbers.** `inner_rect()` = Rect2(−100, −380, 1480, 1480) (`assault_corridor_constraint.gd:83-89`, `arena_camera.gd:40-43`); inset by 24 it is
  (−76, −356)…(1356, 1076). The plan's numbers hold:
  - row 14: 106 px of room above, 956 px right and 476 px left;
  - row 13: the centre clamps to x 134 and the line −76…344 still covers P.x = −40;
  - the overshoot clamp keeps the advance's end inside.
- **The well row.** I simulated the real `HazardInfo.falloff` / `HazardDrift` (half-life 0.35 s, resistance 0.1) on the stated geometry:
  - FORM and TELEGRAPH are untouched: B's slot is 453 px from the well, outside its 420 px reach;
  - B enters the reach 53 px into the advance;
  - the first strained tick is ADVANCE tick ≈ 69 of 115, and COLLAPSED comes ≈ 9 ticks later with ≈ 23 px of lateral drift (> 16);
  - A's path is 760 px away;
  - without the well there is no strain.
- **The twin fairness row** is buildable on `_player_terms()` and `_synthetic()` (`test_enemy_beams.gd:132, 236`): 0.833 ≤ 1.883 s, 240 < 360, static 0.334 ≤
  0.8 s. All three boundaries reject.
- **`EnemyBeam`** matches the plan: `start()` is ignored in TELEGRAPH/ACTIVE; `cancel()` goes TELEGRAPH → OFF and ACTIVE → FADE; the hazard unregisters on
  cancel and in `_exit_tree`; cover is cast only on the physics step and excludes the host. `EnemyMover._avoid` drops a hazard whose `exempt_group` the actor
  is in (`enemy_mover.gd:292`). TELEGRAPH lasts 48 rig ticks and ADVANCE starts inside `ignite_grace`.
- **Engine and spawner behaviour.**
  - `EngagementBudget.active` is Assault-only.
  - `ScoreTracker` reads the spawner's scoring flags duck-typed (`score_tracker.gd:137-143`).
  - `EventBus.enemy_spawned_orphan(enemy: Node)`.
  - `WaveManager._spawn_ship` sets the spawn position before `add_child`.
- **Tick order.** A is added first, so A runs first in tree order, and a reversed order costs ≤ 4 px.
- **Dependencies are acyclic**, and the RefCounted rig names itself as `TargetInfo` does, with the leak check planned.
- **Coverage.** No §2.12 or §2.19 requirement is dropped, and the out-of-scope list matches the epic's t13 / t14 / t16 / t18 / t19 split.

## Round 2

Reviewer: independent subagent (round 2, the last allowed). I re-read the revised plan (`3-plan.md`), `1-context.md`, Round 1 above, the epic's "For every task",
§2.1, §2.3, §2.4, §2.12 and §2.19, `CLAUDE.md` and the Phase 8 section of `DECISIONS.md`. I checked the plan against the committed code
(`global/enemy_ai/enemy_mover.gd`, `steering.gd`, `engagement_budget.gd`, `assault/scenes/enemies/base_enemy.gd`, `test_enemy_mover_single_writer.gd`,
`wreck.gd`, `hazard_field.gd`) and against the uncommitted draft (`assault/scenes/enemies/twin_laser_drone/*`, `tests/integration/test_twin_laser_drones.gd`, the
shared-file diffs). I did not run Godot. The verdict is about the plan; the draft was read only to confirm each fix can be built and can fail.

**Verdict: APPROVED.** All three blocking findings and all eight non-blocking findings from Round 1 are resolved in the plan. The draft already builds every one
except N3's row 4b, which the plan specifies and the implementation still has to add. Nothing new is blocking. The non-blocking items below are cheap and can be
done during implementation without another review.

### Round 1 findings

- **B1: resolved.**
  - *Plan.* l.170-174 now specifies `mover.boost(pair.advance_dir(), advance_speed, delta)`, renewed every tick, so the rig's `advance_left` is the one clock.
  - *Motion rows.* Row 7 (l.273-275), row 8 (l.277) and row 9 (l.283-285) now assert the survivors' motion on the next tick. The deviation from §2.12's literal
    `boost(…, advance_left)` is logged in `DECISIONS.md` (draft diff).
  - *Mover check.* `enemy_mover.gd:115-121, 221, 272-273`: a boost with `duration = delta` is applied for exactly one `step()`, then `_boost_left` goes to 0.
  - *Draft.* `twin_laser_drone_brain.gd:154`; the assertions are in `test_twin_laser_drones.gd:437-447`, used at :472, :503 and :566.
  - *Can it fail?* The velocity half rejects the old design:
    - SOLO: under a lingering boost the change in velocity is zero, so the dot product toward the anchor is 0 and `assert_gt(…, 0)` fails.
    - DISENGAGE: the velocity is exactly `advance_speed`, which is not `> advance_speed + 1`.
  - *Well-row Open Space case.* `context_avoid` (16 slots, well `avoid_weight` 1.0, threshold 0.4) bends B's +u break request away from the well, which lies almost
    exactly along +u at the collapse. I worked both possible best slots through by hand: B's own velocity after the two un-boosted steps still has u > 0 and a
    component along −n < 239. The row holds on a correct build.
  - *Note.* `is_boosting()` read after a tick is false on *any* tick under the one-step design, ADVANCE included. That half only guards against reverting to the
    `advance_left` boost; the velocity half is what carries B1. No change needed.
- **B2: resolved.**
  - *Plan.* l.238 and l.258-266: every case spawns 120 px off its slots along −u. The 200 px/s cases keep the "> 100 px of centre motion before the latch" boundary
    and add "both drones' own speed on the latch tick ≥ 100 px/s". The length is checked on every TELEGRAPH tick.
  - *Draft.* `test_twin_laser_drones.gd:376` (the off-slot spawn), :209-211 (latch speeds), :392-398 (both boundaries).
  - *Why the latch now happens while moving.* The slots move at the stub's 200 px/s and the drones carry the same feed-forward. The overshoot after the latch is
    about 22 px (`v²/2a`), and both drones overshoot it in the same direction, so Risk 1 is exercised and measured.
- **B3: resolved.**
  - *Plan.* l.322-330: row 17 reads at the collapse that B's progress ≤ `60 − wreck.body_radius() + 2`, and that A's lead over B ≥ `sqrt((L + tol)² − L²)`.
  - *Checking the bound.* `wreck_large.tscn:11` has r 40, and the wreck is placed `drone_r + 60` = 73 px ahead. Contact comes at 53 px, so B travels 20 px.
  - *Draft.* :873-885. The derived lag is about 117 px; the expected lag at the collapse is about 153 px.
  - *No-hazard control.* Row 17b (l.328-330, draft :888-921) is a real no-hazard control on the same real-physics spawn. A `_Sampler` child checks the length on
    every TELEGRAPH / ADVANCE physics frame.
  - *Alignment.* The geometry puts B exactly behind the wreck centre (x 850 = 850), so `move_and_slide` has no tangential slide to eat the +2 px slack.
- **N1: resolved.** Plan l.128-131 says every FORM's first frame takes `n_target` outright. The draft sets `_fresh_frame` on FORM entry
  (`twin_laser_pair.gd:81, 269-272, 351-352`). Row 15 (l.311-313, draft :776-786) asserts `n·(mid − P) > 0` on the re-FORM's first tick. Without the fix that is
  negative (the old n points away), so the row discriminates. It also asserts the second TELEGRAPH comes inside `form_timeout` with no BREAK between.
- **N2: resolved.** Plan l.92-96: the rig's `_gone` set is filled in `_on_drone_gone` and `release()`, and `_live()` reads it first (`twin_laser_pair.gd:76-79,
  372-385`). Draft row `test_inside_the_death_hook_the_rig_already_counts_the_drone_gone` (:619-632) pins it; see new item 2.
- **N3: resolved in the plan, not yet in the draft.** Row 4b (l.252-255) is specified. `test_twin_laser_drones.gd` has no such test yet, so it must be added
  before the gate. See new item 1 for its matcher.
- **N4: resolved.** Row 5 (l.262-263) checks every tick: CHARGING while the beam telegraphs, ARMED while it is ACTIVE, OFF otherwise. In the draft this is
  `_lens_for` / `lens_mismatches` (:205-208, :245-254, :389), and row 8 checks A's lens ends OFF.
- **N5: resolved.** Row 18 (l.333-335) reads the midpoint on the `enemy_spawned_orphan` emissions (draft :935, :950-953). `spawn_pair()` sets the positions
  before `add_child` and emits right after `bind()`, before any physics tick (`twin_laser_pair_spawn.gd:42-52`).
- **N6: resolved.** Row 11b (l.293-295, draft :640-678) covers both rails.
  - *Ordering checked.* `base_enemy.gd:131-137` sets `_ai_suspended` before `on_suspended()`. So `release(A)` sees `_suspended(A)` and frees the beam
    (`twin_laser_pair.gd:239-241`).
  - *Rail on B.* `_break_for_good()` cancels a TELEGRAPH beam to OFF and unregisters the wall.
- **N7: resolved.** Row 16's `latch` case (l.314-317, draft :794-820) runs with `engage_seconds = DT` on drones that start on their slots.
  - The budget expires on the latch tick (tick 1).
  - DISENGAGE comes on tick 1 + 47 + 1 + 115 = 164, at 2.733 s, against the bound DT + 0.8 + 1.917 + 2/60 = 2.767 s: a 2-tick margin, as Round 1 computed.
  - `EngagementBudget.update()` stays true once expired (`engagement_budget.gd:37-44`), so the "after the attack" DISENGAGE cannot be missed.
- **N8: resolved.** Plan l.226-227 and l.370. The draft has the `CLAUDE.md` Phase 8 paragraph line and `ENEMY.md` §"Design checklist (IDEAS §43)" (line 102).
  `tests/README.md`'s gate row is still to do (build step 8).

### Acceptance criteria

1. **Length on every TELEGRAPH / ADVANCE tick, both harnesses, standing and 200 px/s stubs:** row 5. Under the engine's own tick order it is also checked by 17b.
2. **Kill ends the beam within one tick:** rows 7 and 8. The beam is not lethal in the same call as the kill.
   **Well and wreck strain and collapse, with no-hazard controls:** row 9 has its control in the same row; row 17 is controlled by 17b.
3. **Inside `inner_rect()`:** rows 13 and 14, and the dual-mode case. **One attack per life:** rows 15, 16 and 16b.
4. **Single-writer gate:** green. The brain writes only through the mover API (`mover.max_speed` is a field). `actor.rotation` appears only as a read inside an
   expression (`twin_laser_drone_brain.gd:201`), which `_ASSIGN` does not match. The root script writes no velocity or rotation.
   **Roster gates:** the draft diffs add the drone to all three rosters, `test_wreck.gd`, `_MIN_ROSTER_SIZE` 19, `_AUTHORED_CONTACT_MODES`, the tow table (with the
   FORM fallback), `HAZARD_PROFILES`, and the `ENEMIES_CLEARED` guard (spawner and bare drone, with a boundary probe).

Nothing from §2.12 or §2.19 is dropped. The plan's two refinements of §2.12 are stated and logged in `DECISIONS.md`:
- a one-step boost;
- in Assault, a collapse during ADVANCE ends the life's attack.

The WAIT rig phase is appended, which the enum rule allows. Nothing in `global/` is reinvented. The rig's self-reference follows the `TargetInfo` RefCounted
precedent, has a stated fallback, and is checked by `check-test-leaks.sh`.

### New findings

**Blocking:** none.

**Non-blocking** (do during implementation; no further review needed):

1. **Row 4b's matcher is narrower than the gate it backs up** (plan l.252-255). It lists `=`, `+=`, `-=`, `*=` on `velocity` / `rotation` plus `move_and_slide(`.
   - *Missing.* The single-writer gate also forbids:
     - `/=`;
     - `velocity.x` / `.y`, `global_rotation` and `rotation_degrees`;
     - `set_velocity(`, `set_rotation(`, `look_at(`, `rotate(`;
     - `move_and_collide(` (`test_enemy_mover_single_writer.gd:17-20, 31-35`).
   - *Fix.* Reuse that file's `_PROPS` / `_ASSIGN` / `_CALLS` with an any-identifier receiver `\b\w+\.`, and blank comments and strings the same way.
   - *Check the rig's own lines stay clean.* `player_velocity = target.velocity if …` and `normal.rotated(` must not match.
   - *Remember.* The draft does not have this row yet.
2. **List the N2 death-hook row in the test plan.** The draft's `test_inside_the_death_hook_the_rig_already_counts_the_drone_gone` (:619-632) is the only row
   that pins N2. Row 11 reads `leader()` after `received_damage.emit()` has returned, and by then `queue_free()` has run, so row 11 passes on a design without the
   `_gone` flag.
3. **No row covers two FORM/BREAK branches the plan specifies.** Two branches are specified and nothing catches a regression in either.
   - **(a) `form_timeout` → BREAK.** No row asserts it, in either mode. *Cheap case:* set both movers' `max_speed` to 10 after `_ready()` on a pair spawned off its
     slots. Assert BREAK at `form_timeout` ± 1 tick with the beam never started, then (Open Space) WAIT.
   - **(b) Assault: a strain collapse in TELEGRAPH BREAKs and re-FORMs instead of disengaging** (plan l.163-165). A change that, say, counted
     `advances_started` at the latch would pass rows 15 and 16. *Cheap hand-ticked case:* after the latch, the test pushes B 30 px along n after each `_step` for
     about 12 ticks. Assert `collapsed(true)` in TELEGRAPH, both brains BREAK (not DISENGAGE), `advances_started == 0`, and a later FORM.
4. **Gate-time arithmetic** (l.358-359). 1.0 + 4 × 0.3 + 0.1 + 0.1 = 2.4 s, not 2.3 s.
   - Row 17b runs the whole attack (about 2.75 s of game time, about 0.35 s of wall time per mode at 8×), so the real-physics share is about 1.1 s.
   - That is inside 2.5 s, but tight. Measure it with `scripts/gate-time.sh` as planned. If it is over, use the epic's levers: a shared scenario or a faster clock.
     For example, run the real-physics rows on the 16× clock. Never drop a mode or an assertion.
5. **Optional, row 17:** add an upper bound on the lag at the collapse, ≤ `lag + advance_speed · (strain_seconds + 2 ticks)`. That would pin `strain_seconds` on
   real physics as well. Today only the hand-ticked well row times the collapse.
