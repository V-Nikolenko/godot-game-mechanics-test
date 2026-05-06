# global/abilities/plasma_nova_ability.gd
class_name PlasmaNovaAbility
extends AbilityBase

const _DAMAGE: int = 50

func get_display_name() -> String: return "Plasma Nova"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Screen-wide flash.
	_spawn_flash(actor)

	## Deal damage to all enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	return true

func _spawn_flash(actor: Node2D) -> void:
	## Purple ColorRect covering the viewport, fades out quickly.
	var overlay := ColorRect.new()
	overlay.color = Color(0.85, 0.5, 1.0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var canvas := CanvasLayer.new()
	canvas.layer = 128  ## Above everything.
	canvas.add_child(overlay)
	actor.get_tree().root.add_child(canvas)

	## Tween owned by canvas so it survives actor death.
	var t := canvas.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, 0.5)
	t.tween_callback(canvas.queue_free)
