class_name BigAsteroid
extends AsteroidBase

## Assign small_asteroid.tscn here once that scene is created.
@export var split_scene: PackedScene

@export var split_min: int = 2
@export var split_max: int = 4
@export var split_speed: float = 70.0

func _on_destroyed() -> void:
	if split_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var count := randi_range(split_min, split_max)
	for i in count:
		var small := split_scene.instantiate() as AsteroidBase
		small.global_position = global_position
		var angle := randf() * TAU
		small.velocity = Vector2.RIGHT.rotated(angle) * split_speed
		parent.call_deferred("add_child", small)
