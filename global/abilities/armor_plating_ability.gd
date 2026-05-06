# global/abilities/armor_plating_ability.gd
class_name ArmorPlatingAbility
extends AbilityBase

const _DURATION: float = 8.0
const _REDUCTION: float = 0.5

var _time_left: float = 0.0

func get_display_name() -> String: return "Armor"
func get_cooldown() -> float: return 20.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	ctx.actor.set("damage_reduction", _REDUCTION)
	## Orange-gold glow.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.75, 0.2, 1.0)
	return true

func tick(_ctx: AbilityController, delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_end(_ctx)

func deactivate(ctx: AbilityController) -> void:
	_end(ctx)

func _end(ctx: AbilityController) -> void:
	_time_left = 0.0
	var actor := ctx.actor
	if not actor:
		return
	actor.set("damage_reduction", 0.0)
	var sprite := actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		actor.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
