## ArcMovement — semicircular arc path that bows left or right.
## Enters from top, arcs down, exits off the top edge.
## Use ExitMode.FREE_ON_DURATION on the EnemyPathMover with this movement.
class_name ArcMovement
extends MovementResource

enum ArcDirection { LEFT, RIGHT }

@export var direction: ArcDirection = ArcDirection.LEFT
@export var amplitude: float = 130.0   ## Radius of the semicircle in pixels
@export_range(0.01, 60.0, 0.1) var duration: float = 3.5      ## Total seconds for full arc

func sample(t: float) -> Vector2:
	if duration <= 0.0:
		return Vector2.ZERO
	var p: float = clampf(t / duration, 0.0, 1.0)
	match direction:
		ArcDirection.LEFT:
			return Vector2(amplitude * (cos(p * PI) - 1.0), amplitude * sin(p * PI))
		ArcDirection.RIGHT:
			return Vector2(amplitude * (1.0 - cos(p * PI)), amplitude * sin(p * PI))
	return Vector2.ZERO

func total_duration() -> float:
	return duration
