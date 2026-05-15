# global/ship_modules/final_resort_module.gd
class_name FinalResortModule
extends ShipModuleBase

const _DAMAGE_MULTIPLIER: float = 3.0
const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"

var _active: bool = false
var _saved_hp: int = 0

func get_display_name() -> String: return "Final Resort"
func get_description() -> String:
	return "Press H to sacrifice hull and shields for overwhelming firepower. HP drops to 1, shields drain, damage is tripled. Press H again to disengage and restore HP."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_damage_up.png")
func get_slot() -> StringName: return &"armor"

func apply(_player: Node) -> void:
	pass

func remove(player: Node) -> void:
	## If active when unequipped, disengage cleanly.
	if _active:
		_disengage(player)

func try_activate(player: Node) -> bool:
	if not _active:
		_engage(player)
	else:
		_disengage(player)
	return true  ## Always consume input.

func tick(_player: Node, _delta: float) -> void:
	pass  ## No time-limited effect; purely a toggle.

func _engage(player: Node) -> void:
	var health: Health = player.get("health_component") as Health
	if health == null:
		push_warning("FinalResortModule: health_component not found on player")
		return
	_active = true
	_saved_hp = health.current_health

	## Collapse HP to 1.
	health.set_health(1)

	## Drain shield.
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null:
		push_warning("FinalResortModule: shield_component not found on player")
	else:
		shield.set_shield(0)

	## Triple damage.
	player.set("damage_multiplier", _DAMAGE_MULTIPLIER)

	## Blood-red ship tint.
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.1, 0.1, 1.0)

func _disengage(player: Node) -> void:
	_active = false
	var health: Health = player.get("health_component") as Health
	if health:
		## Restore saved HP, but never exceed what HP is right now (can't gain HP from the mode).
		health.set_health(mini(_saved_hp, health.current_health))

	## Restore damage multiplier.
	player.set("damage_multiplier", 1.0)

	## Remove tint.
	var sprite := player.get_node_or_null(_SPRITE_PATH) as CanvasItem
	if sprite:
		player.create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
