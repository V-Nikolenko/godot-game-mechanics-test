# assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd
class_name SniperAimVisualizer
extends Node2D

## Draws 5 converging red aim lines from the muzzle's local origin.
## Two outer lines are the cone borders (±25°); three inner lines are randomly
## sampled at charge start. All narrow linearly to 0° over 2 s of charge.
##
## This node is added as a child of the active muzzle (Marker2D), so it
## automatically rotates with the ship.

const LINE_COLOR  := Color(1.0, 0.0, 0.0, 0.7)  ## red, 70% alpha
const LINE_WIDTH  := 1.0
const LINE_LENGTH := 600.0

## All 5 initial line angles in radians relative to ship forward (= Vector2.UP).
## Set by SniperBehavior immediately after instantiation.
## Layout: [0]=left border, [1]=right border, [2..4]=inner random angles.
var initial_angles: Array[float] = []

## 0.0 = charge just started (full cone); 1.0 = fully charged (all lines at 0°).
var charge_fraction: float = 0.0

func _draw() -> void:
	for angle: float in initial_angles:
		var current_angle := angle * (1.0 - charge_fraction)
		var tip := Vector2.UP.rotated(current_angle) * LINE_LENGTH
		draw_line(Vector2.ZERO, tip, LINE_COLOR, LINE_WIDTH)

## Called each physics frame by SniperBehavior.tick() with t in [0.0, 1.0].
func update_charge(t: float) -> void:
	charge_fraction = t
	queue_redraw()
