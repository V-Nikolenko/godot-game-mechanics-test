# assault/scenes/gui/weapon_chip.gd
class_name WeaponChip
extends Control

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

func _ready() -> void:
	# Wait one frame so the player has been added to the tree.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0]
	var ws: WeaponState = player.find_child("WeaponState", true, false) as WeaponState
	if ws == null:
		return
	ws.weapon_changed.connect(_on_weapon_changed)
	# WeaponState already emitted on its own _ready() before we connected;
	# call the public re-emit so the chip renders the current mode immediately.
	ws.emit_current_mode()

func _on_weapon_changed(mode: WeaponModeResource) -> void:
	_icon.texture = mode.icon
	_label.text = mode.display_name
