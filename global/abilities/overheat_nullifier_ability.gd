# global/abilities/overheat_nullifier_ability.gd
class_name OverheatNullifierAbility
extends AbilityBase

func get_display_name() -> String: return "Heat Flush"
func get_cooldown() -> float: return 15.0

func activate(ctx: AbilityController) -> bool:
	if ctx.overheat == null:
		return false  ## Not available without an overheat component (open space).
	ctx.overheat.heat = 0.0
	ctx.overheat._emit_heat()
	## Visual flash: blue-white modulate on ship.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(0.6, 0.9, 1.0, 1.0), 0.05)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.25)
	return true
