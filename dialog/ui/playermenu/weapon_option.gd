# dialog/ui/playermenu/weapon_option.gd
class_name WeaponOption
extends Control

signal option_pressed

const _TEX_UNSELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_select_option.png")
const _TEX_SELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_selected_option.png")

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $WeaponName
@onready var _button: Button = $ClickArea

func _ready() -> void:
	_button.pressed.connect(func() -> void: option_pressed.emit())

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Swap the background sprite between unselected and selected state.
func set_selected(value: bool) -> void:
	_bg_sprite.texture = _TEX_SELECTED if value else _TEX_UNSELECTED
