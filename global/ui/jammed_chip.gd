# global/ui/jammed_chip.gd
## HUD chip for the Phase 9 ability lock: a "JAMMED" label over a thin bar whose width is `ability_lock_fill()`
## (full while held, shrinking through the stabilisation delay). A refused press tints the whole chip red for
## FLASH_SECONDS. Code-built by MissionHud next to the special-weapon icon, so both HUD scenes get it.
class_name JammedChip
extends Control

const BAR_WIDTH: float = 52.0
const BAR_HEIGHT: float = 3.0
const FLASH_SECONDS: float = 0.2
const FLASH_COLOR: Color = Color(1.0, 0.25, 0.2)
const BAR_COLOR: Color = Color(1.0, 0.85, 0.55)

var _flash_left: float = 0.0
var _bar: ColorRect = null

func _init() -> void:
	name = "JammedChip"
	custom_minimum_size = Vector2(BAR_WIDTH, 18.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var text := Label.new()
	text.name = "Text"
	text.text = "JAMMED"
	text.add_theme_font_size_override(&"font_size", 11)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text)

	var back := ColorRect.new()
	back.name = "BarBack"
	back.color = Color(0.0, 0.0, 0.0, 0.6)
	back.position = Vector2(0.0, 15.0)
	back.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_bar = ColorRect.new()
	_bar.name = "Bar"
	_bar.color = BAR_COLOR
	_bar.position = Vector2(0.0, 15.0)
	_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

## Shown while locked, with the bar at [param fill] (0..1).
func show_lock(fill: float) -> void:
	visible = true
	_bar.size.x = clampf(fill, 0.0, 1.0) * BAR_WIDTH

## Hidden, with nothing left over (the flash included).
func clear() -> void:
	visible = false
	_flash_left = 0.0
	modulate = Color.WHITE

## A refused press: red for FLASH_SECONDS.
func flash() -> void:
	_flash_left = FLASH_SECONDS
	modulate = FLASH_COLOR

func is_flashing() -> bool:
	return _flash_left > 0.0

func step(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_flash_left = 0.0
		modulate = Color.WHITE
