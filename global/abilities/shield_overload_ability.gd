# global/abilities/shield_overload_ability.gd
class_name ShieldOverloadAbility
extends AbilityBase

const _RADIUS: float = 100.0
const _DAMAGE_PER_SHIELD: float = 0.5  ## Each point of shield → 0.5 damage to enemies.

## Groups of projectiles that are destroyed by the overload.
const _BULLET_GROUPS: Array[String] = ["enemy_bullets", "bullets"]

func get_display_name() -> String: return "Shield Overload"
func get_cooldown() -> float: return 0.0  ## Cost is the shield itself.

func activate(ctx: AbilityController) -> bool:
	if ctx.shield == null or ctx.shield.is_empty():
		return false  ## Nothing to expend.

	var actor: Node2D = ctx.actor
	var shield_spent: int = ctx.shield.current_shield

	## Drain shield to zero.
	ctx.shield.set_shield(0)

	var damage: int = roundi(shield_spent * _DAMAGE_PER_SHIELD)

	## Damage nearby enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		if n.global_position.distance_to(actor.global_position) > _RADIUS:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(damage)

	## Destroy bullets/obstacles within radius.
	for group in _BULLET_GROUPS:
		for node in actor.get_tree().get_nodes_in_group(group):
			var n := node as Node2D
			if n == null:
				continue
			if n.global_position.distance_to(actor.global_position) <= _RADIUS:
				n.queue_free()

	## Visual: large electric burst.
	_spawn_burst(actor, shield_spent)
	return false  ## No standard cooldown (shield cost is the limiter).

func _spawn_burst(actor: Node2D, _intensity: int) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(0.1, 0.7, 1.0, 1.0)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 6.0)
	line.points = pts
	ring.add_child(line)
	var target_scale: float = _RADIUS / 6.0
	## Tween owned by ring to prevent leak if actor is freed during animation.
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.2)
	t.tween_callback(ring.queue_free)
