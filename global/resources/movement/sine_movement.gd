## SineMovement — descends while weaving left/right in a sine wave.
class_name SineMovement
extends MovementResource

@export_range(1.0, 2000.0, 1.0) var base_speed: float = 140.0          ## Downward travel speed px/s
@export var amplitude: float = 45.0       ## Lateral swing width in pixels
@export_range(0.01, 20.0, 0.01) var frequency: float = 2.5        ## Oscillations per second (default matches original)

func sample(t: float) -> Vector2:
	return Vector2(amplitude * sin(t * frequency), base_speed * t)
