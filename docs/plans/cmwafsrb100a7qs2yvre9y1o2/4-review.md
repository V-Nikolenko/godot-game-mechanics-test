VERDICT: CHANGES_REQUESTED

# Plan review: Phase 10 t4 (Heavy Gunship shell, movement and Assault life)

I read `3-plan.md`, `1-context.md`, the epic plan's "For every task", §2.4, §2.11, §2.12, §2.15 and §2.16, epic review round 2 (N2, N7, N8, N10), DECISIONS.md Phase 10
(:3805-3948) and CLAUDE.md. I checked every claim the plan rests on against the code at `2f7425b`. The design is sound and faithful to the epic. The geometry is right
(see "Verified" below). One acceptance criterion is silently dropped, and that has to be fixed. The minor items are cheap, and most of them remove a risk that would
otherwise land in t11.

## Blocking

**B1. The broadside row runs in Open Space only, but the AC requires both harnesses.** The plan's test row 6 is "**Broadside** (Open Space)". The task AC reads:
"rows of §2.4.5 green in both harnesses: … the broadside angle …". Epic §2.4.5 (3-plan.md:362) heads its rows "both harnesses". The plan gives no deviation or reason. I
don't see one either. In Assault the arc runs at 0.26 rad/s, well under the hull's 0.9 rad/s `max_turn_rate` (`enemy_mover.gd:267-270` caps only rotation), so the
broadside should hold in Assault too. Assault is also where broadside facing matters most: it decides whether a battery is in arc (`turret_mount.gd::_target_in_arc`,
±80° about port). **Fix:** label-parameterise row 6 over `["open_space", "assault"]`, with the Assault run using the shipped Assault arc, the clamp and a still player in
view. Keep the `max_turn_rate` 0.05 control in both.

## Minor

**M1. The gate-time estimate for the probe is missing and probably over budget.** Checked: `tests/helpers/specialist_exit_probe.gd:104-150`, DECISIONS.md:3909, `enemy_module.gd:105-151`,
`turret_mount_builder.gd:29-38`, `bullet_pool.gd:60-68`. The Hacker's probe has the same 2166-run corridor set and costs ≈ 3.4 s (t1 notes). Its exit curves at
`min(1.4, 700/300)` = 1.4 rad/s. The heavy's curves at `min(0.9, 240/300)` = 0.8 rad/s, which is a much larger turning circle and so more ticks per run. Each heavy
instance also builds six modules, and each module creates a `Health`, a `LowHealthSmoke` and two `HitEffect`s. Stripping `MountSlots` correctly avoids the pools, which
pre-instantiate ~40 projectiles per heavy (`BulletPool._ready`). Even so, the probe alone plausibly costs 4–6 s, against a 3.5 s allotment and the 5.25 s escalation line.
The "share scenarios between rows" mitigation cannot touch the probe. **Fix:**
- (a) Let `prepare_probe` free the whole `Modules` node, not only `MountSlots`. `ModularHull._ready()` already returns cleanly with no `Modules` (`modular_hull.gd:30-33`).
  The root script must then tolerate an empty hull (`bind_mounts([])`, `homing_point` falls back to `global_position`). Keep the bit-identity row; it then pins this hook.
- (b) In build step 2, measure the probe's cost **first**, before writing the other rows, and record it.
- (c) State the escalation trigger in the plan: if the probe alone exceeds 1.5 × 3.5 s, the result is `Result: ESCALATE` with the profile.

**M2. Review finding N10 is cited but never addressed.** The plan header lists N10, but nothing in the plan responds to it. From t4 on, the deep_space 3.5 s heavy is
AI-driven and has 9 s to close ≈ 830 px at 140 px/s / 120 px/s² and get a battery onto the player. Every pre-approved lever shortens the budget. **Fix:** pick one of
these and write it down.
- (a) Add an optional `assault_approach_speed` export: default = `max_speed`, so it is bit-identical; the brain writes it in Assault APPROACH the way it writes the exit
  speed. Log it in DECISIONS as the pre-approved attack-in-budget lever for t11.
- (b) Defer it to t11 explicitly, with the reason.

Either way, measure it now. Add one hand-ticked Assault row from the deep_space spawn point (world position from `WaveBuilder`'s scale) to a stub at
`level1_slice_replay.gd`'s `PLAYER_OFFSET`. Record the time to the first battery `TurretMount.Phase.FIRE` in DECISIONS, so t11 starts from a number.

**M3. EMP freezes a shown telegraph, and no row covers the heavy under EMP.** Checked: `base_enemy.gd:128-133`, `turret_mount.gd:150-165`, DECISIONS.md:3640, :3732, :3826.
During the window, `_physics_process` skips `brain.tick`, so the mounts are not ticked. A battery in TELEGRAPH or FIRE stays there, with the StateLight held CHARGING or
ARMED, and fires when the window ends. Ph9's precedent for shown telegraphs is to cancel them on EMP (D2 for the Hacker, the tender's LAUNCH → HOLD). DECISIONS also says
the gunship's EMP deferral "is closed (both heavies answer EMP)", but the only EMP assertion in the plan is `answers_emp()` true. **Fix:** in `on_emp_started()`, call
`scan(0.0)` on every gun mount (it stops the weapon, starts the cooldown if it was firing and enters SCAN) and set the light OFF. Add a row, both harnesses: EMP during a
battery TELEGRAPH → no round from any mount in the window, light OFF, fires again after. Optional and cheap: a row that a railed heavy (`suspend_ai()`, the state of the
three cloud_descent rows and level 2 until t11) fires nothing and shows OFF.

**M4. In Assault the heavy can open fire from above the view.** `DefenseTurretBrain` never fires off-screen (`defense_turret_brain.gd:4-5, 113-117`; DECISIONS.md:2914).
The heavy spawns at world y ≈ −640 and comes in nose-first, and the HEAVY_CANNON has `fire_range` 900 and a 70° arc (`heavy_cannon_mount.tscn`). That brings the player
into range with the hull ≈ 300 px above the top of the view, so 220 px/s shells arrive from nowhere. **Fix:** either AND each mount's `can_fire` with
`EnemyWorld.view_rect(tree).has_point(actor.global_position)` when a view rect exists (the turret rule, one line), with a row showing no TELEGRAPH while the hull is outside
the view, or state the choice and log it.

**M5. The never-parks row is one seed, and its margin depends on luck.** The plan computes 1.5 s within 8 px of the arc's apex at 0.26 rad/s. A reversal (every 5–8 s,
from `rng`) that fires within ±0.19 rad of the apex sends the hull back over it, which doubles the dwell to ≈ 3 s. A drift extremum at the same moment does not help.
The y-spread bound has the same exposure: an arc held within ±37° of the apex gives only 84 px from the arc alone. **Fix:** run row 9 over ≥ 3 seeds (hand-ticked, ≈ 0.1 s
each). If one fails, fix the rule (for example, a reversal that falls inside the apex band waits until the hull leaves it) rather than choosing a seed.

**M6. The late-telegraph control in row 10 is not constructive.** "With the gate bypassed, a telegraph starts too late" happens only if, by chance, a mount is ready inside
the last ≈ 1.1 s of the budget. **Fix:** make it deterministic.
- First run ungated with a long budget in the row's scenario and record the first battery TELEGRAPH time `t0`.
- Then set `engage_seconds = t0 + attack_window() / 2`.
- The ungated run must then telegraph with less than `attack_window() + 0.05` left, and the gated run must not.

**M7. Dropping the view grid has to stay revisitable.** I accept shipping only `corridor_starts()` if the view grid measures no slower, as a logged deviation. But §2.4.3's
lever (1) (`exit_speed` up to 360, `exit_acceleration` up to 320) changes the turning circle. **Fix:** say in the DECISIONS note and in the `ph10_exit_keys.gd` header that
any change to an exit lever re-runs the view-grid comparison.

**M8. Check the derived exit bound in t4, not only in t11.** §2.16 derives `engage_seconds` 9.0 from "exit ≤ 12.6 s" (cloud_descent: 23.2 s at rel −13.2, `attack_window`
≈ 1.05, margin 0.5). t4 is the task that measures the exit, and t4 is where lever (1) is cheapest. **Fix:** add a row to `test_heavy_gunship.gd`:
`engage_seconds + attack_window() + heavy_gunship_exit().seconds + 0.5 < 23.2`, with 23.2 as a named constant that cites §2.12 (t11 replaces it with the live
`_deadline_rows` figure). Record the margin in DECISIONS.

## Verified (no change needed)

- **Port and starboard signs.** The mover's facing is `heading.angle() - sprite_forward_angle` (`enemy_mover.gd:262-270`), so local +y is the nose. The left of (0, 1) is
  `(0, 1).rotated(-PI/2)` = (1, 0), so port is local +x. `nose = bearing.rotated(+PI/2)` puts port on the bearing; `rotated(-PI/2)` puts starboard on it.
- **Mount rest bearings.** `TurretMount._parent_rotation()` is the slot's `global_rotation`, which is the hull's rotation (slot, `MountSlots` and module are unrotated). So
  port is 0°, starboard 180°, nose 90° and aft 270°. Arcs: 160° / 160° / 70° / 360°. Broadside ±20° keeps the player inside the battery's ±80°.
- **Flush-edge table.** Every exposed edge lies exactly on x = ±56 or y = ±72. Every `HomingPoint` is the midpoint of its edge. No two parts overlap. The (56, 51) control is
  21 px from the battery; the bullet capsule is ≈ 10 × 4.7 px (`bullet.tscn`). Same-step overlap holds: `HurtBox` emits on its own side (`hurtbox_component.gd:37-49`)
  and the bullet frees deferred (`bullet.gd:113-146`). A closed vent deflects through `EnemyModule.deflects_hit` and then emits `deflected`
  (`enemy_module.gd:248-258`), so the hull takes ×1.
- **`attack_window()`.** Battery 0.4 + 3 · 0.12 = 0.76; cannon 0.7 + 0.35 = 1.05. `break_seconds` 0.7 ≤ 1.05.
- **Probe shape.** `disengage_seconds()` calls `prepare` before `add_child` and writes `velocity` before `enter_phase` (`specialist_exit_probe.gd:129-150`), so stripping
  `MountSlots` (or `Modules`) is legal. DISENGAGE draws no `rng`, so the shifted `rng` sequence does not break bit-identity.
- **Rails.** On a rail the heavy rides and fires nothing (`base_enemy.gd:127-128`).
- **Line of sight.** Its body never blocks other ships' sight lines (`line_of_sight.gd:56-62`).
- **Body layer deviation.** Layer and mask 1 / 1 match every mover-driven enemy scene. The deviation is justified.
- **Legacy-row moves.** The Bonus Drone has no brain, so `answers_emp()` is false and it keeps the process-disable row. In the support-ship row, the Bonus Drone still
  covers the not-AI-driven clause after the flip (`support_ship_brain.gd:289-300`). The heavy satisfies the every-phase refusal row: AI-driven, not boosting, brain
  refuses (`base_enemy.gd:224-229`). The explosion placement test counts only direct `CPUParticles2D` children, so the pools' bullets do not affect it.
- **N2 and N8.** The plan applies both exactly. N7 goes to DECISIONS as required.
- **Reference sweep.** Every `gunship` reference in `.gd`, `.tscn` and `.tres` files outside `docs/` is in the plan's move list. The only ones not on it are comments in
  `space_station*.gd`, `station_turret.gd`, `gatling_interceptor.gd` and `test_station_incoming_damage_paths.gd`. They name no path or builder, so the AC does not apply.
- **Level-1 replays.** The deep_space heavy does not break `test_level1_ph8_attacks.gd`'s turret slice by collision. `AssaultDrift` writes the turrets' positions
  directly (`assault_drift.gd:32`), so the heavy slides around them rather than displacing them, and turrets fire on LOS, which the heavy does not block.

# Round 2
VERDICT: APPROVED

I checked Revision 2 (`3-plan.md:210-244`) against B1 and M1–M8, and checked its claims against the code at `2f7425b`. Every round-1 finding is resolved. One factual
error in the M2 text has to be corrected while building (finding 3 below). That is a one-line wording fix, and the plan already names the right source, so it does not
need another review round. Notes 4, 6 and 7 are advisory.

## Findings

1. **B1: resolved.** `3-plan.md:214-215` now runs row 6 over both harnesses, with the turn-rate control in both. Checked that it can pass and that it can fail in Assault:
   - The desired heading depends only on the bearing and `_side`, and an `orbit_dir` reversal does not change it.
   - The bearing turns at most 0.26 rad/s (plus drift), well under the 0.9 rad/s cap. `enemy_mover.gd:262-270` caps only rotation, and `turn_lerp` defaults to 0 (`:56`).
   - The 0.05 rad/s control needs > 20 s to turn the 70° it must close from APPROACH's nose-on facing, so it misses the 80 % in both modes.
   - The player at (640, 620) is inside the harness view (camera at (640, 360), `enemy_ai_harness.gd:51-56`; `arena_camera.gd:102-104`).

2. **M1: resolved.** Checked the three pieces the revision rests on:
   - `ModularHull._ready()` returns with an empty `_modules` when `Modules` is missing (`modular_hull.gd:30-33`), and `build_mounts()` then loops over nothing (`:83-99`).
   - The probe calls `prepare` before `add_child` (`specialist_exit_probe.gd:180-187`).
   - Measure-first and the 5.25 s trigger are in the plan.

   Two implementation notes:
   - The hook must use `free()` on `Modules`, not `queue_free()`. The ship is not yet in the tree, so a queued node is still a child when `ModularHull._ready()` runs.
   - The plan's trigger says "the probe alone > 5.25 s". The epic's rule (`cmug23oo…/3-plan.md` "For every task", §2.15) is "**own new / changed files** > 1.5 × 3.5 s",
     and the epic rule is the one that binds.

   From the t1 figures (DECISIONS.md:3909: Hacker ≈ 3.4 s for 2166 runs) and the heavy's slower U-turn (π / 0.8 ≈ 3.9 s against the Hacker's ≈ 2.2 s), I expect the probe
   to cost ≈ 4.5–5.5 s. That is close to the line, so measure it first, as the revision says.

3. **M2: resolved, with one wording error to correct while building.** `3-plan.md:226-227` places the deep_space heavy with "design units × `WORLD_SCALE` **from the view's
   top-left**". That is not the WaveManager formula:
   - `wave_manager.gd:194` is `cam.global_position + cam.offset + offset × ArenaCamera.WORLD_SCALE`. That is from the **view centre**, as `enemy_view_rect()` is
     (`arena_camera.gd:102-104`).
   - `level_1_director.gd:349` `.at(0, -500)` therefore spawns at (640, −640). The top-left reading gives (0, −1000), a different and longer approach, and the wrong number for
     t11.
   - Build the point from `wave_manager.gd:194`'s expression and the `LevelSection` entry's `base_offset` (`level1_slice_replay.gd:65-82`, `placed()`).

   My estimate puts the first battery FIRE at ≈ 6.5–7 s:
   - BROADSIDE at d ≤ 520, which is y ≈ 90, after ≈ 5.8–6.3 s.
   - In APPROACH the battery is only 10° outside its ±80° arc, because the nose faces the player and port rest is 0°.
   - Then 0.4 s charge.

   The gate stops telegraphs after 9 − 1.1 = 7.9 s, so the assertion should hold with about 1 s of margin. If it does not, the plan does not say what follows. State in
   DECISIONS which applies: add `assault_approach_speed` now as a logged lever, or `Result: ESCALATE`.

4. **M3: resolved.** Checked:
   - `turret_mount.gd:139-153`: `scan(0.0)` stops a TELEGRAPH weapon without a cooldown, and a FIRE weapon with one.
   - `base_enemy.gd:174-185`: `on_emp_started()` runs once per window.
   - `base_enemy.gd:124-131`: the brain, and so every mount, is not ticked during the window. The mounts stay in SCAN with no round.

   The rail row passes trivially (`base_enemy.gd:121-122`). That is acceptable as a pin. Advisory: make `on_suspended()` call the same `scan(0.0)`, so a heavy railed while
   it is mid-telegraph does not keep showing a frozen telegraph.

5. **M4: resolved.**
   - `EnemyWorld.has_view_rect()` / `view_rect()` exist (`enemy_world.gd:53-62`).
   - The rule is exactly the turret's (`defense_turret_brain.gd:113-117`).
   - Only the Assault harness adds an `ArenaCamera`, so Open Space rows 4 and 14 are unaffected.
   - In the new row, the cannon at (640, −200) is 820 px from the player at (640, 620), inside `fire_range` 900. So the control can telegraph, and the row can fail.

6. **M5: resolved structurally (three seeds, rule fix rather than seed choice). Advisory on the metric.** "Within 8 px of one y" read as a ±8 band (a 16 px window) makes
   the apex crossing alone take 2·√(16/210) / 0.26 ≈ **2.1 s** at r 420, which is over the 2 s limit. The plan's 1.5 s assumed a one-sided 8 px band.
   - The drift term usually rescues it, because it moves y at up to ≈ 56–80 px/s away from its extremum.
   - Near an r-minimum, though, the drift partly cancels the arc's curvature.
   - So write the metric explicitly: max − min of y over any 2 s window > 16 px.
   - If a seed fails there, the remedy is `assault_orbit_angular_speed` (≥ 0.28). That is t4's own judgement export, legal with a DECISIONS line. The reversal rule in
     `3-plan.md:236` would not help in that case.

7. **M6: resolved.** The run is deterministic:
   - Before expiry, the budget's length changes nothing except the break-away guard, and the scenario has no rusher.
   - Mounts share the brain's seeded `rng` (`turret_mount_builder.gd:28`).
   - The gate can be bypassed by setting each mount's `telegraph_gate = Callable()` (`turret_mount.gd:279` checks `is_valid()`).

   With `engage_seconds = t0 + w/2`, the ungated run telegraphs at t0 with w/2 left, and the gated run refuses from t0 − w/2 − 0.05. So both halves of the control can fail.

8. **M7: resolved.** `3-plan.md:240-241` names all three exit levers. `max_turn_rate` is included, which is correct: the exit rate is `min(max_turn_rate, exit_acceleration /
   exit_speed)`, as in `missile_corvette_brain.gd:475-486`.

9. **M8: resolved.** The row `engage + attack_window() + exit + 0.5 < 23.2` is §2.16's derivation. The bound is exit < 12.65 s, and the constant is named and cited.

No new blocking problem was introduced. The revision's additions (the EMP `scan`, the view AND, the `Modules` strip) touch no motion write, so the single-writer gate is
unaffected. They add no signal, and they do not change the roster or level-1 rows.
