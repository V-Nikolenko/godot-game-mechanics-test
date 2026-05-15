# assault/scenes/player/weapons/behaviors/spread_behavior.gd
class_name SpreadBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null or mode.pellet_count <= 0:
		return
	var spread_rad := deg_to_rad(mode.pellet_spread_deg)
	var step := 0.0 if mode.pellet_count == 1 else spread_rad / float(mode.pellet_count - 1)
	var start_angle := -spread_rad * 0.5
	for i in mode.pellet_count:
		var pellet: Bullet = mode.projectile_scene.instantiate()
		pellet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
		pellet.rotation = actor.rotation + start_angle + step * i
		pellet.range_px = mode.range_px
		pellet.damage = mode.damage
		pellet.shooter_velocity = actor.velocity
		if actor.get("pierce_module_active"):
			pellet.pierces_remaining = Bullet.MAX_PIERCE
		state.add_child(pellet)
