## AimCursor — the hardware mouse cursor open-space flies with, in place of the OS arrow.
##
## A hardware cursor (Input.set_custom_mouse_cursor()) rather than a software one drawn in
## _draw(): the engine docs are explicit that a software cursor "will add at least one frame
## of latency compared to a hardware mouse cursor". The AIM POINT itself has to be that
## precise; the STATE around it (dead zone, snap, hull lag) is a separate, ship-drawn layer
## (see AimReticle) that can afford the extra frame.
##
## Input.set_custom_mouse_cursor() is PROCESS-GLOBAL and STICKY: it survives scene changes,
## so whoever calls apply() must call restore() on every exit path, or the crosshair leaks
## into the boot menu and every other game mode. Input's cursor state cannot be read back,
## so is_applied() is the seam tests use to check the pairing held.
class_name AimCursor
extends RefCounted

const SIZE: int = 32
const COLOR: Color = Color(0.35, 0.9, 1.0)

## True gap gives a dead centre, from just outside it to just inside the outer margin.
const _OUTER_MARGIN: int = 2
const _GAP: int = 4
const _THICKNESS: int = 2

static var _applied: bool = false


## Draws a crosshair: four ticks around a transparent centre gap so whatever is under the
## cursor — a ship, a pickup, a UI element — stays visible. Pure and side-effect free, so it
## is testable with no Input/DisplayServer involved.
static func build_image(size: int, color: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var center: int = size / 2
	var half_thick: int = _THICKNESS / 2
	var lo: int = center - half_thick
	var hi: int = lo + _THICKNESS

	for x: int in range(lo, hi):
		for y: int in range(_OUTER_MARGIN, center - _GAP):
			img.set_pixel(x, y, color)
		for y: int in range(center + _GAP, size - _OUTER_MARGIN):
			img.set_pixel(x, y, color)
	for y: int in range(lo, hi):
		for x: int in range(_OUTER_MARGIN, center - _GAP):
			img.set_pixel(x, y, color)
		for x: int in range(center + _GAP, size - _OUTER_MARGIN):
			img.set_pixel(x, y, color)

	return img


## Installs the crosshair as the OS cursor, hotspot centred so the gap sits exactly on the
## reported cursor position.
static func apply() -> void:
	var texture := ImageTexture.create_from_image(build_image(SIZE, COLOR))
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, Vector2(SIZE / 2, SIZE / 2))
	_applied = true


## Safe no-op if apply() was never called — the &"keys" scheme never applies the cursor, so
## its ships must still be able to call restore() unconditionally on exit.
static func restore() -> void:
	if not _applied:
		return
	Input.set_custom_mouse_cursor(null)
	_applied = false


static func is_applied() -> bool:
	return _applied
