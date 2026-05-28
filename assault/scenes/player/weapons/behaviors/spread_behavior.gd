# assault/scenes/player/weapons/behaviors/spread_behavior.gd
class_name SpreadBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null or mode.pellet_count <= 0:
		return
	var half_rad := deg_to_rad(mode.pellet_spread_deg * 0.5)
	for i in mode.pellet_count:
		var pellet: Bullet = mode.projectile_scene.instantiate()
		pellet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
		## Each pellet fires at a random angle within the cone.
		var angle_offset: float = randf_range(-half_rad, half_rad)
		pellet.rotation = actor.rotation + angle_offset
		pellet.range_px = mode.range_px
		pellet.damage = mode.damage
		pellet.shooter_velocity = actor.velocity
		if actor.get("pierce_module_active"):
			pellet.pierces_remaining = Bullet.MAX_PIERCE
		state.add_child(pellet)
