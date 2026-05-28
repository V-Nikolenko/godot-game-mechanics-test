# assault/scenes/player/weapons/behaviors/straight_behavior.gd
class_name StraightBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null:
		return
	var bullet: Bullet = mode.projectile_scene.instantiate()
	bullet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	## Optional random spread: pellet_spread_deg > 0 adds a per-shot angle jitter
	## of ±half that value (used by gatling for a bullet-rain feel).
	var jitter: float = 0.0
	if mode.pellet_spread_deg > 0.0:
		jitter = randf_range(-deg_to_rad(mode.pellet_spread_deg * 0.5), deg_to_rad(mode.pellet_spread_deg * 0.5))
	bullet.rotation = actor.rotation + jitter
	bullet.range_px = mode.range_px
	bullet.damage = mode.damage
	bullet.shooter_velocity = actor.velocity
	if actor.get("pierce_module_active"):
		bullet.pierces_remaining = Bullet.MAX_PIERCE
	state.add_child(bullet)
