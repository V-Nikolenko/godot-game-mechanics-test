class_name SmallAsteroid
extends AsteroidBase

func _physics_process(delta: float) -> void:
	super(delta)
	move_and_slide()
