# global/ship_modules/parry_module.gd
class_name ParryModule
extends ShipModuleBase

## Armor slot — active module.
## Press H to open a 0.5-second parry window: damage_reduction is set to 1.0
## (full immunity) for the duration. 10-second cooldown.

const _WINDOW:   float = 0.5
const _COOLDOWN: float = 10.0

var _active:        bool  = false
var _window_left:   float = 0.0
var _cooldown_left: float = 0.0
var _prev_reduction: float = 0.0  ## Saved so remove() restores correctly.

func get_display_name() -> String: return "Parry"
func get_description() -> String:
	return "Press H to brace for impact. Negates all incoming damage for 0.5 seconds. 10-second cooldown."
func get_icon() -> Texture2D:
	return null  ## No icon asset yet; slot shows empty.
func get_slot() -> StringName: return &"armor"

func apply(_player: Node) -> void:
	pass  ## No passive effect.

func remove(player: Node) -> void:
	## If parry is active when unequipped, restore damage_reduction immediately.
	if _active:
		_deactivate(player)

func try_activate(player: Node) -> bool:
	if _active or _cooldown_left > 0.0:
		return false
	_active = true
	_window_left = _WINDOW
	_prev_reduction = player.get("damage_reduction")
	player.set("damage_reduction", 1.0)
	## Visual cue: flash sprite white-blue.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.8, 1.0, 1.0, 1.0)
	return true

func tick(player: Node, delta: float) -> void:
	if _active:
		_window_left -= delta
		if _window_left <= 0.0:
			_deactivate(player)
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

func _deactivate(player: Node) -> void:
	if not _active:
		return
	_active = false
	_window_left = 0.0
	_cooldown_left = _COOLDOWN
	player.set("damage_reduction", _prev_reduction)
	## Restore sprite colour.
	var sprite := player.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)

## Safety: restore damage_reduction if freed mid-effect.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _active:
		Engine.time_scale = 1.0  ## Noop for parry, but mirrors trajectory_calc safety net.
