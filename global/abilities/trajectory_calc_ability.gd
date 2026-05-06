# global/abilities/trajectory_calc_ability.gd
class_name TrajectoryCalcAbility
extends AbilityBase

const _DURATION: float = 5.0
const _TIME_SCALE: float = 0.3

var _time_left: float = 0.0

func get_display_name() -> String: return "Trajectory"
func get_cooldown() -> float: return 20.0

func activate(_ctx: AbilityController) -> bool:
	_time_left = _DURATION
	Engine.time_scale = _TIME_SCALE
	## Blue-tint visual.
	var sprite := _ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)
	return true

func tick(_ctx: AbilityController, delta: float) -> void:
	if _time_left <= 0.0:
		return
	## `delta` is already scaled by Engine.time_scale, so divide it back to get real time.
	_time_left -= delta / Engine.time_scale
	if _time_left <= 0.0:
		_restore(_ctx)

func deactivate(ctx: AbilityController) -> void:
	_restore(ctx)

func _restore(ctx: AbilityController) -> void:
	if _time_left <= 0.0 and Engine.time_scale == 1.0:
		return  ## Already restored (idempotent guard).
	_time_left = 0.0
	Engine.time_scale = 1.0
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		ctx.actor.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
