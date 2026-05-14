# global/ship_modules/shield_overload_module.gd
class_name ShieldOverloadModule
extends ShipModuleBase

const _RADIUS: float = 100.0
const _DAMAGE_PER_SHIELD: float = 0.5
const _KNOCKBACK: float = 280.0

## Groups of projectiles cleared by the blast.
const _BULLET_GROUPS: Array[String] = ["enemy_bullets", "bullets"]

## Visual constants.
const _RING_COLOR: Color = Color(0.1, 0.7, 1.0, 1.0)
const _RING_LINE_WIDTH: float = 5.0
const _RING_SEGMENTS: int = 32
const _RING_BASE_RADIUS: float = 6.0

func get_display_name() -> String: return "Shield Overload"
func get_description() -> String:
	return "Press H to detonate your shield. Converts every point of shield into 0.5 damage against enemies within 100px and sends them flying. Also destroys nearby projectiles. Requires shield to activate."
func get_icon() -> Texture2D:
	return null
func get_slot() -> StringName: return &"armor"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null or shield.current_shield <= 0:
		return false  ## Nothing to spend.

	var actor := player as Node2D
	var shield_spent: int = shield.current_shield

	## Drain shield.
	shield.set_shield(0)

	var damage: int = roundi(shield_spent * _DAMAGE_PER_SHIELD)

	## Damage + knockback enemies in radius.
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var dist: float = n.global_position.distance_to(actor.global_position)
		if dist > _RADIUS:
			continue
		## Knockback.
		if n.has_method("apply_knockback"):
			var dir: Vector2 = (n.global_position - actor.global_position).normalized()
			n.apply_knockback(dir * _KNOCKBACK)
		## Damage via HurtBox.
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(damage)

	## Destroy projectiles in radius.
	for group: String in _BULLET_GROUPS:
		for node: Node in player.get_tree().get_nodes_in_group(group):
			var n := node as Node2D
			if n == null:
				continue
			if n.global_position.distance_to(actor.global_position) <= _RADIUS:
				n.queue_free()

	## Visual: electric burst ring.
	_spawn_burst(actor)
	return true  ## Consumed input.

func _spawn_burst(actor: Node2D) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = _RING_LINE_WIDTH
	line.default_color = _RING_COLOR
	var pts: PackedVector2Array
	for i: int in _RING_SEGMENTS + 1:
		var angle: float = TAU * i / _RING_SEGMENTS
		pts.append(Vector2(cos(angle), sin(angle)) * _RING_BASE_RADIUS)
	line.points = pts
	ring.add_child(line)
	var target_scale: float = _RADIUS / _RING_BASE_RADIUS
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.2)
	t.tween_callback(ring.queue_free)
