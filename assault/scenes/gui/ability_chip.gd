# assault/scenes/gui/ability_chip.gd
class_name AbilityChip
extends Control

## Shows the active ability icon and a cooldown fill.
## Call setup(ability_controller) to connect.

@onready var _icon: TextureRect = $Icon
@onready var _cooldown_fill: ColorRect = $CooldownFill
@onready var _label: Label = $Label

var _controller: AbilityController = null

func _ready() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var ctrl := players[0].get_node_or_null("AbilityController") as AbilityController
	if ctrl == null:
		return
	_controller = ctrl
	_refresh()
	AbilityState.ability_changed.connect(func(_id: StringName) -> void: _refresh())

func _refresh() -> void:
	if _controller == null:
		return
	_icon.texture = _controller.get_ability_icon()
	_label.text   = _controller.get_ability_name()

func _process(_delta: float) -> void:
	if _controller == null:
		return
	## Shrink _cooldown_fill from top as cooldown expires.
	## ratio 1.0 = full cooldown remaining; 0.0 = ready.
	var ratio: float = _controller.get_cooldown_ratio()
	_cooldown_fill.visible = ratio > 0.0
	if ratio > 0.0:
		var h: float = _icon.size.y
		_cooldown_fill.size = Vector2(_icon.size.x, h * ratio)
		_cooldown_fill.position = Vector2(0.0, 0.0)
