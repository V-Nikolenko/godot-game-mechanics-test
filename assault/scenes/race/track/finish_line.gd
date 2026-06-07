## FinishLine — visual marker placed as a child of the Track node. It scrolls automatically.
## Place at Track local Y = -track_length (e.g. Y = -18000 for an 18 000-unit race).
## Finish detection is handled by RaceDirector comparing each ship's track_y to track_length.
## This node is purely visual; it shows the player where the finish line is on screen.
class_name FinishLine
extends Node2D

@export var cull_margin: float = 160.0

func _ready() -> void:
	## Register so RaceLevelConfig can derive track_length from this node's authored position.
	add_to_group("finish_line")

func _physics_process(_delta: float) -> void:
	if global_position.y > get_viewport_rect().size.y + cull_margin:
		queue_free()
