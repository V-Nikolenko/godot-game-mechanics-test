class_name LoreLogListItem
extends Control

## Single row in the Lore Logs reader. Title only — no icon, no equipped/selected tint, since
## nothing here is ever installed, just read. Locked/cursor modulate copied from
## ModuleListItem (global/ui/player_menu/module_list_item.gd), minus the icon and "None"/selected
## special cases that don't apply to a read-only catalogue.

const _CURSOR_MODULATE        := Color(1.4, 1.4, 1.0)
const _NORMAL_MODULATE        := Color.WHITE
const _LOCKED_MODULATE        := Color(0.40, 0.40, 0.42)
const _LOCKED_CURSOR_MODULATE := Color(0.55, 0.55, 0.58)

@onready var _label: Label = $Label

var _is_cursor: bool = false
var _is_locked: bool = false


func _ready() -> void:
	_update_modulate()


func configure(display_name: String, locked: bool) -> void:
	_is_locked = locked
	_label.text = display_name
	_update_modulate()


func is_locked() -> bool:
	return _is_locked


func set_cursor(value: bool) -> void:
	_is_cursor = value
	_update_modulate()


func _update_modulate() -> void:
	## Locked is tested before _is_cursor: a locked row under the cursor must not light up
	## yellow as if it were readable.
	if _is_locked:
		modulate = _LOCKED_CURSOR_MODULATE if _is_cursor else _LOCKED_MODULATE
	elif _is_cursor:
		modulate = _CURSOR_MODULATE
	else:
		modulate = _NORMAL_MODULATE
