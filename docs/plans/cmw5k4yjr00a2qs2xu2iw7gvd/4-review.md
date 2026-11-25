VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` (Phase 9 t4: the seeking-ordnance hook and the hijacked homing rocket) against epic §2.4 / §2.5 / "For every task"
(`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`), `CLAUDE.md` and the code at HEAD `d0dc62d`.

The design is faithful to §2.5. It reuses `ContactBlast`, `Steering.turn_toward`, `ProjectileLifetime.expire_now()`, `ExplosionEffect` and `HurtBox`, and adds no collision bit.
Both of its deviations hold up against the code (see "Verified" below). The build order works. The problems are in the **test plan**: three behaviours the task names
explicitly can regress with every planned row still green. They are cheap to fix and do not need a redesign.

## Required changes

### R1. The Arming row cannot fail on a build that drops either arming condition on its own (3-plan.md:112)
Arming is `_since_claim >= 0.25` **and** `_cleared` (≥ 60 px once). The plan's falsifier is "[an unarmed rule would blast on tick 1]", which only catches a build with
*no* arming. Working through both sub-rows at ~8.2 px/tick (500 easing to 380):
- *Claimed at 20 px*, with any heading. Toward the player it passes through on about tick 3 and is 60 px past by about tick 10. Away from the player it is 60 px off by about tick 5.
  Either way it is about 100 to 140 px off on tick 15. It can only come back within 30 px after a turn of about π at 1.6 rad/s (about 2 s, a turning circle of radius 240 to 310 px).
  - A build **without the clearance rule** (time only) passes: no blast before tick 15, and none "before the first tick ≥ 60 px".
  - A build **without the time rule** (clearance only) also passes: it is cleared at about tick 10 but is already far away.
- *Claimed on the ship (0 px)*: both one-condition builds pass for the same reason.

Nothing else in the plan pins either condition. The Blast row claims at 300 px, and the Dodge and Lifetime rows start far away.
Add one falsifier for each condition, both hand-ticked in both harnesses:
- **Time rule:** claim at 70 px, heading straight at a stationary target, so `_cleared` latches on the claim and d ≤ 30 on about tick 5. Assert no blast on ticks 1 to 15. With the time rule
  the rocket is about 52 px past the target on tick 15, so there is also no blast on that pass. A clearance-only build blasts on about tick 5.
- **Clearance rule:** claim at 20 px, then move the fake player each tick to stay 20 px behind the rocket (the "player chasing its own just-claimed rocket" case the rule exists
  for). Assert no blast through tick 30, even though `_since_claim >= 0.25` from tick 15. A time-only build blasts on tick 15. Optionally, stop the player and assert the
  rocket blasts only after it has opened to ≥ 60 px.

### R2. `jam_guidance()` is built here and pinned by no row (3-plan.md:39, rows 106–125)
The task text and §2.5 list `jam_guidance(source)` in the contract. The "Jammed" row (3-plan.md:121) tests the **field** path (`Hazards.jammer_at`), not the method.
t5 (epic §2.6, row "Seekers") calls it only through `EmpPulse` on an *unhijacked* rocket. The hijacked branch (`_guidance_jammed`: "keeps flying straight and still fizzles at the end
of its window") belongs to t4 alone and nothing would catch its regression.

Add a hand-ticked row in both harnesses:
- an unhijacked rocket with a `locked_target`, after `jam_guidance(null)`: `locked_target == null` and the heading stays constant;
- a hijacked rocket, after `jam_guidance(src)` on tick 10: the heading stays constant to the end of the window, `retarget_ended` fires once on tick 150 ± 1 and there is no blast;
- a control: the same rocket without the call does turn.

### R3. The `seconds >= 0` branch of `retarget()` is unpinned (3-plan.md:34, Fizzle row 3-plan.md:113)
The task text calls out "(seconds < 0 uses its own hijack_seconds)". Every planned claim passes `-1.0` (the fixture claimer, 3-plan.md:102), so a build that ignores `seconds` and
always uses `hijack_seconds` passes everything. Add a fizzle sub-row: `retarget(target, 1.0, src)` fizzles on tick 60 ± 1, and `retarget(target, 0.0, src)` fizzles on its first tick.

## Recommended (not blocking on their own, but fold them in while editing)

- **M1. The audit of what sees a layer-512 area is incomplete (1-context.md, "Who sees a layer-512 area").** `laser_ray.gd:85` has `_HIT_MASK := 128 | 256 | 512`, and
  `laser_ray.gd:127` applies it unless `hit_mask_override` is set. Only the station laser phase overrides it (`station_laser_phase.gd:159`). The level-1 laser columns and all 12 rays of
  `laser_wall.tscn` use the default. `LaserRay._on_area_entered` (laser_ray.gd:275–282) emits `received_damage(_KILL_DAMAGE)` straight on any `HurtBox` it meets, so a lit column
  **destroys a hijacked rocket** through `_on_shot_down`. This contradicts the plan's "only primary fire shoots it down".
  A reflected `EnemyBullet` (`enemy_bullet.gd:64–65`, layer 64 / mask 513) is listed but is also a shooter. This is probably acceptable gameplay (lasers kill everything), but list it under **Risks** as
  accepted, so t8/t14 (Hacker in level 1) are not surprised.
- **M2. A freed *target* mid-hijack.** Step 4 (3-plan.md:48) handles "the target is gone", but step 6 (3-plan.md:51) reads the target's position for `d` with no guard. The real
  target is the player, which can be freed while a hijacked rocket is in flight. Guard step 6 with `is_instance_valid(_hijack_target)`. Add a hand-ticked row: free the target on tick 20, then
  expect no error, straight flight, a fizzle on tick 150 and no blast.
- **M3. The null-source Choice (3-plan.md:45) is unpinned.** It deviates from the literal §2.5 ("not a valid instance → fizzle at once"), and the deviation is sensible: a null-source claim
  would otherwise fizzle on its first tick with the EventBus already emitted. Pin it with one assertion: a claim with `source = null` lasts its whole window.
- **M4. The Tell row (3-plan.md:125) needs an awaited frame.** `retarget()` sets the HurtBox flags with `set_deferred`, so a synchronous hand-ticked assertion reads `false`. Also add
  the trail's colour-ramp check: `RocketTrail.set_colors` is a new public method on a shared component and otherwise has no assertion.
- **M5. The self-reference Choice (3-plan.md:71) is fine as a precaution, but its rationale overstates the risk.** `enemy_rocket.gd` names its own `class_name` freely: `Array[EnemyRocket]`
  :308, `as EnemyRocket` :310, `is EnemyRocket` :381 and :392. The gate is leak-free with that, so the `enemy_mine.gd` trap is not a general self-reference rule. Keep
  `get_script() == get_script()` if preferred, since it is harmless with no subclass of `homing_missile` existing. But record it in `DECISIONS.md` as a precaution, citing the
  `EnemyRocket` counter-example, not as a known leak, so the docs do not spread a false rule. `warhead_missile.gd` naming `homing_missile` is fine either way: no cycle, because
  `homing_missile.gd` never references `WarheadMissile`.
- **M6. Note for t8 (put it in `DECISIONS.md`).** The rockets are children of `RocketState` (`warhead_missile_shooting_state.gd:64–80`). A rocket freed together with its player, or any
  parent-free, never reaches `_finish`, so it emits no `retarget_ended`. A Hacker that counts its claims must also check `is_instance_valid`. Also, beam primaries
  (`mining_laser`, which picks targets by group) can never shoot a hijacked rocket down. That is epic-level and inherent to §2.5, but worth flagging for t9's fairness rows.

## Verified (the plan's claims hold)

- **Resolution: `queue_free()` at the end of the frame, not two ticks later. Correct.**
  - `test_homing_missile_lifetime.gd:112–123` loops `while not r.is_queued_for_deletion()` and asserts tick 360 ± 1.5. A 2-tick delay gives 362.
  - The 2400 px row (:134–141, ± 2.5 around 288) would reach about 291.
  - `test_player_bullet_lifetime.gd:481–482` asserts `is_queued_for_deletion()` straight after `expired.emit()`.
  - The delay's own doc (`enemy_rocket.gd:418–429`) says it exists only because a **pool** re-parents a live rocket and `Area2D` re-reports the pair. `RocketState` never pools a homing rocket, so freeing at the end of the frame removes its pairs.
  - With `_done` latched first, the deferred close, and `area_entered` on enemy hurtboxes firing once per entry, nothing double-hits.
- **Choice: a pop only on a hijacked rocket's end.** This keeps unhijacked ends observably unchanged, as §2.5's last line requires. Note that the existing `homing_missile.gd:60–63` / `:51–52` ends already go through the new `_finish`.
  `test_enemy_rockets.gd:624–646`, `test_armor_query.gd:288–306` and `test_enemy_shield_hits.gd:131–141` only observe the free and the damage, so they are unaffected.
- **A `ContactBlast` into a `State` parent works.** `RocketState` is a plain `Node` under `AttackStateMachine` (`player_fighter.tscn:346–358`, `player_ship.tscn:268–279`), so a rocket and its
  blast are transform-top-level. `ContactBlast._enter_tree` (contact_blast.gd:66–67) sets `global_position` after parenting, so the position is right. `_attach` (contact_blast.gd:57–61) copes with a freed container.
  `ExplosionEffect.explode(at, container)` (explosion_effect.gd:41–80) adds non-physics particles synchronously, which is safe in a physics callback, as `EnemyRocket._pop_here` already does.
- **The self-hit guard is needed and the rows can fail.**
  - The homing HitBox is 32 / 513 with a capsule of r 7, h 18 (`homing_missile.tscn:44–58`), and the salvo spread is 7 px (`warhead_missile_shooting_state.gd:74`). So the claimed rocket's own HurtBox (512) and its mates' HitBoxes overlap at once.
  - The warhead HitBox is also 32 / 513 (`warhead_missile.tscn:59–61`) and frees on any non-deflected hit (`warhead_missile.gd:33–36`).
  - `ArmorQuery.deflects` (armor_query.gd:18–24) returns false for a rocket parent, so a bullet that hits the HurtBox is consumed.
  - Plan step 5, which removes each guard once, rightly makes sure the deferred `monitorable` switch-on really produces the pair.
- **No player damage of 100 is possible.** The player HurtBox is layer 128 / mask 1281 (`player_fighter.tscn:335–336`, `player_ship.tscn:261–262`). The rocket HitBox is on 32 and its mask 513 never sees 128, so the
  poll in step 6 plus `ContactBlast` (256) is the only path. The "exactly 18, never 100" row is meaningful.
- **EventBus.** `player_ordnance_hijacked(rocket: Node2D, source: Node)` is declared (event_bus.gd:44) and has never been emitted (grep). The arity is already pinned by `test_player_ability_lock_tells.gd:217–222`.
- **Clock arithmetic.** The fizzle lands on tick 150 and the tether's last visible tick is 17 under the `<= 1e-6` rule. The lifetime row's 300 + 60 ticks matches t3's tick 360. Its "< 500 px, inside the rect,
  no blast at ≥ 700 px" holds: about 425 px in 1 s with the ease.
- The jammer gating (`Hazards.count() > 0 and jammer_at`, hazards.gd:25–27 and 79–88) leaves `test_hazard_projectiles.gd`'s homing-well row bit-identical: a well is not a jammer.
- The dodge speeds match the ships: Open Space `max_speed` 420 (`player_ship.gd:10`), Assault `move_speed` 360 (`player_fighter.gd:126–130`).

## To approve
Add R1–R3 to the test plan, with each new falsifier named in its row the way the guard rows already are, and fold in M1–M4. No design change is needed.

## Round 2
VERDICT: APPROVED

Review of `3-plan.md` Revision 2 against round 1's R1–R3 / M1–M6, epic §2.5 and the code at HEAD `d0dc62d`. I re-ran the arming and turn geometry
with the plan's own update order (clocks, then speed `lerpf(500, 380, since / 0.5)`, then `Steering.turn_toward` at 1.6 rad/s, then move, then measure `d`) at 1/60 s.

### Required changes from round 1: all addressed
- **R1, time rule.** Claimed 70 px out with the nose on the target. `d` first drops to 30 px or less on tick 5 (29.33 px) and stays there through tick 12. A clearance-only
  build blasts on tick 5. The correct build is 46.95 px past the target on tick 15, when it arms, so it does not blast. The row fails on the build it targets. The plan's "~47 px" is
  right (round 1's "about 52" was not).
- **R1, clearance rule.** The player is kept 20 px behind the rocket, so `d` stays at about 26 to 28 px and `_cleared` never latches. A time-only build blasts on tick 15
  (`d` 27.33). The correct build does not blast through tick 30. The row fails on the build it targets.
- **R2.** `jam_guidance()` is now pinned on both branches. The hijacked sub-row's "still `is_retargeted()`" plus "`retarget_ended` on tick 150" also catches a build where
  `jam_guidance` ends the hijack instead of only its guidance. The control row catches a build that does nothing.
- **R3.** 1.0 s gives a fizzle on tick 60. 0.0 s gives a fizzle on tick 1 (`_since_claim` is 1/60 there, so the rocket cannot be armed first). A build that ignores `seconds` gives tick 150 in both cases. Both sub-rows fail on that build.
- **M1–M4** are folded in sensibly. The `LaserRay` / reflected-`EnemyBullet` risk is checked against `laser_ray.gd:85,127,272,282`. I also swept every
  direct `received_damage.emit` (nova, overload, engine boost, warp, `Hazards.pulse_damage`). They all pick targets by group, so none of them reaches a rocket. The M2 guard is on both step 4 and step 6, and the M4 row awaits the deferred open.
  M5 and M6 are recorded.

### New problems introduced by Revision 2
None blocking. The new rows' clocks are consistent with the `x -= delta`, `<= 1e-6` rule. The null-source Choice and the target guard do not contradict §2.5's mechanics.

### Recommendations (fold in while implementing)
1. **The In-flight turn row only works from far enough away. Fix the claim distance in the row.** This was already in Revision 1; round 1 did not check it. Take a rocket flying straight away from the player at
   distance D. At maximum turn rate it lines up with the player only after turning θ = 2π − 2·atan(D/r), where r ≈ 240 to 310 px. In the simulation it is within 0.05 rad on tick
   164 for D = 300 (after the tick-150 fizzle), tick 149 for D = 500, tick 138 for D = 800 and tick 134 for D = 1000. Use D ≥ 800 px. The flight spans about 480 px sideways
   and reaches about 260 px beyond the start, which fits the Assault rect. If the row fails at a short D, fix the geometry. Never raise `hijack_turn_rate` for it: the Risks licence to change a number covers only the dodge rows.
2. **The tail of the clearance row is vacuous.** After the player stops at tick 30, the rocket clears 60 px on tick 36 and is about 474 px away when it fizzles on tick 150. It never
   blasts, so "any later blast comes only after `d >= 60`" can never be tested. Drop the tail, or label it as documentation rather than a falsifier.
3. **Assault placement for the tick-150 rows.** These are Fizzle, Null source, Target freed, the hijacked `jam_guidance` row and the R3 1.0 s row. Each needs roughly 600 to 1000 px of flight
   inside the 1608 px projectile world rect. Otherwise the rect rule ends the rocket first, through `_on_expired`, on the wrong tick. Choose start points with that much room ahead of the rocket.
4. **`birth_color()` must read the live ramp** (`_particles.color_ramp.get_color(0)`), not a stored field. Otherwise a build that stores the colour but never rewrites the gradient passes M4.
5. **Log the null-source Choice in `DECISIONS.md` as a deviation** from §2.5's literal "not a valid instance → fizzle at once". "For every task" requires every deviation to be logged, and step 8 currently lists only the Resolution, M1, M5 and M6.
6. **Crossing guard geometry.** The salvo is launched 15 px ahead of the ship that is the hijack target (`warhead_missile_shooting_state.gd:75`). Make the crossing happen at least
   about 100 px from that ship, for example by launching while the hijacked rocket is 200 px or more away. Otherwise the hijacked rocket can arm and blast within the 10 frames after the crossing, and the "all alive" check fails on a correct build.
   For the same reason, in the primary-fire row, place B's hijacked rocket so that it neither reaches B nor flies into B's own fire within the 120 ticks.
7. Optional: guard the target in steps 4 and 6 with `is_instance_valid(t) and t.is_inside_tree()`, matching the existing `locked_target.is_inside_tree()` check in `_physics_process`.
