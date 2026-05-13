# dialog/ui/playermenu/weapon_option.gd
## Single item in a weapon selection list. Shows a background sprite (tinted pink when
## selected) and a row highlight (yellow) when the keyboard cursor is positioned here.
class_name WeaponOption
extends Control

## Pink tint applied to the background sprite when this item is the active selection.
const _SELECTED_MODULATE := Color(2.0, 0.5, 1.2)
## Yellow tint applied to the whole control when the keyboard cursor is here.
const _CURSOR_MODULATE := Color(1.4, 1.4, 1.0)
## Restores the node to its unmodified appearance.
const _NORMAL_MODULATE := Color.WHITE

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $SelectionBG/WeaponName

var _is_selected: bool = false
var _is_cursor: bool = false

func _ready() -> void:
	_update_modulate()

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Tint the background sprite pink when selected, or restore it to white.
func set_selected(value: bool) -> void:
	_is_selected = value
	_update_modulate()

## Highlight the whole row yellow when the keyboard cursor is here.
func set_cursor(value: bool) -> void:
	_is_cursor = value
	_update_modulate()

func _update_modulate() -> void:
	modulate = _CURSOR_MODULATE if _is_cursor else _NORMAL_MODULATE
	if _bg_sprite != null:
		_bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
