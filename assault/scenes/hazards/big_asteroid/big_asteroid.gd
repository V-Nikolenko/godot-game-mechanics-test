class_name BigAsteroid
extends AsteroidBase

@export var split_min: int = 2
@export var split_max: int = 4
@export var split_speed: float = 70.0

func _on_destroyed() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var small_scene := load("res://assault/scenes/hazards/small_asteroid/small_asteroid.tscn") as PackedScene
	if small_scene == null:
		return
	var count := randi_range(split_min, split_max)
	for i in count:
		var small := small_scene.instantiate() as CharacterBody2D
		small.global_position = global_position
		var angle := randf() * TAU
		small.velocity = Vector2.RIGHT.rotated(angle) * split_speed
		parent.add_child(small)
