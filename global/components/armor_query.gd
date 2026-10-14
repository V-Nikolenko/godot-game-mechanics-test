## ArmorQuery — the one place a player projectile asks "does this target refuse my hit?".
##
## Two duck types, tried in this order (neither is a shared interface, same idiom as
## `is_laser_blocking()` in `beam_behavior.gd`):
##   1. `deflects_hit(hit_box: HitBox) -> bool` — hit-aware: "deflect a bullet, accept a rocket".
##      Used by `ArmorPlate` (the Ram Corvette's plates).
##   2. `is_armored() -> bool` — hit-blind, today's rule. The space station's core answers this
##      and implements no `deflects_hit`, so it takes the unchanged fallback path.
##
## Called by `bullet.gd`, `homing_missile.gd` and `warhead_missile.gd` from their (kept)
## `_hit_is_deflected` wrappers.
class_name ArmorQuery
extends RefCounted


## True when the hurtbox `area` refused damage from `hit_box` (so the projectile must not be
## consumed). `hit_box` is the projectile's own HitBox.
static func deflects(area: Area2D, hit_box: HitBox) -> bool:
	var target := area.get_parent()
	if target == null:
		return false
	if target.has_method("deflects_hit"):
		return target.deflects_hit(hit_box)
	return target.has_method("is_armored") and target.is_armored()
