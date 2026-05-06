# global/abilities/trajectory_calc_ability.gd
class_name TrajectoryCalcAbility
extends AbilityBase

const _DURATION: float = 5.0
const _TIME_SCALE: float = 0.3

var _time_left: float = 0.0
var _active: bool = false

func get_display_name() -> String: return "Trajectory"
func get_cooldown() -> float: return 20.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	_active = true
	Engine.time_scale = _TIME_SCALE
	## Blue-tint visual.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)
	return true

func tick(ctx: AbilityController, delta: float) -> void:
	if not _active:
		return
	## delta is already scaled by Engine.time_scale; divide by _TIME_SCALE (what we set)
	## to get real elapsed time. Using the const avoids miscount if another system
	## changes Engine.time_scale externally.
	_time_left -= delta / _TIME_SCALE
	if _time_left <= 0.0:
		_restore(ctx)

func deactivate(ctx: AbilityController) -> void:
	_restore(ctx)

## Safety net: if the node is freed while the ability is active (scene reload, game over),
## restore time_scale to prevent it from being stuck at 0.3 permanently.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _active:
		Engine.time_scale = 1.0

func _restore(ctx: AbilityController) -> void:
	if not _active:
		return
	_active = false
	_time_left = 0.0
	Engine.time_scale = 1.0
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		ctx.actor.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
