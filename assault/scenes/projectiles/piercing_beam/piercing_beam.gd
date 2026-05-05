# assault/scenes/projectiles/piercing_beam/piercing_beam.gd
class_name PiercingBeam
extends Node2D

@onready var _line: Line2D = $Line2D

func set_endpoints(world_from: Vector2, world_to: Vector2) -> void:
	if _line == null:
		return
	_line.points = PackedVector2Array([world_from, world_to])
