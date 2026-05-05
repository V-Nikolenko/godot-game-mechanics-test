# assault/scenes/gui/weapon_chip.gd
class_name WeaponChip
extends Control

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

func _ready() -> void:
	# Wait one frame so the player has been added to the tree.
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0]
	var ws: WeaponState = player.find_child("WeaponState", true, false) as WeaponState
	if ws == null:
		return
	ws.weapon_changed.connect(_on_weapon_changed)
	# The state emitted on its own _ready() before we connected, so ask it
	# to re-emit so the chip renders the initial mode.
	ws._emit_changed()

func _on_weapon_changed(mode: WeaponModeResource) -> void:
	_icon.texture = mode.icon
	_label.text = mode.display_name
