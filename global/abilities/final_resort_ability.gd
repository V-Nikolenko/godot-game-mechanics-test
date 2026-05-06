# global/abilities/final_resort_ability.gd
class_name FinalResortAbility
extends AbilityBase

const _DAMAGE_MULTIPLIER: float = 3.0

var _active: bool = false
var _saved_hp: int = 0

func get_display_name() -> String: return "Final Resort"
func get_cooldown() -> float: return 0.0  ## Toggle — no cooldown between uses.

func activate(ctx: AbilityController) -> bool:
	if not _active:
		_engage(ctx)
	else:
		_disengage(ctx)
	return false  ## Don't trigger the cooldown system.

func deactivate(ctx: AbilityController) -> void:
	if _active:
		_disengage(ctx)

func _engage(ctx: AbilityController) -> void:
	if not ctx.health:
		push_warning("FinalResortAbility: ctx.health is null, cannot engage")
		return
	_active = true
	_saved_hp = ctx.health.current_health

	## Collapse HP to 1, drain shield.
	ctx.health.set_health(1)
	if ctx.shield:
		ctx.shield.set_shield(0)

	## Triple damage.
	ctx.damage_multiplier = _DAMAGE_MULTIPLIER
	ctx.actor.set("damage_multiplier", _DAMAGE_MULTIPLIER)

	## Blood-red ship tint.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.1, 0.1, 1.0)

func _disengage(ctx: AbilityController) -> void:
	_active = false
	if not ctx.health:
		return

	## Restore HP to what it was when we engaged (can't gain HP from the mode).
	ctx.health.set_health(mini(_saved_hp, ctx.health.current_health))

	## Restore damage.
	ctx.damage_multiplier = 1.0
	ctx.actor.set("damage_multiplier", 1.0)

	## Remove tint.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		ctx.actor.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
