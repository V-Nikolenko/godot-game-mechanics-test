## CarrierEnginePlume - the code-drawn exhaust of one Carrier engine (Phase 10 §2.6.3 / §2.9, t6). It is the engine part's `Light` child, so
## `EnemyModule.destroy()` hides it: the plume goes out with the engine. Points along local −y (the stern of the nose-down hull). Visual only.
class_name CarrierEnginePlume
extends Node2D

## Flame length (px) and half-width at the nozzle (px).
@export var length: float = 34.0
@export var half_width: float = 12.0
@export var color: Color = Color(0.45, 0.75, 1.0, 0.85)
## Flicker period (s) and depth (share of `length`).
@export var flicker_period: float = 0.12
@export var flicker_depth: float = 0.2

var _clock: float = 0.0


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var f := 1.0 - flicker_depth * 0.5 * (1.0 + sin(TAU * _clock / maxf(flicker_period, 0.01)))
	var tip := Vector2(0.0, -length * f)
	draw_colored_polygon(PackedVector2Array([Vector2(-half_width, 0.0), Vector2(half_width, 0.0), tip]), color)
	var core := Color(1.0, 1.0, 1.0, color.a)
	draw_colored_polygon(PackedVector2Array([Vector2(-half_width * 0.4, 0.0), Vector2(half_width * 0.4, 0.0), tip * 0.5]), core)
