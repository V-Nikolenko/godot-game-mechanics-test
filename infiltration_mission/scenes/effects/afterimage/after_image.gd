extends Node2D

@export var lifetime: float = 0.3

var time_passed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _process(delta: float) -> void:
	time_passed += delta

	var t = time_passed / lifetime

	# Fade out
	sprite.modulate.a = 1.0 - t

	# Optional: slight shrink for style
	scale = Vector2.ONE * (1.0 - t * 0.3)

	if time_passed >= lifetime:
		queue_free()
