# global/ship_modules/overheat_nullifier_module.gd
class_name OverheatNullifierModule
extends ShipModuleBase

const _COOLDOWN: float = 15.0
## Passive: equipped module doubles heat dissipation speed (halves cooldown_time).
const _DISSIPATION_MULTIPLIER: float = 0.5

const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"
const _FLASH_COLOR: Color = Color(0.6, 0.9, 1.0, 1.0)
const _FLASH_IN_DURATION: float = 0.05
const _FLASH_OUT_DURATION: float = 0.25

var _cooldown_left: float = 0.0
var _original_cooldown_time: float = -1.0

func get_display_name() -> String: return "Heat Flush"
func get_description() -> String:
	return "Passive: doubles heat dissipation speed. Active (H): instantly vents all accumulated heat. 15-second cooldown."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_emergyl.png")
func get_slot() -> StringName: return &"weapons"

func apply(player: Node) -> void:
	var overheat := _find_overheat(player)
	if overheat == null:
		return
	_original_cooldown_time = overheat.cooldown_time
	overheat.cooldown_time = _original_cooldown_time * _DISSIPATION_MULTIPLIER

func remove(player: Node) -> void:
	if _original_cooldown_time < 0.0:
		return
	var overheat := _find_overheat(player)
	if overheat:
		overheat.cooldown_time = _original_cooldown_time
	_original_cooldown_time = -1.0

func _find_overheat(player: Node) -> Overheat:
	var overheat: Overheat = player.get("overheat_component") as Overheat
	if overheat == null:
		overheat = player.get_node_or_null("OverheatComponent") as Overheat
	return overheat

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	var overheat := _find_overheat(player)
	if overheat == null:
		return false  ## No overheat component found on this player.
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
