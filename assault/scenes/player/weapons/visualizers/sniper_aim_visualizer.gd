# assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd
class_name SniperAimVisualizer
extends Node2D

## Two display modes, selected by whether initial_angles is populated:
##
## CONE mode (player sniper — initial_angles set by SniperBehavior):
##   Draws 5 converging red aim lines. Two outer lines are the ±25° cone
##   borders; three inner lines are randomly sampled. All narrow linearly
##   to 0° over the charge duration.
##
## SINGLE-LINE mode (enemy sniper — initial_angles left empty):
##   Draws one red line pointing straight ahead (Vector2.UP in local space).
##   Dim while tracking (charge < 1), bright when locked (charge = 1).
##
## This node is added as a child of the active muzzle (Marker2D), so it
## automatically rotates with the ship.

## ── Cone mode ────────────────────────────────────────────────────────────────
const LINE_COLOR  := Color(1.0, 0.0, 0.0, 0.7)
const LINE_WIDTH  := 1.0
const LINE_LENGTH := 600.0

## ── Single-line mode ─────────────────────────────────────────────────────────
const COLOR_TRACKING := Color(1.0, 0.1, 0.1, 0.55)  ## dim red while aiming
const COLOR_LOCKED   := Color(1.0, 0.15, 0.0, 1.0)  ## bright orange-red when locked
const WIDTH_TRACKING : float = 1.0
const WIDTH_LOCKED   : float = 2.0

## All 5 initial line angles in radians relative to ship forward (= Vector2.UP).
## Set by SniperBehavior immediately after instantiation.
## Leave empty for single-line enemy mode.
var initial_angles: Array[float] = []

## 0.0 = charge just started; 1.0 = fully charged / locked.
var charge_fraction: float = 0.0

func _draw() -> void:
	if initial_angles.is_empty():
		## Single-line mode — one tracking/lock line straight ahead.
		var locked := charge_fraction >= 1.0
		var color  := COLOR_LOCKED   if locked else COLOR_TRACKING
		var width  := WIDTH_LOCKED   if locked else WIDTH_TRACKING
		draw_line(Vector2.ZERO, Vector2.UP * LINE_LENGTH, color, width)
	else:
		## Cone mode — 5 lines converging as charge_fraction → 1.
		for angle: float in initial_angles:
			var current_angle := angle * (1.0 - charge_fraction)
			var tip := Vector2.UP.rotated(current_angle) * LINE_LENGTH
			draw_line(Vector2.ZERO, tip, LINE_COLOR, LINE_WIDTH)

## Called each frame by SniperBehavior.tick() or SniperEnemy._process() with t in [0.0, 1.0].
func update_charge(t: float) -> void:
	charge_fraction = t
	queue_redraw()
