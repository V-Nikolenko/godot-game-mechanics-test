# global/ship_modules/overdrive_module.gd
class_name OverdriveModule
extends ShipModuleBase

const _DURATION: float = 10.0
const _FIRE_RATE_MULTIPLIER: float = 2.0
const _EXPIRY_DAMAGE: int = 15
const _COOLDOWN: float = 30.0

const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"
const _ENGAGE_COLOR: Color = Color(1.0, 0.4, 0.1, 1.0)
const _RESTORE_TWEEN_DURATION: float = 0.4

var _active: bool = false
var _time_left: float = 0.0
var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Overdrive"
func get_description() -> String:
	return "Press H to push weapons beyond safe limits. Fire rate is doubled for 10 seconds and overheating is suppressed. When the effect expires naturally, the hull takes 15 damage. 30-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_overclock.png")
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(player: Node) -> void:
	## If active when unequipped, end cleanly without the expiry damage.
	if _active:
		_end(player, false)

func try_activate(player: Node) -> bool:
	if _active or _cooldown_left > 0.0:
		return false
	_active = true
	_time_left = _DURATION
	player.set("fire_rate_multiplier", _FIRE_RATE_MULTIPLIER)
	player.set("overdrive_active", true)
	## Red-orange ship tint.
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		sprite.modulate = _ENGAGE_COLOR
	return true

func tick(player: Node, delta: float) -> void:
	if _active:
		_time_left -= delta
		if _time_left <= 0.0:
			_end(player, true)  ## Natural expiry — apply damage penalty.
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

func _end(player: Node, apply_expiry_damage: bool) -> void:
	if not _active:
		return
	_active = false
	_time_left = 0.0
	_cooldown_left = _COOLDOWN
	player.set("fire_rate_multiplier", 1.0)
	player.set("overdrive_active", false)
	if apply_expiry_damage:
		var health: Health = player.get("health_component") as Health
		if health:
			health.decrease(_EXPIRY_DAMAGE)
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), _RESTORE_TWEEN_DURATION)

## Safety: reset multipliers reference so they are not left set if freed mid-effect.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _active:
		_active = false
