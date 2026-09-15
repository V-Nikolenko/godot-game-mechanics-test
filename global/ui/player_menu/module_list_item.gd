# global/ui/dialog_system/playermenu/module_list_item.gd
## Single selectable row in the module detail list.
## Shows icon, display name, and description. Supports cursor + selection tints.
class_name ModuleListItem
extends Control

const _CURSOR_MODULATE   := Color(1.4, 1.4, 1.0)   ## Yellow highlight when cursor here.
const _SELECTED_MODULATE := Color(2.0, 0.5, 1.2)    ## Pink tint when this is equipped.
const _NORMAL_MODULATE   := Color.WHITE
const _GREY_MODULATE     := Color(0.45, 0.45, 0.45) ## None/empty-slot appearance.
## Locked rows follow MissionListItem's shipped pattern (a resting tint plus a dimmed
## cursor tint, `mission_list_item.gd:13-14`), but sit darker than _GREY_MODULATE: that
## value is already spoken for by the selectable "None" row, and at rest the player has to
## be able to tell "nothing installed" from "cannot install this".
const _LOCKED_MODULATE        := Color(0.30, 0.30, 0.32)
const _LOCKED_CURSOR_MODULATE := Color(0.50, 0.50, 0.52)

@onready var _bg_sprite: Sprite2D  = $SelectionBG
@onready var _icon:      Sprite2D  = $ModuleIcon
@onready var _name_lbl:  Label     = $SelectionBG/ModuleName

var _is_selected: bool = false
var _is_cursor:   bool = false
var _is_none:     bool = false
var _is_locked:   bool = false

func _ready() -> void:
	_update_modulate()

## Populate this row. Pass null icon and empty name for the "None" row.
## `locked` greys the row out and makes ModuleList.confirm() a no-op on it; the "None"
## row is never locked, since taking a module out must always be possible.
func configure(display_name: String, icon: Texture2D, locked: bool = false) -> void:
	_is_none = display_name == ""
	_is_locked = locked
	_name_lbl.text = display_name if display_name != "" else "None"
	if _icon != null:
		if icon != null:
			_icon.texture = icon
			_icon.visible = true
		else:
			_icon.visible = false
	_update_modulate()

func is_locked() -> bool:
	return _is_locked

func set_cursor(value: bool) -> void:
	_is_cursor = value
	_update_modulate()

func set_selected(value: bool) -> void:
	_is_selected = value
	_update_modulate()

func _update_modulate() -> void:
	## Locked is tested before _is_cursor: a locked row under the cursor must not light up
	## yellow as if it were selectable.
	if _is_locked:
		modulate = _LOCKED_CURSOR_MODULATE if _is_cursor else _LOCKED_MODULATE
	elif _is_cursor:
		modulate = _CURSOR_MODULATE
	elif _is_none:
		modulate = _GREY_MODULATE
	else:
		modulate = _NORMAL_MODULATE
	if _bg_sprite != null:
		_bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
