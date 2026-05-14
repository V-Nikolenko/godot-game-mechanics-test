# global/ship_modules/overheat_nullifier_module.gd
class_name OverheatNullifierModule
extends ShipModuleBase

const _COOLDOWN: float = 15.0

const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"
const _FLASH_COLOR: Color = Color(0.6, 0.9, 1.0, 1.0)
const _FLASH_IN_DURATION: float = 0.05
const _FLASH_OUT_DURATION: float = 0.25

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Heat Flush"
func get_description() -> String:
	return "Press H to instantly vent all accumulated heat. Resets the overheat gauge to zero. 15-second cooldown. Has no effect in open space (no overheat system)."
func get_icon() -> Texture2D:
	return null
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	var overheat: Overheat = player.get("overheat_component") as Overheat
	if overheat == null:
		return false  ## Not available without an overheat component (open space).
	_cooldown_left = _COOLDOWN
	overheat.heat = 0.0
	overheat._emit_heat()
	## Visual: blue-white flash.
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		var t := player.create_tween()
		t.tween_property(sprite, "modulate", _FLASH_COLOR, _FLASH_IN_DURATION)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), _FLASH_OUT_DURATION)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
