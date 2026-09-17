class_name SettingsPanel
extends Node2D

## Settings sub-overlay, opened from the ESC menu's Settings option. Same shape as LoreLogList —
## open() / close() / navigate(dir) plus cycle(dir) — because PauseMenu routes both the same way:
## while it is open, _unhandled_input absorbs ALL menu input (menu_confirm included, so it can
## never fall through to _confirm() and re-open this panel) and ui_cancel returns to the option
## list rather than closing the whole pause menu.
##
## Two rows: which steering scheme the open-space ship flies with, and how much automatic
## camera motion (lead + speed-zoom) it applies. Both rows are shown in every mode because
## they are stored preferences, not mode-local toggles — a player in a mission who wants to
## change their controls should not have to fly back to the hub first.
##
## Another row is another entry in _rows/_value_lbls and another branch in cycle()/_refresh().
## There is deliberately no generic settings framework here — a couple of small-valued keys do
## not pay for one, and SettingsState already owns validation, persistence and the change signal.

const _CURSOR_COLOR: Color = Color(1.4, 1.4, 1.0)
const _NORMAL_COLOR: Color = Color.WHITE

## Scheme StringName -> the wording the player reads. SettingsState owns the values and which of
## them are legal; this owns only how they are spelled on screen.
const _SCHEME_LABELS: Dictionary = {
	&"mouse": "Mouse Aim",
	&"keys": "Classic (A/D)",
}

## camera_motion StringName -> the wording the player reads. Same split of ownership as above.
const _CAMERA_MOTION_LABELS: Dictionary = {
	&"full": "Full",
	&"reduced": "Reduced",
	&"off": "Off",
}

## Kept as its own accessor (rather than folded into _value_lbls only) because existing tests
## address the steering row's label directly, the same way the panel's own callers do.
@onready var _value_lbl: Label = $Rows/Row0/ValueLabel

var _rows: Array[Node2D] = []
## ValueLabel per row, resolved by node path once in _ready() — _refresh() writes through
## this array rather than hard-coding a single label, so a third row is one more entry here.
var _value_lbls: Array[Label] = []
var _cursor_row: int = 0


func _ready() -> void:
	_rows = [$Rows/Row0, $Rows/Row1]
	_value_lbls = [_value_lbl, $Rows/Row1/ValueLabel as Label]
	visible = false


## Show the panel with the cursor on the first row, reading current values from the store.
func open() -> void:
	_cursor_row = 0
	_refresh()
	visible = true


func close() -> void:
	visible = false


## +1/-1 moves the cursor between rows. Clamped, not wrapped — with one row it is a no-op.
func navigate(delta: int) -> void:
	if _rows.is_empty():
		return
	_cursor_row = clampi(_cursor_row + delta, 0, _rows.size() - 1)
	_refresh()


## +1/-1 cycles the hovered row's value, wrapping past the ends.
func cycle(delta: int) -> void:
	match _cursor_row:
		0:
			_cycle_open_space_scheme(delta)
		1:
			_cycle_camera_motion(delta)
	_refresh()


func _cycle_open_space_scheme(delta: int) -> void:
	var schemes: Array[StringName] = SettingsState.SCHEMES
	if schemes.is_empty():
		return
	var i: int = schemes.find(SettingsState.get_open_space_scheme())
	if i < 0:
		i = 0
	SettingsState.set_open_space_scheme(schemes[wrapi(i + delta, 0, schemes.size())])


func _cycle_camera_motion(delta: int) -> void:
	var values: Array[StringName] = SettingsState.CAMERA_MOTION_VALUES
	if values.is_empty():
		return
	var i: int = values.find(SettingsState.get_camera_motion())
	if i < 0:
		i = 0
	SettingsState.set_camera_motion(values[wrapi(i + delta, 0, values.size())])


## Rebuilt from SettingsState on every open() and every cycle(), never cached: the panel is
## instantiated with the pause-menu scene and the value can change behind its back long before
## anyone opens it.
func _refresh() -> void:
	var scheme: StringName = SettingsState.get_open_space_scheme()
	_value_lbls[0].text = _SCHEME_LABELS.get(scheme, String(scheme))
	var motion: StringName = SettingsState.get_camera_motion()
	_value_lbls[1].text = _CAMERA_MOTION_LABELS.get(motion, String(motion))
	for i: int in _rows.size():
		_rows[i].modulate = _CURSOR_COLOR if i == _cursor_row else _NORMAL_COLOR
