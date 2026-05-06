# global/abilities/shield_recharge_ability.gd
class_name ShieldRechargeAbility
extends AbilityBase

func get_display_name() -> String: return "Shield Up"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	if ctx.shield == null:
		return false
	ctx.shield.set_shield(ctx.shield.max_shield)
	## Visual flash: bright cyan.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(0.0, 1.0, 1.0, 1.0), 0.08)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.4)
	return true
