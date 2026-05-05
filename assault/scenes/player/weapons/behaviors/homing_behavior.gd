# assault/scenes/player/weapons/behaviors/homing_behavior.gd
class_name HomingBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
	var actor: Node2D = state.get("actor")
	if actor == null or mode.projectile_scene == null:
		return
	var p: PrimaryHoming = mode.projectile_scene.instantiate()
	p.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	p.rotation = actor.rotation
	p.turn_rate_deg_per_sec = mode.homing_turn_rate_deg_per_sec
	p.lifetime_sec = mode.homing_lifetime_sec
	p.damage = mode.damage
	p.locked_target = _pick_target(actor)
	state.add_child(p)

## Picks the nearest enemy within the forward 90° cone.
func _pick_target(actor: Node2D) -> Node:
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	var forward := Vector2.UP.rotated(actor.rotation)
	var best: Node = null
	var best_dist := INF
	for e in enemies:
		var n := e as Node2D
		if n == null or not n.is_inside_tree():
			continue
		var to: Vector2 = n.global_position - actor.global_position
		if to.length() < 1.0:
			continue
		if forward.angle_to(to) > PI / 4.0 or forward.angle_to(to) < -PI / 4.0:
			continue
		var d := to.length()
		if d < best_dist:
			best_dist = d
			best = n
	return best
