# dialog/ui/playermenu/weapon_option.gd
class_name WeaponOption
extends Control

const _TEX_UNSELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_select_option.png")
const _TEX_SELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_selected_option.png")

## Colour applied to this control when the keyboard cursor is on it.
const _CURSOR_MODULATE := Color(1.4, 1.4, 1.0)
const _NORMAL_MODULATE := Color.WHITE

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $WeaponName

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Swap the background sprite between unselected and selected state.
func set_selected(value: bool) -> void:
	var tex := _TEX_SELECTED if value else _TEX_UNSELECTED
	if _bg_sprite.texture == tex:
		return
	_bg_sprite.texture = tex

## Highlight this row when the keyboard cursor is positioned here.
func set_cursor(value: bool) -> void:
	modulate = _CURSOR_MODULATE if value else _NORMAL_MODULATE
