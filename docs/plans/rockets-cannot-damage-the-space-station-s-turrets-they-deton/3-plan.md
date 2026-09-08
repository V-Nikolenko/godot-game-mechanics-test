# Rockets must survive a deflected hit on the armoured core

## Problem

A player who has equipped homing or warhead missiles and fires up a turret lane at the space
station's armoured core gets nothing: the rocket reaches the core's 240×240 `HurtBox` a couple of
frames before the turret rim behind it, is deflected for 0 damage, and detonates there —
`homing_missile.gd:47` and `warhead_missile.gd:23` both `queue_free()` on *any* `area_entered`,
armoured or not. The player reads this as "my rockets are broken." A default-gun bullet on the
same lane already survives the exact same deflection and goes on to hit the turret
(`bullet.gd::_hit_is_deflected`) — rockets are the odd one out, not the core.

## Design

Give both missiles the same exemption `Bullet` already has: duck-type `is_armored()` on the thing
they just hit, and only detonate on a hit that was not deflected. This is a direct transplant of
`bullet.gd::_hit_is_deflected`, not a new mechanism — `SpaceStation.is_armored()` already exists
and is already the sanctioned extension point per its own docstring ("any future entity that needs
to deflect a bullet without consuming it must expose its own `is_armored()`-shaped query").

Concretely, in both `homing_missile.gd` and `warhead_missile.gd`:

```gdscript
func _on_hit_box_area_entered(area: Area2D) -> void:
	if _hit_is_deflected(area):
		return
	queue_free()

func _hit_is_deflected(area: Area2D) -> bool:
	var target := area.get_parent()
	return target != null and target.has_method("is_armored") and target.is_armored()
```

### Alternatives considered

- **Have `HurtBox` report back whether it absorbed the hit** (the task body's first option). Not
  needed: the duck-type already reads the *target*, not the `HurtBox`, exactly as `Bullet` proves
  today. Adding a `HurtBox`-side API would be a second mechanism doing the same job the existing
  one already does, for no gain.
- **A separate armour-plate `HurtBox` over just the core** (the Gradius idiom, task body's second
  option). `ENEMY.md` → "Core hurtbox" already rejected narrowing/splitting the core hurtbox once
  (the 88×240 proposal) and explicitly defers the separate-hurtbox idiom as "a third HP bucket and
  new art" — out of scope for a code-health fix and orthogonal to this bug, which is entirely about
  the *missile's* self-consumption, not the core's geometry. The turret's `HurtBox` mask already
  includes rockets (bit 32, `station_turret.gd:35`); nothing about the collision layers needs to
  change.
- **Accept it as intended counterplay and document it.** Rejected: `CLAUDE.md`'s own bullet
  convention treats "consumed by a deflected hit" as a bug class already fixed once for bullets,
  and the task body itself frames this as the same bug recurring in the second projectile family,
  not a design decision to ratify.

### Scope check: does this change rocket behaviour against anything else?

`is_armored()` exists only on `SpaceStation` today (`grep -rl "func is_armored"` confirms it). Every
other enemy's `area.get_parent()` either has no `is_armored` method (the check short-circuits
false) or is `null` (contact hitboxes, hazards). So this change is inert everywhere except the
station: a rocket still detonates on its first hit against every other enemy, exactly as before.

## Build sequence

1. Add `_hit_is_deflected()` and the guard in `homing_missile.gd`. Independently testable: fire a
   homing missile at the armoured core and assert it survives and keeps flying.
2. Add the identical guard in `warhead_missile.gd`.
3. Update `tests/integration/test_station_incoming_damage_paths.gd`'s
   `test_a_rocket_up_a_turret_lane_dies_on_the_armored_core_and_never_reaches_the_turret` — rename
   and rewrite to assert the turret *does* take damage now, mirroring
   `test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core` in
   `test_space_station.gd`. Keep the two "deflected while armoured" tests
   (`test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it` and its asteroid
   sibling, which is unaffected) passing unchanged — a rocket must still register `armor_deflected`
   and be spent for 0 when nothing is left for it to hit.
4. Update `ENEMY.md`'s "Load-bearing dependency" / rocket-specific paragraph (currently states "a
   rocket cannot reach a turret behind the armoured core") to describe the fixed behaviour, via the
   `updating-project-docs` skill (structural behaviour change to a documented entity).
5. `bash /agent/verify.sh`.

## Test plan

- **`test_a_rocket_up_a_turret_lane_now_damages_the_turret_behind_the_armored_core`** (renamed from
  the CHARACTERIZED test): spawn a homing missile up the lane index-3 turret sits on; after 16
  physics frames assert `armor_deflected` was emitted (core still registered the hit) **and** the
  turret's health dropped by `HOMING_DAMAGE`, **and** the missile is gone (spent on the turret hit,
  not the core).
- Keep `test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it` passing
  unmodified: fired at the core's centre (no turret behind it on that lane), the rocket must still
  register `armor_deflected`, deal 0 core damage, and be consumed — proving the exemption only
  lets it *pass through* an armoured hurtbox, it does not make the rocket unkillable/pierce
  everything.
- **Boundary case**: a rocket that survives the core deflection and then reaches a *live* turret
  must still detonate normally on that turret (not pass through it too) — the existing
  `queue_free()` on a non-deflected hit already guarantees this; the rewritten test's assertion
  that the missile instance is gone after hitting the turret covers it.
- No new test needed for the warhead missile specifically beyond the existing
  `test_a_real_warhead_missile_damages_the_unarmored_core_through_the_collision_layers` (already
  covers the unarmoured path) — the deflection guard is identical code to the homing case and the
  homing test above is sufficient to prove the shared idiom works; adding a second full turret-lane
  test for the warhead would be duplicate coverage of the same four lines of logic, which
  `CLAUDE.md` discourages ("don't add features/tests beyond what the task requires" reasoning
  extends to duplicate test coverage of identical logic).

## Risks

- None to collision layers/masks — untouched.
- The rewritten test must still prove the deflection actually happened (not just "nothing stood in
  the way"), same trap `test_the_station_hull_does_not_block_the_players_mining_laser` already
  documents — assert `armor_deflected` emitted, not just the turret's final HP.

## Out of scope

- The separate armour-plate `HurtBox` (Gradius idiom) — already deferred in `ENEMY.md`, stays
  deferred.
- Any change to turret or core collision layers/masks.
- Pierce-style multi-hit rockets — out of scope; a rocket still detonates on its first *damaging*
  hit, exactly like a bullet with `pierces_remaining == 0`.
