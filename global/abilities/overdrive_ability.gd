# global/abilities/overdrive_ability.gd
class_name OverdriveAbility
extends AbilityBase

const _DURATION: float = 10.0
const _FIRE_RATE_MULTIPLIER: float = 2.0
const _EXPIRY_DAMAGE: int = 15

var _time_left: float = 0.0

func get_display_name() -> String: return "Overdrive"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	ctx.fire_rate_multiplier = _FIRE_RATE_MULTIPLIER
	ctx.overdrive_active = true
	ctx.actor.set("fire_rate_multiplier", _FIRE_RATE_MULTIPLIER)
	ctx.actor.set("overdrive_active", true)
	## Red-orange pulsing glow.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.4, 0.1, 1.0)
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
	ctx.fire_rate_multiplier = 1.0
	ctx.overdrive_active = false
	if actor:
		actor.set("fire_rate_multiplier", 1.0)
		actor.set("overdrive_active", false)
	## Expiry damage — bypasses shield for dramatic effect.
	if ctx.health:
		ctx.health.decrease(_EXPIRY_DAMAGE)
	if actor:
		var sprite := actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
		if sprite:
			actor.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.4)
