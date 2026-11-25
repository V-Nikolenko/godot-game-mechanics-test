VERDICT: CHANGES_REQUESTED

# Plan review — t5 (Heavy Gunship phases, vent, emergency, rear missiles, cannon shield), round 1

Read: `3-plan.md`, `1-context.md`, the epic plan §2.5 / §2.9 / §2.16 / "For every task", the epic review (N1, #3, #11, #15, N5), DECISIONS.md Phase 10
(plan stage, t1–t4), `CLAUDE.md`, `tests/README.md` → Gate time, and the code each claim rests on (files and lines below). Nothing was run; every
number below is derived from the code.

**Verdict: changes requested.** Most of the design is right and checks out against the code. The VENT fire rule deviation is right. The heat signal
is sound. The Assault closure leaves no path for a late rocket. `scan(0.0)` is valid. The Sniper Shot row and the beam / nova rows are buildable.
Two problems stop the build as written:

- **(1)** The cannon shield turns a t4 gate red, but the plan says every t4 row stays green unchanged.
- **(2)** The self-hit fallback cannot work. An exemption inside the rocket does not stop the damage, which the gunship's own hurtbox deals. The
  hand-ticked 60 s row also does nothing to make that branch unlikely.

Findings 3 to 5 are spec gaps that would leave rows fragile or weak. Findings 6 to 8 are small.

## Findings

| # | Sev. | Problem (file:line checked) | Required change |
|---|---|---|---|
| 1 | **blocking** | **The cannon shield breaks t4's flush-edge reachability row.** `test_heavy_gunship.gd:340-385` (`test_a_bullet_through_each_exposed_edge_hits_that_part_and_the_hull`, both harnesses) fires a bullet at each part's `homing_point()` along that part's edge normal. For the cannon, that is (0, 72) straight up the nose. It then asserts `hits[0] == 1` and cannon HP −50. With t5's shield attached in `HeavyGunship._ready()` and faced along the nose, the hit bears 0° from the cannon's centre. `EnemyShield.absorbs_hit` absorbs it (`enemy_shield.gd:152-175`), and `HurtBox._on_area_entered` then emits `hit_absorbed` instead of `received_damage` (`hurtbox_component.gd:44-47`). So `EnemyModule.damaged` never fires (`enemy_module.gd:243-254`). That is 2 assertions × 2 harnesses red. 3-plan.md:102-104 ("every t4 row stay green unchanged") is false. | Say how this t4 row changes. For example, spend the shield first (two frontal bullets) or detach it for the row, and keep the cannon-reachability assertion. Record it as a t4-gate change in the DECISIONS t5 notes. |
| 2 | **blocking** | **The launcher-exemption fallback cannot prevent a self-hit.** `enemy_rocket.gd:403-410` only decides whether the *rocket* detonates. The damage comes from the target's own `HurtBox._on_area_entered` → `received_damage.emit(hb.damage)` (`hurtbox_component.gd:38-47`) for any HitBox on its mask. The rocket HitBox is on layer 32 (`pursuit_rocket.tscn` HitBox `collision_layer = 32`). The gunship root hurtbox mask 1121 and every part's 1120 (`heavy_gunship.tscn:88`; `enemy_module.gd:60`) include 32. `test_enemy_rockets.gd:649-675` relies on exactly this: the enemy takes `impact_damage` from its own hurtbox. So "ignore an area whose parent is `_launcher`" stops the blast but not the 18 damage. The rocket would then fly on through the hull and hit the parts as well. Row 15's own assertion (an armed HitBox *shape* overlapping the root rectangle) is purely geometric, so no exemption could ever turn it green. The branch is likely to be taken. The harness player is a bare `CharacterBody2D` with no hurtbox (`enemy_ai_harness.gd:47-50`), so rockets never detonate on it. A PURSUIT rocket (`turn_rate` 1.6, `guidance_seconds` 3.0, `pursuit_rocket.tscn`) passes through a player 250 px from the hull and U-turns back towards it, and the hull lies just beyond. | Specify a mechanism that keeps the launcher's hurtboxes from seeing the HitBox. For example, make the arming rule continuous: while the rocket is within its live launcher's `rocket_clear_radius() + body_radius + arm_clearance`, close the HitBox (monitoring / monitorable and the shape, as `_mark_done()` does), deferred from `_tick()`. That runs in `_physics_process`, so the change lands before that tick's physics step. The margin is 109.2 px against the hull's 92 px half-diagonal + 6, which leaves 11 px, more than the 8.7 px a 520 px/s rocket moves per step. A hurtbox-side owner check would also work. State what row 15 asserts in that branch: an *open* armed HitBox overlapping. Add a real-physics row in `test_enemy_rockets.gd` that turns a rocket back through its launcher, with the launcher's Health unchanged and a control showing another enemy still takes `impact_damage`. Add a DECISIONS line, since this changes every rocket launcher (corvette, turret battery). Also state that row 15's Health / `damaged` assertions see no physics events outside the awaited frames, so the overlap is the real measurement. Or emulate the physics event on each overlap. |
| 3 | should fix | **The Open Space EMERGENCY range puts both weapons out of reach of a player who is not pursuing, and the emergency run does not say where the player stands.** The burst battery's `fire_range` is 700 (`burst_cannon_mount.tscn`), measured from the muzzle (`turret_mount.gd:239-242`). Broadside, that is about 770 px from the hull centre. The hold is `emergency_range` 800 ± `range_drift` 90, so the batteries reach only in the inner part of the drift cycle. A boost (420 px/s × 0.9 s along `break_contact`, about 31° off straight away for a still player, `steering.gd:192-202`) adds about 320 px. Braking from 420 px/s at 360 px/s² adds about 245 px more. So during the missile window the hull is usually past the rocket battery's 900 px `fire_range` as well (`rocket_battery_mount.tscn`). The emergency run has a still player for 0–20 s at an unspecified distance. Row 13 ("≥ 1 salvo before 20 s") and row 14's control ("the starboard battery and the Missiles mount each fired before 20 s") then rest on the first boost alone, or fail in Open Space. §2.5's "the batteries keep firing" therefore holds in Open Space only against a pursuer. | Make the 0–20 s player a pursuer, for example holding 450 px as it does from 20–50 s (the AC says "at a pursuer"). Or pin the start distance and show both controls hold in Open Space. Record the 800 px hold against the ≈ 770 px battery reach in DECISIONS, or log a lower `emergency_range` as a starting-value change. |
| 4 | should fix | **The (D) shield-arc analysis is wrong** (3-plan.md:83-86: "every projectile that reaches it lands within ≈ 53° of the nose"). `absorbs_hit` reads `hit_box.global_position` inside `area_entered` (`enemy_shield.gd:160-164`). Godot reports that one physics step after the move that made the overlap, so the bullet can already be up to 15 px past the nose edge (900 px/s, `bullet.gd:29`). Its capsule also reaches about 5 px ahead of its origin (`bullet.tscn`: capsule height 59.5 × scale 0.168). Measured from the cannon centre (0, 60), dy is therefore 2–17 px and dx up to about 18 px, which is up to about 83° off the nose. A frontal shot near the edge's corners can land outside the 60° half-arc with the shield up. That is roughly a third of frontal bullets spread evenly over the 32 px edge, plus player homing rockets arriving at an angle from the front quadrants, which home on the cannon's (0, 72) marker when it is the nearest one. Row 10 is unaffected, because its frontal shot comes in at x = 0, and the Sniper Shot row is exactly 90° at y = 60 whatever the penetration. | Correct the analysis. Either accept the corner leak and record it in DECISIONS / ENEMY.md, or pin it with a boundary row (an off-centre frontal shot). |
| 5 | should fix | **Row 16's boundary cannot tell the three closure mechanisms apart.** At R = 1.0 the window opens with 0.1 s of budget left. Any one of the gate's budget clause, the `can_fire` `not _expiry_seen` clause or the DISENGAGE `scan(0.0)` keeps the row green, so removing any two of them still passes. At R = 3.5 the salvo runs 0.9 → 1.75 s and ends with 1.75 s left, so the gate's budget clause is never asked. Epic review N5's case is not exercised either: expiry deferred by a committed gun burst (`heavy_gunship_brain.gd:137-142`, `_disengage_pending`), during which the brain keeps ticking EMERGENCY. | Add an R where the window opens with budget remaining inside (0, `salvo_window` + margin), e.g. R = 1.3, asserting no Missiles TELEGRAPH (the gate). Add an expiry deferred by a battery in FIRE with the window open, asserting no TELEGRAPH and no rocket after expiry (the `can_fire` clause). |
| 6 | minor | Row 2's control ("a gun telegraphs again within 3.5 s of VENT's end") cannot be read off the heat run, which stops 0.5 s after the first VENT ends (3-plan.md:121-127). | Extend phase B to 3.5 s after VENT's end, or tighten the control to what the log holds. |
| 7 | minor | **No row covers the new EMP / rail hooks.** One hook is `on_suspended()` closing a VENT through the exit hook (vents locked, lights OFF, `max_speed` restored). The other is `on_emp_started()` turning the weapon-part lights OFF and cancelling a Missiles TELEGRAPH in EMERGENCY. Both can regress. The design choice "an EMP keeps an open VENT open for the whole window" stretches the 2.2 s weak point to up to 7.2 s under the 5 s EMP Blast. It is not in §2.5 and is not marked (D). | Add one row, e.g. a rail mid-VENT. Add a DECISIONS line for the EMP-in-VENT choice. |
| 8 | minor (note) | The Missiles mount's `cooldown_seconds` 5.5 (`rocket_battery_mount.tscn`) is longer than `emergency_period` 5.0. A salvo at 0.9–1.75 s after a boost leaves the mount in COOLDOWN until 7.25 s. That is past the next window's last legal TELEGRAPH start (7.0 s), so the pod fires after every other boost. §2.5 says "allowed to fire", so this is not wrong, but nothing says it. | Record it in DECISIONS / ENEMY.md so a later task does not "fix" row 13 into one salvo per window. |

## Checked and correct

- **(D) VENT fire rule.** `TurretMount.is_committed()` is false in the base (`turret_mount.gd:210-212`). Only `beam_turret_mount.gd:46-47` overrides it,
  and `defense_turret_brain.gd:134` lights COMMIT from it, so overriding it on `BurstCannonMount` would light COMMIT on every Phase 8 burst. With the
  replacement `can_fire = normal ∧ phase() == FIRE`:
  - a mount in FIRE keeps `_fire_tick(delta, true)` running its `BurstClock` (`burst_cannon_mount.gd:58-70`);
  - a TELEGRAPH with `can_fire` false stops and goes back to TRACK before `_telegraph_done()` can enter FIRE (`turret_mount.gd:117-121`);
  - TRACK never telegraphs (`_wants_telegraph` is false before the gate is asked, `:275-281`).

  So a started burst finishes and none starts. Row 6 can fail on the literal `is_committed()` rule, which would cut the burst after round 1.
- **"Burst ends = gun mount enters COOLDOWN".** `phase_changed(phase: int)` is declared with arity (`:40`) and emitted on every real change (`:333-338`).
  COOLDOWN is entered only in `_end_fire()` (`:292-294`), from the TELEGRAPH and FIRE branches (`:122-129`), including a burst cut by lost
  `can_fire`. `scan()` goes to SCAN and `power_down()` to UNPOWERED (`:139-162`), so bursts cut by an EMP or the hub idle add no heat. That is
  consistent with "adds 1 heat when it ends".
- **No rocket after the budget in Assault.** All of these hold, so I found no path:
  - The gate needs 0.85 + 0.05 s of budget at TELEGRAPH start, so the second rocket leaves with at least 0.05 s left.
  - `_expiry_seen` is set before the dispatch on the expiry tick (`heavy_gunship_brain.gd:137-139`), so `can_fire` drops that tick and
    `_fire_tick(…, false)` stops any salvo (`rocket_battery_mount.gd:76-79`).
  - DISENGAGE ticks no mount.
  - An EMP freezes both the brain and the budget (`base_enemy.gd:126-139`).
- **`scan(0.0)` at DISENGAGE** is valid for the rocket mount (`turret_mount.gd:139-152`, `rocket_battery_mount.gd:91-94`). It does not change the
  mount's rotation. It needs a null guard, because the exit probe strips `Modules` (`ph10_exit_keys.gd:57-70`) and `module(MISSILES)` then returns
  null.
- **CONTROLLED stays bit-identical in motion.**
  - No rng draw is added.
  - The Missiles mount's new gate is never asked while `can_fire` is false.
  - The DISENGAGE fast path stays first, so the exit probe never runs `_update_hull_phase()`.
  - The new nodes sit under `Modules` (stripped by the probe) or are visual only.

  Finding 1 is a test-level break, not a motion change. I found no test or level-1 replay that damages a gunship by 280 HP or more without killing
  it.
- **Row 15's mechanics are sound, apart from finding 2.**
  - `BulletPool` defers `_recycle` (`bullet_pool.gd:96-98`), and any frame boundary flushes it.
  - `reset()` turns the lifetime's physics back on (`enemy_rocket.gd:177`), so turning it off again on every `round_fired` is required; the plan
    does say "each launched rocket".
  - Physics in an awaited frame sees the areas only at their hand-ticked positions.
  - `ContactBlast` (layer 256, `contact_blast.gd`) never reaches an enemy mask, so the impact HitBox is the only self-hit path.
  - Every part lies inside the root rectangle, so checking the root shape covers the parts.
- **Sniper Shot row.** It is realistic: an `unlimited_pierce` bullet passes through regular enemies (`bullet.gd:113-131`), and
  `sniper_behavior.gd:85` sets that flag. At hull-local y 60 its bearing from the cannon centre is exactly 90°, whatever the penetration, so it is
  outside the 60° half-arc. It crosses no other part (BatteryPort spans y −10..30). A plain bullet at y 60 enters through the bare flank (x 56,
  y 30..72) and stops there.
- **Beam / nova rows.**
  - The line at y −34 passes through both vent centres. The Missiles centre is 26 px off it and the hull centre 34 px, both beyond the beam's 12 px
    (`beam_behavior.gd:93-95`).
  - The body is on layer 1 but answers `is_laser_blocking()` false.
  - The nova emits directly (`plasma_nova_module.gd:34-41`), so it bypasses the shield. Its numbers hold: hull −50, closed vents ping, the other four
    parts −50 each.
- **Gate-time estimate.** About 14 000 hand-ticked steps plus about 16 real-physics shots at 16× is plausible against the 2.5 s allotment. The extra
  rows asked for above are short.
- **Coverage of §2.5 / §2.9 and the AC.** It is complete apart from the items above. Hull bands, heat / VENT, weak points, emergency boosts, the rear
  missiles, the Assault closure and the bounded-exception note, own rockets, the shield (with N1's replacement), battery / missiles loss, and Heavy
  Shells are all covered. The §2.9 gunship lights are covered too: orange vents, yellow charging, dark wrecks, white ping, cyan shield. Nothing in
  `global/components/` is reinvented, and nothing contradicts `CLAUDE.md`.

## Round 2

VERDICT: CHANGES_REQUESTED

Re-read the revised `3-plan.md` (all sections plus "Review round 1 — what changed") against the code. I also ran a scratch probe outside the repo:
the t4 brain in the real Assault harness, 18 runs, seeds 1–6 × 3 start times. It is described in R2-2; nothing in the repo was touched. Round-1
findings 1, 3 (Open Space), 4, 6 and 8 are resolved in the text. Findings 2, 5 and 7 are resolved in design but need the fixes below. **Two of the
revisions do not hold against the code as written.** Both need only sentence-level changes, so a round 3 should be quick.

| # | Sev. | Problem (file:line checked) | Required change |
|---|---|---|---|
| R2-1 | should fix | **As specified, the launcher guard's look-ahead changes every rocket's first arming and can break a Ph5 row.** `_guard_radius()` = arming radius + (`_speed` + `launch_velocity().length()`)·delta. That sum is never zero for a flying rocket (`launch_speed` ≥ 120), so the Risks claim (3-plan.md:256-257, "at rest its radius is today's arming radius … every Ph5 / Ph8 arming row keeps its numbers") does not hold. Suppose `_armed` / `is_armed()` latches when the HitBox first opens outside `_guard_radius()`. Then `test_enemy_rockets.gd:514-542` (`test_a_moving_launcher_never_overruns_its_rocket`, both modes, DUMB and PURSUIT) fails. It asserts `r.is_armed() == (d >= arm_at)` on every tick with `arm_at` = today's radius, a launcher at 210 px/s and the rocket at 330–350 px/s. The look-ahead is (350 + 210)/60 ≈ 9.3 px while the gap opens 2.0–2.3 px per tick, so about 4 ticks read the wrong state. If `_armed` keeps today's latch, that row passes. The HitBox would still open about 1 tick later than today for every rocket of every launcher, which the plan says does not happen. The rest of the guard is sound. `monitorable` false keeps the launcher's hurtboxes from seeing the HitBox (`hurtbox_component.gd:38-47` reacts only to areas it detects). A deferred write from `_tick()` lands in the flush before that tick's physics step (the order is documented at `enemy_rocket.gd:443-450`). The 12 px margin is right: 109.2 against 91.2 + 6. A reopen that already overlaps something forms no pair (measured, `test_seeking_ordnance.gd:883-885`), so it cannot double-hit. | 1. Keep `_update_arming()`'s arming test and latch exactly as today. 2. Make the look-ahead the **closing** speed only: `max(0, −(rel_pos · rel_vel) / |rel_pos|) · delta`, with `rel_vel` = `_heading · _speed − launch_velocity()`. It is zero while the rocket recedes, so on the way out the HitBox opens on today's tick and `is_armed()` / `is_hit_open()` agree. Only a returning rocket is closed early. 3. Apply the guard only while `_had_launcher` and the launcher is live (a submunition's launch point is not a launcher). 4. Write it only on a change. 5. Note that a triggered WARHEAD returns before `_update_arming()` (`enemy_rocket.gd:270-278`), so the "never hits its launcher after arming" claim excludes it. |
| R2-2 | should fix | **In Assault, the emergency boost carries the hull out of the view, so rows 16, 16b, 20(b) and the Assault half of 13 / 14 can fail, or pass for the wrong reason.** Missiles `can_fire` includes "the hull in the Assault view" (3-plan.md:57). In the hand-ticked harness that view is fixed at x 0..1280, y 0..720: the camera never moves (`arena_camera.gd:102-104`; viewport 1280 × 720 in `project.godot:42-43`). A hull holding 540 px from a player at `ASSAULT_PLAYER` (640, 620) sits near the view's top or side edge. A boost "away" (≈ 380 px, 31° off straight out, `steering.gd:192-202`) carries it out. **The probe:** the t4 brain, holding the kinder 420 px, was given an emergency-style boost (`break_contact`, 420 px/s, 0.9 s) after 3, 5 or 7 s of BROADSIDE. The hull was inside the view on only **0–46 of the 121 window ticks** (0.9–2.9 s), mostly at the window's start. It never reached the **51 contiguous ticks** a full salvo needs (0.5 s glow + 0.35 s gap; leaving the view aborts the TELEGRAPH or cuts the salvo, `turret_mount.gd:117-129`). EMERGENCY's 540 px hold pulls the hull further out. Consequences: (a) Row 16 R = 3.5 "≥ 1 salvo" and R = 1.3's bypassed-gate control are likely red. (b) **Row 16b can be built mechanically** (overwrite the mount's `telegraph_gate`; a row-started `mover.boost` makes `_is_committed()` true at `heavy_gunship_brain.gd:293-295`; the 0.5 s TELEGRAPH from 0.9 s spans the 1.3 s expiry). But if the hull has left the view, the view clause cancels the TELEGRAPH before expiry and the row passes without the `_expiry_seen` clause, so it proves nothing. Its own 1.0 s boost, whose speed and direction are unspecified, can do the same. Its preconditions ("TELEGRAPH started before expiry", "phase still EMERGENCY") do not catch this. (c) In Assault, row 20(b) and the "fired before 20 s" controls of rows 13 / 14 depend on where the pursuer drags the hull. (d) Design: in Assault the rear pod rarely completes a salvo, and the batteries pause for each boost too. That is acceptable (fewer persistent rockets, which helps t11's deadline term), but it is not recorded. | 1. Hold the hull's position inside the view (written back each tick, as the heat run does) in the Assault runs of rows 16, 16b, 20(b) and 13 / 14. Or place it so the window lands inside the view, and assert `view_rect().has_point()` through the window as a precondition. 2. In 16b, give the row's boost negligible speed (or hold the position). Add the precondition "the Missiles mount is still in TELEGRAPH on the tick before expiry", so only the `can_fire` budget clause can stop the FIRE. 3. Record the Assault reach / view relation next to the Open Space one in DECISIONS and ENEMY.md. |
| R2-3 | minor | Row 12 ("each boost before 20 s moves the hull away", both harnesses) now runs against a pursuer. The Risks bullet still says "away only while the player stands still" (3-plan.md:253). In Assault the corridor filter also acts on boost velocity (`enemy_mover.gd:254-255`; soft / hard bands at `assault_corridor_constraint.gd:60-75`). The pursuer dragging the pair, and a hull held per R2-2, both make a displacement test unreliable there. | Assert the committed boost direction (`break_contact` result · away > 0) in both harnesses. Measure the displacement in Open Space only. Update the Risks line. |

**Resolved and checked:**
- **t4 row (finding 1).** Freeing `Modules/Cannon/Shield` before the cannon shot releases the slot through `_exit_tree` (`enemy_shield.gd:111-113`). The
  row keeps its reachability assertion. It needs either `free()` or a frame after `queue_free()` before the shot lands; the shot's own flight frames
  give that frame.
- **Self-hit definition (finding 2).** Damage is dealt hurtbox-side and the HitBox has to be closed. Row 15 now asserts "open HitBox overlapping", and
  its Health check is labelled as secondary. The guard row in `test_enemy_rockets.gd` can fail: without the guard the launcher's hull takes
  `impact_damage`, and the control is a second gunship.
- **Pursuer and reach in Open Space (finding 3).** At 450 px the player is inside the batteries' ≈ 770 px and the pod's ≈ 930 px reach.
- **Arc analysis and corner leak accepted (finding 4).** Correct.
- **Row 16 R = 1.3 / control and row 16b (finding 5).** They isolate the gate clause and the `can_fire` clause, once R2-2 is applied.
- **Phase B to 3.5 s (finding 6).** Done.
- **Row 20 and EMP-in-VENT marked (D) (finding 7).** Both are in. The Open Space half of row 20 is buildable as written: an EMP `scan()` from TELEGRAPH
  sets no cooldown (`turret_mount.gd:145-150`), and the frozen emergency clock leaves the window open after the EMP.
- **Pod cadence (finding 8).** Recorded.

## Round 3
VERDICT: APPROVED

Re-read the whole of `3-plan.md` (with "Review round 2 — what changed") and `1-context.md`, then checked the revised text against the code. Since the plan was
written, t6 / t7 landed. That added `BaseEnemy.emp_seconds_left()` and the Carrier as a new rocket launcher, and changed nothing the gunship plan reads. The
`draft-brain.diff` in this directory (not part of the reviewed design) was also read: it is consistent with the plan (the exit hook in `enter_phase()`, `CLOCK_EPS`, the window
and the missiles gate, `scan(0.0)` on DISENGAGE). No scratch probe was needed: every number below is derived from the code. The owner's decision on Assault
emergency geometry is not re-raised.

**Round-2 findings: all three resolved in the text and consistent with the code.**
- **R2-1 (launcher guard).** It holds against the code:
  - `_update_arming()` and the `_armed` latch are untouched (`enemy_rocket.gd:291-292, 372-388`), so
    `test_enemy_rockets.gd:514-542` keeps reading `is_armed() == (d >= arm_at)`.
  - The look-ahead uses the closing speed only, `max(0, −rel_pos·rel_vel/|rel_pos|)`, with `rel_vel` = `_heading·_speed − launch_velocity()`. That is zero while
    the rocket recedes, so on the way out the guard is the arming radius.
  - The margin is right. `rocket_clear_radius()` = 91.21 + 4 (`heavy_gunship.gd:87-88`), so the guard at rest is 109.21. A HitBox of r 6 can touch the
    rectangle only from 97.21. That leaves 12 px, against the ≤ 7 px a 420 px/s hull can move between the rocket's check and the physics step.
  - A triggered WARHEAD is correctly excluded: it returns at `:270-278`.
  - The scope ("`_had_launcher` and live") matches `_update_arming()`'s own liveness test (`:375-378`).
  - The closed state relies on the same `monitorable = false` semantics that today's launch-inside-the-hull already depends on (`reset()` `:171-172`).
- **R2-2 (Assault view).** The camera is fixed (`enemy_ai_harness.gd:52-56`) and the boost runs on time, not position (`enemy_mover.gd:115-121, 273`). So
  holding the hull's position keeps the turret rule true and leaves the cadence and the window intact. `_spawn()` writes `engage_seconds = 1000`
  (`test_heavy_gunship.gd:107-118`), so the 50 s Assault emergency run is not cut at 9 s.
  - **16b's timeline isolates the `can_fire` budget clause.**
    - The brain's boost runs E−1.3 → E−0.4, so the window opens at E−0.4 and the 0.5 s TELEGRAPH spans E−0.4 → E+0.1.
    - The row's 1 px/s boost (E−0.3 → E+0.7) makes `_is_committed()` true at expiry (`heavy_gunship_brain.gd:293-300`). Expiry is therefore pending
      (`:137-142`) and EMERGENCY keeps ticking.
    - `_expiry_seen` is set before the dispatch, so `can_fire` drops and the TELEGRAPH falls back to TRACK (`turret_mount.gd:117-121`). There is no FIRE,
      and DISENGAGE has not run yet.
    - The new precondition (TELEGRAPH on the tick before expiry) holds with 0.1 s to spare.
  - **R = 1.3 gated** refuses only on the gate's budget clause: 0.4 < 0.9 while the window still has 2.0 s.
- **R2-3 (row 12 direction).** `Steering.break_contact()` returns `(away + w·lateral).normalized()` with lateral ⊥ away (`steering.gd:192-202`). So
  `emergency_boost_dir · (hull − player) > 0` holds for any correct call and fails a swapped-argument one. Displacement is now checked in Open Space only,
  and the Risks line is updated (3-plan.md:273-275).

**Also checked and correct:**
- **Row 6's wording is safe.** At hull-local 67.5° the starboard battery never bears (its arc is 180° ± 80°). A cannon burst already in FIRE when the port's
  first round leaves ends first: 0.35 s against 0.36 s (`heavy_cannon_mount.tscn`, `burst_cannon_mount.tscn`). So "then no round from any mount" is exact.
- **The Missiles mount can aim at a beam-on player.** Its slot is 360° (`heavy_gunship.tscn`, `Missiles/MountSlots/Slot0`). It tracks with `can_fire` false
  (`turret_mount.gd:275-282`), so it is already aimed when the window opens.
- **Row 20(b)'s control is buildable.** An EMP `scan()` from TELEGRAPH sets no cooldown (`:145-150`). The emergency clock freezes with the brain
  (`base_enemy.gd:126-139`).
- **CONTROLLED and the exit probe stay bit-identical.** The Shield and the Lights sit under the stripped `Modules`, and the StateLight is stripped too
  (`ph10_exit_keys.gd:70-73`).
- **Roster and sweep gates are unaffected.** No new texture, no new collision layer, no HurtBox, UID-less `ext_resource`s, signals declared with arity, and
  `max_speed` writes are allowed by the single-writer sweep.

**Findings (all minor; fold them in during the build, no further round needed):**

| # | Sev. | Problem (file:line checked) | Change |
|---|---|---|---|
| R3-1 | minor | **No row crosses VENT → EMERGENCY.** The exit hook (3-plan.md:35-36) is exercised by VENT → BROADSIDE (rows 3, 8) and by the rail (row 20(a)), which the draft closes directly, not through the hook. Nothing covers the one transition epic §2.5 calls out: "Venting stops in EMERGENCY (the vents stay closed)" (`cmug23oo90029m52wae4clve0/3-plan.md:411-412`). A hook that only fires on the clock exit would leave the vents doubling damage for the rest of the fight, against the AC "vents vulnerable only while venting". | Add one assertion, to row 7 or row 20: in VENT, `health` cut to ≤ 209. On the next tick: phase EMERGENCY, both vents `is_vulnerable()` false, vent lights OFF, `mover.max_speed` 140. |
| R3-2 | minor | **The guard has scope and side effects the plan does not record (if row 15 adds it).** (a) The Carrier, built after this plan, is a third launcher: its Dorsal PURSUIT bank goes through `TurretMountBuilder` with the Carrier root as host, and it answers `launch_velocity()` / `rocket_clear_radius()` (`carrier.gd:215-221`). 3-plan.md:101 lists only the corvette and the turret battery. (b) Closing `monitoring` also stops a rocket from detonating on a **player** inside the launcher's guard radius. The HitBox's mask 128 is what detects the player (`enemy_rocket.gd:17-21, 403-410`), and a reopen while already overlapping forms no pair. So a player hugging the hull (corvette ≈ 54 px, gunship ≈ 109 px from centre) is passed through by a returning rocket. Today that rocket would blast the player. | In the DECISIONS line, name the Carrier and state (b) as an accepted, player-facing consequence. `test_carrier.gd` stays in the step-6 run, which the full gate already covers. |
| R3-3 | minor | **EMERGENCY's arc breaks the t4 arc-speed invariant.** t4 pins `orbit_angular_speed·(range + drift) < max_speed` for both modes (`test_heavy_gunship.gd:284-285`). At EMERGENCY's held ranges the products are 0.16 × 890 = 142.4 px/s (Open Space) and 0.26 × 630 = 163.8 px/s (Assault), both above 140. The arc anchor then outruns the hull, and only `ORBIT_MAX_LEAD` bounds the lag (`heavy_gunship_brain.gd:410-428`). That is harmless for a retreat that also boosts every 5 s, but it is not stated. | One sentence beside "Reach in EMERGENCY" and in the DECISIONS t5 notes, so a later task does not "fix" it into a lower `emergency_range`. Alternatively, scale the arc speed in EMERGENCY. |
| R3-4 | minor (wording) | 3-plan.md:90 says "the first opening happens on today's tick for every rocket of every launcher". That is true for every rocket not being closed on at its arming tick. A launcher that boosts along the rocket's heading after launch makes the closing speed positive on that tick, and the guard keeps the HitBox shut. `is_armed()` is unaffected, and this is exactly the self-hit case. | Qualify the clause. |
