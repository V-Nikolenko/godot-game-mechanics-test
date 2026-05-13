# global/ui/dialog_system/playermenu/module_list_item.gd
## Single selectable row in the module detail list.
## Shows icon, display name, and description. Supports cursor + selection tints.
class_name ModuleListItem
extends Control

const _CURSOR_MODULATE   := Color(1.4, 1.4, 1.0)   ## Yellow highlight when cursor here.
const _SELECTED_MODULATE := Color(2.0, 0.5, 1.2)    ## Pink tint when this is equipped.
const _NORMAL_MODULATE   := Color.WHITE
const _GREY_MODULATE     := Color(0.45, 0.45, 0.45) ## None/empty-slot appearance.

@onready var _bg_sprite: Sprite2D  = $SelectionBG
@onready var _icon:      Sprite2D  = $ModuleIcon
@onready var _name_lbl:  Label     = $SelectionBG/ModuleName
@onready var _desc_lbl:  Label     = $SelectionBG/ModuleDesc

var _is_selected: bool = false
var _is_cursor:   bool = false

func _ready() -> void:
	_update_modulate()

## Populate this row. Pass null icon and empty strings for the "None" row.
func configure(display_name: String, description: String, icon: Texture2D) -> void:
	_name_lbl.text = display_name if display_name != "" else "None"
	_desc_lbl.text = description
	if icon != null:
		_icon.texture = icon
		_icon.visible = true
	else:
		_icon.visible = false

func set_cursor(value: bool) -> void:
	_is_cursor = value
	_update_modulate()

func set_selected(value: bool) -> void:
	_is_selected = value
	_update_modulate()

func _update_modulate() -> void:
	modulate = _CURSOR_MODULATE if _is_cursor else _NORMAL_MODULATE
	if _bg_sprite != null:
		_bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
