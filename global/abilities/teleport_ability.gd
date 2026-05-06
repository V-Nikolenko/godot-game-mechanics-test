# global/abilities/teleport_ability.gd
class_name TeleportAbility
extends AbilityBase

const _DISTANCE: float = 120.0
const _CONTACT_DAMAGE: int = 25
const _CONTACT_RADIUS: float = 16.0

func get_display_name() -> String: return "Teleport"
func get_cooldown() -> float: return 3.0

func activate(ctx: AbilityController) -> bool:
	var actor: CharacterBody2D = ctx.actor
	var dir: Vector2 = _get_direction(actor)
	if dir == Vector2.ZERO:
		return false

	var dest: Vector2 = actor.global_position + dir * _DISTANCE

	## Ghost flash at origin.
	_spawn_ghost(actor)

	## Move.
	actor.global_position = dest

	## Contact damage: any enemy within _CONTACT_RADIUS of landing point.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		if n.global_position.distance_to(dest) > _CONTACT_RADIUS:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_CONTACT_DAMAGE)

	return true

func _get_direction(actor: Node2D) -> Vector2:
	## Assault: use WASD movement input direction.
	var v := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if v != Vector2.ZERO:
		return v.normalized()
	## Open space / no input: teleport forward (facing direction).
	return Vector2.UP.rotated(actor.rotation)

func _spawn_ghost(actor: Node2D) -> void:
	## Brief translucent copy of the sprite at the origin.
	var ghost := Sprite2D.new()
	var sprite := actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	if sprite and sprite.sprite_frames:
		ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.modulate = Color(0.5, 0.8, 1.0, 0.6)
	actor.get_parent().add_child(ghost)
	## Set global transform after add_child so world-space scale is correct.
	ghost.global_position = actor.global_position
	ghost.global_scale = actor.global_scale
	## Tween owned by ghost so it survives actor death.
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.3)
	t.tween_callback(ghost.queue_free)
