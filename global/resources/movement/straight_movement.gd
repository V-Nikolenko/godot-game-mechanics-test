## StraightMovement — constant-velocity linear path.
## angle: radians from straight-down (0=down, PI/2=right, -PI/2=left, PI=up).
class_name StraightMovement
extends MovementResource

@export_range(1.0, 2000.0, 1.0) var speed: float = 100.0
@export_range(-PI, PI, 0.01, "radians") var angle: float = 0.0
## When > 0, this step ends after this many seconds and SequenceMovement advances.
## When 0 (default), duration is infinite — step runs until the entity exits.
@export_range(0.0, 60.0, 0.01, "or_greater") var duration: float = 0.0

func sample(t: float) -> Vector2:
	return Vector2(sin(angle), cos(angle)) * speed * t

func total_duration() -> float:
	return duration if duration > 0.0 else INF
