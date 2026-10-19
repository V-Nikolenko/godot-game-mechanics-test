VERDICT: CHANGES_REQUESTED

Review of `docs/plans/cmv9szqlf001nqs2xlf0nad51/3-plan.md` (t5, enemy rockets: Dumb + Pursuit) against the approved epic
plan `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` ("For every task", §2.6, §2.7, §4.1, §4.3) and the code.

Overall the plan follows the epic closely. The file layout, scene shape, layers, exports, `_RESET_PROPS`, the `_mark_done`
latch, `ContactBlast.spawn`, `ProjectileLifetime`, the `BulletPool` hand-over and the fixture launcher are all as the epic
specifies, and it reuses the existing components rather than rebuilding them. I checked every collision pairing below
against the scenes and they are correct. Changes are needed for three reasons: one contract deviation (the no-target
guidance), three test rows that cannot fail as written, and two scene facts the plan does not account for that the
implementer would otherwise find mid-run.

## Collision pairings (checked; all correct)

- Rocket impact HitBox 32 / mask 640 against the player HurtBox 128 / 1281 (`player_ship.tscn:259-263`,
  `player_fighter.tscn:334-337`): 640 & 128 is non-zero, so the rocket detonates on the player. 1281 & 32 is zero, so the
  player never takes the impact. Correct: the player takes the blast only.
- Enemy hurtboxes 512 / 1121 (`ram_corvette.tscn:81-83`; `BaseEnemy` default `DefenseProfile`): both directions overlap,
  so enemies take `impact_damage`. The enemy contact boxes are on 256 (`ram_corvette.tscn:103`), which the rocket's
  masks 640 and 96 do not include.
- Ram plates 512 / 96 (`ram_corvette.tscn:123-125,146-148,170-172`): each sees the other. `ArmorPlate.breaks_on` takes
  `ROCKET` (`armor_plate.gd:87-91`), and `_resolve` caches its answer per HitBox, so the plate is damaged once whichever
  callback runs first. The hull answers `deflects_hit → is_armored` (`ram_corvette.gd:88-89`), and `_on_received_damage`
  refuses the hit (`:126-131`).
- Big asteroid 512 / 32, `accepted_damage_types = [1]` (ROCKET) (`big_asteroid.tscn:35-39`): correct. Its
  ContactHitBox on 1024 is in neither rocket mask.
- Player bullet HitBox 64 / 513 (`bullet.tscn:43-45`) and homing missile HitBox 32 / 513 (`homing_missile.tscn:53-55`):
  each sees the rocket's 512 HurtBox and the rocket's mask 96 sees both, so they destroy each other. `ArmorQuery`
  finds no `deflects_hit` or `is_armored` on the rocket, so the bullet is consumed (`bullet.gd:113-137`) and the
  missile frees itself (`homing_missile.gd:51-54`).
- The rocket's own HurtBox 512 / 96: its own HitBox and its siblings' HitBoxes (640 includes 512) see it, and the
  parent-is-`EnemyRocket` checks ignore them. No enemy, player or asteroid mask includes 512. `ContactBlast` is on 256
  (`contact_blast.gd:191`), outside mask 96, so a sibling's blast never defuses a rocket.

## Required changes

1. **No target must mean "keep heading", not "steer at the stale aim point"** (plan lines 65-66 and 75). The plan sets
   `_aim = _aim_point()` and then always calls `Steering.turn_toward(heading, _aim − global_position, …)`. With no
   player, `_aim_point()` returns the old `_aim`, so the rocket keeps steering toward the launch aim point. Once it has
   passed that point it turns round (1.6 rad/s × 3 s = 4.8 rad, a full U-turn) and comes back. The same happens
   whenever the launch direction is not exactly toward the aim (t8's cone and lead step). Epic §2.7 says: "No player →
   keep heading." Ph4's `EnemyOrdnance._aim_point()` (`enemy_ordnance.gd:193-195`) has the stale-point behaviour, so
   mirroring it here would be a regression against the epic. Fix: when `TargetInfo.player(...).has_target` is false,
   skip the turn and leave `_aim` alone. Add a hand-ticked row in both modes: remove the harness player from group
   `player` (or free it) during the guidance window, and assert the heading stays constant to 1e-6 through
   `boost + guidance`.

2. **The real-player rows cannot detect the regression they exist for** (plan line 135; epic §2.7 "not
   `impact_damage + blast_damage`"; finding 2 of the epic review). Shipped DUMB and PURSUIT have
   `impact_damage == blast_damage` (16/16, 18/18), and `PlayerBase._apply_damage` starts 0.5 s of i-frames after every
   hit (`player_base.gd:105-124`). Suppose the impact HitBox were wrongly put where the player's mask sees it (on 256,
   say). The player would take the impact (16), and the i-frames would swallow the blast. "HP drops by exactly
   `blast_damage`" and "exactly one shield charge" would both still pass. Fix both rows:
   - Before `launch()`, set the test rocket's `impact_damage` to a value distinct from `blast_damage` (e.g. 3). The
     epic allows setting exports before `launch()`.
   - Record every `received_damage` emission on the real player `HurtBox` and assert the list equals exactly
     `[blast_damage]`. This does not depend on i-frames, so it also proves that the shield charge was spent by the
     blast. Lowering `invincibility_sec` does not work: `Timer.start(0)` falls back to `wait_time`, and the timer is
     idle-processed while the 8× clock runs several physics steps per idle frame.

3. **`tests/helpers/fixture_enemy.tscn` has no HurtBox shape and 10 HP** (`fixture_enemy.tscn` "HurtBox" node has no
   CollisionShape2D child; `Health max_health = 10`). Context line 26 and plan lines 131-132 treat it as a ready
   target. As written:
   - The friendly-fire row cannot pass: 16 damage clamps at 10 and kills the fixture, and with no shape the rocket
     never meets it.
   - The homing-missile row's "fixture enemy behind untouched" is true even if the rocket is absent, because nothing
     can touch a shapeless hurtbox. That row cannot fail.

   Follow the established pattern in `tests/integration/test_enemy_shield_hits.gd:10-13,60-69`: raise HP (e.g. 1000)
   before entering the tree, add a circle shape to the HurtBox, and read HP deltas. For the homing row, also add a
   control (or reuse a build) showing that the same missile reaches and damages the fixture when no rocket is in its
   path.

4. **The hand-ticked fizzle row cannot see a blast** (plan line 137). `ContactBlast.spawn()` parents the blast through
   `_attach.call_deferred(container)` (`contact_blast.gd:204`). A synchronous hand-ticked test that counts
   `ContactBlast` children right after expiry sees zero even on a build that wrongly blasts on fizzle. Fix: after
   expiry, `await` one frame before counting (or count via `child_entered_tree` after that await, as
   `test_enemy_ordnance.gd:72-79` does). Add a positive control in the same harness: a hand-ticked `_detonate()` path
   does produce exactly one counted blast.

5. **The Ram plate row never makes the rocket cross the armoured hull, so the `ArmorQuery` pass-through is untested**
   (plan line 133; epic §2.6 "an armoured hull lets a rocket through (`ArmorQuery`)"). `PlateFront` sits at (0, 36),
   outside the hull HurtBox circle of r = 34 (`ram_corvette.tscn:23-24,119-130`). A rocket fired at a plate from
   outside meets the plate first, or in the same step with undefined order. A build whose impact handler skipped
   `ArmorQuery` and detonated on the hull would still pass 50 → 34. Fix: fire from behind or across the hull
   (e.g. from −y toward `PlateFront`), so the rocket overlaps the hull HurtBox for several ticks before it reaches a
   plate. The 50 → 34 assertion then fails on that regression. Also state in the plan that the Ram is frozen for the
   row (`suspend_ai()`, or physics off), so its brain and mover do not move the plates. Connect `plate_broken` with a
   one-argument callable: it emits `plate_name: StringName` (`ram_corvette.gd:34`; the README arity trap).

6. **Exports set between `acquire()` and `launch()` never reach the children** (plan lines 45-46, 52-57). The epic
   (§2.6, "Ph16 difficulty tiers scale a rocket by setting exports before `launch()`") and DECISIONS line 1876 make
   "set exports, then `launch()`" the tuning path. `BulletPool.acquire()` calls `reset()` (`bullet_pool.gd:89-90`),
   and that is where the plan pushes `max_time` / `max_distance` into `ProjectileLifetime` and sizes the shapes. A
   tier change made after `acquire()` therefore changes the rocket's exports but not its lifetime or collision radii.
   Fix: apply `max_time`, `max_distance`, `body_radius` (both shapes) and `impact_damage` in `launch()`, which the
   plan already does for `impact_damage`. Keeping them in `_ready()`/`reset()` as well is harmless. The `reset
   restores exports` row should also check that a `max_time` set after `acquire()` and before `launch()` reaches the
   lifetime.

## Should fix (not blocking on their own, but do them in the same revision)

7. **The ally fighter's ContactHitBox is on layer 64** (`ally_fighter.tscn:56-60`, damage_type CONTACT). The rocket's
   shoot-down mask 96 sees it, so a rocket meeting an ally can be *defused* (no blast) by the ally's contact box or
   *detonated* by its 128 hurtbox. Which one depends on the undefined `area_entered` order. The epic's table says
   allies take `blast_damage`. This is an epic-level gap rather than something the plan introduced, so the plan should
   not change the design silently. It should log the gap in DECISIONS under Phase 5 for t17, where rockets and allies
   meet in level 1. If the owner agrees, the narrow fix is for the shoot-down handler to ignore `CONTACT`-type
   HitBoxes, which keeps the stated intent ("a player bullet or player missile and a rocket destroy each other").

8. **Add a cheap "not an enemy" row.** "Never in group `enemies`, never scored" is part of the §2.6 contract (plan
   line 85) but has no test. `test_enemy_ordnance.gd::test_ordnance_is_not_an_enemy` is the precedent.

9. **Define the detonation geometry in the real-player rows by the measured blast position.** For "30 px" and
   "`blast_radius + 20`", record the `ContactBlast` position on `child_entered_tree` and assert its distance from the
   player's HurtBox centre, not the fixture's placement: the rocket detonates at the fixture's edge, not its centre.
   The fighter's HurtBox shape is offset (0, 1) (`player_fighter.tscn:340-342`). The margin at +20 is only about
   5.5 px (36 + 13.5 + 1 = 50.5 against 56), so route the approach so the rocket never comes within
   `body_radius` + 13.5 of the player first.

10. **Use a tolerance for `rotation == heading.angle() + PI/2`** (plan line 125). `Node2D.rotation` is a `real_t`
    (32-bit), so an exact `assert_eq` against a 64-bit GDScript float is fragile. Use `assert_almost_eq` (1e-5). The
    1e-6 heading-constancy check is fine, because a heading that is never rewritten is bit-identical.

11. **Plan line 116, "Scenarios sit inside the Assault projectile rect so both modes fly the same course",** is not
    true for long rows. The rect is 1608 × 1608 (`arena_camera.gd:86-89`: −164…1444, −444…1164), and DUMB and PURSUIT
    fly 1800 and 2400 px. Assault rows end at the rect edge. The assertions still hold, but the claim should be removed
    so that a later reader does not rely on it.

12. **Plan step 6** asks for a DECISIONS line "tuning lives in the rocket scenes". That line already exists
    (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md:1874-1876`). Append only real deviations (items 1, 6 and 7
    if adopted).

13. **Close the HitBox in `reset()` with `set_deferred` too** (plan line 56 is ambiguous about this). It keeps every
    area toggle flush-safe if a launcher ever calls `acquire()` from a callback.

## Checked and fine

- Build order (lifetime rows first → script and scenes → hand-ticked → real physics → gate) works.
  `EnemyRocketScenes.pool_size_for` gives DUMB 3 × ceil(4/4) = 3 and PURSUIT 3 × ceil(6/4) = 6 with the epic §2.9
  numbers (`salvo_count` 3, `salvo_period_min` 4.0).
- Lifetime arithmetic matches epic §2.6: DUMB 0.25 + 0.422 + 3.126 = 3.80 ≤ 4.0; PURSUIT 5.90 ≤ 6.0. The boundary row
  is present.
- Arming geometry: at the arm point the HitBox edge is at ≥ 40 + 8 px from the launcher centre, outside the fixture's
  r 40 HurtBox, so the launcher can never be hit when the HitBox opens. The plan handles a freed launcher and a null
  launcher as §2.6 requires.
- Flush safety: `_mark_done()` closes areas with `set_deferred`, the blast goes through `ContactBlast.spawn`, and
  `ExplosionEffect.explode` adds no physics body (the same calls `EnemyOrdnance._defuse` makes inside a flush). Idle
  pooled rockets are `PROCESS_MODE_DISABLED`, which removes their areas from physics under the default `disable_mode`.
- The automatic sweeps (signal arity, layer names, sprite transparency with no texture, project load, UID with
  path-only references) see nothing they would reject.
- The gate-time plan and the over-allotment fallback match §4.3. The 6.0 s budget is tight for roughly 15 real-physics
  cases including two real player scenes per mode, so sharing builds as planned matters.

---

# Round 2

VERDICT: APPROVED

I re-checked the "Revision 1" table (`3-plan.md:156-172`) and the line-117 wording change against each round-1 finding
and the code.

| # | Answer | Check |
|---|---|---|
| 1 | No player → no turn; new hand-ticked row in both modes | Matches epic §2.7 "No player → keep heading". The row can fail on the old stale-aim build: once the rocket passes its launch aim it turns. |
| 2 | `impact_damage` 3; the player HurtBox `received_damage` list must equal `[blast_damage]`, or `[]` at +20 | Independent of i-frames (`player_base.gd:105-124`). An impact that wrongly reached the player would put 3 in the list, so the row can now fail. The shield row asserts the same list. |
| 3 | Fixture with HP 1000 and an r 16 circle shape, as in `test_enemy_shield_hits.gd`; homing control on a second fixture | Correct. The homing HitBox deals 100 (`homing_missile.tscn` HitBox `damage = 100`), so the control fixture's 1000 → 900 is observable. The "untouched" assertion is no longer vacuous. |
| 4 | Two physics frames awaited before counting; positive control through the impact handler | Covers the deferred `_attach` (`contact_blast.gd:204`). The control proves the counter can see a blast. |
| 5 | Ram frozen; fired from −y along +y at `PlateFront` | Geometry checked: the `PlateFront` capsule is r 6, height 36, rotated 90° at (0, 36), so it spans y ≈ 30..42 and x −18..18. The side plates sit at x ±35.45 (`ram_corvette.tscn:26-31,119-170`), off the x = 0 path. The rocket overlaps the hull circle (r 34) for about 60 px (≈ 7 ticks at 520 px/s) before the plate, so a build that skipped `ArmorQuery` would detonate on the hull and fail 50 → 34. `on_suspended()` (`ram_corvette_brain.gd:205-208`) has no side effect that matters here. |
| 6 | `launch()` applies lifetime, shapes and damage; the reset row checks a post-`acquire()` `max_time` | Closes the Ph16 path. |
| 7 | Shoot-down ignores `CONTACT` HitBoxes, logged in DECISIONS, with a row | Coordinator-adopted narrow fix. No player projectile is `CONTACT`: bullet and sniper bullet are 0 (LASER), homing and warhead missiles are 1 (ROCKET). The only `CONTACT` HitBox on 32 or 64 is the ally fighter's (`ally_fighter.tscn:56-60`), so player shoot-downs are unchanged. |
| 8 | Not-an-enemy row | Fine. |
| 9 | Blast position measured; far rocket fired from the far side | Fine. One tightening is listed in note (a) below. |
| 10-13 | Tolerance on `rotation`, rect claim removed, no duplicate DECISIONS line, deferred HitBox close | All fine. Line 117 now reads correctly. |

## Notes for the implementer (non-blocking)

a. **The near (30 px) row should prove it is a near miss.** As written, the bound is "blast distance to the player
   centre ≤ 30 + `body_radius`". A rocket that detonated directly on the player (distance ≈ 11–13.5 + `body_radius`)
   also satisfies it, so this row would quietly turn into a second direct-hit row. Add a lower bound: the distance is
   greater than the player hurtbox radius + `body_radius`. Alternatively, or as well, assert that the fixture's HP fell
   by `impact_damage`, which shows the rocket detonated on the fixture.

b. **Update the plan body to match the Revision table**, so the implementer does not code from the stale text:
   - Line 75 still says "no target → `_aim` unchanged (heading kept)" and steps 1/66 still turn toward `_aim`
     unconditionally. Revision item 1 is the rule.
   - Line 111 still asks for the duplicate DECISIONS line. Revision item 12 is the rule.
   - Line 57 does not say the HitBox close is deferred. Revision item 13 is the rule.

c. **The gate budget is still tight.** Revision 1 adds a few real-physics assertions: the homing control, the
   `CONTACT` row and the Ram crossing. Fold them into existing builds where possible to stay within the 6.0 s
   allotment.
