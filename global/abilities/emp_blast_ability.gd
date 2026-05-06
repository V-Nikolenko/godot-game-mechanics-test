# global/abilities/emp_blast_ability.gd
class_name EMPBlastAbility
extends AbilityBase

const _STUN_DURATION: float = 5.0

## Groups/class names that are NOT stunned.
const _IMMUNE_CLASSES: Array[String] = ["BigAsteroid", "SmallAsteroid", "Asteroid", "RamShip"]

func get_display_name() -> String: return "EMP Blast"
func get_cooldown() -> float: return 15.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Visual: bright green flash expanding outward.
	_spawn_emp_visual(actor)

	## Stun eligible enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node
		if n == null:
			continue
		if _is_immune(n):
			continue
		_stun_enemy(n, actor)

	return true

func _is_immune(node: Node) -> bool:
	for class_name_str in _IMMUNE_CLASSES:
		if node.is_class(class_name_str):
			return true
		if node.get_script() != null and node.get_script().get_global_name() == class_name_str:
			return true
	return false

func _stun_enemy(enemy: Node, actor: Node2D) -> void:
	## Disable processing for _STUN_DURATION seconds.
	enemy.set_process_mode(Node.PROCESS_MODE_DISABLED)

	## Re-enable after the stun expires.
	var timer := actor.get_tree().create_timer(_STUN_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(enemy):
			enemy.set_process_mode(Node.PROCESS_MODE_INHERIT)
	)

func _spawn_emp_visual(actor: Node2D) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(0.2, 1.0, 0.5, 0.9)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 10.0)
	line.points = pts
	ring.add_child(line)
	## Tween owned by ring to prevent leak if actor is freed during animation.
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(80.0, 80.0), 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.35)
	t.tween_callback(ring.queue_free)
