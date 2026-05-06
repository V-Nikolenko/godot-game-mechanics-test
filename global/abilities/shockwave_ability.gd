# global/abilities/shockwave_ability.gd
class_name ShockwaveAbility
extends AbilityBase

const _RADIUS: float = 90.0
const _DAMAGE: int = 20
const _KNOCKBACK: float = 280.0

func get_display_name() -> String: return "Shockwave"
func get_cooldown() -> float: return 8.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Visual ring: scale a temporary circle from 0 to _RADIUS.
	_spawn_ring(actor)

	## Find all enemies inside the radius.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var dist: float = n.global_position.distance_to(actor.global_position)
		if dist > _RADIUS:
			continue

		## Knockback: push enemy away from player.
		if n.has_method("apply_knockback"):
			var dir: Vector2 = (n.global_position - actor.global_position).normalized()
			n.apply_knockback(dir * _KNOCKBACK)

		## Damage via HurtBox.
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	return true

func _spawn_ring(actor: Node2D) -> void:
	## Simple expanding circle drawn with a Line2D arc.
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.4, 0.8, 1.0, 0.8)
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 32
	for i in steps + 1:
		var angle: float = TAU * i / steps
		pts.append(Vector2(cos(angle), sin(angle)) * 4.0)
	line.points = pts
	ring.add_child(line)

	var t := actor.create_tween()
	t.tween_property(ring, "scale", Vector2(_RADIUS / 4.0, _RADIUS / 4.0), 0.25) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.25)
	t.tween_callback(ring.queue_free)
