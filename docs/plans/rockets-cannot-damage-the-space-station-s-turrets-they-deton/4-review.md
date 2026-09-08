VERDICT: APPROVED

## Findings (verification notes, not blockers)

- `assault/scenes/projectiles/bullets/bullet.gd:139-141` — `_hit_is_deflected()` is exactly the
  duck-typed `area.get_parent().has_method("is_armored") and is_armored()` check the plan proposes
  to transplant. The plan's claim that this is "already the sanctioned extension point" is backed
  by the docstring at `bullet.gd:21-23` ("Any future entity that needs to deflect a bullet without
  consuming it must expose its own `is_armored()`-shaped query"). No new HurtBox API is needed —
  correct call to reject the task body's option 1.

- `assault/scenes/projectiles/missiles/homing/homing_missile.gd:46-47` and
  `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd:23-24` — both confirmed to
  unconditionally `queue_free()` on any `area_entered`, exactly as the plan states. The proposed
  guard (`if _hit_is_deflected(area): return` before `queue_free()`) is a correct, minimal fix.

- `assault/scenes/enemies/space_station/space_station.gd:155-156` — `is_armored()` is
  `live_turret_count() > 0`, independent of which HurtBox (core vs. any given turret) registered
  the hit, and depends only on turret liveness, not on anything the incoming projectile does. Safe
  to query synchronously as the plan assumes.

- Scope-check claim verified empirically: `grep -rn "func is_armored"` across the repo returns
  exactly `space_station.gd:155` (production) and `test_player_bullet_lifetime.gd:66` (a
  test-only stand-in). No other enemy, hazard, or entity implements `is_armored()`, so the plan's
  "inert against every other enemy" claim holds — a rocket still detonates on its first hit against
  everything else, unchanged.

- `homing_missile.tscn:53-64` and `warhead_missile.tscn:59-72` — both `HitBox` nodes are wired
  identically to `bullet.tscn`'s pattern (`area_entered -> _on_hit_box_area_entered` on the
  missile root), confirming no scene changes are required, as the plan states.

- `assault/scenes/enemies/space_station/station_turret.gd:62-77` — `_destroy()` (deferred)
  disables `monitoring`, `monitorable`, and the `CollisionShape2D` on a dead turret's `HurtBox`.
  Checked the turret-death interaction explicitly asked about: a turret has no `is_armored()`
  method, so a rocket hitting a *live* turret directly is never "deflected" — it registers via the
  turret's own `HurtBox.received_damage` and the missile's `_on_hit_box_area_entered` sees a
  non-deflected hit and detonates, exactly as today. A rocket that reaches an *already-dead*
  turret's disabled `HurtBox` never receives `area_entered` there at all — it simply keeps flying
  until the existing off-screen/arena-bounds self-free fires (`homing_missile.gd:29-32`,
  `warhead_missile.gd:19-20`). This is the same shape of race that already exists today for
  `Bullet` against this exact boss (`bullet.gd` has carried the identical deflection guard since
  the prior fix), so the missile transplant introduces no new leak or edge case here — it inherits
  a already-proven-safe interaction, not a new one.

- Test rewrite (`tests/integration/test_station_incoming_damage_paths.gd:164-187`) — read the
  CHARACTERIZED test being replaced and its two "deflected" siblings
  (`test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it`,
  `test_a_real_asteroid_is_deflected_by_the_armored_core_rather_than_missing_it`). The plan's
  replacement keeps asserting `armor_deflected` was emitted (proves the core was actually crossed,
  not bypassed) in addition to the turret HP delta and missile-consumed check — this avoids the
  exact vacuous-pass trap the file's own header warns about ("silence cannot tell a wrong mask from
  working armour"). Frame budget checked against the physics: missile at 500 px/s from y=200
  reaches the core's bottom edge (~80 px, ~9.6 frames) and then the turret rim at y=+102 (~98 px
  total, ~11.8 frames) — comfortably inside the proposed 16-frame budget, so the assertions are not
  vacuous.

- `tests/integration/test_player_bullet_lifetime.gd:151-172` (`test_a_deflected_hit_does_not_
  consume_the_bullet`) is a reasonable model for the new rocket-side test; the plan's decision not
  to duplicate a full turret-lane test for the warhead missile (identical 4-line transplant, already
  covered by `test_a_real_warhead_missile_damages_the_unarmored_core_through_the_collision_layers`
  for the layer/mask path) is consistent with the project's stated aversion to duplicate coverage
  of identical logic.

- `ENEMY.md` "Core hurtbox" section (`:549-597`) and the rejected 88×240 proposal, and the
  deferred armour-plate `HurtBox` idiom, are both accurately represented by the plan as reasons to
  reject alternatives 1 and 2 from the task body — neither the core geometry nor the collision
  layers/masks need to change, only the missile's own self-consumption.

No correctness, convention, or test-coverage problems found. The plan is a direct, minimal
transplant of an already-shipped and documented idiom, correctly scoped, with adequate
characterization-to-intent test conversion and a docs-update step.
