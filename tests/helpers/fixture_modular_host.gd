## The fixture host for `EnemyModule` / `ModularHull` (Phase 10 t2, docs/plans/cmwafsrau009zqs2yc1rli3sj/3-plan.md): a `BaseEnemy`
## with an **armoured** root and three parts under `Modules` (`Open`, `Locked`, `Laser`) plus a `ModularHull`. Scene:
## `tests/helpers/fixture_modular_host.tscn`; the part table (ids, roles, authored values) is in the plan's fixture section.
##
## The root deflects every projectile (`deflects_hit` / `is_armored` true) and refuses every damage that reaches its own hurtbox, so a
## shot always flies on to the part it is aimed at and the root's `Health` moves only through a part's `hull_share`. Its body is on the
## default layer 1, which the player beam's block ray sees, and it answers `is_laser_blocking() == false`, so the beam passes over it.
##
## No `class_name`: test-only types stay out of the game's global class list. Preload the scene.
extends BaseEnemy


func deflects_hit(_hit_box: HitBox) -> bool:
	return true


func is_armored() -> bool:
	return true


func is_laser_blocking() -> bool:
	return false


## Root damage is refused whatever its source (projectile, beam, nova, laser ray, enemy energy weapon).
func _on_received_damage(_damage: int) -> void:
	pass
