# global/ship_modules/trajectory_calc_module.gd
class_name TrajectoryCalcModule
extends ShipModuleBase

const _DURATION:   float = 5.0
const _TIME_SCALE: float = 0.3
const _COOLDOWN:   float = 20.0

var _active:        bool  = false
var _time_left:     float = 0.0
var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Trajectory Calculation"
func get_description() -> String:
	return "Press H to engage targeting computers. Slows time to 30%% for 5 seconds. 20-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_time_slow_down.png")
func get_slot() -> StringName: return &"cockpit"

func apply(_player: Node) -> void:
	pass  ## No passive effect; H-key triggers everything.

func remove(player: Node) -> void:
	_restore(player)

func try_activate(player: Node) -> bool:
	if _active or _cooldown_left > 0.0:
		return false
	_active    = true
	_time_left = _DURATION
	Engine.time_scale = _TIME_SCALE
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)
	return true

func tick(player: Node, delta: float) -> void:
	if _active:
		## delta / _TIME_SCALE recovers real elapsed seconds while time is slowed.
		_time_left -= delta / _TIME_SCALE
		if _time_left <= 0.0:
			_restore(player)
	elif _cooldown_left > 0.0:
		## Module is inactive; time_scale == 1.0, so plain delta is correct.
		_cooldown_left -= delta

func _restore(player: Node) -> void:
	if not _active:
		return
	_active        = false
	_time_left     = 0.0
	_cooldown_left = _COOLDOWN
	Engine.time_scale = 1.0
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.3)

## Safety net: restore time_scale if node is freed mid-effect.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _active:
		Engine.time_scale = 1.0
