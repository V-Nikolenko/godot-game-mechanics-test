## HoldMovement — keeps the ship stationary for a fixed duration.
## Returns Vector2.ZERO for the entire duration.
## Used as a step in SequenceMovement: approach → hold → strafe.
class_name HoldMovement
extends MovementResource

## Seconds to hold position. 0.0 = free actor immediately on first frame (if using FREE_ON_DURATION).
@export_range(0.0, 60.0, 0.1) var duration: float = 2.0

func sample(_t: float) -> Vector2:
	return Vector2.ZERO

func total_duration() -> float:
	return duration
