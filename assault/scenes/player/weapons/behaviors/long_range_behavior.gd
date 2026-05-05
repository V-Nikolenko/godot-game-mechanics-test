# assault/scenes/player/weapons/behaviors/long_range_behavior.gd
class_name LongRangeBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null:
		return
	var bullet: Bullet = mode.projectile_scene.instantiate()
	bullet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	bullet.rotation = actor.rotation
	bullet.range_px = mode.range_px
	bullet.damage = mode.damage
	state.add_child(bullet)
